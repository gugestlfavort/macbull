import Foundation

/// Opt-in Claude Code hooks: a tiny script Claude Code runs on its events, registered in
/// ~/.claude/settings.json. The script drops each event as a file for MacBull to read, so a
/// session's state is exact instead of guessed.
///
/// The merge and unmerge functions are pure (a dictionary in, a dictionary out) so they can be
/// tested without touching a real settings file.
enum ClaudeHooks {
    enum Failure: LocalizedError {
        case invalidJSON
        case unexpectedShape(String)
        case io(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                "Your Claude settings file (~/.claude/settings.json) is not valid JSON, so MacBull left it untouched. Fix it, then turn Claude Code hooks on again."
            case .unexpectedShape(let key):
                "\"\(key)\" in your Claude settings file is not shaped the way Claude Code expects, so MacBull left the file untouched."
            case .io(let message):
                "MacBull could not update the Claude Code hooks: \(message)"
            }
        }
    }

    /// Where everything lives. `home` is a parameter so a test can point it at a temp folder.
    struct Paths: Sendable {
        let home: URL

        static var standard: Paths { Paths(home: FileManager.default.homeDirectoryForCurrentUser) }

        var support: URL { home.appendingPathComponent("Library/Application Support/MacBull", isDirectory: true) }
        var script: URL { support.appendingPathComponent("claude-hook.sh") }
        var events: URL { support.appendingPathComponent("claude-events", isDirectory: true) }
        var settings: URL { home.appendingPathComponent(".claude/settings.json") }
        var backup: URL { home.appendingPathComponent(".claude/settings.json.macbull-backup") }
    }

    /// Events MacBull listens to.
    static let eventNames = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SubagentStop", "Notification", "SessionEnd"]
    /// Events Claude Code filters by tool name; "*" is every tool.
    private static let toolEventNames: Set<String> = ["PreToolUse", "PostToolUse"]

    /// Never blocks, never touches the network, always exits 0. It keeps five fields of the event and nothing
    /// else: `session_id`, `hook_event_name`, `cwd`, `notification_type` and `mentions_permission` (whether a
    /// notification's message says "permission"). Prompts, tool input and output, the message itself and the
    /// transcript path are read into a shell variable, never written. Plain POSIX sh plus `plutil`, which
    /// extracts each field and writes the JSON, so quotes, backslashes and control characters in a value
    /// (a folder name, say) are escaped by the system and not by hand. The result goes to a hidden file first
    /// and is renamed, so MacBull never reads half of one; files are owner-only (`umask 077`). With no MacBull
    /// running nothing is written. `MACBULL_PROCESS` only lets a test name a stand-in process.
    static let scriptSource = """
    #!/bin/sh
    # Installed by MacBull. Hands a few fields of each Claude Code hook event to MacBull. Never blocks, never fails.
    payload="$(cat 2>/dev/null)"
    /usr/bin/pgrep -qx "${MACBULL_PROCESS:-MacBull}" || exit 0
    umask 077
    dir="$HOME/Library/Application Support/MacBull/claude-events"
    mkdir -p "$dir" 2>/dev/null || exit 0
    name="$(date +%s)-$$-$PPID"
    plist="$dir/.$name.plist"
    tmp="$dir/.$name.tmp"
    field() { printf '%s' "$payload" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }
    session="$(field session_id)"
    event="$(field hook_event_name)"
    if [ -n "$session" ] && [ -n "$event" ]; then
      cwd="$(field cwd)"
      kind=""
      mentions=false
      if [ "$event" = "Notification" ]; then
        kind="$(field notification_type)"
        case "$(field message)" in
          *[Pp][Ee][Rr][Mm][Ii][Ss][Ss][Ii][Oo][Nn]*) mentions=true ;;
        esac
      fi
      {
        /usr/bin/plutil -create xml1 "$plist" &&
        /usr/bin/plutil -insert session_id -string "$session" "$plist" &&
        /usr/bin/plutil -insert hook_event_name -string "$event" "$plist" &&
        { [ -z "$cwd" ] || /usr/bin/plutil -insert cwd -string "$cwd" "$plist"; } &&
        { [ -z "$kind" ] || /usr/bin/plutil -insert notification_type -string "$kind" "$plist"; } &&
        /usr/bin/plutil -insert mentions_permission -bool "$mentions" "$plist" &&
        /usr/bin/plutil -convert json -o "$tmp" "$plist" &&
        mv "$tmp" "$dir/$name.json"
      } >/dev/null 2>&1
    fi
    rm -f "$plist" "$tmp" 2>/dev/null
    exit 0

    """

    // MARK: - Pure merge

    /// The command Claude Code runs: the script path in single quotes (the folder has a space).
    static func command(forScript path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isOurs(_ hook: Any, scriptPath: String) -> Bool {
        guard let hook = hook as? [String: Any], let command = hook["command"] as? String else { return false }
        return command.contains(scriptPath)
    }

    /// `settings` plus our hook on every event. Everything else stays as it is; an event that
    /// already has our hook is left alone, so installing twice changes nothing.
    static func merge(_ settings: [String: Any], scriptPath: String) throws -> [String: Any] {
        var root = settings
        var hooks = try hooksObject(in: root)
        for event in eventNames {
            var groups = try groups(of: hooks, event: event)
            let registered = groups.contains { group in
                (group["hooks"] as? [Any])?.contains { isOurs($0, scriptPath: scriptPath) } ?? false
            }
            if registered { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(forScript: scriptPath)]]]
            if toolEventNames.contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return root
    }

    /// `settings` without our hooks. Someone else's hook in the same group stays. An event list or
    /// the `hooks` object goes only when removing ours is what emptied it.
    static func unmerge(_ settings: [String: Any], scriptPath: String) throws -> [String: Any] {
        var root = settings
        guard root["hooks"] != nil else { return root }
        var hooks = try hooksObject(in: root)
        var removedAny = false
        for event in hooks.keys.sorted() {
            // Events of other tools are only touched when they are shaped like hook groups.
            guard eventNames.contains(event) || hooks[event] is [[String: Any]] else { continue }
            let (kept, removed) = removingOurs(from: try groups(of: hooks, event: event), scriptPath: scriptPath)
            guard removed else { continue }
            removedAny = true
            hooks[event] = kept.isEmpty ? nil : kept
        }
        if removedAny { root["hooks"] = hooks.isEmpty ? nil : hooks }
        return root
    }

    private static func removingOurs(from groups: [[String: Any]], scriptPath: String) -> (kept: [[String: Any]], removed: Bool) {
        var kept: [[String: Any]] = []
        var removed = false
        for var group in groups {
            guard let entries = group["hooks"] as? [Any] else {
                kept.append(group)
                continue
            }
            let others = entries.filter { !isOurs($0, scriptPath: scriptPath) }
            guard others.count != entries.count else {
                kept.append(group)
                continue
            }
            removed = true
            if !others.isEmpty {
                group["hooks"] = others
                kept.append(group)
            }
        }
        return (kept, removed)
    }

    private static func hooksObject(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw Failure.unexpectedShape("hooks") }
        return hooks
    }

    private static func groups(of hooks: [String: Any], event: String) throws -> [[String: Any]] {
        guard let value = hooks[event] else { return [] }
        guard let groups = value as? [[String: Any]] else { throw Failure.unexpectedShape("hooks.\(event)") }
        return groups
    }

    // MARK: - Files

    /// Writes the script and registers it in settings.json. Safe to run again.
    static func install(paths: Paths = .standard) throws {
        try writeScript(paths)
        try updateSettings(paths, createIfMissing: true) { try merge($0, scriptPath: paths.script.path) }
        try createFolder(paths.events)
    }

    /// Removes our hooks from settings.json, then the script and any unread events. When the
    /// settings can't be changed, the script stays because settings.json still points at it.
    static func uninstall(paths: Paths = .standard) throws {
        try updateSettings(paths, createIfMissing: false) { try unmerge($0, scriptPath: paths.script.path) }
        try removeIfPresent(paths.script)
        try removeIfPresent(paths.events)
    }

    private static func writeScript(_ paths: Paths) throws {
        let fileManager = FileManager.default
        let current = try? String(contentsOf: paths.script, encoding: .utf8)
        let executable = fileManager.isExecutableFile(atPath: paths.script.path)
        guard current != scriptSource || !executable else { return }
        do {
            try createFolder(paths.support)
            try scriptSource.write(to: paths.script, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.script.path)
        } catch {
            throw Failure.io(error.localizedDescription)
        }
    }

    private static func createFolder(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw Failure.io(error.localizedDescription)
        }
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw Failure.io(error.localizedDescription)
        }
    }

    /// Reads settings.json, applies `change`, and writes it back only when something changed. The
    /// first write keeps the original next to it. A file that isn't valid JSON is never written.
    private static func updateSettings(_ paths: Paths, createIfMissing: Bool,
                                       change: ([String: Any]) throws -> [String: Any]) throws {
        let fileManager = FileManager.default
        // The real file when settings.json is a symlink (dotfiles), so the link stays a link
        let target = paths.settings.resolvingSymlinksInPath()
        let existed = fileManager.fileExists(atPath: target.path)
        if !existed, !createIfMissing { return }

        var original: [String: Any] = [:]
        if existed {
            let data: Data
            do { data = try Data(contentsOf: target) } catch { throw Failure.io(error.localizedDescription) }
            original = try parseSettings(data)
        }
        let updated = try change(original)
        if existed, NSDictionary(dictionary: updated).isEqual(to: original) { return }
        if !existed, updated.isEmpty { return }

        do {
            if existed, !fileManager.fileExists(atPath: paths.backup.path) {
                try fileManager.copyItem(at: target, to: paths.backup)
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let permissions = (try? fileManager.attributesOfItem(atPath: target.path))?[.posixPermissions]
            try serialize(updated).write(to: target, options: .atomic)
            if let permissions { try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        } catch {
            throw Failure.io(error.localizedDescription)
        }
    }

    static func parseSettings(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data), let settings = object as? [String: Any] else {
            throw Failure.invalidJSON
        }
        return settings
    }

    static func serialize(_ settings: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
