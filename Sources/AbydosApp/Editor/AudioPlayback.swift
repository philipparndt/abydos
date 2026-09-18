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
		/// A `var` because a file that is still being written is opened again
		/// to see what has arrived: an `AVAudioFile` knows the length it had
		/// when it was opened, and never more.
		var file: AVAudioFile
		let node = AVAudioPlayerNode()
		/// Silence to the longest file's end, in this file's own frames; nil
		/// when this is the longest.
		var padding: AVAudioPCMBuffer?
		/// This file's length in its own frames.
		var length: AVAudioFramePosition { file.length }
		var rate: Double { file.processingFormat.sampleRate }
	}

	private var voices: [Voice]
	/// The volume each voice is at, or on its way to: see `setVolumes`.
	private var volumes: [Float]
	private var fade: Timer?
	private let engine = AVAudioEngine()
	/// The one whose sample time is the playhead: the first.
	private var node: AVAudioPlayerNode { voices[0].node }

	/// The first file's rate, which is the timeline every frame here is in.
	let sampleRate: Double
	/// The longest file's length, in `sampleRate` frames. A `var` because a
	/// streamed render grows: see `grew(toFrames:)`.
	private(set) var frameCount: AVAudioFramePosition

	private(set) var isPlaying = false

	/// The file is still being written — `mat render --stream` — so its end is
	/// not the song's end, and what has arrived since the last schedule is put
	/// behind what is already queued rather than restarting anything.
	///
	/// Asked for 2026-09-16: "it takes way too long till a song can be started
	/// … can we create a render streaming support?"
	private(set) var isGrowing = false
	/// The frame every voice is scheduled up to, while growing.
	private var scheduledThrough: AVAudioFramePosition = 0
	/// Playing ran out of rendered song and waits for more. Only the first
	/// seconds of a song can do this: `mat` renders far faster than real time.
	private var isStarved = false
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

	/// What the loop plays, in seconds; nil for the whole of it.
	///
	/// Asked for 2026-09-16: "Would be nice if we could play one section in a
	/// loop and while playing make the changes to the sounds" — so a few bars
	/// go round while the song is rendered again under them.
	var loopRange: ClosedRange<Double>? {
		didSet {
			guard loopRange != oldValue, isPlaying else { return }
			let here = currentFrame
			stopNodes()
			start(from: here)
		}
	}

	/// The loop's first frame and the frame it ends before.
	private var loopBounds: (from: AVAudioFramePosition, to: AVAudioFramePosition) {
		guard let loopRange, sampleRate > 0 else { return (0, frameCount) }
		let from = AVAudioFramePosition(max(0, loopRange.lowerBound * sampleRate))
		let to = AVAudioFramePosition(min(Double(frameCount), loopRange.upperBound * sampleRate))
		return to > from ? (from, to) : (0, frameCount)
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

		voices = files.map { Voice(file: $0, padding: Self.padding(of: $0, toSeconds: longest)) }
		volumes = Array(repeating: 1, count: files.count)
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

	/// Silence from a file's end to `longest` seconds; nil when it reaches that.
	private static func padding(of file: AVAudioFile, toSeconds longest: Double) -> AVAudioPCMBuffer? {
		let own = AVAudioFramePosition((longest * file.processingFormat.sampleRate).rounded())
		let short = AVAudioFrameCount(max(0, own - file.length))
		return short > 0 ? silence(short, as: file.processingFormat) : nil
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
		fade?.invalidate()
		fade = nil
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
		var all = volumes
		all[index] = volume
		setVolumes(all)
	}

	/// How loud every file plays, 0 to 1, changed together and faded.
	///
	/// Reported 2026-09-18: "when switching between stem and Mix there is a
	/// small interruption / click". The switch set one node's volume after
	/// another, so a render cycle could fall between the mix going to nothing
	/// and the stems coming up — a hole — and even without one, a mix after
	/// its limiter and the stems before it are not the same wave, so a cut
	/// from one to the other is a step in the signal. Now every voice moves in
	/// the same tick, from where it is to where it is going, over `fadeSeconds`.
	func setVolumes(_ targets: [Float]) {
		for index in voices.indices where index < targets.count {
			volumes[index] = max(0, min(1, targets[index]))
		}
		fade?.invalidate()
		fade = nil
		guard isPlaying else {
			for index in voices.indices { voices[index].node.volume = volumes[index] }
			return
		}
		let from = voices.map(\.node.volume)
		let to = volumes
		let began = ProcessInfo.processInfo.systemUptime
		let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] timer in
			MainActor.assumeIsolated {
				guard let self else { timer.invalidate(); return }
				let done = min(1, (ProcessInfo.processInfo.systemUptime - began) / Self.fadeSeconds)
				for index in self.voices.indices where index < to.count {
					self.voices[index].node.volume = from[index] + (to[index] - from[index]) * Float(done)
				}
				if done >= 1 {
					timer.invalidate()
					self.fade = nil
				}
			}
		}
		RunLoop.main.add(timer, forMode: .common)
		fade = timer
	}

	/// How long a change of volume takes. Long enough that the steps it is
	/// made in — a render cycle apart, some ten milliseconds — are small.
	static let fadeSeconds: Double = 0.08

	/// Where a voice's volume is going, which is where it is once a fade is over.
	func volume(ofVoice index: Int) -> Float {
		volumes.indices.contains(index) ? volumes[index] : 0
	}

	/// Where the timeline's node has got to since it was scheduled, neither
	/// wrapped nor stopped at the end; nil while nothing plays.
	private var playedFrame: AVAudioFramePosition? {
		// **A render time with no valid time in it crashes the app.** Right
		// after nodes are started at a future sample time, `lastRenderTime` is
		// an `AVAudioTime` with neither its sample time nor its host time valid,
		// and `playerTime(forNodeTime:)` raises an Objective-C exception on it —
		// which Swift cannot catch. Three crashes on 2026-09-14, all a render
		// landing while a song played: the new player is started and asked
		// where it is in the same turn. Until the node has rendered, it is
		// where it was scheduled from.
		guard isPlaying,
		      let renderTime = node.lastRenderTime,
		      renderTime.isSampleTimeValid,
		      let playerTime = node.playerTime(forNodeTime: renderTime)
		else { return nil }
		return scheduledFrom + max(0, playerTime.sampleTime)
	}

	/// Where the playhead is, in frames, wrapped by the length while looping.
	var currentFrame: AVAudioFramePosition {
		guard let played = playedFrame else { return restingFrame }
		return wrapped(played)
	}

	/// A frame on the node's timeline as a place in the song: into the loop
	/// while looping, and no further than the end.
	private func wrapped(_ played: AVAudioFramePosition) -> AVAudioFramePosition {
		guard frameCount > 0 else { return played }
		if isLooping {
			let (from, to) = loopBounds
			let length = max(1, to - from)
			guard played >= to else { return played }
			return from + (played - to) % length
		}
		guard played >= frameCount else { return played }
		return frameCount
	}

	var currentSeconds: Double {
		sampleRate > 0 ? Double(currentFrame) / sampleRate : 0
	}


	func play() {
		guard !isPlaying, frameCount > 0 else { return }
		if !engine.isRunning {
			do { try engine.start() } catch { return }
			// Several files start on the output's sample clock, which exists
			// once the engine has rendered; measured, it has by the time `start`
			// returns, and this waits at most a tenth of a second if it has not.
			if voices.count > 1 {
				for _ in 0..<100 where engine.outputNode.lastRenderTime?.isSampleTimeValid != true {
					usleep(1000)
				}
			}
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
		// Into the loop, when the playhead is outside it: a pass that begins
		// past the loop's end has nothing to play.
		var frame = frame
		if isLooping {
			let (from, to) = loopBounds
			if frame < from || frame >= to { frame = from }
		}
		scheduledFrom = frame
		restingFrame = frame
		scheduledThrough = frameCount
		isStarved = false
		// What has been written since the files were opened, which the files
		// as they were opened cannot see.
		if isGrowing { for index in voices.indices { reopen(index) } }

		for index in voices.indices {
			let through = schedulePass(ofVoice: index, from: frame, generation: scheduled)
			if index == 0, isGrowing { scheduledThrough = through }
			if isLooping { queuePass(ofVoice: index, generation: scheduled) }
		}

		if voices.count == 1 {
			node.play()
		} else if let now = engine.outputNode.lastRenderTime, now.isSampleTimeValid {
			// **Every node at one sample time on the output's clock.** Reported
			// 2026-09-14: the stems sounded very slightly off. They were started
			// at one *host* time, 20 ms out, and measured with a noise file and
			// its inverse on two players through a silent mixer: started that
			// way the pair did not cancel (residual 0.499 of a 0.5 noise), while
			// the players' own clocks said they were in step — which is what the
			// pane's drift report had read, and why it said zero. Started at one
			// sample time, 1024 frames out, they cancel to 0.0000, eight trials
			// of eight. `play()` one after the other was 512 frames apart.
			let start = AVAudioTime(sampleTime: now.sampleTime + 1024, atRate: now.sampleRate)
			for voice in voices { voice.node.play(at: start) }
		} else {
			let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.02))
			for voice in voices { voice.node.play(at: start) }
		}
		isPlaying = true
	}

	/// The rest of one file from `frame` — its sound, then its silence to
	/// the longest file's end. The timeline's voice reports the end of the
	/// pass; the others play theirs and say nothing.
	///
	/// - Returns: the frame the pass ends before, on the timeline. While the
	///   file grows that is as far as it has been written, which is not the end.
	@discardableResult
	private func schedulePass(
		ofVoice index: Int, from frame: AVAudioFramePosition, generation scheduled: Int
	) -> AVAudioFramePosition {
		let voice = voices[index]
		let own = ownFrame(frame, of: voice)
		// A loop over part of the song ends where it ends, and has no padding:
		// the file goes on past it.
		if isLooping, loopRange != nil {
			let ownEnd = ownFrame(loopBounds.to, of: voice)
			let count = min(ownEnd, voice.length) - own
			guard count > 0 else { return frame }
			voice.node.scheduleSegment(
				voice.file, startingFrame: own, frameCount: AVAudioFrameCount(count), at: nil,
				completionCallbackType: .dataPlayedBack, completionHandler: ended(ofVoice: index, generation: scheduled)
			)
			return loopBounds.to
		}
		// Growing, the file may hold a little more than the render has said is
		// written — the stretch being written — and that is not played yet.
		let written = isGrowing ? min(voice.length, ownFrame(frameCount, of: voice)) : voice.length
		let remaining = written - own
		// Nor is it padded: its end is not the song's end.
		let padding = isGrowing ? 0 : voice.padding.map {
			AVAudioFrameCount(max(0, Int64($0.frameLength) - max(0, own - voice.length)))
		} ?? 0
		let through = isGrowing ? timelineFrame(max(own, written), of: voice) : frameCount
		let ended = ended(ofVoice: index, generation: scheduled, through: through)

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
			guard let buffer else { return through }
			voice.node.scheduleBuffer(
				buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack, completionHandler: ended
			)
		}
		return through
	}

	/// What the timeline's voice says when a stretch of it has been heard;
	/// nil for the others, which say nothing.
	///
	/// - Parameter through: the frame the stretch ends before, so a stretch
	///   with more queued behind it is not taken for the last one.
	private func ended(
		ofVoice index: Int, generation scheduled: Int, through: AVAudioFramePosition = .max
	) -> (@Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void)? {
		guard index == 0 else { return nil }
		return { [weak self] _ in DispatchQueue.main.async { self?.passPlayed(scheduled, through: through) } }
	}

	/// A frame on the timeline as a frame of one voice's file, and back.
	private func ownFrame(_ frame: AVAudioFramePosition, of voice: Voice) -> AVAudioFramePosition {
		AVAudioFramePosition((Double(frame) * voice.rate / sampleRate).rounded())
	}

	private func timelineFrame(_ own: AVAudioFramePosition, of voice: Voice) -> AVAudioFramePosition {
		AVAudioFramePosition((Double(own) * sampleRate / voice.rate).rounded())
	}

	/// Opens a voice's file again, to see what has been written to it since.
	private func reopen(_ index: Int) {
		guard let file = try? AVAudioFile(forReading: voices[index].file.url) else { return }
		voices[index].file = file
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
		// Part of the song: the same stretch again, and nothing after it.
		if loopRange != nil {
			let (from, to) = loopBounds
			let ownFrom = AVAudioFramePosition((Double(from) * voice.rate / sampleRate).rounded())
			let ownTo = min(AVAudioFramePosition((Double(to) * voice.rate / sampleRate).rounded()), voice.length)
			guard ownTo > ownFrom else { return }
			voice.node.scheduleSegment(
				voice.file, startingFrame: ownFrom, frameCount: AVAudioFrameCount(ownTo - ownFrom), at: nil,
				completionCallbackType: .dataConsumed, completionHandler: again
			)
			return
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

	// MARK: - Files that join

	/// Plays these files too, from where the others are, without stopping
	/// them. They join silent; `setVolumes` brings them in.
	///
	/// For the stems of a streamed render, which land when the mix is already
	/// playing. Before this the song was made again from all of its files — a
	/// new engine, started where the old one was torn down — and that was a
	/// hole in the sound at the moment the render finished.
	func add(urls: [URL]) throws {
		let files = try urls.map { try AVAudioFile(forReading: $0) }
		guard !files.isEmpty else { return }
		// The files already playing, whole: a render that has finished.
		for index in voices.indices { reopen(index) }
		let longest = max(
			Double(frameCount) / max(1, sampleRate),
			files.map { Double($0.length) / max(1, $0.processingFormat.sampleRate) }.max() ?? 0
		)
		let lengthened = AVAudioFramePosition((longest * sampleRate).rounded()) > frameCount
		if lengthened {
			frameCount = AVAudioFramePosition((longest * sampleRate).rounded())
			for index in voices.indices {
				voices[index].padding = Self.padding(of: voices[index].file, toSeconds: longest)
			}
		}
		let first = voices.count
		for file in files {
			let voice = Voice(file: file, padding: Self.padding(of: file, toSeconds: longest))
			voice.node.volume = 0
			engine.attach(voice.node)
			engine.connect(voice.node, to: engine.mainMixerNode, format: file.processingFormat)
			voices.append(voice)
			volumes.append(0)
		}
		guard isPlaying else { return }
		// Longer than what is queued: the passes queued end too soon, and what
		// plays is scheduled again, once.
		let now = engine.outputNode.lastRenderTime
		let at = now.flatMap { $0.isSampleTimeValid ? AVAudioTime(sampleTime: $0.sampleTime + 2048, atRate: $0.sampleRate) : nil }
		guard !lengthened, let at, let playerTime = node.playerTime(forNodeTime: at) else {
			let here = currentFrame
			stopNodes()
			start(from: here)
			return
		}
		// Where the timeline's node will be at that sample time, which is where
		// the new ones start from: on the same clock, as `start` does it.
		let frame = wrapped(scheduledFrom + max(0, playerTime.sampleTime))
		for index in first..<voices.count {
			schedulePass(ofVoice: index, from: frame, generation: generation)
			if isLooping { queuePass(ofVoice: index, generation: generation) }
			voices[index].node.play(at: at)
		}
	}

	// MARK: - A file that is still being written

	/// Plays this file as one that grows: nothing stops at what is in it now.
	func beGrowing() {
		isGrowing = true
	}

	/// More of the render has been written: `frames` of it can be read.
	///
	/// What has arrived goes behind what is queued, on the node's own
	/// timeline, so it plays straight on from the last sample scheduled — the
	/// same seamlessness the loop is built on. Nothing is rescheduled and the
	/// playhead does not move.
	///
	/// - Parameter finished: the render is over. The file can end up a little
	///   *shorter* than the last reading said, since the tail is trimmed and
	///   faded, so anything queued past its end is dropped by scheduling again
	///   from where the playhead is.
	func grew(toFrames frames: AVAudioFramePosition, finished: Bool = false) {
		guard isGrowing else { return }
		if finished {
			isGrowing = false
			// The whole file, for every schedule from now on: a seek, a loop,
			// a play from the top.
			for index in voices.indices { reopen(index) }
		}
		let shrank = frames < frameCount
		frameCount = max(0, frames)
		guard isPlaying || isStarved else { return }
		if shrank {
			isStarved = false
			let here = min(currentFrame, frameCount)
			stopNodes()
			isPlaying = false
			guard here < frameCount else {
				restingFrame = frameCount
				onStopped?()
				return
			}
			start(from: here)
			return
		}
		if isStarved {
			// Ran dry waiting for the render: on again from where it stopped.
			guard restingFrame < frameCount else { return }
			isStarved = false
			start(from: restingFrame)
			return
		}
		// A loop plays what it has, and takes what has arrived on its next
		// pass: a stretch put behind it would play after the loop, not in it.
		guard frameCount > scheduledThrough, !isLooping else { return }
		// **Ran dry before this arrived.** The node's clock goes on through
		// the silence, and what is put behind it now would play from wherever
		// that clock is while the playhead says it is later in the song. So
		// on again from where the sound ran out, scheduled afresh.
		if let played = playedFrame, played + AVAudioFramePosition(sampleRate * Self.margin) >= scheduledThrough {
			let here = min(played, scheduledThrough)
			stopNodes()
			start(from: here)
			return
		}
		guard let through = append(toVoice: 0, upTo: frameCount) else { return }
		for index in voices.indices.dropFirst() { _ = append(toVoice: index, upTo: through) }
		scheduledThrough = through
	}

	/// How close to running dry a node can be and still have a stretch put
	/// behind it in time: a few render cycles.
	static let margin: Double = 0.03

	/// Nothing more is coming: what is in the file is the whole song. Said when
	/// a render ends without saying so itself — it failed, or it was replaced.
	func stoppedGrowing() {
		guard isGrowing else { return }
		isGrowing = false
		guard isStarved else { return }
		isStarved = false
		restingFrame = frameCount
		onStopped?()
	}

	/// The stretch between what is queued and what has been written, out of the
	/// file as it is now — the file opened before the write cannot see it.
	///
	/// - Returns: the frame on the timeline the stretch ends before; nil when
	///   there was nothing new in the file to put behind what is queued.
	private func append(toVoice index: Int, upTo frames: AVAudioFramePosition) -> AVAudioFramePosition? {
		reopen(index)
		let voice = voices[index]
		let from = ownFrame(scheduledThrough, of: voice)
		let to = min(ownFrame(frames, of: voice), voice.length)
		guard to > from else { return nil }
		let through = timelineFrame(to, of: voice)
		voice.node.scheduleSegment(
			voice.file, startingFrame: from, frameCount: AVAudioFrameCount(to - from), at: nil,
			completionCallbackType: .dataPlayedBack,
			completionHandler: ended(ofVoice: index, generation: generation, through: through)
		)
		return through
	}

	private func passPlayed(_ scheduled: Int, through: AVAudioFramePosition) {
		// Everything written has been played and there is more coming: the
		// render fell behind. It waits where the sound ran out, until the next
		// stretch lands.
		//
		// **Only the last stretch queued says so.** Reported 2026-09-18: "when
		// open a song file and start it while it is still streaming, there are
		// some heavy interruptions and false playbacks in the first seconds".
		// Every stretch put behind the first said it had been played, and every
		// one was taken for the render having fallen behind: the sound stopped
		// at each and started again at the next, from a file opened before any
		// of them had been written.
		if generation == scheduled, isPlaying, isGrowing, !isLooping {
			guard through >= scheduledThrough else { return }
			restingFrame = min(through, frameCount)
			stopNodes()
			isPlaying = false
			isStarved = true
			return
		}
		// A pass that ends while looping is followed by the one queued behind it.
		// A stretch that ends with more queued behind it is not the end: the
		// render finished while it was queued.
		guard generation == scheduled, isPlaying, !isLooping, through >= scheduledThrough else { return }
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
