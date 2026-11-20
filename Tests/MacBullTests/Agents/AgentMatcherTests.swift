import Foundation
import Testing
@testable import MacBull

struct AgentMatcherTests {
    private let matcher = AgentMatcher(definitions: AgentCatalogue.builtIn)

    private func match(_ name: String, _ path: String?, _ arguments: [String]) -> AgentMatch? {
        matcher.match(name: name, path: path, arguments: arguments)
    }

    // MARK: Recognition rules

    @Test func processNameEqualsAnExecutableName() {
        let found = match("claude", nil, ["claude", "--resume"])
        #expect(found?.agent.id == "claude")
        #expect(found?.ownArguments == ["--resume"])
    }

    @Test func binaryLastComponentEqualsAnExecutableName() {
        let found = match("MainThread", "/opt/homebrew/bin/codex", ["codex", "-m", "o3"])
        #expect(found?.agent.id == "codex")
        #expect(found?.ownArguments == ["-m", "o3"])
    }

    @Test func versionFolderInTheBinaryPath() {
        let claude = match("2.1.4", "/Users/x/.local/share/claude/versions/2.1.4", ["claude", "-p", "hi"])
        #expect(claude?.agent.id == "claude")
        let cursor = match("12.3", "/Users/x/.local/share/cursor-agent/versions/12.3/cursor-agent", ["cursor-agent"])
        #expect(cursor?.agent.id == "cursor-agent")
    }

