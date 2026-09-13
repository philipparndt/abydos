import AVFoundation
import Foundation
import Testing
@testable import AbydosKit

/// A sound file reduced to what a tab draws: peaks for the wave, columns for
/// the spectrogram. Checked against signals whose answer is known.
struct AudioAnalysisTests {
	private func tone(_ hertz: Double, seconds: Double, rate: Double = 44_100, level: Float = 0.5) -> [Float] {
		let count = Int(seconds * rate)
		return (0..<count).map { level * Float(sin(2 * .pi * hertz * Double($0) / rate)) }
	}

	// MARK: - Peaks

	@Test func peaksAreTheLowestAndHighestOfEachStretch() {
		var reducer = PeakReducer(framesPerPeak: 4)
		reducer.add([0, 1, -1, 0.5, 0.25, -0.75, 0.5, 0])
		let peaks = reducer.finish()
		#expect(peaks.minimums == [-1, -0.75])
		#expect(peaks.maximums == [1, 0.5])
	}

	/// Chunks split anywhere give the same peaks as the stream in one piece.
	@Test func aChunkBoundaryDoesNotSplitAPeak() {
		let ramp = (0..<1000).map { Float($0) / 1000 }
		var whole = PeakReducer(framesPerPeak: 256)
		whole.add(ramp)
		var pieces = PeakReducer(framesPerPeak: 256)
		pieces.add(Array(ramp[0..<100]))
		pieces.add(Array(ramp[100..<700]))
		pieces.add(Array(ramp[700...]))
		#expect(whole.finish() == pieces.finish())
	}

	@Test func theLastPartialStretchIsAPeakToo() {
		var reducer = PeakReducer(framesPerPeak: 256)
		reducer.add([Float](repeating: 0.25, count: 300))
		#expect(reducer.finish().count == 2)
	}

	/// A spike one peak wide still reaches the column it falls in.
	@Test func foldingKeepsASpike() {
		var minimums = [Float](repeating: -0.1, count: 1000)
		var maximums = [Float](repeating: 0.1, count: 1000)
		maximums[517] = 0.9
		minimums[517] = -0.9
		let folded = AudioPeaks(framesPerPeak: 256, minimums: minimums, maximums: maximums).folded(into: 10)
		#expect(folded.maximums[5] == 0.9)
		#expect(folded.minimums[5] == -0.9)
		#expect(folded.maximums[4] == 0.1)
	}

	// MARK: - Spectrogram

	/// A 1 kHz tone is loudest in the 1 kHz band.
	@Test func aToneIsLoudestAtItsOwnFrequency() {
		let builder = SpectrogramBuilder(sampleRate: 44_100, frames: 44_100)
		builder.add(tone(1000, seconds: 1))
		let spectrogram = builder.finish()
		#expect(spectrogram.columns > 1)
		let column = spectrogram.columns / 2
		let loudest = (0..<spectrogram.bins).max {
			spectrogram.value(column: column, bin: $0) < spectrogram.value(column: column, bin: $1)
		}!
		let frequency = spectrogram.frequency(ofBin: loudest)
		// One bin is 21.5 Hz wide at this window and rate.
		#expect(abs(frequency - 1000) < 22, "loudest at \(frequency) Hz")
	}

	/// However long the file, the columns stay within what a tab can show.
	@Test func anHourIsNoMoreColumnsThanATabIsWide() {
		let frames = 3600 * 44_100
		let hop = SpectrogramBuilder.hop(forFrames: frames)
		let columns = (frames - SpectrogramBuilder.defaultWindow) / hop + 1
		#expect(columns <= SpectrogramBuilder.maximumColumns)
		#expect(columns > SpectrogramBuilder.maximumColumns - 2)
	}

	/// A zoomed-in reading may ask for closer columns than a quarter window.
	@Test func aZoomedReadingCanOverlapItsWindowsMore() {
		#expect(SpectrogramBuilder.hop(forFrames: 44_100, minimumHop: 64) == 64)
		// Still no more columns than asked for.
		#expect(SpectrogramBuilder.hop(forFrames: 441_000, maximumColumns: 1000, minimumHop: 64) > 64)
	}

	/// A short file does not space its windows further apart than a quarter.
	@Test func aShortFileOverlapsItsWindows() {
		#expect(SpectrogramBuilder.hop(forFrames: 44_100) == SpectrogramBuilder.defaultWindow / 4)
	}

