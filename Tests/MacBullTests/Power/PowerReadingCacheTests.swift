import Foundation
import Testing
@testable import MacBull

struct PowerReadingCacheTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    private final class Source {
        var percent = 80
        private(set) var reads = 0

        func read() -> PowerReading {
            reads += 1
            return PowerReading(percent: percent, onBattery: false)
        }
    }

    @Test func readsOnceWithinTheLifetime() {
        var cache = PowerReadingCache()
        let source = Source()
        for offset in [0.0, 0.2, 0.9] {
            _ = cache.reading(at: start.addingTimeInterval(offset)) { source.read() }
        }
        #expect(source.reads == 1)
    }

    @Test func readsAgainAfterTheLifetime() {
        var cache = PowerReadingCache()
        let source = Source()
        _ = cache.reading(at: start) { source.read() }
        source.percent = 79
        let later = cache.reading(at: start.addingTimeInterval(PowerReadingCache.lifetime)) { source.read() }
        #expect(later.percent == 79)
        #expect(source.reads == 2)
    }

    @Test func aChangeNotificationClearsIt() {
        var cache = PowerReadingCache()
        let source = Source()
        _ = cache.reading(at: start) { source.read() }
        source.percent = 50
        cache.invalidate()
        #expect(cache.reading(at: start.addingTimeInterval(0.1)) { source.read() }.percent == 50)
    }

    @Test func aClockThatWentBackwardsDoesNotServeAStaleReading() {
        var cache = PowerReadingCache()
        let source = Source()
        _ = cache.reading(at: start) { source.read() }
        _ = cache.reading(at: start.addingTimeInterval(-60)) { source.read() }
        #expect(source.reads == 2)
    }
}
