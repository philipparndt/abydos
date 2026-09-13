import Accelerate
import AVFoundation
import Foundation

/// A sound file reduced to what a tab can draw: its wave as peaks, and its
/// spectrogram as columns of loudness.
///
/// **Reduced as it is read, never held whole.** An hour of stereo at 44.1 kHz
/// is 318 million samples — 1.27 GB of `Float` — and a tab is a few thousand
/// points wide. The file is read in chunks, each chunk is folded into peaks and
/// into the windows the spectrogram needs, and the samples go.
///
/// The folding is pure: `PeakReducer` and `SpectrogramBuilder` take samples and
/// give numbers, so a 1 kHz tone can be checked for its loudest band without a
/// file or a window. Only `read(_:)` touches the decoder.
public struct AudioOverview: Sendable {
	public let sampleRate: Double
	/// Where in the file this reading starts: 0 for the whole file, the first
	/// frame of the region for a zoomed-in reading.
	public var startFrame: Int = 0
	public let frameCount: Int
	/// The channels the file has, which is not always the number of lanes.
	public let channelCount: Int
	/// One lane per channel for mono and stereo; one lane of the mix past two.
	public let lanes: [AudioPeaks]
	public let spectrogram: Spectrogram

	public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
}

/// The minimum and maximum of every `framesPerPeak` frames of one lane.
public struct AudioPeaks: Sendable, Equatable {
	public let framesPerPeak: Int
	public var minimums: [Float]
	public var maximums: [Float]

	public var count: Int { minimums.count }

	/// The peaks folded into `columns` columns, for drawing at a width.
	///
	/// Each column is the lowest minimum and the highest maximum of the peaks
	/// that fall in it, so a spike a single peak wide still reaches its column.
	/// Where there are fewer peaks than columns, a column repeats its peak.
	public func folded(into columns: Int) -> (minimums: [Float], maximums: [Float]) {
		guard columns > 0, count > 0 else { return ([], []) }
		var lows = [Float](repeating: 0, count: columns)
		var highs = [Float](repeating: 0, count: columns)
		for column in 0..<columns {
			let start = column * count / columns
			let end = max(start + 1, (column + 1) * count / columns)
			var low = Float.greatestFiniteMagnitude
			var high = -Float.greatestFiniteMagnitude
			for index in start..<min(end, count) {
				low = min(low, minimums[index])
				high = max(high, maximums[index])
			}
			lows[column] = low
			highs[column] = high
		}
		return (lows, highs)
	}
}

/// Loudness over time and frequency: `columns` columns of `bins` decibel values,
/// bin `b` of a column centred on `b × sampleRate / windowSize` Hz.
public struct Spectrogram: Sendable, Equatable {
	public let windowSize: Int
	public let hop: Int
	public let sampleRate: Double
	public let columns: Int
	public var bins: Int { windowSize / 2 }
	/// Column by column, `bins` values each, in decibels.
	public let decibels: [Float]
	/// The loudest value anywhere, which the colour scale hangs from.
	public let loudest: Float

	public func value(column: Int, bin: Int) -> Float {
		decibels[column * bins + bin]
	}

	/// The centre frequency of a bin, in Hz.
	public func frequency(ofBin bin: Int) -> Double {
		Double(bin) * sampleRate / Double(windowSize)
	}
}

// MARK: - Peaks

/// Folds a stream of samples into min/max pairs, `framesPerPeak` at a time,
/// across chunk boundaries.
public struct PeakReducer: Sendable {
	public let framesPerPeak: Int
	private(set) var peaks: AudioPeaks
	private var low = Float.greatestFiniteMagnitude
	private var high = -Float.greatestFiniteMagnitude
	private var filled = 0

	public init(framesPerPeak: Int = 256) {
		self.framesPerPeak = framesPerPeak
		peaks = AudioPeaks(framesPerPeak: framesPerPeak, minimums: [], maximums: [])
	}

	public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
		for sample in samples {
			low = min(low, sample)
			high = max(high, sample)
			filled += 1
			if filled == framesPerPeak { flush() }
		}
	}

	public mutating func add(_ samples: [Float]) {
		samples.withUnsafeBufferPointer { add($0) }
	}

	/// The last, partial peak, and the result.
	public mutating func finish() -> AudioPeaks {
		if filled > 0 { flush() }
		return peaks
	}

	private mutating func flush() {
		peaks.minimums.append(low)
		peaks.maximums.append(high)
		low = .greatestFiniteMagnitude
		high = -.greatestFiniteMagnitude
		filled = 0
	}
}

// MARK: - Spectrogram

/// Builds a spectrogram from a stream of mono samples: a Hann window of
/// `windowSize` samples every `hop` samples, each turned into decibels.
///
/// **The hop is chosen from the length**, so a file of any duration yields at
/// most `maximumColumns` columns — an overview the width of a tab, and a
/// bounded cost: 4,096 FFTs of 2,048 samples, whatever the file is.
public final class SpectrogramBuilder: @unchecked Sendable {
	public let windowSize: Int
	public let hop: Int
	public let sampleRate: Double

