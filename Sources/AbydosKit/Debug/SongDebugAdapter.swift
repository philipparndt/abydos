import Foundation

/// A playing song as a program in the debugger: its tracks are the threads,
/// and a track's stack is the note it is on, inside the pattern it is playing,
/// inside the `play` step that plays it, inside the track.
///
/// Asked for on 2026-09-15: "while playing the debugger shall also be open,
/// showing the threads". The song pane is the program — it plays, it pauses,
/// it stops on breakpoints — and this answers the debug pane's questions about
/// it in the Debug Adapter Protocol, from the timeline `mat lsp` sends, so the
/// pane, its toolbar and its breakpoint list are the ones every debugger here
/// uses. Nothing is spawned: see `InProcessDebugAdapter`.
///
/// Everything the answers need comes through closures, so it is tested with
/// a timeline and a clock and no pane.
public final class SongDebugAdapter: InProcessDebugAdapter {
	public var send: (([String: Any]) -> Void)?

	/// The song's file, which every frame is in.
	public let program: String
	private let placedTimeline: () -> LineTimeline?
	/// A line of the song as it is now, 0-based.
	private let lineText: (Int) -> String?
	/// Where the song is, in seconds.
	private let now: () -> Double

	/// The debugger's verbs, done to the song.
	public var onContinue: () -> Void = {}
	public var onPause: () -> Void = {}
	/// Step: the song goes to this moment and stays paused there.
	public var onStep: (Double) -> Void = { _ in }
	/// Stop, or the session going away: the song pauses.
	public var onDisconnect: () -> Void = {}

	private var sequence = 1
	private var configured = false
	/// Where the song was when it last stopped, for the stack of a stop.
	private var stoppedAt: (seconds: Double, line: Int?)?
	private var lastThreadNames: [String] = []
	private var lastTops: [String] = []
	private var lastMoveSaid = Date.distantPast

	public init(program: String, timeline: @escaping () -> LineTimeline?, lineText: @escaping (Int) -> String?, now: @escaping () -> Double) {
		self.program = program
		self.placedTimeline = timeline
		self.lineText = lineText
		self.now = now
	}

	// MARK: - What the song says

	/// The song paused: on a breakpoint's line (0-based), or where it was.
	public func stopped(line: Int?) {
		guard configured else { return }
		let seconds = now()
		stoppedAt = (seconds, line)
		let thread = line.flatMap { threadHearing(line: $0, at: seconds) } ?? threads(at: seconds).first?.id ?? 1
		event("stopped", [
			"reason": line == nil ? "pause" : "breakpoint",
			"threadId": thread,
			"allThreadsStopped": true,
			"description": line.map { "Stopped on line \($0 + 1)" } ?? "Paused",
		])
	}

	/// The song plays again.
	public func continued() {
		guard configured else { return }
		stoppedAt = nil
		event("continued", ["threadId": 1, "allThreadsContinued": true])
	}

	/// The song ran to its end: the program exited.
	public func ended() {
		guard configured else { return }
		event("exited", ["exitCode": 0])
		event("terminated", [:])
		configured = false
	}

	/// The playhead moved while playing: says when a thread's name changed —
	/// a track went on to another pattern — and, a few times a second at most,
	/// when some track's note did.
	public func tick() {
		guard configured else { return }
		let seconds = now()
		let listed = threads(at: seconds)
		let names = listed.map(\.name)
		if names != lastThreadNames {
			lastThreadNames = names
			event("thread", ["reason": "started", "threadId": listed.first?.id ?? 1])
		}
		let tops = listed.map { frames(thread: $0.id, at: seconds).first?.name ?? "" }
		if tops != lastTops, Date().timeIntervalSince(lastMoveSaid) > 0.12 {
			lastTops = tops
			lastMoveSaid = Date()
			event(DebugSession.stackMovedEvent, [:])
		}
	}

	// MARK: - The program's structure

	public struct Frame: Equatable, Sendable {
		public var id: Int
		public var name: String
		/// 1-based, as the protocol is asked for.
		public var line: Int
		public var column: Int
	}

	/// One thread per heard track, named for what it is playing now.
	public func threads(at seconds: Double) -> [(id: Int, name: String)] {
		guard let timeline = placedTimeline() else { return [] }
		return timeline.tracks.enumerated().map { index, track in
			let what: String
			if let play = play(of: track, at: seconds) {
				what = play.pattern ?? "audio"
			} else if let last = track.plays.last, seconds >= last.end {
				what = "done"
			} else {
				what = "resting"
			}
			return (index + 1, "\(track.name) · \(what)")
		}
	}

