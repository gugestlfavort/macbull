import AVFoundation
import Foundation
import Testing

/// Reads the generated .caf files straight from Resources/Sounds.
struct SoundFilesTests {
    private static let files = [
        "macbull-crack.caf", "macbull-clink.caf", "macbull-crumple.caf", "macbull-burp.caf",
        "macbull-fizz.caf", "macbull-ping.caf", "macbull-knock.caf",
    ]
    private static let loop = "macbull-fizz.caf"

    private func samples(_ name: String) throws -> (samples: [Float], seconds: Double) {
        let url = WindowsTestSupport.soundsFolder.appendingPathComponent(name)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(file.length)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        let data = (0..<Int(buffer.frameLength)).map { channel[$0] }
        return (data, Double(buffer.frameLength) / file.processingFormat.sampleRate)
    }

    @Test(arguments: files)
    func existsAndHasSound(name: String) throws {
        let (data, seconds) = try samples(name)
        #expect(seconds > 0.1)
        #expect(data.contains { abs($0) > 0.1 })
    }

    @Test(arguments: files.filter { $0 != loop })
    func shortSoundsAreUnderTwoSeconds(name: String) throws {
        #expect(try samples(name).seconds < 2)
    }

    @Test func fizzLoopIsTwoSeconds() throws {
        let seconds = try samples(Self.loop).seconds
        #expect(abs(seconds - 2) < 0.02)
    }

    @Test(arguments: files)
    func peakIsAboutMinusThreeDecibelsWithoutClipping(name: String) throws {
        let peak = try #require(try samples(name).samples.map { abs($0) }.max())
        let decibels = 20 * log10(Double(peak))
        #expect(peak < 1)
        #expect(decibels > -4 && decibels < -2, "\(name): \(decibels) dBFS")
    }

    @Test func fizzLoopHasNoStepAtTheSeam() throws {
        let data = try samples(Self.loop).samples
        let steps = zip(data, data.dropFirst()).map { abs(Double($1 - $0)) }.sorted()
        let ninetyNinth = steps[Int(Double(steps.count) * 0.99)]
        let seam = abs(Double(data[0] - data[data.count - 1]))
        #expect(seam <= ninetyNinth)
    }

    @Test func fizzLevelIsEvenAcrossTheSeam() throws {
        let data = try samples(Self.loop).samples
        func rms(_ slice: ArraySlice<Float>) -> Double {
            (slice.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(slice.count)).squareRoot()
        }
        let window = 1_100
        let around = Array(data[(data.count - window)...]) + Array(data[0..<window])
        let ratio = 20 * log10(rms(around[...]) / rms(data[...]))
        #expect(abs(ratio) < 3)
    }
}
