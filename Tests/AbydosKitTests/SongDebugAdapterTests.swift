import Foundation
import Testing
@testable import AbydosKit

/// A playing song answered for in the Debug Adapter Protocol: tracks as
/// threads, a note inside a pattern inside a play step inside a track as a
/// stack, and a breakpoint's stop where the program is.
@MainActor
struct SongDebugAdapterTests {
	/// 0-based lines: `pattern verse` at 5, its line `  C4:h D4 |` at 6,
	/// `track melody` at 12 and its `play verse x2` at 14. A bar is 2 s.
	private let source = [
		"tempo 120", "", "instrument lead synth", "  osc saw", "",
		"pattern verse", "  C4:h D4 |", "", "", "", "", "",
		"track melody", "  instrument lead", "  play verse x2",
	]

	private func timeline() -> LineTimeline {
		var timeline = LineTimeline(
			seconds: 4, barSeconds: 2, spans: [6: [0...2, 2...4]],
			notes: [6: .init(passes: [0, 2], notes: [
				.init(start: 0, end: 1, columns: 2..<6),
				.init(start: 1, end: 2, columns: 7..<9),
			])]
		)
		timeline.tracks = [.init(
			name: "melody", line: 12, layer: "melody", instrument: "lead", instrumentLine: 2,
			plays: [.init(line: 14, pattern: "verse", patternLine: 5, start: 0, end: 4, pass: 2)]
		)]
		return timeline
	}

	private final class Clock { var seconds = 0.0 }

	private func adapter(_ clock: Clock) -> SongDebugAdapter {
		let lines = source
		let placed = timeline()
		return SongDebugAdapter(
			program: "/songs/verse.song", timeline: { placed },
			lineText: { lines.indices.contains($0) ? lines[$0] : nil }, now: { clock.seconds }
		)
	}

	@Test func aTrackIsAThreadNamedForWhatItPlays() {
		let clock = Clock()
		let adapter = adapter(clock)
		#expect(adapter.threads(at: 1).map(\.name) == ["melody · verse"])
		#expect(adapter.threads(at: 5).map(\.name) == ["melody · done"])
	}

	@Test func aStackIsTheNoteInsideThePatternInsideThePlayInsideTheTrack() {
		let clock = Clock()
		let adapter = adapter(clock)
		let frames = adapter.frames(thread: 1, at: 1.5)
		#expect(frames.map(\.name) == ["verse: D4", "pattern verse · pass 1 of 2", "play verse x2", "track melody"])
		#expect(frames.map(\.line) == [7, 6, 15, 13], "1-based, as the protocol is asked for")
		#expect(frames.first?.column == 8)
		#expect(adapter.frames(thread: 1, at: 2.2).map(\.name).prefix(2) == ["verse: C4:h", "pattern verse · pass 2 of 2"])
		#expect(adapter.frames(thread: 1, at: 1.9999).first?.name == "verse: C4:h", "a seek to 2 reads a sample short of it")
	}

	@Test func theProtocolIsSpokenAndAStopOnABreakpointIsWhereTheProgramIs() throws {
		let clock = Clock()
		let adapter = adapter(clock)
		var said: [[String: Any]] = []
		adapter.send = { said.append($0) }
		var paused = 0
		adapter.onPause = { paused += 1 }

		func ask(_ command: String, _ arguments: [String: Any] = [:]) -> [String: Any] {
			said.removeAll()
			adapter.receive(["seq": 1, "type": "request", "command": command, "arguments": arguments])
			return said.first { $0["type"] as? String == "response" }?["body"] as? [String: Any] ?? [:]
		}

		_ = ask("initialize")
		#expect(said.contains { $0["event"] as? String == "initialized" })
		let set = ask("setBreakpoints", ["source": ["path": "/songs/verse.song"], "breakpoints": [["line": 6]]])
		#expect((set["breakpoints"] as? [[String: Any]])?.first?["verified"] as? Bool == true)
		_ = ask("configurationDone")
		#expect(said.contains { $0["event"] as? String == "thread" })

		let threads = ask("threads")["threads"] as? [[String: Any]]
		#expect(threads?.first?["name"] as? String == "melody · verse")

		// The pane stops at 2 s on line 5, the pattern's header.
		clock.seconds = 2
		said.removeAll()
		adapter.stopped(line: 5)
		let stop = try #require(said.first { $0["event"] as? String == "stopped" }?["body"] as? [String: Any])
		#expect(stop["reason"] as? String == "breakpoint")
		#expect(stop["threadId"] as? Int == 1)
		let frames = ask("stackTrace", ["threadId": 1])["stackFrames"] as? [[String: Any]] ?? []
		#expect(frames.first?["line"] as? Int == 6, "the line it stopped on is the top of the stack")
		#expect((frames.first?["source"] as? [String: Any])?["path"] as? String == "/songs/verse.song")

		let scopes = ask("scopes", ["frameId": frames.first?["id"] as? Int ?? 0])["scopes"] as? [[String: Any]] ?? []
		#expect(scopes.map { $0["name"] as? String } == ["Now", "Track", "Notes"])
		let now = ask("variables", ["variablesReference": scopes.first?["variablesReference"] as? Int ?? 0])["variables"] as? [[String: Any]] ?? []
		#expect(now.first { $0["name"] as? String == "Time" }?["value"] as? String == "0:02.000")
		#expect(now.first { $0["name"] as? String == "Pass" }?["value"] as? String == "2 of 2")

		_ = ask("pause", ["threadId": 1])
		#expect(paused == 1)
		_ = ask("disconnect")
		#expect(paused == 1, "disconnect is its own verb")
		#expect(said.contains { $0["event"] as? String == "terminated" })
	}

