import AbydosKit
import AVFoundation
import Foundation

/// Plays a sound file, and loops it without a seam.
///
/// **An `AVAudioPlayerNode`, not an `AVPlayer`, because of the loop.** Seeking
/// an `AVPlayer` back to zero at the end takes tens of milliseconds, and the gap
/// is audible on anything rhythmic — which is what a loop is for. The node plays
/// segments of the file on its own sample timeline, so a pass scheduled straight
/// behind another begins on the sample after the last one ends. While looping
/// there is always one whole pass queued, and each pass that is used up queues
/// the next.
///
/// **Several files at once, since the song pane.** A song renders to a mix and
/// one stem per layer, and the pane plays them as one thing: every file has a
/// node of its own, every node is started at the same host time and scheduled
/// from the same moment, and a stem is muted by its node's volume rather than by
/// stopping it, so muting and unmuting never lose the place. The stems are not
/// all the same length — each layer keeps its own reverb tail — so the shorter
/// ones are padded with silence to the longest, and a loop over them stays in
/// step from pass to pass.
///
/// The engine is started on the first play and not before, so opening a tab
/// touches no audio device. A driven run is muted: it proves where the playhead
/// is, and a machine that starts making sound while somebody works is a jump
/// scare.
@MainActor
final class AudioPlayback {
	/// One file and the node that plays it.
	private struct Voice {
		let file: AVAudioFile
		let node = AVAudioPlayerNode()
		/// Silence to the longest file's end, in this file's own frames; nil
		/// when this is the longest.
		let padding: AVAudioPCMBuffer?
		/// This file's length in its own frames.
		var length: AVAudioFramePosition { file.length }
		var rate: Double { file.processingFormat.sampleRate }
	}

	private let voices: [Voice]
	private let engine = AVAudioEngine()
	/// The one whose sample time is the playhead: the first.
	private var node: AVAudioPlayerNode { voices[0].node }

	/// The first file's rate, which is the timeline every frame here is in.
	let sampleRate: Double
	/// The longest file's length, in `sampleRate` frames.
	let frameCount: AVAudioFramePosition

	private(set) var isPlaying = false
	/// The frame the current schedule began at.
	private var scheduledFrom: AVAudioFramePosition = 0
	/// Where the playhead rests while nothing plays.
	private var restingFrame: AVAudioFramePosition = 0
	/// Bumped by every stop and every reschedule, so a completion from a
	/// schedule that has been replaced does nothing.
	private var generation = 0
	private var configurationObserver: NSObjectProtocol?

	/// Playing stopped by itself: the end of a pass without the loop, or the
	/// output device going away.
	var onStopped: (() -> Void)?

	var isLooping = false {
		didSet {
			guard isLooping != oldValue, isPlaying else { return }
			// From where it is, under the new rule. A restart that can be heard
			// once, at the press, rather than a seam at every pass.
			let here = currentFrame
			stopNodes()
			start(from: here)
		}
	}

	convenience init(url: URL) throws {
		try self.init(urls: [url])
	}

