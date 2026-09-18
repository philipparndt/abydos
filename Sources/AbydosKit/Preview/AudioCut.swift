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

	/// Writes what this cut leaves of `source` into a **new** file, in the same
	/// format the source is in — its rate, its channels, its depth — and the
	/// container the destination's name asks for.
	///
	/// Asked for 2026-09-16: "when selecting a part in a wav file, it should be
	/// also possible to save as (save the selection to a new file)". Cutting a
	/// long recording into samples is the case, and it must not touch the
	/// recording: nothing here writes to `source`.
	public func write(from source: URL, toNew destination: URL) throws {
		let ext = destination.pathExtension.lowercased()
		guard Self.canWrite(destination) else { throw Failure.cannotWrite(ext.uppercased()) }
		let input: AVAudioFile
		do { input = try AVAudioFile(forReading: source) } catch {
			throw Failure.failed(error.localizedDescription)
		}
		let segments = segments(frameCount: Int(input.length))
		guard segments.reduce(0, { $0 + $1.count }) > 0 else { throw Failure.nothingLeft }
		var settings = input.fileFormat.settings
		if settings[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC {
			settings.removeValue(forKey: AVLinearPCMBitDepthKey)
		}
		// A selection written into a container the source's codec does not
		// belong in — a CAF cut out of an M4A — is written as linear PCM.
		if ext == "wav" || ext == "aif" || ext == "aiff" || ext == "caf",
		   settings[AVFormatIDKey] as? UInt32 != kAudioFormatLinearPCM {
			settings = [
				AVFormatIDKey: kAudioFormatLinearPCM,
				AVSampleRateKey: input.processingFormat.sampleRate,
				AVNumberOfChannelsKey: input.processingFormat.channelCount,
				AVLinearPCMBitDepthKey: 24,
				AVLinearPCMIsFloatKey: false,
				AVLinearPCMIsNonInterleaved: false,
			]
		}
		let temporary = destination.deletingLastPathComponent()
			.appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent).abydos-\(UUID().uuidString.prefix(8)).\(ext)")
		do {
			try Self.render(segments, from: input, to: temporary, settings: settings)
		} catch {
			try? FileManager.default.removeItem(at: temporary)
			throw Failure.failed(error.localizedDescription)
		}
		do {
			if FileManager.default.fileExists(atPath: destination.path) {
				_ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
			} else {
				try FileManager.default.moveItem(at: temporary, to: destination)
			}
		} catch {
			try? FileManager.default.removeItem(at: temporary)
			throw Failure.failed(error.localizedDescription)
		}
	}

	/// A name for a selection cut out of a file: the file's own, and the
	/// seconds it starts at, so slicing a recording numbers itself.
	public static func name(of source: URL, at seconds: Double, extension ext: String? = nil) -> String {
		let stem = source.deletingPathExtension().lastPathComponent
		let whole = Int(seconds)
		let clock = String(format: "%d-%02d.%03d", whole / 60, whole % 60, Int((seconds - Double(whole)) * 1000))
		return "\(stem) \(clock).\(ext ?? source.pathExtension)"
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
