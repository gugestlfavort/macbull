import Foundation

/// The decisions behind sound and haptics, kept pure so they can be tested without audio.
enum FeedbackPolicy {
    /// The Mac's own "Play user interface sound effects" switch. A missing value counts as on.
    static func systemUISoundsEnabled(_ raw: Any?) -> Bool {
        if let number = raw as? NSNumber { return number.boolValue }
        return true
    }

    /// Reads the system preference.
    static func readSystemUISounds() -> Bool {
        systemUISoundsEnabled(UserDefaults(suiteName: ".GlobalPreferences")?.object(forKey: "com.apple.sound.uiaudio.enabled"))
    }

    /// Player volume for a one-shot cue, or nil when it must stay silent.
    static func cueVolume(sounds: Bool, volume: Double, systemUISounds: Bool) -> Float? {
        guard sounds, systemUISounds else { return nil }
        let clamped = min(max(volume, 0), 1)
        return clamped > 0 ? Float(clamped) : nil
    }

    /// Player volume of the fizz loop for a pour level, or nil when the loop must stop.
    static func fizzVolume(level: Double?, sounds: Bool, volume: Double, systemUISounds: Bool) -> Float? {
        guard let level, let base = cueVolume(sounds: sounds, volume: volume, systemUISounds: systemUISounds) else {
            return nil
        }
        let scaled = base * Float(min(max(level, 0), 1))
        return scaled > 0.001 ? scaled : nil
    }

    static func fileName(for cue: SoundCue) -> String {
        "macbull-\(cue.rawValue).caf"
    }

    static let fizzFileName = "macbull-fizz.caf"
}