	/// A track's stack at a moment, innermost first.
	public func frames(thread: Int, at seconds: Double) -> [Frame] {
		guard let timeline = placedTimeline(), timeline.tracks.indices.contains(thread - 1) else { return [] }
		let track = timeline.tracks[thread - 1]
		var frames: [(name: String, line: Int, column: Int)] = []
		if let play = play(of: track, at: seconds) {
			let passes = max(1, Int(((play.end - play.start) / max(play.pass, 0.001)).rounded()))
			if let patternLine = play.patternLine, let pattern = play.pattern, play.pass > 0 {
				let pass = min(passes - 1, max(0, Int(((seconds + LineTimeline.slack - play.start) / play.pass).rounded(.down))))
				let passStart = play.start + Double(pass) * play.pass
				for note in sounding(in: patternLine, pattern: pattern, passStart: passStart, at: seconds, timeline: timeline) {
					frames.append(note)
				}
				frames.append(("pattern \(pattern) · pass \(pass + 1) of \(passes)", patternLine, 0))
			}
			frames.append(("play \(play.pattern ?? "audio")\(passes > 1 ? " x\(passes)" : "")", play.line, 0))
		}
		frames.append(("track \(track.name)", track.line, 0))
		// A stop on a breakpoint is where the program is: the frames inside the
		// line it stopped on are not reached yet.
		if let stop = stoppedAt, abs(stop.seconds - seconds) < 0.001, let line = stop.line,
		   let index = frames.firstIndex(where: { $0.line == line }) {
			frames.removeFirst(index)
		}
		return frames.enumerated().map { depth, frame in
			Frame(id: thread * 100 + depth, name: frame.name, line: frame.line + 1, column: frame.column + 1)
		}
	}

	private func play(of track: LineTimeline.Track, at seconds: Double) -> LineTimeline.Play? {
		let at = seconds + LineTimeline.slack
		return track.plays.first { $0.start <= at && at < $0.end }
	}

	/// The notes a pass of a pattern is on: its lines, from its header to the
	/// next header anything names, that have a note sounding.
	private func sounding(
		in patternLine: Int, pattern: String, passStart: Double, at seconds: Double, timeline: LineTimeline
	) -> [(name: String, line: Int, column: Int)] {
		let headers = Set(timeline.tracks.flatMap { track in
			[track.line] + [track.instrumentLine].compactMap { $0 } + track.plays.compactMap(\.patternLine)
		})
		let end = headers.filter { $0 > patternLine }.min() ?? Int.max
		let into = seconds + LineTimeline.slack - passStart
		var found: [(name: String, line: Int, column: Int)] = []
		for (line, placed) in timeline.notes.sorted(by: { $0.key < $1.key }) where line > patternLine && line < end {
			guard placed.passes.contains(where: { abs($0 - passStart) < 0.002 }) else { continue }
			for note in placed.notes where note.start <= into && into < note.end {
				found.append(("\(pattern): \(token(line: line, columns: note.columns))", line, note.columns.lowerBound))
				break
			}
		}
		return found
	}

	private func token(line: Int, columns: Range<Int>) -> String {
		guard let text = lineText(line) as NSString?, columns.upperBound <= text.length else { return "note" }
		return text.substring(with: NSRange(location: columns.lowerBound, length: columns.count))
	}

	private func threadHearing(line: Int, at seconds: Double) -> Int? {
		threads(at: seconds).first { thread in
			frames(thread: thread.id, at: seconds).contains { $0.line == line + 1 }
		}?.id
	}

