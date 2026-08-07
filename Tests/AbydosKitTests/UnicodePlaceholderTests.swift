import Foundation
import Testing
@testable import AbydosKit

/// Unicode placeholders: the way kitty's own `icat` shows a picture, and the
/// reason an image survives being scrolled back inside tmux.
struct UnicodePlaceholderTests {
	/// The character, and the diacritics for a row and a column.
	private func placeholder(row: Int?, column: Int?, idHighByte: Int? = nil) -> String {
		var text = String(UnicodeScalar(UnicodePlaceholder.scalar)!)
		for index in [row, column, idHighByte] {
			guard let index else { break }
			text.unicodeScalars.append(UnicodeScalar(UnicodePlaceholder.diacritics[index])!)
		}
		return text
	}

	private func emulator(columns: Int = 40, rows: Int = 10) -> TerminalEmulator {
		let terminal = TerminalEmulator(rows: rows, columns: columns)
		terminal.cellPixelSize = (width: 10, height: 20)
		return terminal
	}

	/// A four-by-two picture, transmitted as a virtual placement.
	private func transmitVirtual(
		id: UInt32, columns: Int, rows: Int, in terminal: TerminalEmulator
	) {
		let pixels = Data([UInt8](repeating: 0x40, count: 16 * 8 * 3)).base64EncodedString()
		terminal.write(
			"\u{1B}_Ga=T,q=2,f=24,U=1,s=16,v=8,c=\(columns),r=\(rows),i=\(id);\(pixels)\u{1B}\\"
		)
	}

	/// kitty's `icat` sends `U=1`, and a virtual placement belongs to no
	/// position: placing it at the cursor as well drew the picture for the
	/// instant before the placeholders were written over it, which is what
	/// "the image blinks and is gone" was.
	@Test func aVirtualPlacementGoesNowhereByItself() {
		let terminal = emulator()
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: terminal)