	/// - Parameter urls: the files to play together, the first of which is the
	///   timeline. At least one.
	init(urls: [URL]) throws {
		precondition(!urls.isEmpty, "a playback needs a file")
		let files = try urls.map { try AVAudioFile(forReading: $0) }
		let rate = files[0].processingFormat.sampleRate
		sampleRate = rate
		// The longest, measured in seconds so a file at another rate is still
		// padded to the right end.
		let longest = files.map { Double($0.length) / max(1, $0.processingFormat.sampleRate) }.max() ?? 0
		frameCount = AVAudioFramePosition((longest * rate).rounded())

		voices = files.map { file in
			let own = AVAudioFramePosition((longest * file.processingFormat.sampleRate).rounded())
			let short = AVAudioFrameCount(max(0, own - file.length))
			return Voice(file: file, padding: short > 0 ? Self.silence(short, as: file.processingFormat) : nil)
		}
		for voice in voices {
			engine.attach(voice.node)
			engine.connect(voice.node, to: engine.mainMixerNode, format: voice.file.processingFormat)
		}
		if DrivenRun.isActive { engine.mainMixerNode.outputVolume = 0 }

		// Headphones unplugged, the output device changed: the engine stops, and
		// the player says so rather than showing a playhead that is not moving.
		configurationObserver = NotificationCenter.default.addObserver(
			forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self, self.isPlaying else { return }
				self.restingFrame = self.currentFrame
				self.isPlaying = false
				self.generation += 1
				self.onStopped?()
			}
		}
	}

	/// Silence, `frames` long, in a file's format.
	private static func silence(_ frames: AVAudioFrameCount, as format: AVAudioFormat) -> AVAudioPCMBuffer? {
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
		buffer.frameLength = frames
		if let channels = buffer.floatChannelData {
			for channel in 0..<Int(format.channelCount) {
				channels[channel].update(repeating: 0, count: Int(frames))
			}
		}
		return buffer
	}

	/// Stops for good: the tab has gone.
	func tearDown() {
		if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
		configurationObserver = nil
		generation += 1
		for voice in voices { voice.node.stop() }
		engine.stop()
		isPlaying = false
	}

	var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

	var voiceCount: Int { voices.count }

	/// How loud one file plays, 0 to 1. A muted stem is one at 0: it keeps
	/// its place, so unmuting it is instant and in step.
	func setVolume(_ volume: Float, ofVoice index: Int) {
		guard voices.indices.contains(index) else { return }
		voices[index].node.volume = max(0, min(1, volume))
	}

	func volume(ofVoice index: Int) -> Float {
		voices.indices.contains(index) ? voices[index].node.volume : 0
	}

	/// Where the playhead is, in frames, wrapped by the length while looping.
	var currentFrame: AVAudioFramePosition {
		guard isPlaying,
		      let renderTime = node.lastRenderTime,
		      let playerTime = node.playerTime(forNodeTime: renderTime)
		else { return restingFrame }
		let played = scheduledFrom + max(0, playerTime.sampleTime)
		guard played >= frameCount, frameCount > 0 else { return played }
		return isLooping ? (played - frameCount) % frameCount : frameCount
	}

	var currentSeconds: Double {
		sampleRate > 0 ? Double(currentFrame) / sampleRate : 0
	}

	func play() {
		guard !isPlaying, frameCount > 0 else { return }
		if !engine.isRunning {
			do { try engine.start() } catch { return }
		}
		// From the top again once it has run to the end.
		start(from: restingFrame >= frameCount ? 0 : restingFrame)
	}

	func pause() {
		guard isPlaying else { return }
		restingFrame = currentFrame
		stopNodes()
		isPlaying = false
	}

	func seek(toSeconds seconds: Double) {
		let frame = AVAudioFramePosition(max(0, min(Double(frameCount), seconds * sampleRate)))
		if isPlaying {
			stopNodes()
			start(from: frame)
		} else {
			restingFrame = frame
		}
	}

	// MARK: - Scheduling

	private func start(from frame: AVAudioFramePosition) {
		generation += 1
		let scheduled = generation
		scheduledFrom = frame
		restingFrame = frame

		for index in voices.indices {
			schedulePass(ofVoice: index, from: frame, generation: scheduled)
			if isLooping { queuePass(ofVoice: index, generation: scheduled) }
		}

		if voices.count == 1 {
			node.play()
		} else {
			// Every node at the same host time, a few milliseconds out, so the
			// stems start on the same sample. Started one after another with
			// `play()` they would be as far apart as the calls took.
			let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.02))
			for voice in voices { voice.node.play(at: start) }
		}
		isPlaying = true
	}

	/// The rest of one file from `frame` — its sound, then its silence to
	/// the longest file's end. The timeline's voice reports the end of the
	/// pass; the others play theirs and say nothing.
	private func schedulePass(ofVoice index: Int, from frame: AVAudioFramePosition, generation scheduled: Int) {
		let voice = voices[index]
		let own = AVAudioFramePosition((Double(frame) * voice.rate / sampleRate).rounded())
		let remaining = voice.length - own
		let padding = voice.padding.map { AVAudioFrameCount(max(0, Int64($0.frameLength) - max(0, own - voice.length))) } ?? 0
		var ended: (@Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void)?
		if index == 0 {
			ended = { [weak self] _ in DispatchQueue.main.async { self?.passPlayed(scheduled) } }
		}

		if remaining > 0 {
			let onSegment: (@Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void)? = padding > 0 ? nil : ended
			voice.node.scheduleSegment(
				voice.file, startingFrame: own, frameCount: AVAudioFrameCount(remaining), at: nil,
				completionCallbackType: .dataPlayedBack, completionHandler: onSegment
			)
		}
		if padding > 0, let silence = voice.padding {
			// The tail of the padding: what is left of it after `own`.
			let buffer = padding == silence.frameLength ? silence : Self.silence(padding, as: voice.file.processingFormat)
			guard let buffer else { return }
			voice.node.scheduleBuffer(
				buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack, completionHandler: ended
			)
		}
	}

	/// One more whole pass behind whatever is queued, and another when this one
	/// has been consumed — so the node never runs dry between passes.
	private func queuePass(ofVoice index: Int, generation scheduled: Int) {
		let voice = voices[index]
		let again: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
			DispatchQueue.main.async {
				guard let self, self.generation == scheduled, self.isLooping, self.isPlaying else { return }
				self.queuePass(ofVoice: index, generation: scheduled)
			}
		}
		let onSegment: (@Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void)? = voice.padding == nil ? again : nil
		voice.node.scheduleSegment(
			voice.file, startingFrame: 0, frameCount: AVAudioFrameCount(voice.length), at: nil,
			completionCallbackType: .dataConsumed, completionHandler: onSegment
		)
		if let padding = voice.padding {
			voice.node.scheduleBuffer(
				padding, at: nil, options: [], completionCallbackType: .dataConsumed, completionHandler: again
			)
		}
	}

	private func passPlayed(_ scheduled: Int) {
		// A pass that ends while looping is followed by the one queued behind it.
		guard generation == scheduled, isPlaying, !isLooping else { return }
		restingFrame = frameCount
		stopNodes()
		isPlaying = false
		onStopped?()
	}

	private func stopNodes() {
		generation += 1
		for voice in voices { voice.node.stop() }
	}
}
