import AVFoundation
import Foundation
import Testing
@testable import AbydosKit

/// Cutting a sound file to a selection: which frames stay, and the files.
struct AudioCutTests {
	private let rate = 8_000.0

	private func scratch() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audio-cut-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	/// A stereo file whose left sample at frame `n` is `n / frames` and whose
	/// right is its negative: every frame says where it came from.
	private func ramp(seconds: Double, at url: URL, settings extra: [String: Any] = [:]) throws {
		let frames = AVAudioFrameCount(seconds * rate)
		let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
		buffer.frameLength = frames
		for n in 0..<Int(frames) {
			buffer.floatChannelData![0][n] = Float(n) / Float(frames)
			buffer.floatChannelData![1][n] = -Float(n) / Float(frames)
		}
		var settings: [String: Any] = [
			AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
			AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
		]
		settings.merge(extra) { _, new in new }
		let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
		try file.write(from: buffer)
	}

	private func samples(_ url: URL) throws -> (left: [Float], length: Int) {
		let file = try AVAudioFile(forReading: url)
		let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
		try file.read(into: buffer)
		return (Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))), Int(file.length))
	}

	@Test func theMarksBecomeFramesInEitherOrder() {
		#expect(AudioCut.frames(from: 2, to: 4, sampleRate: 8_000, frameCount: 64_000) == 16_000..<32_000)
		#expect(AudioCut.frames(from: 4, to: 2, sampleRate: 8_000, frameCount: 64_000) == 16_000..<32_000)
		#expect(AudioCut.frames(from: -1, to: 99, sampleRate: 8_000, frameCount: 64_000) == 0..<64_000)
	}

	@Test func keepingLeavesTheSelectionAndDeletingLeavesTheRest() {
		#expect(AudioCut.keep(10..<20).segments(frameCount: 100) == [10..<20])
		#expect(AudioCut.delete(10..<20).segments(frameCount: 100) == [0..<10, 20..<100])
		#expect(AudioCut.delete(0..<20).segments(frameCount: 100) == [20..<100])
		#expect(AudioCut.delete(90..<200).segments(frameCount: 100) == [0..<90])
		#expect(AudioCut.keep(50..<50).segments(frameCount: 100).isEmpty)
	}

	/// The frames after a deleted stretch are the frames that were after it,
	/// exactly: no fade, no drift.
	@Test func aDeleteJoinsTheFramesEitherSideExactly() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let take = directory.appendingPathComponent("take.wav")
		try ramp(seconds: 8, at: take)
		let working = directory.appendingPathComponent("working.caf")
		let cut = AudioCut.delete(AudioCut.frames(from: 3, to: 3.5, sampleRate: rate, frameCount: 64_000))
		#expect(try cut.write(from: take, to: working) == 60_000)

		let (left, length) = try samples(working)
		#expect(length == 60_000)
		#expect(left[23_999] == Float(23_999) / 64_000)
		#expect(left[24_000] == Float(28_000) / 64_000, "the frame after the join is the frame that was at 3.5 s")
	}

	@Test func keepingNothingIsRefused() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let take = directory.appendingPathComponent("take.wav")
		try ramp(seconds: 1, at: take)
		#expect(throws: AudioCut.Failure.nothingLeft) {
			try AudioCut.keep(100..<100).write(from: take, to: directory.appendingPathComponent("w.caf"))
		}
	}

	/// ⌘S writes the file in its own format, over itself.
	@Test func savingWritesTheOriginalInItsOwnFormat() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		for (name, extra) in [
			("take.wav", [AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false] as [String: Any]),
			("take.aiff", [AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true]),
			("take.caf", [:]),
		] {
			let take = directory.appendingPathComponent(name)
			try ramp(seconds: 2, at: take, settings: extra)
			let before = try AVAudioFile(forReading: take).fileFormat
			let working = directory.appendingPathComponent("\(name).working.caf")
			try AudioCut.keep(4_000..<12_000).write(from: take, to: working)
			try AudioCut.save(working, over: take)

			let after = try AVAudioFile(forReading: take)
			#expect(after.length == 8_000, "\(name)")
			#expect(after.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == before.settings[AVLinearPCMBitDepthKey] as? Int, "\(name)")
			#expect(after.fileFormat.sampleRate == before.sampleRate, "\(name)")
			let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".abydos-") }
			#expect(leftovers.isEmpty, "no temporary file is left beside \(name)")
		}
	}

	@Test func anMP3IsNotWrittenAndSaysWhy() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(!AudioCut.canWrite(URL(fileURLWithPath: "/x/song.mp3")))
		#expect(AudioCut.canWrite(URL(fileURLWithPath: "/x/song.WAV")))
		#expect(throws: AudioCut.Failure.cannotWrite("MP3")) {
			try AudioCut.save(directory.appendingPathComponent("w.caf"), over: directory.appendingPathComponent("song.mp3"))
		}
		#expect(AudioCut.Failure.cannotWrite("MP3").errorDescription?.contains("macOS cannot write MP3") == true)
	}
}
