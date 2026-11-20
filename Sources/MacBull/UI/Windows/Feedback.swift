import AppKit
import AVFoundation

/// Something that can tap the trackpad. A seam so tests do not need hardware.
@MainActor
protocol HapticPerforming: AnyObject {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern)
}

@MainActor
final class SystemHaptics: HapticPerforming {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Panel sounds and trackpad haptics. Players load on first use and are all released two seconds
/// after the last sound, because an open audio stream keeps the Mac awake.
@MainActor
final class Feedback: FeedbackPlaying {
    private let settings: Settings
    private let soundsFolder: URL?
    private let haptics: HapticPerforming
    private let systemUISounds: () -> Bool
    private let idleRelease: Duration
    private let pause: Pause
    private let isPlaying: (AVAudioPlayer) -> Bool
    private var players: [String: AVAudioPlayer] = [:]
    private var releaseTask: Task<Void, Never>?

    /// - Parameters:
    ///   - soundsFolder: where the .caf files are; nil looks in the app bundle's `Sounds` folder.
    ///   - idleRelease: how long after the last sound the players are let go.
    ///   - pause: how that wait is spent; tests pass one that does not touch the wall clock.
    ///   - isPlaying: whether a player still makes sound; tests pass one that is never busy.
    init(
        settings: Settings,
        soundsFolder: URL? = nil,
        haptics: HapticPerforming = SystemHaptics(),
        systemUISounds: @escaping () -> Bool = FeedbackPolicy.readSystemUISounds,
        idleRelease: Duration = .seconds(2),
        pause: @escaping Pause = { try await Task.sleep(for: $0) },
        isPlaying: @escaping (AVAudioPlayer) -> Bool = { $0.isPlaying }
    ) {
        self.settings = settings
        self.soundsFolder = soundsFolder
        self.haptics = haptics
        self.systemUISounds = systemUISounds
        self.idleRelease = idleRelease
        self.pause = pause
        self.isPlaying = isPlaying
    }

    typealias Pause = @Sendable (Duration) async throws -> Void

    /// Players currently loaded (zero when the audio is released).
    var loadedPlayerCount: Int { players.count }

    /// Whether a release is waiting for its idle time.
    var releaseIsScheduled: Bool { releaseTask != nil }

    /// Returns once the scheduled release has run (or none is scheduled). For tests.
    func settleRelease() async {
        while let task = releaseTask {
            await task.value
            if releaseTask == task { return }
        }
    }

    func play(_ cue: SoundCue) {
        guard let volume = FeedbackPolicy.cueVolume(
            sounds: settings.sounds, volume: settings.soundVolume, systemUISounds: systemUISounds()
        ), let player = player(for: FeedbackPolicy.fileName(for: cue)) else { return }
        player.numberOfLoops = 0
        player.currentTime = 0
        player.volume = volume
        player.play()
        scheduleRelease()
    }

    func setFizz(_ level: Double?) {
        guard let volume = FeedbackPolicy.fizzVolume(
            level: level, sounds: settings.sounds, volume: settings.soundVolume, systemUISounds: systemUISounds()
        ) else {
            stopFizz()
            return
        }
        guard let player = player(for: FeedbackPolicy.fizzFileName) else { return }
        releaseTask?.cancel()
        releaseTask = nil
        player.numberOfLoops = -1
        player.volume = volume
        if !player.isPlaying { player.play() }
    }

    func detent(strong: Bool) {
        guard settings.haptics else { return }
        haptics.perform(strong ? .levelChange : .alignment)
    }

    /// Lets go of every player now.
    func releaseAll() {
        releaseTask?.cancel()
        releaseTask = nil
        for player in players.values {
            player.stop()
        }
        players.removeAll()
    }

    private func stopFizz() {
        guard let player = players[FeedbackPolicy.fizzFileName] else { return }
        player.stop()
        player.currentTime = 0
        scheduleRelease()
    }

    private func player(for file: String) -> AVAudioPlayer? {
        if let existing = players[file] { return existing }
        guard let url = url(for: file) else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[file] = player
            return player
        } catch {
            Log.ui.error("Could not load sound \(file, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Missing files are normal in an unbundled development run: nothing plays.
    private func url(for file: String) -> URL? {
        if let soundsFolder {
            let candidate = soundsFolder.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
    }

    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self, idleRelease, pause] in
            do {
                try await pause(idleRelease)
            } catch {
                return
            }
            self?.releaseIfQuiet()
        }
    }

    /// Releases when nothing is playing; otherwise checks again after the same wait.
    private func releaseIfQuiet() {
        if players.values.contains(where: isPlaying) {
            scheduleRelease()
        } else {
            releaseAll()
        }
    }
}