	/// What a frame's scopes hold: the moment, the track, and every note it
	/// has sounding.
	public func variables(frame: Int, scope: Int, at seconds: Double) -> [(name: String, value: String)] {
		guard let timeline = placedTimeline() else { return [] }
		let thread = frame / 100
		guard timeline.tracks.indices.contains(thread - 1) else { return [] }
		let track = timeline.tracks[thread - 1]
		let play = play(of: track, at: seconds)
		switch scope {
		case 1:
			var values = [("Time", LineTimeline.clock(seconds))]
			if timeline.barSeconds > 0 {
				let bar = Int(((seconds + LineTimeline.slack) / timeline.barSeconds).rounded(.down)) + 1
				let into = (seconds + LineTimeline.slack).truncatingRemainder(dividingBy: timeline.barSeconds) / timeline.barSeconds
				values.append(("Bar", "\(bar) · \(Int((into * 100).rounded(.down)))%"))
			}
			if let play, play.pass > 0 {
				let passes = max(1, Int(((play.end - play.start) / play.pass).rounded()))
				let pass = min(passes, Int(((seconds + LineTimeline.slack - play.start) / play.pass).rounded(.down)) + 1)
				values.append(("Pass", "\(pass) of \(passes)"))
			}
			return values
		case 2:
			var values = [("Track", track.name), ("Stem", track.layer)]
			if let instrument = track.instrument { values.append(("Instrument", instrument)) }
			values.append(("Pattern", play.map { $0.pattern ?? "audio" } ?? "none"))
			if let play, play.transpose != 0 { values.append(("Transpose", "\(play.transpose) semitones")) }
			return values
		default:
			return frames(thread: thread, at: seconds)
				.filter { $0.name.contains(": ") }
				.map { ("Line \($0.line)", String($0.name.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)) }
		}
	}

	// MARK: - The protocol

	public func receive(_ message: [String: Any]) {
		guard message["type"] as? String == "request", let command = message["command"] as? String else { return }
		let arguments = message["arguments"] as? [String: Any] ?? [:]
		let request = message["seq"] as? Int ?? 0
		func reply(_ body: [String: Any] = [:], success: Bool = true, error: String? = nil) {
			var response: [String: Any] = [
				"seq": nextSequence(), "type": "response", "request_seq": request,
				"command": command, "success": success, "body": body,
			]
			if let error { response["message"] = error }
			send?(response)
		}
		let seconds = stoppedAt?.seconds ?? now()

		switch command {
		case "initialize":
			reply(["supportsConfigurationDoneRequest": true, "supportsTerminateRequest": true])
			event("initialized", [:])
		case "launch", "attach", "setExceptionBreakpoints", "setFunctionBreakpoints":
			reply()
		case "setBreakpoints":
			let wanted = arguments["breakpoints"] as? [[String: Any]] ?? []
			reply(["breakpoints": wanted.map { ["verified": true, "line": $0["line"] as? Int ?? 0] }])
		case "configurationDone":
			configured = true
			reply()
			lastThreadNames = threads(at: seconds).map(\.name)
			event("thread", ["reason": "started", "threadId": 1])
		case "threads":
			reply(["threads": threads(at: seconds).map { ["id": $0.id, "name": $0.name] }])
		case "stackTrace":
			let thread = arguments["threadId"] as? Int ?? 1
			let frames = frames(thread: thread, at: seconds)
			reply([
				"stackFrames": frames.map { frame in
					[
						"id": frame.id, "name": frame.name, "line": frame.line, "column": frame.column,
						"source": ["path": program, "name": (program as NSString).lastPathComponent],
					] as [String: Any]
				},
				"totalFrames": frames.count,
			])
		case "scopes":
			let frame = arguments["frameId"] as? Int ?? 100
			reply(["scopes": [("Now", 1), ("Track", 2), ("Notes", 3)].map { name, scope in
				["name": name, "variablesReference": frame * 10 + scope, "expensive": false] as [String: Any]
			}])
		case "variables":
			let reference = arguments["variablesReference"] as? Int ?? 0
			let values = variables(frame: reference / 10, scope: reference % 10, at: seconds)
			reply(["variables": values.map { ["name": $0.name, "value": $0.value, "variablesReference": 0] }])
		case "continue":
			reply(["allThreadsContinued": true])
			onContinue()
		case "pause":
			reply()
			onPause()
		case "next", "stepIn", "stepOut":
			// A step is a bar: the song goes to the start of the next one and
			// stops there, which is the one unit every track shares.
			reply()
			guard let bar = placedTimeline()?.barSeconds, bar > 0 else { return }
			let next = ((seconds + LineTimeline.slack) / bar).rounded(.down) * bar + bar
			onStep(next)
			stoppedAt = (now(), nil)
			event("stopped", ["reason": "step", "threadId": arguments["threadId"] as? Int ?? 1, "allThreadsStopped": true])
		case "disconnect", "terminate":
			reply()
			configured = false
			onDisconnect()
			event("terminated", [:])
		case "evaluate":
			reply(success: false, error: "A song has no expressions to evaluate.")
		default:
			reply()
		}
	}

	private func nextSequence() -> Int {
		defer { sequence += 1 }
		return sequence
	}

	private func event(_ name: String, _ body: [String: Any]) {
		send?(["seq": nextSequence(), "type": "event", "event": name, "body": body])
	}
}
