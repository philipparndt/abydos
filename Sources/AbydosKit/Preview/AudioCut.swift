import AVFoundation
import Foundation

/// Cutting a sound file to a selection, without a window.
///
/// Asked for on 2026-09-14: `i` and `o` mark a selection in a sound tab, and
/// the selection is kept or deleted. The tab does the marking and the
/// drawing; this is the arithmetic and the files, so both are tested on
/// synthesised audio.
///
/// **Frames, not seconds.** A selection is held in seconds on screen and
/// becomes frames here, once, by truncation — so the same two marks always
/// cut the same frames, and a cut is exact to the frame.
///
/// **No fades.** A loop cut at its downbeat is the use this was asked for, and
/// a fade added behind somebody's back is a loop that no longer loops. A click
/// at a careless join is the cut somebody made.
///
/// **A cut writes a working copy, never the file.** The copy is 32-bit float
/// CAF in the temporary directory, so a chain of cuts decodes a compressed
/// original once and loses nothing between cuts; ⌘S writes the file in its
/// own format from the last copy, by replacing it whole.
public enum AudioCut: Equatable, Sendable {
	/// Leave only these frames.
	case keep(Range<Int>)
	/// Remove these frames and join what is either side.
	case delete(Range<Int>)

	/// The frames of the source a cut leaves, in order.
	public func segments(frameCount: Int) -> [Range<Int>] {
		switch self {
		case .keep(let range):
			let clamped = range.clamped(to: 0..<frameCount)
			return clamped.isEmpty ? [] : [clamped]
		case .delete(let range):
			let clamped = range.clamped(to: 0..<frameCount)
			return [0..<clamped.lowerBound, clamped.upperBound..<frameCount].filter { !$0.isEmpty }
		}
	}

	/// The frames between two marks, in either order, inside the file.
	public static func frames(from a: Double, to b: Double, sampleRate: Double, frameCount: Int) -> Range<Int> {
		func frame(_ seconds: Double) -> Int {
			min(frameCount, max(0, Int((seconds * sampleRate).rounded(.down))))
		}
		let (start, end) = (frame(min(a, b)), frame(max(a, b)))
		return start..<end
	}

	public enum Failure: Error, LocalizedError, Equatable {
		/// A cut that would leave nothing.
		case nothingLeft
		/// macOS has no encoder for this container.
		case cannotWrite(String)
		/// What the system said, in its words.
		case failed(String)

		public var errorDescription: String? {
			switch self {
			case .nothingLeft: return "That would leave no sound at all."
			case .cannotWrite(let format): return "macOS cannot write \(format) files. The edit is kept and not saved."
			case .failed(let said): return said
			}
		}
	}

	/// Formats a file can be written back in, by extension; everything else
	/// the sound tab opens is read only as far as ⌘S is concerned.
	public static let writable: Set<String> = ["wav", "aif", "aiff", "caf", "m4a", "aac", "flac"]

	public static func canWrite(_ url: URL) -> Bool {
		writable.contains(url.pathExtension.lowercased())
	}

	static let chunk: AVAudioFrameCount = 65_536

	/// Writes what `self` leaves of `source` to `destination`, a new 32-bit
	/// float CAF. Answers the frames written.
	@discardableResult
	public func write(from source: URL, to destination: URL) throws -> Int {
		let input: AVAudioFile
		do { input = try AVAudioFile(forReading: source) } catch { throw Failure.failed(error.localizedDescription) }
		let format = input.processingFormat
		let segments = segments(frameCount: Int(input.length))
		let total = segments.reduce(0) { $0 + $1.count }
		guard total > 0 else { throw Failure.nothingLeft }
		let settings: [String: Any] = [
			AVFormatIDKey: kAudioFormatLinearPCM,
			AVSampleRateKey: format.sampleRate,
			AVNumberOfChannelsKey: format.channelCount,
			AVLinearPCMBitDepthKey: 32,
			AVLinearPCMIsFloatKey: true,
			AVLinearPCMIsNonInterleaved: false,
		]
		do {
			try Self.render(segments, from: input, to: destination, settings: settings)
		} catch let failure as Failure {
			throw failure
		} catch {
			throw Failure.failed(error.localizedDescription)
		}
		return total
	}

	/// Writes `working` over `original` in the original's own format: its
	/// container, codec, rate and channels. The file is replaced whole, so a
	/// failure leaves the original as it was.
	public static func save(_ working: URL, over original: URL) throws {
		let ext = original.pathExtension.lowercased()
		guard canWrite(original) else { throw Failure.cannotWrite(ext.uppercased()) }
		let input: AVAudioFile
		let target: AVAudioFile
		do {
			input = try AVAudioFile(forReading: working)
			target = try AVAudioFile(forReading: original)
		} catch {
			throw Failure.failed(error.localizedDescription)
		}
		var settings = target.fileFormat.settings
		// A compressed file's settings name the codec and not the bits; a bit
		// rate the encoder picks is kept when the file said one.
		if settings[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC {
			settings.removeValue(forKey: AVLinearPCMBitDepthKey)
		}
		let temporary = original.deletingLastPathComponent()
			.appendingPathComponent(".\(original.deletingPathExtension().lastPathComponent).abydos-\(UUID().uuidString.prefix(8)).\(ext)")
		do {
			try render([0..<Int(input.length)], from: input, to: temporary, settings: settings)
		} catch {
			try? FileManager.default.removeItem(at: temporary)
			throw Failure.failed(error.localizedDescription)
		}
		do {
			_ = try FileManager.default.replaceItemAt(original, withItemAt: temporary)
		} catch {
			try? FileManager.default.removeItem(at: temporary)
			throw Failure.failed(error.localizedDescription)
		}
	}

	/// Writes the segments into a new file at `url`.
	///
	/// **The writer lives and dies in here.** `AVAudioFile` finishes a file —
	/// its header, an encoder's last packets — when it is released, and
	/// `close()` is macOS 15. A writer still alive when its file is renamed over
	/// the original is a file with a header that says nothing was written.
	private static func render(_ segments: [Range<Int>], from input: AVAudioFile, to url: URL, settings: [String: Any]) throws {
		let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
		try copy(segments, from: input, to: output)
		if #available(macOS 15.0, *) { output.close() }
	}

	private static func copy(_ segments: [Range<Int>], from input: AVAudioFile, to output: AVAudioFile) throws {
		guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: chunk) else {
			throw Failure.failed("The system could not make room to decode this file.")
		}
		for segment in segments {
			input.framePosition = AVAudioFramePosition(segment.lowerBound)
			var left = segment.count
			while left > 0 {
				try input.read(into: buffer, frameCount: min(chunk, AVAudioFrameCount(left)))
				guard buffer.frameLength > 0 else { break }
				try output.write(from: buffer)
				left -= Int(buffer.frameLength)
			}
		}
	}
}
