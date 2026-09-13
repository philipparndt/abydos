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
/// The engine is started on the first play and not before, so opening a tab
/// touches no audio device. A driven run is muted: it proves where the playhead
/// is, and a machine that starts making sound while somebody works is a jump
/// scare.
@MainActor
final class AudioPlayback {
	private let file: AVAudioFile
	private let engine = AVAudioEngine()
	private let node = AVAudioPlayerNode()

	let sampleRate: Double
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
			stopNode()
			start(from: here)
		}
	}

	init(url: URL) throws {
		file = try AVAudioFile(forReading: url)
		sampleRate = file.processingFormat.sampleRate
		frameCount = file.length
		engine.attach(node)
		engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
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

	/// Stops for good: the tab has gone.
	func tearDown() {
		if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
		configurationObserver = nil
		generation += 1
		node.stop()
		engine.stop()
		isPlaying = false
	}

	var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

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
		stopNode()
		isPlaying = false
	}

	func seek(toSeconds seconds: Double) {
		let frame = AVAudioFramePosition(max(0, min(Double(frameCount), seconds * sampleRate)))
		if isPlaying {
			stopNode()
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

		let remaining = frameCount - frame
		if remaining > 0 {
			node.scheduleSegment(
				file, startingFrame: frame, frameCount: AVAudioFrameCount(remaining), at: nil,
				completionCallbackType: .dataPlayedBack
			) { [weak self] _ in
				DispatchQueue.main.async { self?.passPlayed(scheduled) }
			}
		}
		if isLooping { queuePass(for: scheduled) }
		node.play()
		isPlaying = true
	}

	/// One more whole pass behind whatever is queued, and another when this one
	/// has been consumed — so the node never runs dry between passes.
	private func queuePass(for scheduled: Int) {
		node.scheduleSegment(
			file, startingFrame: 0, frameCount: AVAudioFrameCount(frameCount), at: nil,
			completionCallbackType: .dataConsumed
		) { [weak self] _ in
			DispatchQueue.main.async {
				guard let self, self.generation == scheduled, self.isLooping, self.isPlaying else { return }
				self.queuePass(for: scheduled)
			}
		}
	}

	private func passPlayed(_ scheduled: Int) {
		// A pass that ends while looping is followed by the one queued behind it.
		guard generation == scheduled, isPlaying, !isLooping else { return }
		restingFrame = frameCount
		stopNode()
		isPlaying = false
		onStopped?()
	}

	private func stopNode() {
		generation += 1
		node.stop()
	}
}