    @Test func nodeRunningAnAgentScript() {
        let found = match("node", "/usr/local/bin/node", ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--verbose"])
        #expect(found?.agent.id == "claude")
        #expect(found?.ownArguments == ["--verbose"])
    }

    @Test func nodeWithFlagsBeforeTheScript() {
        let found = match("node", nil, ["node", "--max-old-space-size=4096", "/usr/local/bin/codex", "exec", "fix it"])
        #expect(found?.agent.id == "codex")
        #expect(found?.ownArguments == ["exec", "fix it"])
    }

    @Test func bunRunScript() {
        let found = match("bun", nil, ["bun", "run", "/Users/x/.bun/bin/gemini", "-p", "hello"])
        #expect(found?.agent.id == "gemini")
        #expect(found?.ownArguments == ["-p", "hello"])
    }

    @Test func pythonDashM() {
        let found = match("python", nil, ["python", "-m", "aider", "--model", "x"])
        #expect(found?.agent.id == "aider")
        #expect(found?.ownArguments == ["--model", "x"])
    }

    @Test func versionedPythonCountsAsARuntime() {
        #expect(match("python3.12", nil, ["python3.12", "/x/bin/aider"])?.agent.id == "aider")
        #expect(match("pythonista", nil, ["pythonista", "/x/bin/aider"]) == nil)
        #expect(match("python3x", nil, ["python3x", "/x/bin/aider"]) == nil)
    }

    @Test func nodeCliThatRewroteItsTitleToJustTheAgentName() {
        let found = match("node", "/usr/local/bin/node", ["claude"])
        #expect(found?.agent.id == "claude")
        #expect(found?.ownArguments == [])
    }

    @Test func onlyTheFirstFiveArgumentsOfARuntimeAreLookedAt() {
        #expect(match("node", nil, ["node", "a", "b", "c", "/x/codex"])?.agent.id == "codex")
        #expect(match("node", nil, ["node", "a", "b", "c", "d", "/x/codex"]) == nil)
    }

    @Test func unrelatedProcessesDoNotMatch() {
        #expect(match("node", nil, ["node", "server.js"]) == nil)
        #expect(match("Claude", "/Applications/Claude.app/Contents/MacOS/Claude", ["Claude"]) == nil)
        #expect(match("bash", nil, ["bash", "-c", "claude"]) == nil)
        #expect(match("vim", nil, ["vim", "claude.md"]) == nil)
    }

    @Test func needsArgumentsOnlyForRuntimesAndDirectMatches() {
        #expect(matcher.needsArguments(name: "node", path: nil))
        #expect(matcher.needsArguments(name: "claude", path: nil))
        #expect(!matcher.needsArguments(name: "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
    }

    @Test func catalogueOrderDecidesWhenTwoAgentsMatch() {
        let found = match("node", nil, ["node", "/x/claude", "/x/codex"])
        #expect(found?.agent.id == "claude")
    }

    // MARK: Service and one-shot

    private func kind(_ agent: String, _ arguments: [String]) -> RunKind {
        let definition = AgentCatalogue.builtIn.first { $0.id == agent }!
        return ArgumentClassifier.classify(arguments, for: definition)
    }

    @Test func serviceRunsAreDropped() {
        #expect(kind("claude", ["mcp", "serve"]) == .service)
        #expect(kind("claude", ["--verbose", "mcp", "serve"]) == .service)
        #expect(kind("codex", ["mcp-server"]) == .service)
        #expect(kind("codex", ["mcp"]) == .service)
        #expect(kind("claude", ["--chrome-native-host"]) == .service)
        #expect(kind("claude", ["--verbose", "--chrome-native-host=x"]) == .service)
    }

    @Test func aPromptThatLooksLikeASubcommandIsNotAService() {
        #expect(kind("claude", ["-p", "mcp"]) == .oneShot)
        #expect(kind("claude", ["--print", "mcp", "serve"]) == .oneShot)
        #expect(kind("claude", ["fix", "mcp"]) == .interactive)
    }

    @Test func oneShotFlagsAndSubcommands() {
        #expect(kind("claude", ["-p", "hello"]) == .oneShot)
        #expect(kind("claude", ["--verbose", "--print", "hello"]) == .oneShot)
        #expect(kind("codex", ["exec", "fix"]) == .oneShot)
        #expect(kind("codex", ["e", "fix"]) == .oneShot)
        #expect(kind("codex", ["-m", "o3", "exec", "fix"]) == .oneShot)
        #expect(kind("gemini", ["-p", "hi"]) == .oneShot)
        #expect(kind("gemini", ["--prompt=hi"]) == .oneShot)
        #expect(kind("cursor-agent", ["--print", "x"]) == .oneShot)
        #expect(kind("copilot", ["--prompt", "x"]) == .oneShot)
        #expect(kind("opencode", ["run", "x"]) == .oneShot)
        #expect(kind("amp", ["-x", "do it"]) == .oneShot)
        #expect(kind("amp", ["--execute", "do it"]) == .oneShot)
        #expect(kind("aider", ["--message", "x"]) == .oneShot)
        #expect(kind("aider", ["--message-file", "x.txt"]) == .oneShot)
        #expect(kind("aider", ["-m", "x"]) == .oneShot)
    }

    @Test func interactiveSessionsAreNotOneShot() {
        #expect(kind("claude", []) == .interactive)
        #expect(kind("claude", ["--resume"]) == .interactive)
        #expect(kind("codex", []) == .interactive)
        #expect(kind("codex", ["-m", "o3"]) == .interactive)
        #expect(kind("opencode", []) == .interactive)
    }

    @Test func streamJSONInputIsInteractiveWhateverElseIsSet() {
        #expect(kind("claude", ["-p", "--input-format", "stream-json", "--output-format", "stream-json"]) == .interactive)
        #expect(kind("claude", ["--print", "--input-format=stream-json"]) == .interactive)
        #expect(kind("claude", ["-p", "--input-format", "text"]) == .oneShot)
        #expect(kind("claude", ["-p", "--output-format", "stream-json"]) == .oneShot)
    }

    // MARK: Custom agents

    @Test(arguments: [
        ("uv run my_agent.py", "my_agent.py"),
        ("python -m my_agent", "my_agent"),
        ("  python3 /opt/tools/runner.py  ", "runner.py"),
        ("'./bin/my_runner'", "my_runner"),
        ("\"/Users/x/My Tools/agent\"", "agent"),
        ("python3x", "python3x"),
        ("pythonista", "pythonista"),
    ])
    func customNamesAreNormalised(typed: String, stored: String) {
        #expect(CustomAgentNames.normalise(typed) == stored)
    }

    @Test(arguments: [
        ("  node   ./tools/bot.js  ", "bot.js"),
        ("\"my_agent.py\"", "my_agent.py"),
        ("'/Users/me/code/runner.mjs'", "runner.mjs"),
        ("python /opt/tools/watcher", "watcher"),
        ("my-agent", "my-agent"),
        ("nodemon", "nodemon"),
    ])
    func moreCustomNamesAreNormalised(typed: String, stored: String) {
        #expect(CustomAgentNames.normalise(typed) == stored)
    }

    @Test(arguments: ["", "   ", "\"\"", "''", "scripts/", "run \"\"", "/", ".", ".."])
    func emptyNamesAreRejectedAsEmpty(typed: String) {
        #expect(CustomAgentNames.evaluate(typed) == .rejected(.empty))
        #expect(CustomAgentNames.normalise(typed) == nil)
    }

    @Test(arguments: ["node", "bun", "deno", "python", "python3", "Python", "python3.12", "python3.9",
                      "/usr/bin/python3.11", "uv run python", "/usr/bin/python3"])
    func interpretersAreRejected(typed: String) {
        #expect(CustomAgentNames.evaluate(typed) == .rejected(.interpreter))
        #expect(CustomAgentNames.normalise(typed) == nil)
    }

    @Test(arguments: ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "nu", "/bin/zsh", "\"bash\""])
    func shellsAreRejected(typed: String) {
        #expect(CustomAgentNames.evaluate(typed) == .rejected(.shell))
        #expect(CustomAgentNames.normalise(typed) == nil)
    }

