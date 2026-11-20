// Synthesises every MacBull sound from scratch (no samples) and writes 16-bit mono CAF files.
// Run from the repo root:
//   swift scripts/make-sounds.swift Resources/Sounds
// Then it reads each file back and prints duration, peak level and, for the fizz loop, the seam check.
import AVFoundation
import Foundation

let sampleRate = 44_100.0
/// Peak level of every file: -3 dBFS.
let peakTarget: Float = 0.7079
let fizzSeconds = 2.0

// MARK: - Small DSP kit

/// Deterministic noise (xorshift), so a rerun writes the same files.
struct Noise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// White noise in -1...1.
    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(Double(state >> 11) / Double(1 << 53)) * 2 - 1
    }

    /// Uniform in 0...1.
    mutating func unit() -> Float {
        (next() + 1) / 2
    }
}

/// RBJ biquad filter.
struct Biquad {
    enum Kind {
        case lowpass
        case highpass
        case bandpass
    }

    private var b0: Float
    private var b1: Float
    private var b2: Float
    private var a1: Float
    private var a2: Float
    private var z1: Float = 0
    private var z2: Float = 0

    init(_ kind: Kind, frequency: Double, q: Double = 0.707) {
        let w = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w) / (2 * q)
        let cosW = cos(w)
        let a0 = 1 + alpha
        var nb0 = 0.0
        var nb1 = 0.0
        var nb2 = 0.0
        switch kind {
        case .lowpass:
            nb0 = (1 - cosW) / 2
            nb1 = 1 - cosW
            nb2 = (1 - cosW) / 2
        case .highpass:
            nb0 = (1 + cosW) / 2
            nb1 = -(1 + cosW)
            nb2 = (1 + cosW) / 2
        case .bandpass:
            nb0 = alpha
            nb1 = 0
            nb2 = -alpha
        }
        b0 = Float(nb0 / a0)
        b1 = Float(nb1 / a0)
        b2 = Float(nb2 / a0)
        a1 = Float(-2 * cosW / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * sampleRate))
}

func time(_ index: Int) -> Double {
    Double(index) / sampleRate
}

/// Adds `part` into `buffer` starting at `start` seconds (clipped to the buffer).
func mix(_ part: [Float], into buffer: inout [Float], at start: Double, gain: Float = 1) {
    let offset = Int(start * sampleRate)
    for (i, value) in part.enumerated() where offset + i < buffer.count && offset + i >= 0 {
        buffer[offset + i] += value * gain
    }
}

/// Scales to the target peak.
func normalise(_ samples: [Float]) -> [Float] {
    let peak = samples.reduce(0) { max($0, abs($1)) }
    guard peak > 0 else { return samples }
    let gain = peakTarget / peak
    return samples.map { $0 * gain }
}

/// Short fades at both ends so a file never starts or stops with a step.
func fade(_ samples: [Float], inSeconds: Double, outSeconds: Double) -> [Float] {
    var out = samples
    let fadeIn = max(1, Int(inSeconds * sampleRate))
    let fadeOut = max(1, Int(outSeconds * sampleRate))
    for i in 0..<min(fadeIn, out.count) {
        out[i] *= Float(i) / Float(fadeIn)
    }
    for i in 0..<min(fadeOut, out.count) {
        out[out.count - 1 - i] *= Float(i) / Float(fadeOut)
    }
    return out
}

// MARK: - The sounds

/// Can opening: a sharp click, a tiny thump, then a short hiss.
func crack() -> [Float] {
    var out = silence(0.55)
    var clickNoise = Noise(seed: 11)
    var hissNoise = Noise(seed: 12)
    var click = Biquad(.highpass, frequency: 1500)
    var hiss = Biquad(.bandpass, frequency: 6500, q: 0.8)
    for i in 0..<out.count {
        let t = time(i)
        let clickPart = click.process(clickNoise.next()) * Float(exp(-t / 0.0012))
        let thump = Float(sin(2 * .pi * 1900 * t) * exp(-t / 0.004)) * 0.6
        let start = max(0, t - 0.012)
        let rise = 1 - exp(-start / 0.004)
        let hissEnvelope = t > 0.012 ? Float(rise * exp(-start / 0.11)) : 0
        out[i] = clickPart + thump + hiss.process(hissNoise.next()) * hissEnvelope * 0.9
    }
    return fade(normalise(out), inSeconds: 0.0003, outSeconds: 0.02)
}

