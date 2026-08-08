import AppKit
import CoreText
import Foundation
import Testing
@testable import AbydosKit

/// One tmux pane border, and the ligatures on every line it crossed.
///
/// A run is the unit shaped, and a run ends where the cell attributes change.
/// tmux paints the border of the pane that is *not* active with
/// `pane-border-style`, which is `default` out of the box — the same
/// attributes as ordinary text — so the border lands in the same run as the
/// text either side of it. The border is a box drawing, which a terminal
/// draws itself rather than taking from the font, and the run used to give up
/// whole when it met one: the line's ligatures went, all of them.
///
/// Making the other pane active paints that border green — a different
/// foreground, so the run ends before it — and the ligatures came back. Which
/// is the whole bug: position-dependent, focus-dependent, in both directions,
/// and the same after a restart, because it is decided by what is in the cells
/// rather than by anything remembered.
///
/// Recorded from a real tmux 3.7 attach on 80x24 with one vertical split; the
/// two states below are the bytes it sent, shortened to the row in question.
struct LigatureRunSpanTests {
	private var bundled: NSFont? {
		let fonts = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Resources/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf")
		CTFontManagerRegisterFontsForURL(fonts as CFURL, .process, nil)
		return NSFont(name: "JetBrainsMonoNFM-Regular", size: 14)
	}

	/// What the renderers refuse to hand a font: a box drawing, a powerline
	/// separator, a picture's placeholder, an empty cell.
	private func canShape(_ cell: TerminalCell) -> Bool {
		cell.scalar != 0 && cell.scalar != UnicodePlaceholder.scalar
			&& !(0xE0B0...0xE0B7).contains(cell.scalar)
			&& !(0xE0C0...0xE0C3).contains(cell.scalar)
			&& !(0x2500...0x259F).contains(cell.scalar)
	}

	private func hasInk(_ glyph: CGGlyph, _ font: CTFont) -> Bool {
		var one = glyph
		var rect = CGRect.zero
		CTFontGetBoundingRectsForGlyphs(font, .horizontal, &one, &rect, 1)
		return !rect.isEmpty
	}

	/// The line tmux paints, with the border either its own colour or the
	/// default one — the only difference between the two focus states.
	private func paneLine(borderIsActive: Bool) -> TerminalLine {
		let emulator = TerminalEmulator(rows: 24, columns: 80)
		let border = borderIsActive ? "\u{1b}[32m\u{2502}\u{1b}[39m" : "\u{2502}"
		emulator.write("\u{1b}[H" + "node 2.1.224 -> 2.1.226" + "\u{1b}[1;41H" + border)
		return emulator.screen.lines[0]
	}

	/// The columns of a line the shaper would leave without ink, which for
	/// these fonts is exactly the cells a ligature has swallowed.
	private func carriers(on line: TerminalLine, font: NSFont) -> Set<Int> {
		var shaped = ShapedRuns()
		var found = Set<Int>()
		let cells = line.cells
		var start = 0
		while start < cells.count {
			var end = start + 1
			while end < cells.count, cells[end].attributes == cells[start].attributes { end += 1 }
			defer { start = end }
			guard Ligatures.mayLigate(cells[start..<end].lazy.map(\.scalar)) else { continue }

			for span in Ligatures.spans(in: start..<end, canShape: { canShape(cells[$0]) }) {
				guard Ligatures.mayLigate(cells[span].lazy.map(\.scalar)) else { continue }
				var text = ""
				var cellOfOffset: [Int] = []
				for column in span {
					guard let scalar = UnicodeScalar(cells[column].scalar) else { continue }
					let piece = cells[column].combining ?? String(Character(scalar))
					text += piece
					cellOfOffset.append(
						contentsOf: Array(repeating: column - span.lowerBound, count: piece.utf16.count)
					)
				}
				guard let pieces = shaped.pieces(
					for: text, cellOfOffset: cellOfOffset, font: font, faceIndex: 0
				) else { continue }
				for piece in pieces where !hasInk(piece.glyph, piece.font) {
					found.insert(span.lowerBound + piece.cellOffset)
				}
			}
		}
		return found
	}

	/// The border and the text share their attributes exactly when the pane is
	/// not the active one, which is what puts them in one run.
	@Test func anInactivePaneBorderSharesTheAttributesOfTheTextBesideIt() {
		let inactive = paneLine(borderIsActive: false)
		#expect(inactive.cells[40].scalar == 0x2502)
		#expect(inactive.cells[40].attributes == inactive.cells[0].attributes)

		let active = paneLine(borderIsActive: true)
		#expect(active.cells[40].scalar == 0x2502)
		#expect(active.cells[40].attributes != active.cells[0].attributes)
	}

	/// A run stops at the border rather than giving up on it, so the two
	/// screenshots of the same text now agree.
	@Test func theSameLineLigatesWhicheverPaneIsActive() {
		guard let font = bundled else { Issue.record("the bundled font is missing"); return }

		// `node 2.1.224 -> 2.1.226`: the `-` at column 13 is the carrier and
		// the `>` at 14 holds the arrow's ink.
		let inactive = carriers(on: paneLine(borderIsActive: false), font: font)
		let active = carriers(on: paneLine(borderIsActive: true), font: font)

		#expect(inactive.contains(13), "the arrow joins with the border in the run")
		#expect(active.contains(13), "and with the border in a run of its own")
		#expect(inactive == active, "which pane is active decides nothing about shaping")
	}

	/// And the span is split at the border rather than thrown away, which is
	/// the whole of the change.
	@Test func aSpanStopsAtACharacterTheTerminalDrawsItself() {
		let line = paneLine(borderIsActive: false)
		let spans = Ligatures.spans(in: 0..<line.cells.count, canShape: { canShape(line.cells[$0]) })
		#expect(spans == [0..<40, 41..<80])
	}
}