		#expect(terminal.graphics.placements.isEmpty)
		#expect(terminal.graphics.hasVirtualPlacements)
	}

	/// The id is in the foreground colour, the row and column in the
	/// diacritics. One cell is one cell of the picture.
	@Test func aPlaceholderCellNamesItsImageAndItsPlaceInIt() {
		let cell = TerminalCell(
			scalar: UnicodePlaceholder.scalar,
			attributes: {
				var attributes = TerminalAttributes()
				// 1234 == 0x0004D2
				attributes.foreground = .rgb(0x00, 0x04, 0xD2)
				return attributes
			}()
		)
		var withMarks = cell
		withMarks.combining = placeholder(row: 1, column: 3)

		let read = UnicodePlaceholder.decode(
			scalar: withMarks.scalar, combining: withMarks.combining,
			foreground: withMarks.attributes.foreground
		)
		#expect(read?.imageID == 1234)
		#expect(read?.row == 1)
		#expect(read?.column == 3)
	}

	/// A cell with no colour belongs to no image and is left alone — otherwise
	/// any private-use character anybody prints would turn into a picture.
	@Test func aPlaceholderWithoutAColourIsJustACharacter() {
		#expect(UnicodePlaceholder.decode(
			scalar: UnicodePlaceholder.scalar, combining: nil, foreground: .default
		) == nil)
		#expect(UnicodePlaceholder.decode(
			scalar: 0x41, combining: nil, foreground: .rgb(0, 4, 210)
		) == nil)
	}

	/// Cells after the first in a run leave the row and column out, and
	/// continue from the cell before. Most cells of a picture are written that
	/// way, so getting it wrong loses all but the first column.
	@Test func cellsThatSayNothingContinueTheOneBeforeThem() {
		var attributes = TerminalAttributes()
		attributes.foreground = .rgb(0x00, 0x04, 0xD2)

		var cells: [TerminalCell] = []
		for column in 0..<4 {
			var cell = TerminalCell(scalar: UnicodePlaceholder.scalar, attributes: attributes)
			// Only the first says where it is.
			cell.combining = column == 0 ? placeholder(row: 1, column: 0) : placeholder(row: nil, column: nil)
			cells.append(cell)
		}

		let runs = UnicodePlaceholder.runs(in: cells, screenRow: 7)
		#expect(runs.count == 1)
		#expect(runs.first?.imageID == 1234)
		#expect(runs.first?.screenRow == 7)
		#expect(runs.first?.column == 0)
		#expect(runs.first?.length == 4)
		#expect(runs.first?.imageRow == 1)
		#expect(runs.first?.imageColumn == 0)
	}

	/// Ordinary text between two stretches of placeholder breaks the run: they
	/// are two separate pieces of the picture with something else in between.
	@Test func textBetweenTwoStretchesBreaksTheRun() {
		var attributes = TerminalAttributes()
		attributes.foreground = .rgb(0x00, 0x04, 0xD2)

		func mark(_ row: Int, _ column: Int) -> TerminalCell {
			var cell = TerminalCell(scalar: UnicodePlaceholder.scalar, attributes: attributes)
			cell.combining = placeholder(row: row, column: column)
			return cell
		}
		let cells = [
			mark(0, 0), mark(0, 1),
			TerminalCell(scalar: 0x41),
			mark(0, 2), mark(0, 3),
		]

		let runs = UnicodePlaceholder.runs(in: cells, screenRow: 0)
		#expect(runs.count == 2)
		#expect(runs.first?.length == 2)
		#expect(runs.last?.column == 3)
		#expect(runs.last?.imageColumn == 2)
	}

	/// The whole point, end to end: the picture is drawn where the characters
	/// are, and it is one strip of the image per row.
	@Test func thePictureIsBuiltFromWhereTheCharactersAre() throws {
		let terminal = emulator()
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: terminal)

		var attributes = TerminalAttributes()
		attributes.foreground = .rgb(0x00, 0x04, 0xD2)
		func strip(_ imageRow: Int) -> [TerminalCell] {
			(0..<4).map { column in
				var cell = TerminalCell(scalar: UnicodePlaceholder.scalar, attributes: attributes)
				cell.combining = placeholder(row: imageRow, column: column)
				return cell
			}
		}

		let runs = UnicodePlaceholder.runs(in: strip(0), screenRow: 3)
			+ UnicodePlaceholder.runs(in: strip(1), screenRow: 4)
		let placements = terminal.graphics.placements(for: runs)
		#expect(placements.count == 2)

		let top = try #require(placements.first)
		#expect(top.row == 3)
		#expect(top.column == 0)
		#expect(top.columns == 4)
		#expect(top.rows == 1)
		// The top half of a sixteen-by-eight image, across its full width.
		#expect(top.source == .init(x: 0, y: 0, width: 16, height: 4))

		let bottom = try #require(placements.last)
		#expect(bottom.row == 4)
		#expect(bottom.source == .init(x: 0, y: 4, width: 16, height: 4))
	}

	/// Half a picture is half a picture: a strip that starts part way along
	/// takes the matching part of the image, which is what makes a placeholder
	/// picture survive being scrolled or reflowed by tmux.
	@Test func aPartOfARowTakesThatPartOfThePicture() throws {
		let terminal = emulator()
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: terminal)

		var attributes = TerminalAttributes()
		attributes.foreground = .rgb(0x00, 0x04, 0xD2)
		let cells = (2..<4).map { column -> TerminalCell in
			var cell = TerminalCell(scalar: UnicodePlaceholder.scalar, attributes: attributes)
			cell.combining = placeholder(row: 0, column: column)
			return cell
		}

		let placements = terminal.graphics.placements(
			for: UnicodePlaceholder.runs(in: cells, screenRow: 0)
		)
		let only = try #require(placements.first)
		#expect(only.columns == 2)
		#expect(only.source == .init(x: 8, y: 0, width: 8, height: 4))
	}

	/// A cell naming a piece the picture does not have is not drawn, rather
	/// than drawn as whatever the arithmetic came to.
	@Test func aCellBeyondThePictureDrawsNothing() {
		let terminal = emulator()
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: terminal)

		var attributes = TerminalAttributes()
		attributes.foreground = .rgb(0x00, 0x04, 0xD2)
		var cell = TerminalCell(scalar: UnicodePlaceholder.scalar, attributes: attributes)
		cell.combining = placeholder(row: 9, column: 0)

		#expect(terminal.graphics.placements(
			for: UnicodePlaceholder.runs(in: [cell], screenRow: 0)
		).isEmpty)
	}

	/// An id larger than a colour can hold carries its top byte in a third
	/// diacritic.
	@Test func aThirdDiacriticCarriesTheTopByteOfTheId() {
		let read = UnicodePlaceholder.decode(
			scalar: UnicodePlaceholder.scalar,
			combining: placeholder(row: 0, column: 0, idHighByte: 0xD5),
			foreground: .rgb(0xA0, 0xF0, 0x25)
		)
		#expect(read?.imageID == 0xD5A0_F025)
	}
}
