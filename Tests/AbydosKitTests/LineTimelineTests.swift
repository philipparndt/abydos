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
}
