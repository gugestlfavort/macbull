import Foundation
import Testing
@testable import MacBull

struct HostAppTests {
    private let parents: [pid_t: pid_t] = [500: 400, 400: 300, 300: 200, 200: 1]

    @Test func firstRegularAppAboveTheSessionWins() {
        let found = HostApp.find(from: 500, parentOf: { parents[$0] }, isRegularApp: { $0 == 300 || $0 == 200 })
        #expect(found == 300)
    }

    @Test func noGuiAppAboveMeansNone() {
        #expect(HostApp.find(from: 500, parentOf: { parents[$0] }, isRegularApp: { _ in false }) == nil)
    }

    @Test func theSessionItselfCanBeTheApp() {
        #expect(HostApp.find(from: 500, parentOf: { parents[$0] }, isRegularApp: { $0 == 500 }) == 500)
    }

    @Test func aBrokenParentChainStopsInsteadOfLooping() {
        let loop: [pid_t: pid_t] = [10: 20, 20: 10]
        #expect(HostApp.find(from: 10, parentOf: { loop[$0] }, isRegularApp: { _ in false }) == nil)
        let selfParent: [pid_t: pid_t] = [10: 10]
        #expect(HostApp.find(from: 10, parentOf: { selfParent[$0] }, isRegularApp: { _ in false }) == nil)
    }

    @Test func launchdIsNeverAnApp() {
        #expect(HostApp.find(from: 500, parentOf: { parents[$0] }, isRegularApp: { $0 == 1 }) == nil)
    }
}
