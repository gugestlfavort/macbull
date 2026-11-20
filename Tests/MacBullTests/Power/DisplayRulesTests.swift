import Testing
@testable import MacBull

struct DisplayRulesTests {
    private static let dell = DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: 0x10AC, model: 0xA0C7)
    private static let builtin = DisplayTraits(isBuiltin: true, mirrorsAnotherDisplay: false, vendor: 0x0610, model: 0xA050)

    @Test func aRealExternalDisplayCounts() {
        #expect(DisplayRules.countsAsExternal(Self.dell))
        #expect(DisplayRules.hasExternalDisplay([Self.builtin, Self.dell]))
    }

    @Test func theBuiltInScreenAloneIsNotAnExternalDisplay() {
        #expect(!DisplayRules.hasExternalDisplay([Self.builtin]))
        #expect(!DisplayRules.hasExternalDisplay([]))
    }

    @Test func aMirroredCopyDoesNotCount() {
        var copy = Self.dell
        copy.mirrorsAnotherDisplay = true
        #expect(!DisplayRules.countsAsExternal(copy))
        #expect(!DisplayRules.hasExternalDisplay([Self.builtin, copy]))
    }

    @Test func aDisplayThatIsTheMirrorSourceStillCounts() {
        // The built-in mirrors the external one (clamshell with a monitor): the monitor itself is not a copy.
        var laptop = Self.builtin
        laptop.mirrorsAnotherDisplay = true
        #expect(DisplayRules.hasExternalDisplay([laptop, Self.dell]))
    }

    @Test(arguments: [
        DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: 0, model: 0),
        DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: UInt32.max, model: UInt32.max),
        DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: 0, model: 0x1234),
        DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: 0x10AC, model: UInt32.max),
    ])
    func aVirtualDisplayWithNoHardwareIdentityDoesNotCount(_ display: DisplayTraits) {
        #expect(!DisplayRules.isPhysical(display))
        #expect(!DisplayRules.hasExternalDisplay([Self.builtin, display]))
    }

    @Test func aVirtualDisplayDoesNotHideARealOne() {
        let virtual = DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: 0, model: 0)
        #expect(DisplayRules.hasExternalDisplay([Self.builtin, virtual, Self.dell]))
    }

    @Test func aPhysicalDisplayWithModelZeroStillCounts() {
        let plain = DisplayTraits(isBuiltin: false, mirrorsAnotherDisplay: false, vendor: 0x1234, model: 0)
        #expect(DisplayRules.countsAsExternal(plain))
    }
}