	/// A song whose pattern is in an included kit: the pattern's frames are in
	/// the kit, the play step and the track in the song.
	@Test func aFrameIsInTheFileItsLineIsIn() {
		let kit = ["# kit", "pattern beat grid=1/8", "  kick X...X..."]
		let song = LineTimeline(seconds: 2, barSeconds: 2, spans: [:])
		var withTracks = song
		withTracks.files = ["file:///songs/song.song", "file:///songs/kit.song"]
		withTracks.tracks = [.init(
			name: "drums", line: 4, layer: "drums", instrument: nil, instrumentLine: nil,
			plays: [.init(line: 5, pattern: "beat", patternLine: 1, start: 0, end: 2, pass: 2, patternFile: 1)]
		)]
		let placedKit = LineTimeline(
			seconds: 2, barSeconds: 2, spans: [2: [0...2]],
			notes: [2: .init(passes: [0], notes: [.init(start: 0, end: 0.25, columns: 7..<8), .init(start: 1, end: 1.25, columns: 11..<12)])]
		)
		let adapter = SongDebugAdapter(
			program: "/songs/song.song", files: { ["/songs/song.song", "/songs/kit.song"] },
			timeline: { $0 == 0 ? withTracks : placedKit },
			lineText: { file, line in file == 1 && kit.indices.contains(line) ? kit[line] : nil },
			now: { 1.1 }
		)
		let frames = adapter.frames(thread: 1, at: 1.1)
		#expect(frames.map(\.name) == ["kick: X", "pattern beat · pass 1 of 1", "play beat", "track drums"], "a grid row by its drum")
		#expect(frames.map(\.file) == [1, 1, 0, 0])
		#expect(frames.map(\.line) == [3, 2, 6, 5])
	}

	/// Two rows of a grid side by side inside their pattern, the one between
	/// hits subtle with its last hit; parents say what is inside what.
	@Test func aPatternsRowsAreSiblingsAndARowBetweenNotesIsSubtle() {
		let kit = ["pattern beat grid=1/8", "  kick X...X...", "  hat  ..x...x."]
		var song = LineTimeline(seconds: 2, barSeconds: 2, spans: [:])
		song.tracks = [
			.init(name: "drums", line: 4, layer: "kit", instrument: nil, instrumentLine: nil,
			      plays: [.init(line: 5, pattern: "beat", patternLine: 0, start: 0, end: 2, pass: 2)]),
			.init(name: "toms", line: 7, layer: "kit", instrument: nil, instrumentLine: nil, plays: []),
		]
		song.notes = [
			1: .init(passes: [0], notes: [.init(start: 0, end: 0.25, columns: 7..<8), .init(start: 1, end: 1.25, columns: 11..<12)]),
			2: .init(passes: [0], notes: [.init(start: 0.5, end: 0.75, columns: 9..<10), .init(start: 1.5, end: 1.75, columns: 13..<14)]),
		]
		let placed = song
		let lines = kit
		let adapter = SongDebugAdapter(
			program: "/songs/beat.song", timeline: { placed },
			lineText: { lines.indices.contains($0) ? lines[$0] : nil }, now: { 1.1 }
		)
		let frames = adapter.frames(thread: 1, at: 1.1)
		#expect(frames.map(\.name) == ["kick: X", "hat: x", "pattern beat · pass 1 of 1", "play beat", "track drums"])
		#expect(frames.map(\.isSubtle) == [false, true, false, false, false], "the hat between its hits")
		#expect(frames[1].column == 10, "its last hit, not its next")
		let byID = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
		#expect(frames[0].parent == frames[2].id && frames[1].parent == frames[2].id)
		#expect(byID[frames[2].parent ?? 0]?.name == "play beat")
		#expect(frames[4].parent == nil)
		// Both tracks render into `kit`: grouped; the toms play nothing: quiet.
		let threads = adapter.details(at: 1.1)
		#expect(threads.map(\.group) == ["kit", "kit"])
		#expect(threads.map(\.quiet) == [false, true])
		#expect(adapter.variables(frame: frames[0].id, scope: 3, at: 1.1).map(\.value) == ["X"], "only the notes sounding")
	}
}