    @Test(arguments: ["claude", "codex", "gemini", "cursor-agent", "copilot", "opencode", "amp", "aider",
                      "uv run claude", "python -m aider", "npx claude", "/usr/local/bin/aider"])
    func catalogueNamesAreRejected(typed: String) {
        #expect(CustomAgentNames.evaluate(typed) == .rejected(.knownAgent))
        #expect(CustomAgentNames.normalise(typed) == nil)
    }

    @Test func everyBuiltInExecutableIsRejectedAsKnown() {
        for name in AgentCatalogue.builtInExecutableNames {
            #expect(CustomAgentNames.normalise(name) == nil, "\(name) should be refused")
        }
    }

    @Test func hintsOnlyForRealMistakes() {
        #expect(CustomAgentNames.hint(for: .empty) == nil)
        #expect(CustomAgentNames.hint(for: .interpreter) != nil)
        #expect(CustomAgentNames.hint(for: .shell) != nil)
        #expect(CustomAgentNames.hint(for: .knownAgent) != nil)
    }

    @Test func nameWithoutExtensionAlsoMatchesScriptEndings() {
        let custom = CustomAgentNames.definition(for: "my_agent")
        #expect(custom.executableNames == ["my_agent", "my_agent.py", "my_agent.js", "my_agent.mjs", "my_agent.cjs", "my_agent.ts"])
        let customMatcher = AgentMatcher(definitions: [custom])
        #expect(customMatcher.match(name: "python3", path: nil, arguments: ["python3", "/work/my_agent.py"])?.agent.isCustom == true)
        #expect(customMatcher.match(name: "node", path: nil, arguments: ["node", "my_agent.mjs"]) != nil)
        #expect(customMatcher.match(name: "my_agent", path: nil, arguments: ["my_agent"]) != nil)
        #expect(customMatcher.match(name: "python3", path: nil, arguments: ["python3", "my_agent.rb"]) == nil)
    }

    @Test func nameWithAnExtensionMatchesOnlyItself() {
        let custom = CustomAgentNames.definition(for: "my_agent.py")
        #expect(custom.executableNames == ["my_agent.py"])
        let customMatcher = AgentMatcher(definitions: [custom])
        #expect(customMatcher.match(name: "python", path: nil, arguments: ["python", "my_agent.py"]) != nil)
        #expect(customMatcher.match(name: "python", path: nil, arguments: ["python", "my_agent.js"]) == nil)
    }

    @Test func storedListIsCleanedOfRejectsAndDuplicates() {
        #expect(CustomAgentNames.cleaned(["uv run a.py", "a.py", "node", "b", "claude", "'b'"]) == ["a.py", "b"])
        #expect(CustomAgentNames.definitions(for: ["b"]).first?.id == "custom:b")
    }
}
