import IOKit.pwr_mgt
import Testing
@testable import MacBull

@MainActor
final class FakeAssertionBackend: AssertionBackend {
    var created: [IOKitPowerAssertions.Kind] = []
    var reasons: [String] = []
    var released: [IOPMAssertionID] = []
    var refuse = false
    private var next: IOPMAssertionID = 100

    func create(kind: IOKitPowerAssertions.Kind, reason: String) -> IOPMAssertionID? {
        if refuse { return nil }
        created.append(kind)
        reasons.append(reason)
        next += 1
        return next
    }

    func release(_ id: IOPMAssertionID) {
        released.append(id)
    }
}

@MainActor
struct IOKitPowerAssertionsTests {
    @Test func createsOnlyOnChange() {
        let backend = FakeAssertionBackend()
        let assertions = IOKitPowerAssertions(backend: backend)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        #expect(backend.created == [.systemSleep])
        assertions.set(preventSystemSleep: true, preventDisplaySleep: true)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: true)
        #expect(backend.created == [.systemSleep, .displaySleep])
        #expect(backend.released.isEmpty)
    }

    @Test func releasesOnlyOnChange() {
        let backend = FakeAssertionBackend()
        let assertions = IOKitPowerAssertions(backend: backend)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: true)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        #expect(backend.released == [102])
        assertions.set(preventSystemSleep: false, preventDisplaySleep: false)
        assertions.set(preventSystemSleep: false, preventDisplaySleep: false)
        #expect(backend.released == [102, 101])
    }

    @Test func recreatesAfterRelease() {
        let backend = FakeAssertionBackend()
        let assertions = IOKitPowerAssertions(backend: backend)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        assertions.set(preventSystemSleep: false, preventDisplaySleep: false)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        #expect(backend.created == [.systemSleep, .systemSleep])
    }

    @Test func retriesWhenTheSystemRefusedBefore() {
        let backend = FakeAssertionBackend()
        backend.refuse = true
        let assertions = IOKitPowerAssertions(backend: backend)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        backend.refuse = false
        assertions.set(preventSystemSleep: true, preventDisplaySleep: false)
        #expect(backend.created == [.systemSleep])
    }

    @Test func reasonsAreOurOwnWords() {
        let backend = FakeAssertionBackend()
        let assertions = IOKitPowerAssertions(backend: backend)
        assertions.set(preventSystemSleep: true, preventDisplaySleep: true)
        #expect(backend.reasons.allSatisfy { $0.hasPrefix("MacBull") })
    }

    @Test func realBackendCreatesAndReleases() throws {
        let backend = SystemAssertionBackend()
        let id = try #require(backend.create(kind: .systemSleep, reason: "MacBull test, released at once"))
        backend.release(id)
    }
}
