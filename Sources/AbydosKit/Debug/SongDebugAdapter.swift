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
	/// The song's files as paths, the song first. Since includes a frame can
	/// be in any of them.
	private let files: () -> [String]
	/// Where the lines of one of `files` are heard; the song's, at 0, holds
	/// the tracks.
	private let placedTimeline: (Int) -> LineTimeline?
	/// A line of one of `files`, both 0-based.
	private let lineText: (Int, Int) -> String?
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
	private var stoppedAt: (seconds: Double, line: Int?, file: Int)?
	private var lastThreadNames: [String] = []
	private var lastTops: [String] = []
	private var lastMoveSaid = Date.distantPast

	public init(
		program: String, files: @escaping () -> [String], timeline: @escaping (Int) -> LineTimeline?,
		lineText: @escaping (Int, Int) -> String?, now: @escaping () -> Double
	) {
		self.program = program
		self.files = files
		self.placedTimeline = timeline
		self.lineText = lineText
		self.now = now
	}

	/// A song of one file.
	public convenience init(
		program: String, timeline: @escaping () -> LineTimeline?, lineText: @escaping (Int) -> String?, now: @escaping () -> Double
	) {
		self.init(
			program: program, files: { [program] }, timeline: { $0 == 0 ? timeline() : nil },
			lineText: { $0 == 0 ? lineText($1) : nil }, now: now
		)
	}

	// MARK: - What the song says

	/// The song paused: on a breakpoint's line (0-based) in one of its files,
	/// or where it was.
	public func stopped(line: Int?, file: Int = 0) {
		guard configured else { return }
		let seconds = now()
		stoppedAt = (seconds, line, file)
		let thread = line.flatMap { threadHearing(line: $0, file: file, at: seconds) } ?? threads(at: seconds).first?.id ?? 1
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
		/// Which of the song's files, 0 the song.
		public var file: Int = 0
		/// The frame this one is inside; nil for the track.
		public var parent: Int? = nil
		/// A line of the pattern with no note sounding now.
		public var isSubtle = false
	}

	/// One thread per heard track, named for what it is playing now.
	public func threads(at seconds: Double) -> [(id: Int, name: String)] {
		details(at: seconds).map { ($0.id, $0.name) }
	}

	/// The threads with what the tree needs: the stem, when several tracks
	/// share it, and whether the track is playing.
	public func details(at seconds: Double) -> [(id: Int, name: String, group: String?, quiet: Bool)] {
		guard let timeline = placedTimeline(0) else { return [] }
		let layers = Dictionary(timeline.tracks.map { ($0.layer, 1) }, uniquingKeysWith: +)
		return timeline.tracks.enumerated().map { index, track in
			let playing = play(of: track, at: seconds) != nil
			let named = name(of: track, at: seconds)
			return (index + 1, named, layers[track.layer, default: 0] > 1 ? track.layer : nil, !playing)
		}
	}

	private func name(of track: LineTimeline.Track, at seconds: Double) -> String {
		let what: String
		if let play = play(of: track, at: seconds) {
			what = play.pattern ?? "audio"
		} else if let last = track.plays.last, seconds >= last.end {
			what = "done"
		} else {
			what = "resting"
		}
		return "\(track.name) · \(what)"
	}

	/// A track's stack at a moment, as a tree: the track, the `play` step
	/// inside it, the pattern and pass inside that, and every line of the
	/// pattern side by side inside the pattern — a line with a note sounding
	/// says the note, and a line between notes says its last one, subtle.
	///
	/// Listed innermost first, as a stack is, so a client that knows nothing
	/// of `parent` still reads a stack: the lines sounding, then the quiet
	/// ones, the pattern, the play step, the track — and on a breakpoint's
	/// stop, the frame of the line it stopped on first. Ids are by position in
	/// the tree, not in the list, so a row keeps its id while notes come and go.
	public func frames(thread: Int, at seconds: Double) -> [Frame] {
		guard let timeline = placedTimeline(0), timeline.tracks.indices.contains(thread - 1) else { return [] }
		let track = timeline.tracks[thread - 1]
		let base = thread * 100
		var frames: [Frame] = []
		func frame(_ id: Int, _ name: String, line: Int, column: Int = 0, file: Int, parent: Int?, subtle: Bool = false) -> Frame {
			Frame(id: base + id, name: name, line: line + 1, column: column + 1, file: file, parent: parent.map { base + $0 }, isSubtle: subtle)
		}
		let trackFrame = frame(0, "track \(track.name)", line: track.line, file: track.file, parent: nil)
		if let play = play(of: track, at: seconds) {
			let passes = max(1, Int(((play.end - play.start) / max(play.pass, 0.001)).rounded()))
			let playFrame = frame(1, "play \(play.pattern ?? "audio")\(passes > 1 ? " x\(passes)" : "")", line: play.line, file: play.file, parent: 0)
			if let patternLine = play.patternLine, let pattern = play.pattern, play.pass > 0 {
				let pass = min(passes - 1, max(0, Int(((seconds + LineTimeline.slack - play.start) / play.pass).rounded(.down))))
				let passStart = play.start + Double(pass) * play.pass
				let patternFile = play.patternFile ?? 0
				let lines = rows(in: patternLine, file: patternFile, pattern: pattern, passStart: passStart, at: seconds, song: timeline)
				let made = lines.enumerated().map { index, row in
					frame(10 + index, row.name, line: row.line, column: row.column, file: patternFile, parent: 2, subtle: !row.sounding)
				}
				frames += made.filter { !$0.isSubtle } + made.filter(\.isSubtle)
				frames.append(frame(2, "pattern \(pattern) · pass \(pass + 1) of \(passes)", line: patternLine, file: patternFile, parent: 1))
			}
			frames.append(playFrame)
		}
		frames.append(trackFrame)
		// A stop on a breakpoint is where the program is: that line's frame first.
		if let stop = stoppedAt, abs(stop.seconds - seconds) < 0.001, let line = stop.line,
		   let index = frames.firstIndex(where: { $0.line == line + 1 && $0.file == stop.file }), index > 0 {
			frames.insert(frames.remove(at: index), at: 0)
		}
		return frames
	}

	private func play(of track: LineTimeline.Track, at seconds: Double) -> LineTimeline.Play? {
		let at = seconds + LineTimeline.slack
		return track.plays.first { $0.start <= at && at < $0.end }
	}

	/// Every line of a pass of a pattern — from its header to the next header
	/// anything names, heard in this pass — with the note sounding on it, or
	/// the last one before now, or the first when none has sounded yet.
	private func rows(
		in patternLine: Int, file: Int, pattern: String, passStart: Double, at seconds: Double, song: LineTimeline
	) -> [(name: String, line: Int, column: Int, sounding: Bool)] {
		// The headers of the pattern's own file: where its lines end.
		var headers = Set<Int>()
		for track in song.tracks {
			if track.file == file { headers.insert(track.line) }
			if track.instrumentFile == file, let line = track.instrumentLine { headers.insert(line) }
			for play in track.plays where play.patternFile == file {
				if let line = play.patternLine { headers.insert(line) }
			}
		}
		guard let placed = placedTimeline(file) else { return [] }
		let end = headers.filter { $0 > patternLine }.min() ?? Int.max
		let into = seconds + LineTimeline.slack - passStart
		var found: [(name: String, line: Int, column: Int, sounding: Bool)] = []
		for (line, notes) in placed.notes.sorted(by: { $0.key < $1.key }) where line > patternLine && line < end {
			guard notes.passes.contains(where: { abs($0 - passStart) < 0.002 }), let first = notes.notes.first else { continue }
			let now = notes.notes.first { $0.start <= into && into < $0.end }
			let shown = now ?? notes.notes.last { $0.start <= into } ?? first
			let label = rowLabel(file: file, line: line, notes: notes.notes) ?? pattern
			found.append(("\(label): \(token(file: file, line: line, columns: shown.columns))", line, shown.columns.lowerBound, now != nil))
		}
		return found
	}

	/// A grid row's name — `kick` of `  kick X...x...` — or nil for a line of
	/// notes, whose first word is a note.
	private func rowLabel(file: Int, line: Int, notes: [LineTimeline.Note]) -> String? {
		guard let text = lineText(file, line) else { return nil }
		let leading = text.prefix { $0 == " " || $0 == "\t" }.utf16.count
		let word = text.dropFirst(text.prefix { $0 == " " || $0 == "\t" }.count).prefix { $0 != " " && $0 != "\t" }
		guard !word.isEmpty, !notes.contains(where: { $0.columns.lowerBound == leading }) else { return nil }
		return String(word)
	}

	private func token(file: Int, line: Int, columns: Range<Int>) -> String {
		guard let text = lineText(file, line) as NSString?, columns.upperBound <= text.length else { return "note" }
		return text.substring(with: NSRange(location: columns.lowerBound, length: columns.count))
	}

	private func threadHearing(line: Int, file: Int, at seconds: Double) -> Int? {
		threads(at: seconds).first { thread in
			frames(thread: thread.id, at: seconds).contains { $0.line == line + 1 && $0.file == file }
		}?.id
	}

	/// A file of the song as a path, the song's own when it is not known.
	private func path(of file: Int) -> String {
		let known = files()
		return known.indices.contains(file) ? known[file] : program
	}

	/// What a frame's scopes hold: the moment, the track, and every note it
	/// has sounding.
	public func variables(frame: Int, scope: Int, at seconds: Double) -> [(name: String, value: String)] {
		guard let timeline = placedTimeline(0) else { return [] }
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
				.filter { $0.name.contains(": ") && !$0.isSubtle }
				.map { frame in
					let place = frame.file == 0 ? "Line \(frame.line)" : "\((path(of: frame.file) as NSString).lastPathComponent):\(frame.line)"
					return (place, String(frame.name.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces))
				}
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
			reply(["threads": details(at: seconds).map { thread -> [String: Any] in
				var entry: [String: Any] = ["id": thread.id, "name": thread.name, "abydos/quiet": thread.quiet]
				if let group = thread.group { entry["abydos/group"] = group }
				return entry
			}])
		case "stackTrace":
			let thread = arguments["threadId"] as? Int ?? 1
			let frames = frames(thread: thread, at: seconds)
			reply([
				"stackFrames": frames.map { frame in
					var entry: [String: Any] = [
						"id": frame.id, "name": frame.name, "line": frame.line, "column": frame.column,
						"source": ["path": path(of: frame.file), "name": (path(of: frame.file) as NSString).lastPathComponent],
					]
					if let parent = frame.parent { entry["abydos/parentId"] = parent }
					if frame.isSubtle { entry["presentationHint"] = "subtle" }
					return entry
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
			guard let bar = placedTimeline(0)?.barSeconds, bar > 0 else { return }
			let next = ((seconds + LineTimeline.slack) / bar).rounded(.down) * bar + bar
			onStep(next)
			stoppedAt = (now(), nil, 0)
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
