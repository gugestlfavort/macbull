import Foundation

/// Everything the scanner needs to know about one kind of agent. Built-in agents come from
/// `AgentCatalogue.builtIn`; user-added ones from `CustomAgentNames.definition(for:)`.
struct AgentDefinition: Equatable, Sendable {
    /// Stable identifier: "claude", "codex", ..., or "custom:<name>".
    let id: String
    /// Display name, for example "Claude Code".
    let name: String
    /// Process names or binary names that identify the agent.
    let executableNames: [String]
    /// Path fragments that identify the agent when it runs as a script under a language runtime.
    let packageFragments: [String]
    /// Folders native installers name binaries after (the binary is called after a version number).
    let versionFolders: [String]
    /// Log folders, relative to the home folder.
    let logFolders: [String]
    /// Endings of files that are session logs.
    let logEndings: [String]
    /// The agent keeps one log folder per working directory (Claude Code).
    let logsPerProject: Bool
    let oneShotFlags: [String]
    let oneShotSubcommands: [String]
    let serviceFlags: [String]
    let serviceSubcommands: [String]
    let isCustom: Bool

    init(
        id: String, name: String, executableNames: [String], packageFragments: [String] = [],
        versionFolders: [String] = [], logFolders: [String] = [], logEndings: [String] = [],
        logsPerProject: Bool = false, oneShotFlags: [String] = [], oneShotSubcommands: [String] = [],
        serviceFlags: [String] = [], serviceSubcommands: [String] = [], isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.executableNames = executableNames
        self.packageFragments = packageFragments
        self.versionFolders = versionFolders
        self.logFolders = logFolders
        self.logEndings = logEndings
        self.logsPerProject = logsPerProject
        self.oneShotFlags = oneShotFlags
        self.oneShotSubcommands = oneShotSubcommands
        self.serviceFlags = serviceFlags
        self.serviceSubcommands = serviceSubcommands
        self.isCustom = isCustom
    }
}

enum AgentCatalogue {
    static let claudeID = "claude"

    private static let jsonEndings = [".jsonl", ".json"]

    /// In the order the panel lists them.
    static let builtIn: [AgentDefinition] = [
        AgentDefinition(
            id: claudeID, name: "Claude Code", executableNames: ["claude"],
            packageFragments: ["/node_modules/@anthropic-ai/claude-code/"],
            versionFolders: ["/claude/versions/"],
            logFolders: [".claude/projects"], logEndings: jsonEndings, logsPerProject: true,
            oneShotFlags: ["-p", "--print"],
            serviceFlags: ["--chrome-native-host"], serviceSubcommands: ["mcp"]
        ),
        AgentDefinition(
            id: "codex", name: "Codex", executableNames: ["codex"],
            packageFragments: ["/node_modules/@openai/codex/"],
            logFolders: [".codex/sessions"], logEndings: jsonEndings,
            oneShotSubcommands: ["exec", "e"],
            serviceSubcommands: ["mcp", "mcp-server"]
        ),
        AgentDefinition(
            id: "gemini", name: "Gemini CLI", executableNames: ["gemini"],
            packageFragments: ["/node_modules/@google/gemini-cli/"],
            logFolders: [".gemini/tmp"], logEndings: jsonEndings,
            oneShotFlags: ["-p", "--prompt"]
        ),
        AgentDefinition(
            id: "cursor-agent", name: "Cursor Agent", executableNames: ["cursor-agent"],
            packageFragments: ["/cursor-agent/versions/"],
            versionFolders: ["/cursor-agent/versions/"],
            logFolders: [".cursor/chats"], logEndings: [".db", ".db-wal", ".jsonl", ".json"],
            oneShotFlags: ["-p", "--print"]
        ),
        AgentDefinition(
            id: "copilot", name: "Copilot CLI", executableNames: ["copilot"],
            packageFragments: ["/node_modules/@github/copilot/"],
            logFolders: [".copilot/session-state"], logEndings: jsonEndings,
            oneShotFlags: ["-p", "--prompt"]
        ),
        AgentDefinition(
            id: "opencode", name: "OpenCode", executableNames: ["opencode"],
            packageFragments: ["/node_modules/opencode-ai/"],
            logFolders: [".local/share/opencode"], logEndings: jsonEndings,
            oneShotSubcommands: ["run"]
        ),
        AgentDefinition(
            id: "amp", name: "Amp", executableNames: ["amp"],
            packageFragments: ["/node_modules/@sourcegraph/amp/"],
            oneShotFlags: ["-x", "--execute"]
        ),
        AgentDefinition(
            id: "aider", name: "Aider", executableNames: ["aider"],
            oneShotFlags: ["-m", "--message", "--message-file"]
        ),
    ]

    /// Names of every executable in the built-in catalogue.
    static let builtInExecutableNames: Set<String> = Set(builtIn.flatMap(\.executableNames))
}