	private let log2n: vDSP_Length
	private let setup: FFTSetup
	private var window: [Float]
	/// Samples not yet past, starting at `pendingStart` in the stream.
	private var pending: [Float] = []
	private var pendingStart = 0
	private var nextColumnStart = 0
	private var decibels: [Float] = []
	private(set) var columns = 0
	/// No more columns than this, however long the stream.
	public let maximumColumns: Int

	public static let defaultWindow = 2048
	public static let maximumColumns = 4096

	/// The hop for a stream of `frames` frames: at most `maximumColumns`
	/// columns, and never closer than `minimumHop` — a quarter of the window
	/// unless asked otherwise. A zoomed-in reading asks for less, so a second of
	/// sound is as many columns as the screen has pixels rather than eighty.
	public static func hop(
		forFrames frames: Int, window: Int = defaultWindow,
		maximumColumns: Int = maximumColumns, minimumHop: Int? = nil
	) -> Int {
		let span = max(0, frames - window)
		let spread = Int((Double(span) / Double(max(1, maximumColumns - 1))).rounded(.up))
		return max(max(1, minimumHop ?? window / 4), spread)
	}

	public init(
		sampleRate: Double, frames: Int, windowSize: Int = defaultWindow,
		maximumColumns: Int = SpectrogramBuilder.maximumColumns, minimumHop: Int? = nil
	) {
		self.windowSize = windowSize
		self.sampleRate = sampleRate
		self.maximumColumns = max(1, maximumColumns)
		hop = Self.hop(
			forFrames: frames, window: windowSize, maximumColumns: self.maximumColumns, minimumHop: minimumHop
		)
		log2n = vDSP_Length(log2(Double(windowSize)))
		setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
		window = [Float](repeating: 0, count: windowSize)
		vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
	}

	deinit { vDSP_destroy_fftsetup(setup) }

	public func add(_ samples: UnsafeBufferPointer<Float>) {
		pending.append(contentsOf: samples)
		// Every window that now lies wholly inside what is pending.
		while nextColumnStart + windowSize <= pendingStart + pending.count,
		      columns < maximumColumns {
			let offset = nextColumnStart - pendingStart
			pending.withUnsafeBufferPointer { buffer in
				appendColumn(UnsafeBufferPointer(rebasing: buffer[offset..<offset + windowSize]))
			}
			nextColumnStart += hop
		}
		// Anything before the next window is never needed again.
		let spent = min(pending.count, max(0, nextColumnStart - pendingStart))
		if spent > 0 {
			pending.removeFirst(spent)
			pendingStart += spent
		}
	}

	public func add(_ samples: [Float]) {
		samples.withUnsafeBufferPointer { add($0) }
	}

	public func finish() -> Spectrogram {
		// A stream shorter than one window still gets one column, zero-padded,
		// so a click of sound has a spectrum rather than none.
		if columns == 0, !pending.isEmpty {
			let padded = pending + [Float](repeating: 0, count: max(0, windowSize - pending.count))
			padded.withUnsafeBufferPointer { appendColumn(UnsafeBufferPointer(rebasing: $0[0..<windowSize])) }
		}
		return Spectrogram(
			windowSize: windowSize, hop: hop, sampleRate: sampleRate, columns: columns,
			decibels: decibels, loudest: decibels.max() ?? 0
		)
	}

	private func appendColumn(_ frame: UnsafeBufferPointer<Float>) {
		let half = windowSize / 2
		var windowed = [Float](repeating: 0, count: windowSize)
		vDSP_vmul(frame.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(windowSize))

		var real = [Float](repeating: 0, count: half)
		var imaginary = [Float](repeating: 0, count: half)
		var magnitudes = [Float](repeating: 0, count: half)
		real.withUnsafeMutableBufferPointer { realPointer in
			imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
				var split = DSPSplitComplex(
					realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!
				)
				windowed.withUnsafeBufferPointer { input in
					input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
						vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
					}
				}
				vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
				vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
			}
		}
		// Power to decibels, floored so silence is a number rather than -inf.
		var floor: Float = 1e-12
		vDSP_vclip(magnitudes, 1, &floor, [Float.greatestFiniteMagnitude], &magnitudes, 1, vDSP_Length(half))
		var reference: Float = 1
		var column = [Float](repeating: 0, count: half)
		vDSP_vdbcon(magnitudes, 1, &reference, &column, 1, vDSP_Length(half), 0)
		decibels.append(contentsOf: column)
		columns += 1
	}
}

// MARK: - Reading a file

public enum AudioAnalysis {
	public static let chunkFrames: AVAudioFrameCount = 65_536

