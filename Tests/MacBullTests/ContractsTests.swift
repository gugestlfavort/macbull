import Testing
@testable import MacBull

@MainActor
struct ContractsTests {
    @Test func menuIconBaseFollowsState() {
        let state = AppState()
        #expect(state.menuIconBase == .off)
        state.cutoff = .heat
        #expect(state.menuIconBase == .cutoff)
        state.agentHold = true
        #expect(state.menuIconBase == .agents)
    }
}
