import Testing
@testable import AbydosKit

/// The ring that holds terminal history.
struct ScrollbackBufferTests {
	private func line(_ text: String) -> TerminalLine {
		var line = TerminalLine(columns: text.count)
		for (index, character) in text.enumerated() {
			line.cells[index] = TerminalCell(character: character)
		}
		return line
	}

	private func texts(_ buffer: ScrollbackBuffer) -> [String] {
		buffer.map(\.text)
	}

	@Test func keepsWhatFits() {
		var buffer = ScrollbackBuffer(capacity: 4)
		for name in ["a", "b", "c"] { #expect(buffer.append(line(name)) == nil) }

		#expect(buffer.count == 3)
		#expect(texts(buffer) == ["a", "b", "c"])
		#expect(buffer.last?.text == "c")
		#expect(!buffer.isEmpty)
	}

	/// Past capacity the oldest goes, and the rest keep their order.
	@Test func dropsTheOldestOnceFull() {
		var buffer = ScrollbackBuffer(capacity: 3)
		for name in ["a", "b", "c"] { buffer.append(line(name)) }

		#expect(buffer.append(line("d"))?.text == "a")
		#expect(texts(buffer) == ["b", "c", "d"])

		buffer.append(line("e"))
		#expect(texts(buffer) == ["c", "d", "e"])
		#expect(buffer.count == 3)
	}

	/// Wrapping many times over must not disturb the order.
	@Test func staysInOrderAcrossManyWraps() {
		var buffer = ScrollbackBuffer(capacity: 5)
		for index in 0..<100 { buffer.append(line("line\(index)")) }

		#expect(texts(buffer) == (95..<100).map { "line\($0)" })
		#expect(buffer[0].text == "line95")
		#expect(buffer[4].text == "line99")
	}

	/// A shrinking terminal pulls history back down into the grid.
	@Test func popsFromTheEnd() {
		var buffer = ScrollbackBuffer(capacity: 3)
		for name in ["a", "b", "c", "d"] { buffer.append(line(name)) }

		#expect(buffer.popLast()?.text == "d")
		#expect(buffer.popLast()?.text == "c")
		#expect(texts(buffer) == ["b"])
		#expect(buffer.popLast()?.text == "b")
		#expect(buffer.popLast() == nil)
		#expect(buffer.isEmpty)
	}

	/// Popping after a wrap must not reach back into evicted storage.
	@Test func popsCorrectlyAfterWrapping() {
		var buffer = ScrollbackBuffer(capacity: 3)
		for name in ["a", "b", "c", "d", "e"] { buffer.append(line(name)) }

		#expect(buffer.popLast()?.text == "e")
		#expect(texts(buffer) == ["c", "d"])
		buffer.append(line("f"))
		#expect(texts(buffer) == ["c", "d", "f"])
	}

	@Test func writingThroughTheSubscriptLandsOnTheRightLine() {
		var buffer = ScrollbackBuffer(capacity: 3)
		for name in ["a", "b", "c", "d"] { buffer.append(line(name)) }

		buffer[1] = line("changed")
		#expect(texts(buffer) == ["b", "changed", "d"])
	}

	@Test func growingKeepsEverything() {
		var buffer = ScrollbackBuffer(capacity: 3)
		for name in ["a", "b", "c", "d"] { buffer.append(line(name)) }

		buffer.setCapacity(5)
		#expect(texts(buffer) == ["b", "c", "d"])
		buffer.append(line("e"))
		buffer.append(line("f"))
		#expect(texts(buffer) == ["b", "c", "d", "e", "f"])
	}

	/// Shrinking keeps the newest, which is the end anyone is looking at.
	@Test func shrinkingDropsTheOldest() {
		var buffer = ScrollbackBuffer(capacity: 5)
		for name in ["a", "b", "c", "d", "e"] { buffer.append(line(name)) }

		buffer.setCapacity(2)
		#expect(texts(buffer) == ["d", "e"])
		buffer.append(line("f"))
		#expect(texts(buffer) == ["e", "f"])
	}

	/// No history at all is a legitimate setting, not a crash.
	@Test func aBufferWithNoRoomKeepsNothing() {
		var buffer = ScrollbackBuffer(capacity: 0)
		#expect(buffer.append(line("a"))?.text == "a")
		#expect(buffer.isEmpty)
		#expect(buffer.count == 0)
		#expect(buffer.last == nil)
	}

	@Test func removingEverythingLeavesItEmpty() {
		var buffer = ScrollbackBuffer(capacity: 3)
		for name in ["a", "b", "c", "d"] { buffer.append(line(name)) }

		buffer.removeAll()
		#expect(buffer.isEmpty)
		buffer.append(line("x"))
		#expect(texts(buffer) == ["x"])
	}
}
