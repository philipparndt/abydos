import Foundation
import Testing
@testable import AbydosKit

/// What a selection over a diff copies.
///
/// **The table of cases the view cannot be asked about.** `DiffView` needs a
/// window to exist and there is no view test target, so the geometry — where a
/// character is under the pointer — is claimed by a driven run. What a run of
/// rows and two offsets *produces* is arithmetic over strings, and it is where
/// the mistakes are: an off-by-one at a row boundary, a drag made upwards, a
/// selection that ends at the very start of a row, an empty row in the middle.
struct DiffTextSpanTests {
	/// A row of code and the two rows under it, as the view would hand them
	/// over: what the rows *say*, with no marker and no number on them.
	private let three = [
		"let text = try String(contentsOf: url)",
		"    return text",
		"}",
	]

	@Test func aRunOfCharactersOnOneRowIsThoseCharacters() {
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 11),
			to: DiffTextPoint(row: 12, offset: 21),
			rows: [three[0]]
		)
		#expect(span.text == "try String")
	}

	/// The tail of the first row, the whole of the middle one, the head of the
	/// last — which is what a drag from the middle of one line to the middle of
	/// another covers.
	@Test func aRunAcrossThreeRowsIsTailWholeHead() {
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 11),
			to: DiffTextPoint(row: 14, offset: 1),
			rows: three
		)
		#expect(span.text == "try String(contentsOf: url)\n    return text\n}")
	}

	/// A drag upwards is as ordinary as a drag downwards, and the pair arrives
	/// in the order the pointer made it.
	@Test func aPairGivenBackwardsReadsForwards() {
		let downwards = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 11),
			to: DiffTextPoint(row: 13, offset: 10),
			rows: three
		)
		let upwards = DiffTextSpan(
			from: DiffTextPoint(row: 13, offset: 10),
			to: DiffTextPoint(row: 12, offset: 11),
			rows: three
		)
		#expect(upwards.start == downwards.start)
		#expect(upwards.end == downwards.end)
		#expect(upwards.text == downwards.text)
	}

	/// **A selection that stops at the start of a row is the rows above it and a
	/// newline**, not those rows plus the row it stopped in front of. It is what
	/// dragging one row too far and coming back gives, and it is how every other
	/// text view answers the same gesture.
	@Test func aSelectionEndingAtTheStartOfARowKeepsTheNewline() {
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 0),
			to: DiffTextPoint(row: 14, offset: 0),
			rows: three
		)
		#expect(span.text == "let text = try String(contentsOf: url)\n    return text\n")
	}

	/// A blank line inside a selection is a blank line on the clipboard: the
	/// pasted code has to have the same shape as the code that was read.
	@Test func anEmptyRowInTheMiddleIsAnEmptyLine() {
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 4, offset: 0),
			to: DiffTextPoint(row: 6, offset: 1),
			rows: ["a", "", "b"]
		)
		#expect(span.text == "a\n\nb")
	}

	/// ⌘A then ⌘C: every row, whole, one per line.
	@Test func theWholeThingIsEveryRowInOrder() {
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 0, offset: 0),
			to: DiffTextPoint(row: 2, offset: three[2].utf16.count),
			rows: three
		)
		#expect(span.text == three.joined(separator: "\n"))
	}

	/// A press with nothing dragged covers nothing, and nothing is what it
	/// copies — a click is how a selection is put away.
	@Test func aSpanOfNoCharactersCopiesNothing() {
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 7),
			to: DiffTextPoint(row: 12, offset: 7),
			rows: [three[0]]
		)
		#expect(span.isEmpty)
		#expect(span.text.isEmpty)
	}

	/// **The rows went away under it** — the diff was rebuilt, or the offsets
	/// outlived the row they were measured against. What is there is copied and
	/// nothing is invented, because a stale selection should cost a short string
	/// rather than a trap.
	@Test func aSpanWhoseRowsHaveGoneCopiesWhatIsThere() {
		let none = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 0),
			to: DiffTextPoint(row: 14, offset: 4),
			rows: []
		)
		#expect(none.text.isEmpty)

		// Two rows where it covers three: the second is whole, because the
		// offset that would have cut it belongs to a row nobody has.
		let short = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 11),
			to: DiffTextPoint(row: 14, offset: 1),
			rows: [three[0], three[1]]
		)
		#expect(short.text == "try String(contentsOf: url)\n    return text")

		// An offset past the end of the row it names is the end of that row.
		let past = DiffTextSpan(
			from: DiffTextPoint(row: 12, offset: 4),
			to: DiffTextPoint(row: 12, offset: 900),
			rows: [three[0]]
		)
		#expect(past.text == "text = try String(contentsOf: url)")
	}
}

/// What ⌘A then ⌘C costs over a diff nobody reads line by line.
///
/// **The claim is that copying is a string join and nothing else.** No row is
/// laid out and nothing off-screen is measured — the view hands over the text it
/// already has from `GitPatch` — so a selection over five thousand rows costs the
/// rows it covers and not the diff. The number is printed with the load beside it
/// whether the bound is applied or not, for the reason `MachineLoad` gives; the
/// bound itself only lands in `make timing`.
struct DiffTextSpanCostTests {
	@Test func copyingFiveThousandRowsIsAStringJoin() {
		let rows = (0..<5000).map { "\tlet value\($0) = try read(url\($0)) // a line of a generated file" }
		let span = DiffTextSpan(
			from: DiffTextPoint(row: 0, offset: 0),
			to: DiffTextPoint(row: rows.count - 1, offset: rows[rows.count - 1].utf16.count),
			rows: rows
		)

		let began = Date()
		let copied = span.text
		let took = Date().timeIntervalSince(began)

		#expect(copied.hasPrefix("\tlet value0 ="))
		#expect(copied.hasSuffix("generated file"))
		print(String(
			format: "DIFF COPY: %d rows joined in %.1f ms — %@",
			rows.count, took * 1000, MachineLoad.said as NSString
		))
		if Stopwatch.maySay("DIFF COPY", "the join of a five-thousand-row selection") {
			#expect(took < 0.1)
		}
	}
}