	public enum Failure: Error, LocalizedError, Equatable {
		/// What the decoder said, in its words.
		case undecodable(String)
		case cancelled

		public var errorDescription: String? {
			switch self {
			case .undecodable(let said): return said
			case .cancelled: return "Stopped before it finished."
			}
		}
	}

	/// Reads a sound file into its overview, off whatever thread calls it.
	///
	/// - Parameter isCancelled: asked between chunks; a tab that closes stops
	///   the read at the next one.
	/// - Parameters:
	///   - range: the frames to read; the whole file when nil. A zoomed-in tab
	///     reads what is on screen, at the detail its width allows.
	///   - framesPerPeak: how many frames each peak folds.
	///   - maximumColumns: how many spectrogram columns at most.
	public static func read(
		_ url: URL,
		range: Range<Int>? = nil,
		framesPerPeak: Int = 256,
		maximumColumns: Int = SpectrogramBuilder.maximumColumns,
		minimumHop: Int? = nil,
		isCancelled: @Sendable () -> Bool = { false }
	) throws -> AudioOverview {
		let file: AVAudioFile
		do {
			file = try AVAudioFile(forReading: url)
		} catch {
			throw Failure.undecodable(describe(error))
		}
		let format = file.processingFormat
		let channels = Int(format.channelCount)
		let length = Int(file.length)
		let start = min(max(0, range?.lowerBound ?? 0), length)
		let end = min(max(start, range?.upperBound ?? length), length)
		let frames = end - start
		file.framePosition = AVAudioFramePosition(start)
		guard channels > 0, format.sampleRate > 0 else {
			throw Failure.undecodable("The file holds no audio the system can read.")
		}
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
			throw Failure.undecodable("The system could not make room to decode this file.")
		}

		let laneCount = channels <= 2 ? channels : 1
		var reducers = (0..<laneCount).map { _ in PeakReducer(framesPerPeak: max(1, framesPerPeak)) }
		let spectrum = SpectrogramBuilder(
			sampleRate: format.sampleRate, frames: frames, maximumColumns: maximumColumns,
			minimumHop: minimumHop
		)
		var mix = [Float](repeating: 0, count: Int(chunkFrames))
		var read = 0

		while read < frames {
			if isCancelled() { throw Failure.cancelled }
			do {
				try file.read(
					into: buffer, frameCount: min(chunkFrames, AVAudioFrameCount(frames - read))
				)
			} catch {
				// A file that stops decoding part-way keeps what was read.
				if read == 0 { throw Failure.undecodable(describe(error)) }
				break
			}
			let count = Int(buffer.frameLength)
			guard count > 0, let data = buffer.floatChannelData else { break }

			// The mono mix, for the spectrogram and for a file past two channels.
			vDSP_vclr(&mix, 1, vDSP_Length(mix.count))
			for channel in 0..<channels {
				vDSP_vadd(mix, 1, data[channel], 1, &mix, 1, vDSP_Length(count))
			}
			var scale = 1 / Float(channels)
			vDSP_vsmul(mix, 1, &scale, &mix, 1, vDSP_Length(count))

			mix.withUnsafeBufferPointer { mixed in
				let chunk = UnsafeBufferPointer(rebasing: mixed[0..<count])
				spectrum.add(chunk)
				if laneCount == 1, channels > 1 {
					reducers[0].add(chunk)
				}
			}
			if channels <= 2 {
				for channel in 0..<channels {
					reducers[channel].add(UnsafeBufferPointer(start: data[channel], count: count))
				}
			}
			read += count
		}

		return AudioOverview(
			sampleRate: format.sampleRate,
			startFrame: start,
			frameCount: read,
			channelCount: channels,
			lanes: reducers.indices.map { reducers[$0].finish() },
			spectrogram: spectrum.finish()
		)
	}

	/// What went wrong, as a sentence.
	///
	/// **Core Audio answers in four-character codes.** A text file named
	/// `.wav` comes back as "The operation couldn't be completed.
	/// (com.apple.coreaudio.avfaudio error 1954115647.)" — which is `typ?`, an
	/// unsupported file type, spelled as a decimal. The codes a file on disk can
	/// produce are said in words; anything else keeps its code, readably.
	static func describe(_ error: Error) -> String {
		let nsError = error as NSError
		let code = UInt32(bitPattern: Int32(truncatingIfNeeded: nsError.code))
		let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
		guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }),
		      let fourCC = String(bytes: bytes, encoding: .ascii)
		else { return nsError.localizedDescription }
		switch fourCC {
		case "typ?": return "It is not a sound file the system can read."
		case "fmt?": return "Its audio is in a format the system cannot decode."
		case "dta?", "pck?": return "The file is damaged: its audio data could not be read."
		case "perm", "!prm": return "The file could not be opened: permission denied."
		default: return "The system could not decode it (Core Audio '\(fourCC)')."
		}
	}
}