/// Two cans touching: inharmonic metal partials with fast decays.
func clink() -> [Float] {
    func strike(scale: Double) -> [Float] {
        var out = silence(0.5)
        let partials: [(frequency: Double, amplitude: Double, decay: Double)] = [
            (2093, 1.0, 0.16), (3140, 0.6, 0.10), (4720, 0.35, 0.07), (6300, 0.2, 0.04),
        ]
        var noise = Noise(seed: 21)
        var tick = Biquad(.highpass, frequency: 3000)
        for i in 0..<out.count {
            let t = time(i)
            var sum = 0.0
            for partial in partials {
                sum += partial.amplitude * sin(2 * .pi * partial.frequency * scale * t) * exp(-t / partial.decay)
            }
            let onset = tick.process(noise.next()) * Float(exp(-t / 0.0015)) * 0.5
            out[i] = Float(sum) + onset
        }
        return out
    }
    var out = silence(0.55)
    mix(strike(scale: 1), into: &out, at: 0)
    mix(strike(scale: 1.12), into: &out, at: 0.018, gain: 0.5)
    return fade(normalise(out), inSeconds: 0.0003, outSeconds: 0.02)
}

/// Crinkly noise bursts that thin out, like a can being crushed.
func crumple() -> [Float] {
    var rng = Noise(seed: 31)
    var out = silence(0.9)
    var start = 0.0
    while start < 0.78 {
        let length = 0.004 + Double(rng.unit()) * 0.014
        let centre = 1200 + Double(rng.unit()) * 5500
        let amplitude = (0.3 + 0.7 * rng.unit()) * Float(1 - start / 1.0)
        var filter = Biquad(.bandpass, frequency: centre, q: 2)
        var noise = Noise(seed: UInt64(rng.unit() * 1_000_000) + 1)
        var burst = silence(length * 3)
        for i in 0..<burst.count {
            let t = time(i)
            let attack = min(1, t / 0.0005)
            burst[i] = filter.process(noise.next()) * Float(attack * exp(-t / (length * 0.45))) * amplitude
        }
        mix(burst, into: &out, at: start)
        start += 0.004 + Double(rng.unit()) * 0.035 * (1 + start * 2)
    }
    return fade(normalise(out), inSeconds: 0.001, outSeconds: 0.03)
}

/// A playful low burp: a pitch that jumps up and slides down, with a gurgle.
func burp() -> [Float] {
    let duration = 0.62
    var out = silence(duration)
    var lowpass = Biquad(.lowpass, frequency: 700, q: 2)
    var breath = Noise(seed: 41)
    var breathFilter = Biquad(.bandpass, frequency: 900, q: 1)
    var phase = 0.0
    for i in 0..<out.count {
        let t = time(i)
        var frequency: Double
        if t < 0.12 {
            let x = t / 0.12
            frequency = 95 + 55 * (x * x * (3 - 2 * x))
        } else {
            frequency = 150 - 95 * pow((t - 0.12) / 0.5, 1.3)
        }
        frequency *= 1 + 0.03 * sin(2 * .pi * 23 * t)
        phase += 2 * .pi * frequency / sampleRate
        var voiced = 0.0
        for harmonic in 1...30 where Double(harmonic) * frequency < 3000 {
            voiced += sin(Double(harmonic) * phase) / Double(harmonic)
        }
        let gurgle = 0.75 + 0.25 * sin(2 * .pi * 30 * t)
        let envelope = min(1, t / 0.025) * min(1, (duration - t) / 0.12)
        let voice = lowpass.process(Float(voiced))
        let air = breathFilter.process(breath.next()) * 0.15
        out[i] = (voice + air) * Float(gurgle * envelope)
    }
    return fade(normalise(out), inSeconds: 0.002, outSeconds: 0.02)
}

/// Two seconds of filtered noise with tiny pops that loops without a seam.
func fizz() -> [Float] {
    let count = Int(fizzSeconds * sampleRate)
    var rng = Noise(seed: 51)
    var highpass = Biquad(.highpass, frequency: 3000)
    var lowpass = Biquad(.lowpass, frequency: 9000)
    let input = (0..<count).map { _ in rng.next() }
    // Run the filters over the buffer twice and keep the second pass: the filter memory at the start
    // is then the tail of the buffer, so the end flows into the start without a step.
    var out = [Float](repeating: 0, count: count)
    for pass in 0..<2 {
        for i in 0..<count {
            let value = lowpass.process(highpass.process(input[i]))
            if pass == 1 { out[i] = value }
        }
    }
    // Slow level movement with whole cycles per loop, so it is periodic.
    for i in 0..<count {
        let x = Double(i) / Double(count)
        let movement = 1 + 0.25 * sin(2 * .pi * 3 * x) + 0.12 * sin(2 * .pi * 7 * x + 0.3)
        out[i] *= Float(movement)
    }
    // Tiny pops: short damped sines, wrapped around the end of the buffer.
    for _ in 0..<90 {
        let at = Int(rng.unit() * Float(count))
        let frequency = 3000 + Double(rng.unit()) * 5000
        let amplitude = (0.2 + 0.7 * rng.unit()) * 3
        for j in 0..<Int(0.008 * sampleRate) {
            let t = time(j)
            out[(at + j) % count] += amplitude * Float(exp(-t / 0.0007) * sin(2 * .pi * frequency * t))
        }
    }
    return normalise(out)
}

