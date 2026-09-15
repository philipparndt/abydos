import Foundation
import Testing
@testable import AbydosKit

/// Reading `mat/timeline`, and what the gutter draws and says from it.
struct LineTimelineTests {
	/// As `mat lsp` b0083ad sends it: lines 0-based, spans in seconds.
	private let params: [String: Any] = [
		"uri": "file:///songs/neon.song",
		"seconds": 16.0,
		"barSeconds": 2.0,
		"lines": [
			["line": 11, "spans": [[4.0, 8.0]]],
			["line": 6, "spans": [[0.0, 2.0], [8.0, 10.0]]],
			["line": 3, "spans": [[2.0, 4.0]]],
		],
	]

	@Test func theNotificationIsRead() throws {
		let timeline = try #require(LineTimeline(params: params))
		#expect(timeline.seconds == 16)
		#expect(timeline.barSeconds == 2)
		#expect(timeline.spans[11] == [4...8])
		#expect(timeline.spans[6] == [0...2, 8...10])
		#expect(timeline.spans[0] == nil)
		#expect(LineTimeline(params: ["lines": []]) == nil, "no length, no timeline")
	}

	@Test func aLinesBarIsItsStretchesAsFractionsOfTheSong() throws {
		let timeline = try #require(LineTimeline(params: params))
		#expect(timeline.fractions(line: 11) == [0.25...0.5])
		#expect(timeline.fractions(line: 6) == [0...0.125, 0.5...0.625])
		#expect(timeline.fractions(line: 1).isEmpty)
	}

	@Test func aHoverSaysTheBarsAndTheTimes() throws {
		let timeline = try #require(LineTimeline(params: params))
		#expect(timeline.summary(line: 11) == "bars 3–4 · 0:04.000–0:08.000")
		#expect(timeline.summary(line: 3) == "bar 2 · 0:02.000–0:04.000")
		#expect(timeline.summary(line: 6) == "2 times: bars 1, 5 · first at 0:00.000")
		#expect(timeline.summary(line: 0) == nil)
	}

	@Test func aLinesTimeCodeIsWhereItIsFirstHeard() throws {
		let timeline = try #require(LineTimeline(params: params))
		#expect(timeline.timeCode(line: 11) == "0:04.000")
		#expect(timeline.timeCode(line: 6) == "0:00.000")
		#expect(timeline.timeCode(line: 1) == nil)
	}

	@Test func clickingATimeCodeAgainWalksTheRepeats() throws {
		let timeline = try #require(LineTimeline(params: params))
		#expect(timeline.nextStart(line: 6, after: 3) == 8)
		#expect(timeline.nextStart(line: 6, after: 8) == 0, "past the last, back to the first")
		#expect(timeline.nextStart(line: 1, after: 0) == nil)
	}

	@Test func theLinesSoundingAtAMomentHoldTheirStartAndNotTheirEnd() throws {
		let timeline = try #require(LineTimeline(params: params))
		#expect(timeline.sounding(at: 1) == [6])
		#expect(timeline.sounding(at: 2) == [3], "line 6 ends where line 3 starts")
		#expect(timeline.sounding(at: 5) == [11])
		#expect(timeline.sounding(at: 12).isEmpty)
		#expect(timeline.sounding(at: 3.9999) == [11], "a seek to 4 reads a sample short of it")
	}

	@Test func playingStopsAtTheFirstBreakpointItReaches() throws {
		let timeline = try #require(LineTimeline(params: params))
		let lines: Set<Int> = [6, 11]
		#expect(timeline.breakpoint(in: lines, from: 1, to: 1.03) == nil)
		let first = try #require(timeline.breakpoint(in: lines, from: 3.98, to: 4.01))
		#expect(first.line == 11 && first.seconds == 4)
		#expect(timeline.breakpoint(in: lines, from: 4, to: 4.03) == nil, "playing on from a stop")
		#expect(timeline.breakpoint(in: lines, from: 3.9999, to: 4.03) == nil, "from a stop a sample short of it")
		#expect(timeline.breakpoint(in: lines, from: 4.03, to: 4.0299) == nil, "a reading a hair behind is not a loop")
		let second = try #require(timeline.breakpoint(in: lines, from: 7.99, to: 8.02))
		#expect(second.line == 6 && second.seconds == 8)
		#expect(timeline.breakpoint(in: [3], from: 1, to: 3) != nil)
		let wrapped = try #require(timeline.breakpoint(in: lines, from: 15.99, to: 0.02))
		#expect(wrapped.line == 6 && wrapped.seconds == 0, "a loop back to the start reaches the first bar")
	}

	/// A pattern line played at 0 s and 8 s: `C4:h D4 |`, a half note at
	/// columns 2–6 and another at 7–9, a bar of 2 s.
	private let noted: [String: Any] = [
		"seconds": 16.0, "barSeconds": 2.0,
		"lines": [
			["line": 6, "spans": [[0.0, 2.0], [8.0, 10.0]], "passes": [8.0, 0.0],
			 "notes": [[0.0, 1.0, 2, 6], [1.0, 2.0, 7, 9]]],
			["line": 3, "spans": [[2.0, 4.0]]],
		],
	]

	@Test func aPatternLinesPassesAndNotesAreRead() throws {
		let timeline = try #require(LineTimeline(params: noted))
		let line = try #require(timeline.notes[6])
		#expect(line.passes == [0, 8], "sorted")
		#expect(line.notes.map(\.columns) == [2..<6, 7..<9])
		#expect(timeline.notes[3] == nil, "a line with no notes has none")
	}

	@Test func theNoteUnderThePlayheadIsLitAtEveryPass() throws {
		let timeline = try #require(LineTimeline(params: noted))
		#expect(timeline.playing(at: 0.5) == [6: [2..<6]])
		#expect(timeline.playing(at: 1.5) == [6: [7..<9]])
		#expect(timeline.playing(at: 8.2) == [6: [2..<6]], "the second pass")
		#expect(timeline.playing(at: 7.9999) == [6: [2..<6]], "a seek to 8 reads a sample short of it")
		#expect(timeline.playing(at: 4).isEmpty, "between passes")
	}
}
