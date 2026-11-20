import Foundation

/// A matched process that is not a service.
struct RecognisedProcess: Sendable {
    let entry: ProcessTable.Entry
    let match: AgentMatch
    let kind: RunKind

    var agent: AgentDefinition { match.agent }
}

struct Recognition: Sendable {
    /// Every matched process except services (sessions and the agent's own child processes).
    let processes: [pid_t: RecognisedProcess]
    /// Sessions in list order: agent order, then start time, then pid.
    let sessions: [RecognisedProcess]

    /// Pids of the matched processes of one agent.
    func processIDs(ofAgent id: String) -> Set<pid_t> {
        Set(processes.values.filter { $0.agent.id == id }.map(\.entry.pid))
    }

    func sessions(ofAgent id: String) -> [ProcessTable.Entry] {
        sessions.filter { $0.agent.id == id }.map(\.entry)
    }
}

enum AgentRecognizer {
    static func recognise(table: ProcessTable, matcher: AgentMatcher, ownPID: pid_t) -> Recognition {
        var processes: [pid_t: RecognisedProcess] = [:]
        for entry in table.entries.values where entry.pid != ownPID {
            guard let match = matcher.match(name: entry.name, path: entry.path, arguments: entry.arguments) else { continue }
            let kind = ArgumentClassifier.classify(match.ownArguments, for: match.agent)
            guard kind != .service else { continue }
            processes[entry.pid] = RecognisedProcess(entry: entry, match: match, kind: kind)
        }
        let order = Dictionary(uniqueKeysWithValues: matcher.definitions.enumerated().map { ($1.id, $0) })
        let sessions = processes.values
            .filter { process in
                // A matched child of the same agent is the agent's own process, not another session.
                processes[process.entry.parent]?.agent.id != process.agent.id
            }
            .sorted { lhs, rhs in
                let left = (order[lhs.agent.id] ?? .max, lhs.entry.startTime, lhs.entry.pid)
                let right = (order[rhs.agent.id] ?? .max, rhs.entry.startTime, rhs.entry.pid)
                return left < right
            }
        return Recognition(processes: processes, sessions: sessions)
    }
}
