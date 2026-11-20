import CoreGraphics
import Foundation

/// What the probe reads about one online display. Plain values, so the rule below is testable.
struct DisplayTraits: Equatable, Sendable {
    var isBuiltin: Bool
    /// The display mirrors another one (it is a copy, not a screen of its own).
    var mirrorsAnotherDisplay: Bool
    /// EDID vendor, or one of the "unknown" values CoreGraphics returns when there is none.
    var vendor: UInt32
    var model: UInt32
}

/// Which online displays make a closed lid a desk setup instead of a Mac in a bag.
enum DisplayRules {
    /// CoreGraphics answers 0 or `kDisplayVendorIDUnknown` for a display with no EDID vendor: virtual screens
    /// (Sidecar, screen sharing, headless software displays) look like this.
    private static let unknownIDs: Set<UInt32> = [0, UInt32.max]

    /// A display with no hardware identity is a software one.
    static func isPhysical(_ display: DisplayTraits) -> Bool {
        !unknownIDs.contains(display.vendor) && display.model != UInt32.max
    }

    /// The rule:
    /// - the built-in screen is not an external display;
    /// - a display that mirrors another one is a copy, not a desk screen;
    /// - a virtual display (no vendor or model) is not one either;
    /// - everything else counts, **including a physical display that is asleep**: the online list holds it, and
    ///   a dark monitor is still a desk. So the asleep flag is deliberately not consulted: it can never turn a
    ///   physical display into a virtual one, and a virtual one is already out.
    static func countsAsExternal(_ display: DisplayTraits) -> Bool {
        !display.isBuiltin && !display.mirrorsAnotherDisplay && isPhysical(display)
    }

    static func hasExternalDisplay(_ displays: [DisplayTraits]) -> Bool {
        displays.contains(where: countsAsExternal)
    }
}

/// External displays, counting one that is connected but asleep (a desk setup with a dark monitor).
enum DisplayProbe {
    private static let maxDisplays: UInt32 = 32

    /// True when an online display counts as external under `DisplayRules`. The online list includes sleeping displays.
    static func hasExternalDisplay() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &ids, &count) == .success else { return false }
        return DisplayRules.hasExternalDisplay(ids.prefix(Int(count)).map(traits))
    }

    private static func traits(of id: CGDirectDisplayID) -> DisplayTraits {
        DisplayTraits(
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            mirrorsAnotherDisplay: CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay,
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id)
        )
    }
}