	@Test func aSoundShorterThanAWindowStillHasASpectrum() {
		let builder = SpectrogramBuilder(sampleRate: 44_100, frames: 500)
		builder.add(tone(440, seconds: 500.0 / 44_100))
		#expect(builder.finish().columns == 1)
	}

	// MARK: - Files

	/// Written by AVFoundation itself, so the reader is exercised end to end
	/// without an encoder the test machine may not have.
	@Test func aStereoWavReadsAsTwoLanesAndItsTone() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("audio-analysis-\(UUID().uuidString).wav")
		defer { try? FileManager.default.removeItem(at: url) }

		let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
		let samples = tone(1000, seconds: 2)
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
		buffer.frameLength = AVAudioFrameCount(samples.count)
		for index in samples.indices {
			buffer.floatChannelData![0][index] = samples[index]
			buffer.floatChannelData![1][index] = samples[index] * 0.25
		}
		do {
			let file = try AVAudioFile(
				forWriting: url,
				settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
				           AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
				           AVLinearPCMIsFloatKey: false]
			)
			try file.write(from: buffer)
		}

		let overview = try AudioAnalysis.read(url)
		#expect(overview.channelCount == 2)
		#expect(overview.lanes.count == 2)
		// The file's length, exactly: every frame written is a frame read.
		#expect(overview.frameCount == samples.count)
		#expect(overview.lanes[0].count == (samples.count + 255) / 256)
		// The right channel was written at a quarter of the left's level.
		let left = overview.lanes[0].maximums.max()!
		let right = overview.lanes[1].maximums.max()!
		#expect(abs(left - 0.5) < 0.01)
		#expect(abs(right - 0.125) < 0.01)
	}

	/// A zoomed-in tab reads only what is on screen, at its own detail.
	@Test func aRangeReadsOnlyThatRegionAtItsDetail() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("region-\(UUID().uuidString).caf")
		defer { try? FileManager.default.removeItem(at: url) }
		let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
		// One second of silence, then one second of a loud 440 Hz tone.
		let samples = [Float](repeating: 0, count: 44_100) + tone(440, seconds: 1, level: 0.8)
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
		buffer.frameLength = AVAudioFrameCount(samples.count)
		for index in samples.indices { buffer.floatChannelData![0][index] = samples[index] }
		do {
			let file = try AVAudioFile(forWriting: url, settings: format.settings)
			try file.write(from: buffer)
		}

		let quiet = try AudioAnalysis.read(url, range: 0..<22_050, framesPerPeak: 16, maximumColumns: 200)
		#expect(quiet.startFrame == 0)
		#expect(quiet.frameCount == 22_050)
		#expect(quiet.lanes[0].framesPerPeak == 16)
		#expect(quiet.lanes[0].maximums.max()! < 0.001)
		#expect(quiet.spectrogram.columns <= 200)

		let loud = try AudioAnalysis.read(url, range: 66_150..<88_200, framesPerPeak: 16, maximumColumns: 200)
		#expect(loud.startFrame == 66_150)
		#expect(loud.frameCount == 22_050)
		#expect(abs(loud.lanes[0].maximums.max()! - 0.8) < 0.01)
	}

	@Test func aFileThatIsNotAudioSaysSo() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("broken-\(UUID().uuidString).wav")
		defer { try? FileManager.default.removeItem(at: url) }
		try "this is not a wave file".write(to: url, atomically: true, encoding: .utf8)

		#expect(throws: AudioAnalysis.Failure.self) { try AudioAnalysis.read(url) }
	}

	/// Core Audio's four-character codes are said in words.
	@Test func aDecoderCodeIsASentence() {
		let unsupported = NSError(domain: "com.apple.coreaudio.avfaudio", code: 1_954_115_647)
		#expect(AudioAnalysis.describe(unsupported) == "It is not a sound file the system can read.")
		let unknown = NSError(domain: "com.apple.coreaudio.avfaudio", code: 0x7A7A7A3F)
		#expect(AudioAnalysis.describe(unknown).contains("'zzz?'"))
	}

	@Test func aCancelledReadStops() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("cancel-\(UUID().uuidString).caf")
		defer { try? FileManager.default.removeItem(at: url) }
		let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
		let samples = tone(440, seconds: 1)
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
		buffer.frameLength = AVAudioFrameCount(samples.count)
		for index in samples.indices { buffer.floatChannelData![0][index] = samples[index] }
		do {
			let file = try AVAudioFile(forWriting: url, settings: format.settings)
			try file.write(from: buffer)
		}

		#expect(throws: AudioAnalysis.Failure.cancelled) { try AudioAnalysis.read(url) { true } }
	}
}
