import Foundation

/// Name helpers shared by matching, helper detection and custom-agent validation.
enum ProcessNames {
    /// Shells never count as helpers; a shell below a session is a running tool call.
    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "nu"]

    private static let runtimes: Set<String> = ["node", "bun", "deno", "python", "python3", "Python"]
    private static let versionedPythonPrefix = "python3."

    static func isShell(_ name: String) -> Bool {
        shells.contains(name)
    }

    /// node, bun, deno, python, python3, Python, or python3.<digits>. Not names that merely begin with "python".
    static func isInterpreter(_ name: String) -> Bool {
        if runtimes.contains(name) { return true }
        guard name.hasPrefix(versionedPythonPrefix) else { return false }
        let minor = name.dropFirst(versionedPythonPrefix.count)
        return !minor.isEmpty && minor.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The part after the last slash; the whole text when there is none.
    static func lastComponent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}

/// A process that belongs to an agent, with the arguments that follow the matched script or binary.
struct AgentMatch: Equatable, Sendable {
    let agent: AgentDefinition
    /// Everything after the matched binary (direct) or the matched script (language runtime).
    let ownArguments: [String]
}

/// The four rules that recognise an agent process.
struct AgentMatcher: Sendable {
    /// How many leading arguments of a language runtime are inspected (argument zero included).
    static let runtimeArgumentWindow = 5

    let definitions: [AgentDefinition]

    /// The agent whose binary this is (rules 1 to 3), without looking at arguments.
    func directMatch(name: String, path: String?) -> AgentDefinition? {
        let binaryName = path.map(ProcessNames.lastComponent)
        return definitions.first { agent in
            agent.executableNames.contains(name)
                || (binaryName.map(agent.executableNames.contains) ?? false)
                || (path.map { path in agent.versionFolders.contains { path.contains($0) } } ?? false)
        }
    }

    /// Whether the arguments of this process can change the answer, so the scanner should read them.
    func needsArguments(name: String, path: String?) -> Bool {
        ProcessNames.isInterpreter(name) || directMatch(name: name, path: path) != nil
    }

    func match(name: String, path: String?, arguments: [String]) -> AgentMatch? {
        if let agent = directMatch(name: name, path: path) {
            return AgentMatch(agent: agent, ownArguments: Array(arguments.dropFirst()))
        }
        guard ProcessNames.isInterpreter(name) else { return nil }
        let window = arguments.prefix(Self.runtimeArgumentWindow)
        for agent in definitions {
            if let index = window.firstIndex(where: { Self.argument($0, belongsTo: agent) }) {
                return AgentMatch(agent: agent, ownArguments: Array(arguments.dropFirst(index + 1)))
            }
        }
        return nil
    }

    private static func argument(_ argument: String, belongsTo agent: AgentDefinition) -> Bool {
        agent.executableNames.contains(ProcessNames.lastComponent(argument))
            || agent.packageFragments.contains { argument.contains($0) }
    }
}

/// What a matched process is: a coding session, a one-shot run, or a bridge the same binary provides.
enum RunKind: Equatable, Sendable {
    /// Not a coding session (MCP server, native-host bridge): dropped entirely.
    case service
    /// Works until it exits.
    case oneShot
    case interactive
}

/// One-shot and interactive runs, read from the arguments after the matched binary or script.
enum ArgumentClassifier {
    static func classify(_ arguments: [String], for agent: AgentDefinition) -> RunKind {
        if isService(arguments, agent) { return .service }
        if isOneShot(arguments, agent) { return .oneShot }
        return .interactive
    }

    /// `--flag` or `--flag=value` for long flags, the exact token for short ones.
    private static func isFlag(_ argument: String, in flags: [String]) -> Bool {
        flags.contains { flag in
            argument == flag || (flag.hasPrefix("--") && argument.hasPrefix(flag + "="))
        }
    }

    private static func isService(_ arguments: [String], _ agent: AgentDefinition) -> Bool {
        if arguments.contains(where: { isFlag($0, in: agent.serviceFlags) }) { return true }
        for argument in arguments {
            // A one-shot flag before the first positional makes the positional the prompt text.
            if isFlag(argument, in: agent.oneShotFlags) { return false }
            if !argument.hasPrefix("-") { return agent.serviceSubcommands.contains(argument) }
        }
        return false
    }

    private static func isOneShot(_ arguments: [String], _ agent: AgentDefinition) -> Bool {
        if requestsStreamJSONInput(arguments) { return false }
        return arguments.contains { isFlag($0, in: agent.oneShotFlags) || agent.oneShotSubcommands.contains($0) }
    }

    /// Desktop apps talk to interactive sessions over stream-json, whatever other flags are set.
    static func requestsStreamJSONInput(_ arguments: [String]) -> Bool {
        for (index, argument) in arguments.enumerated() {
            if argument == "--input-format=stream-json" { return true }
            if argument == "--input-format", arguments.indices.contains(index + 1), arguments[index + 1] == "stream-json" {
                return true
            }
        }
        return false
    }
}

/// User-added agents.
enum CustomAgentNames {
    private static let scriptEndings = [".py", ".js", ".mjs", ".cjs", ".ts"]
    private static let quotes = CharacterSet(charactersIn: "\"'`\u{2018}\u{2019}\u{201C}\u{201D}")

    /// Why typed text is refused.
    enum Rejection: Equatable {
        case empty
        /// A language runtime: far too broad to match on.
        case interpreter
        case shell
        /// Already watched by the built-in catalogue.
        case knownAgent
    }

    enum Outcome: Equatable {
        case accepted(String)
        case rejected(Rejection)

        var name: String? {
            if case .accepted(let name) = self { return name }
            return nil
        }
    }

    /// The last word, without quotes, reduced to its last path component; or the reason it is refused.
    static func evaluate(_ text: String) -> Outcome {
        guard let lastWord = text.split(whereSeparator: \.isWhitespace).last else { return .rejected(.empty) }
        let unquoted = String(lastWord).trimmingCharacters(in: quotes)
        let name = ProcessNames.lastComponent(unquoted).trimmingCharacters(in: quotes)
        guard !name.isEmpty, name != ".", name != ".." else { return .rejected(.empty) }
        let lower = name.lowercased()
        if ProcessNames.isInterpreter(lower) { return .rejected(.interpreter) }
        if ProcessNames.isShell(lower) { return .rejected(.shell) }
        if AgentCatalogue.builtInExecutableNames.contains(lower) { return .rejected(.knownAgent) }
        return .accepted(name)
    }

    /// The name to store for what the user typed, or nil when it must be rejected (the Add button stays disabled).
    static func normalise(_ text: String) -> String? {
        evaluate(text).name
    }

    /// The stored list as the watcher uses it: normalised again, rejects and duplicates dropped, order kept.
    static func cleaned(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        return stored.compactMap(normalise).filter { seen.insert($0).inserted }
    }

    static func definition(for name: String) -> AgentDefinition {
        let hasExtension = name.contains(".") && !name.hasPrefix(".")
        let names = hasExtension ? [name] : [name] + scriptEndings.map { name + $0 }
        return AgentDefinition(id: "custom:" + name, name: name, executableNames: names, isCustom: true)
    }

    static func definitions(for stored: [String]) -> [AgentDefinition] {
        cleaned(stored).map(definition(for:))
    }
}