/// Bright two-tone ping for "agents done".
func ping() -> [Float] {
    func note(_ frequency: Double) -> [Float] {
        var out = silence(0.55)
        for i in 0..<out.count {
            let t = time(i)
            let tone = sin(2 * .pi * frequency * t) + 0.3 * sin(4 * .pi * frequency * t) + 0.1 * sin(6 * .pi * frequency * t)
            out[i] = Float(tone * min(1, t / 0.003) * exp(-t / 0.12))
        }
        return out
    }
    var out = silence(0.75)
    mix(note(1318.51), into: &out, at: 0)
    mix(note(1975.53), into: &out, at: 0.11)
    return fade(normalise(out), inSeconds: 0.001, outSeconds: 0.03)
}

/// Two soft knocks on a door for "waiting for you".
func knock() -> [Float] {
    func single() -> [Float] {
        var out = silence(0.3)
        var noise = Noise(seed: 61)
        var click = Biquad(.lowpass, frequency: 900)
        var phase = 0.0
        for i in 0..<out.count {
            let t = time(i)
            let frequency = 120 + 90 * exp(-t / 0.03)
            phase += 2 * .pi * frequency / sampleRate
            let body = sin(phase) * min(1, t / 0.002) * exp(-t / 0.045)
            let tap = click.process(noise.next()) * Float(exp(-t / 0.01)) * 0.5
            out[i] = Float(body) + tap
        }
        return out
    }
    var out = silence(0.55)
    mix(single(), into: &out, at: 0)
    mix(single(), into: &out, at: 0.2, gain: 0.8)
    return fade(normalise(out), inSeconds: 0.001, outSeconds: 0.03)
}

// MARK: - Writing and checking

struct SoundError: Error, CustomStringConvertible {
    let description: String
}

func write(_ samples: [Float], to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
          let channel = buffer.floatChannelData?[0]
    else { throw SoundError(description: "no buffer for \(url.lastPathComponent)") }
    for (i, value) in samples.enumerated() {
        channel[i] = value
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    try file.write(from: buffer)
}

func read(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          let channel = buffer.floatChannelData?[0]
    else { throw SoundError(description: "no buffer for \(url.lastPathComponent)") }
    try file.read(into: buffer)
    return (0..<Int(buffer.frameLength)).map { channel[$0] }
}

func rms(_ samples: ArraySlice<Float>) -> Double {
    guard !samples.isEmpty else { return 0 }
    return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
}

func decibels(_ value: Double) -> Double {
    20 * log10(max(value, 1e-9))
}

struct Check {
    let name: String
    let isLoop: Bool
    let maxSeconds: Double
    let render: () -> [Float]
}

let checks = [
    Check(name: "macbull-crack.caf", isLoop: false, maxSeconds: 2, render: crack),
    Check(name: "macbull-clink.caf", isLoop: false, maxSeconds: 2, render: clink),
    Check(name: "macbull-crumple.caf", isLoop: false, maxSeconds: 2, render: crumple),
    Check(name: "macbull-burp.caf", isLoop: false, maxSeconds: 2, render: burp),
    Check(name: "macbull-fizz.caf", isLoop: true, maxSeconds: fizzSeconds + 0.01, render: fizz),
    Check(name: "macbull-ping.caf", isLoop: false, maxSeconds: 2, render: ping),
    Check(name: "macbull-knock.caf", isLoop: false, maxSeconds: 2, render: knock),
]

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Sounds"
let outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
var failed = false

do {
    try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    for check in checks {
        let url = outputFolder.appendingPathComponent(check.name)
        try write(check.render(), to: url)
        let samples = try read(url)
        let seconds = Double(samples.count) / sampleRate
        let peak = Double(samples.reduce(0) { max($0, abs($1)) })
        var line = "\(check.name): \(String(format: "%.3f", seconds)) s, peak \(String(format: "%.2f", decibels(peak))) dBFS"
        if check.isLoop {
            // The wrap point must look like any other point: its step is within the normal range of steps,
            // and the level around it matches the level of the whole loop.
            let diffs = zip(samples, samples.dropFirst()).map { abs(Double($1 - $0)) }
            let sorted = diffs.sorted()
            let p99 = sorted[Int(Double(sorted.count) * 0.99)]
            let seam = abs(Double(samples[0] - samples[samples.count - 1]))
            let window = Int(0.025 * sampleRate)
            let around = Array(samples[(samples.count - window)...]) + Array(samples[0..<window])
            let offset = decibels(rms(around[...]) / rms(samples[...]))
            line += ", seam step \(String(format: "%.3f", seam)) vs 99th percentile step \(String(format: "%.3f", p99))"
            line += ", level around seam vs loop \(String(format: "%.2f", offset)) dB"
            if seam > p99 || abs(offset) > 3 { failed = true }
        }
        if seconds > check.maxSeconds || peak > 0.75 || peak < 0.65 { failed = true }
        print(line)
    }
} catch {
    print("Failed: \(error)")
    exit(1)
}

if failed {
    print("A file is outside its bounds.")
    exit(1)
}
