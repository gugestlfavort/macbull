import Foundation
import OSLog

/// One hook call, as the script left it in the events folder. Holds only what MacBull needs:
/// no message text, tool input or transcript path is ever kept.
struct ClaudeHookEvent: Sendable, Equatable {
    let sessionID: String
    let name: String
    let cwd: String?
    /// `notification_type` of a Notification event, for example "permission_prompt" or "idle_prompt".
    let notificationType: String?
    /// The notification's message mentions permission. Only used when `notificationType` is missing.
    let mentionsPermission: Bool
    /// The process that ran the script: Claude itself, or a shell it started for the hook.
    let parentPID: pid_t
    /// When the script wrote it.
    let date: Date

    init(
        sessionID: String, name: String, cwd: String?, notificationType: String? = nil,
        mentionsPermission: Bool = false, parentPID: pid_t, date: Date
    ) {
        self.sessionID = sessionID
        self.name = name
        self.cwd = cwd
        self.notificationType = notificationType
        self.mentionsPermission = mentionsPermission
        self.parentPID = parentPID
        self.date = date
    }
}

enum ClaudeHookEvents {
    /// An event older than this says nothing about now (the app wasn't running). It is deleted unread.
    static let maxAge: TimeInterval = 30 * 60

    /// The fields we read. Everything else in the file is skipped. The current script writes the answer
    /// `mentions_permission` and no message; a file with a `message` (an older script) is still read, and the
    /// message is reduced to one yes/no answer inside `init` without being kept.
    private struct Payload: Decodable {
        let sessionID: String?
        let name: String?
        let cwd: String?
        let notificationType: String?
        let mentionsPermission: Bool

        private enum Keys: String, CodingKey {
            case sessionID = "session_id"
            case name = "hook_event_name"
            case cwd
            case notificationType = "notification_type"
            case mentionsPermission = "mentions_permission"
            case message
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            sessionID = try? container.decode(String.self, forKey: .sessionID)
            name = try? container.decode(String.self, forKey: .name)
            cwd = try? container.decode(String.self, forKey: .cwd)
            notificationType = try? container.decode(String.self, forKey: .notificationType)
            if let answer = try? container.decode(Bool.self, forKey: .mentionsPermission) {
                mentionsPermission = answer
            } else {
                let message = try? container.decode(String.self, forKey: .message)
                mentionsPermission = message?.localizedCaseInsensitiveContains("permission") ?? false
            }
        }
    }

    /// File names are `<seconds>-<script pid>-<parent pid>.json`.
    static func parentPID(fromFileName name: String) -> pid_t {
        let stem = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
        return stem.split(separator: "-").last.flatMap { pid_t($0) } ?? 0
    }

    static func parse(_ data: Data, fileName: String, date: Date) -> ClaudeHookEvent? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let sessionID = payload.sessionID, !sessionID.isEmpty,
              let name = payload.name else { return nil }
        return ClaudeHookEvent(
            sessionID: sessionID, name: name, cwd: payload.cwd, notificationType: payload.notificationType,
            mentionsPermission: payload.mentionsPermission, parentPID: parentPID(fromFileName: fileName), date: date
        )
    }

    /// Reads every finished event file and deletes it, oldest first. Hidden files are the script's
    /// work in progress and are left alone, unless one was abandoned long ago.
    static func drain(folder: URL, now: Date = Date()) -> [ClaudeHookEvent] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return [] }
        var events: [(name: String, event: ClaudeHookEvent)] = []
        for name in names {
            let url = folder.appendingPathComponent(name)
            let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? now
            let isStale = now.timeIntervalSince(modified) > maxAge
            if name.hasPrefix(".") {
                if isStale { remove(url) }
                continue
            }
            guard name.hasSuffix(".json") else { continue }
            defer { remove(url) }
            guard !isStale, let data = try? Data(contentsOf: url),
                  let event = parse(data, fileName: name, date: modified) else { continue }
            events.append((name, event))
        }
        events.sort { ($0.event.date, $0.name) < ($1.event.date, $1.name) }
        return events.map(\.event)
    }

    private static func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.agents.error("Could not delete a hook event file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
