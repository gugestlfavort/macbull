import AppKit
import Testing
@testable import MacBull

struct FeedbackPolicyTests {
    @Test func cueIsSilentWhenSoundsAreOff() {
        #expect(FeedbackPolicy.cueVolume(sounds: false, volume: 0.5, systemUISounds: true) == nil)
    }

    @Test func cueIsSilentWhenTheSystemMutesInterfaceSounds() {
        #expect(FeedbackPolicy.cueVolume(sounds: true, volume: 0.5, systemUISounds: false) == nil)
    }

    @Test func cueIsSilentAtZeroVolume() {
        #expect(FeedbackPolicy.cueVolume(sounds: true, volume: 0, systemUISounds: true) == nil)
    }

    @Test func cueFollowsTheVolumeSettingAndStaysInRange() {
        #expect(FeedbackPolicy.cueVolume(sounds: true, volume: 0.3, systemUISounds: true) == 0.3)
        #expect(FeedbackPolicy.cueVolume(sounds: true, volume: 7, systemUISounds: true) == 1)
        #expect(FeedbackPolicy.cueVolume(sounds: true, volume: -1, systemUISounds: true) == nil)
    }

    @Test func fizzFollowsTheLevel() {
        let half = FeedbackPolicy.fizzVolume(level: 0.5, sounds: true, volume: 0.4, systemUISounds: true)
        #expect(half == 0.2)
        let full = FeedbackPolicy.fizzVolume(level: 1, sounds: true, volume: 0.4, systemUISounds: true)
        #expect(full == 0.4)
        let over = FeedbackPolicy.fizzVolume(level: 3, sounds: true, volume: 0.4, systemUISounds: true)
        #expect(over == 0.4)
    }

    @Test func fizzStopsOnNilLevelAndWhenGated() {
        #expect(FeedbackPolicy.fizzVolume(level: nil, sounds: true, volume: 0.4, systemUISounds: true) == nil)
        #expect(FeedbackPolicy.fizzVolume(level: 0, sounds: true, volume: 0.4, systemUISounds: true) == nil)
        #expect(FeedbackPolicy.fizzVolume(level: 0.8, sounds: false, volume: 0.4, systemUISounds: true) == nil)
        #expect(FeedbackPolicy.fizzVolume(level: 0.8, sounds: true, volume: 0.4, systemUISounds: false) == nil)
    }

    @Test func missingSystemPreferenceCountsAsOn() {
        #expect(FeedbackPolicy.systemUISoundsEnabled(nil))
        #expect(FeedbackPolicy.systemUISoundsEnabled(NSNumber(value: true)))
        #expect(!FeedbackPolicy.systemUISoundsEnabled(NSNumber(value: false)))
        #expect(FeedbackPolicy.systemUISoundsEnabled("not a number"))
    }

    @Test func everyCueHasASoundFile() {
        for cue in SoundCue.allCases {
            let url = WindowsTestSupport.soundsFolder.appendingPathComponent(FeedbackPolicy.fileName(for: cue))
            #expect(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent)")
        }
        let fizz = WindowsTestSupport.soundsFolder.appendingPathComponent(FeedbackPolicy.fizzFileName)
        #expect(FileManager.default.fileExists(atPath: fizz.path))
    }
}

@MainActor
struct FeedbackPlayerTests {
    private func makeFeedback(
        settings: Settings,
        folder: URL? = WindowsTestSupport.soundsFolder,
        haptics: WindowsFakeHaptics = WindowsFakeHaptics(),
        systemUISounds: Bool = true,
        idleRelease: Duration = .seconds(2)
    ) -> Feedback {
        // The idle wait returns at once and no sound counts as playing: the release is then decided by
        // the code alone, never by how long a real clip or a busy machine takes.
        Feedback(
            settings: settings, soundsFolder: folder, haptics: haptics,
            systemUISounds: { systemUISounds }, idleRelease: idleRelease,
            pause: { _ in }, isPlaying: { _ in false }
        )
    }

    @Test func playingACueLoadsAPlayerAndReleasesItAfterTheIdleTime() async {
        let settings = WindowsTestSupport.makeSettings()
        settings.soundVolume = 0.01
        let feedback = makeFeedback(settings: settings)
        feedback.play(.clink)
        #expect(feedback.loadedPlayerCount == 1)
        #expect(feedback.releaseIsScheduled)
        await feedback.settleRelease()
        #expect(feedback.loadedPlayerCount == 0)
    }

    @Test func nothingLoadsWhenSoundsAreOff() {
        let settings = WindowsTestSupport.makeSettings()
        settings.sounds = false
        let feedback = makeFeedback(settings: settings)
        feedback.play(.crack)
        feedback.setFizz(1)
        #expect(feedback.loadedPlayerCount == 0)
    }

    @Test func nothingLoadsWhenTheSystemMutesInterfaceSounds() {
        let feedback = makeFeedback(settings: WindowsTestSupport.makeSettings(), systemUISounds: false)
        feedback.play(.crack)
        #expect(feedback.loadedPlayerCount == 0)
    }

    @Test func missingSoundFilesAreSilent() {
        let missing = URL(fileURLWithPath: "/nonexistent/sounds")
        let feedback = makeFeedback(settings: WindowsTestSupport.makeSettings(), folder: missing)
        feedback.play(.burp)
        feedback.setFizz(0.5)
        feedback.setFizz(nil)
        #expect(feedback.loadedPlayerCount == 0)
    }

    @Test func fizzStopsAtOnceOnNilAndTheAudioIsReleasedLater() async {
        let settings = WindowsTestSupport.makeSettings()
        settings.soundVolume = 0.01
        let feedback = makeFeedback(settings: settings)
        feedback.setFizz(0.6)
        #expect(feedback.loadedPlayerCount == 1)
        // Still pouring: no release is waiting, so the loop cannot go under the user's finger.
        await feedback.settleRelease()
        #expect(!feedback.releaseIsScheduled)
        #expect(feedback.loadedPlayerCount == 1)
        feedback.setFizz(nil)
        #expect(feedback.releaseIsScheduled)
        await feedback.settleRelease()
        #expect(feedback.loadedPlayerCount == 0)
    }

    @Test func hapticsFollowTheSettingAndStrength() {
        let settings = WindowsTestSupport.makeSettings()
        let haptics = WindowsFakeHaptics()
        let feedback = makeFeedback(settings: settings, haptics: haptics)
        feedback.detent(strong: false)
        feedback.detent(strong: true)
        #expect(haptics.patterns == [.alignment, .levelChange])
        settings.haptics = false
        feedback.detent(strong: true)
        #expect(haptics.patterns.count == 2)
    }
}
