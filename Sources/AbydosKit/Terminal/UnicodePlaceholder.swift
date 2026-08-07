import Foundation

/// Unicode placeholders: how kitty's own `icat` actually shows a picture.
///
/// The protocol has two ways to put an image on the screen. The obvious one
/// places it at the cursor, and it is the one this app implemented — and the
/// one almost nothing uses. kitty's `icat` uses the other: it transmits the
/// image with `U=1`, which creates a *virtual* placement belonging to no
/// position at all, and then writes ordinary text made of the placeholder
/// character U+10EEEE. Each of those cells says which image it belongs to and
/// which of its cells it is; the terminal draws that piece of the picture
/// there.
///
/// The indirection is the whole point. Placeholders are text, so everything
/// that moves text moves the picture with it — and that is why an image
/// survives scrolling back inside tmux in a terminal that implements this and
/// vanishes in one that does not. tmux is not re-sending the picture; it is
/// moving the characters, exactly as it moves every other character, and the
/// terminal draws the picture wherever they land.
///
/// A cell says three things:
///
///   - **which image**, from its foreground colour: a 24-bit colour is the low
///     three bytes of the id, an indexed colour is the id itself. A third
///     diacritic, where there is one, carries the highest byte.
///   - **which row of the image**, from the first combining diacritic.
///   - **which column**, from the second.
///
/// Row and column may both be left out, in which case they continue the cell
/// before: the same row, the next column. Runs are written that way, so most
/// cells carry one diacritic and many carry none.
public enum UnicodePlaceholder {
	/// The character that stands in for a piece of a picture.
	public static let scalar: UInt32 = 0x10EEEE

	/// The diacritics that spell out a row or a column, in order: the *index*
	/// into this list is the number, not the code point.
	///
	/// kitty's own list, copied rather than derived. It comes from the combining
	/// marks of Unicode 6.0.0 with a handful of common accents removed, and a
	/// terminal that generated its own would agree with kitty only by accident.
	public static let diacritics: [UInt32] = [
		0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F,
		0x0346, 0x034A, 0x034B, 0x034C, 0x0350, 0x0351, 0x0352, 0x0357,
		0x035B, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
		0x036A, 0x036B, 0x036C, 0x036D, 0x036E, 0x036F, 0x0483, 0x0484,
		0x0485, 0x0486, 0x0487, 0x0592, 0x0593, 0x0594, 0x0595, 0x0597,
		0x0598, 0x0599, 0x059C, 0x059D, 0x059E, 0x059F, 0x05A0, 0x05A1,
		0x05A8, 0x05A9, 0x05AB, 0x05AC, 0x05AF, 0x05C4, 0x0610, 0x0611,
		0x0612, 0x0613, 0x0614, 0x0615, 0x0616, 0x0617, 0x0657, 0x0658,
		0x0659, 0x065A, 0x065B, 0x065D, 0x065E, 0x06D6, 0x06D7, 0x06D8,
		0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DF, 0x06E0, 0x06E1, 0x06E2,
		0x06E4, 0x06E7, 0x06E8, 0x06EB, 0x06EC, 0x0730, 0x0732, 0x0733,
		0x0735, 0x0736, 0x073A, 0x073D, 0x073F, 0x0740, 0x0741, 0x0743,
		0x0745, 0x0747, 0x0749, 0x074A, 0x07EB, 0x07EC, 0x07ED, 0x07EE,
		0x07EF, 0x07F0, 0x07F1, 0x07F3, 0x0816, 0x0817, 0x0818, 0x0819,
		0x081B, 0x081C, 0x081D, 0x081E, 0x081F, 0x0820, 0x0821, 0x0822,
		0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082A, 0x082B, 0x082C,
		0x082D, 0x0951, 0x0953, 0x0954, 0x0F82, 0x0F83, 0x0F86, 0x0F87,
		0x135D, 0x135E, 0x135F, 0x17DD, 0x193A, 0x1A17, 0x1A75, 0x1A76,
		0x1A77, 0x1A78, 0x1A79, 0x1A7A, 0x1A7B, 0x1A7C, 0x1B6B, 0x1B6D,
		0x1B6E, 0x1B6F, 0x1B70, 0x1B71, 0x1B72, 0x1B73, 0x1CD0, 0x1CD1,
		0x1CD2, 0x1CDA, 0x1CDB, 0x1CE0, 0x1DC0, 0x1DC1, 0x1DC3, 0x1DC4,
		0x1DC5, 0x1DC6, 0x1DC7, 0x1DC8, 0x1DC9, 0x1DCB, 0x1DCC, 0x1DD1,
		0x1DD2, 0x1DD3, 0x1DD4, 0x1DD5, 0x1DD6, 0x1DD7, 0x1DD8, 0x1DD9,
		0x1DDA, 0x1DDB, 0x1DDC, 0x1DDD, 0x1DDE, 0x1DDF, 0x1DE0, 0x1DE1,
		0x1DE2, 0x1DE3, 0x1DE4, 0x1DE5, 0x1DE6, 0x1DFE, 0x20D0, 0x20D1,
		0x20D4, 0x20D5, 0x20D6, 0x20D7, 0x20DB, 0x20DC, 0x20E1, 0x20E7,
		0x20E9, 0x20F0, 0x2CEF, 0x2CF0, 0x2CF1, 0x2DE0, 0x2DE1, 0x2DE2,
		0x2DE3, 0x2DE4, 0x2DE5, 0x2DE6, 0x2DE7, 0x2DE8, 0x2DE9, 0x2DEA,
		0x2DEB, 0x2DEC, 0x2DED, 0x2DEE, 0x2DEF, 0x2DF0, 0x2DF1, 0x2DF2,
		0x2DF3, 0x2DF4, 0x2DF5, 0x2DF6, 0x2DF7, 0x2DF8, 0x2DF9, 0x2DFA,
		0x2DFB, 0x2DFC, 0x2DFD, 0x2DFE, 0x2DFF, 0xA66F, 0xA67C, 0xA67D,
		0xA6F0, 0xA6F1, 0xA8E0, 0xA8E1, 0xA8E2, 0xA8E3, 0xA8E4, 0xA8E5,
		0xA8E6, 0xA8E7, 0xA8E8, 0xA8E9, 0xA8EA, 0xA8EB, 0xA8EC, 0xA8ED,
		0xA8EE, 0xA8EF, 0xA8F0, 0xA8F1, 0xAAB0, 0xAAB2, 0xAAB3, 0xAAB7,
		0xAAB8, 0xAABE, 0xAABF, 0xAAC1, 0xFE20, 0xFE21, 0xFE22, 0xFE23,
		0xFE24, 0xFE25, 0xFE26, 0x10A0F, 0x10A38, 0x1D185, 0x1D186, 0x1D187,
		0x1D188, 0x1D189, 0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242, 0x1D243,
		0x1D244,
	]

	/// The number a diacritic stands for, or nil if it is not one of them.
	public static func index(ofDiacritic scalar: UInt32) -> Int? {
		diacriticIndex[scalar]
	}

	private static let diacriticIndex: [UInt32: Int] = {
		var table: [UInt32: Int] = [:]
		table.reserveCapacity(diacritics.count)
		for (index, scalar) in diacritics.enumerated() { table[scalar] = index }
		return table
	}()
}

// MARK: - Reading the grid

extension UnicodePlaceholder {
	/// A stretch of placeholder cells side by side, standing for one strip of
	/// one image.
	///
	/// A run rather than a cell because a picture is a few thousand cells and
	/// drawing each of them separately would be a few thousand draw calls a
	/// frame. Within a run the image's columns advance with the screen's, so
	/// the whole strip is one piece of the picture in one rectangle.
	public struct Run: Equatable, Sendable {
		public var imageID: UInt32
		/// Row on the screen, counted the way placements are.
		public var screenRow: Int
		/// First column on the screen.
		public var column: Int
		/// How many cells across.
		public var length: Int
		/// Which row of the image the strip comes from.
		public var imageRow: Int
		/// Which of the image's columns the strip starts at.
		public var imageColumn: Int

		public init(
			imageID: UInt32, screenRow: Int, column: Int, length: Int,
			imageRow: Int, imageColumn: Int
		) {
			self.imageID = imageID
			self.screenRow = screenRow
			self.column = column
			self.length = length
			self.imageRow = imageRow
			self.imageColumn = imageColumn
		}
	}

	/// What one cell says, or nil if it is not a placeholder.
	///
	/// Row and column are each optional because a run leaves them out after the
	/// first cell; the caller continues from the cell before.
	public static func decode(
		scalar: UInt32, combining: String?, foreground: TerminalColor
	) -> (imageID: UInt32, row: Int?, column: Int?)? {
		guard scalar == Self.scalar else { return nil }

		var marks: [Int] = []
		if let combining {
			for character in combining.unicodeScalars where character.value != Self.scalar {
				guard let index = index(ofDiacritic: character.value) else { continue }
				marks.append(index)
			}
		}

		// The id lives in the colour. A 24-bit colour is the low three bytes of
		// it; an indexed colour is a small id on its own. Nothing else can
		// carry one, so a placeholder written in the default colour belongs to
		// no image and is left as the character it is.
		var id: UInt32
		switch foreground {
		case let .rgb(red, green, blue):
			id = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
		case let .indexed(index):
			id = UInt32(index)
		default:
			return nil
		}
		// A third diacritic carries the byte the colour has no room for.
		if marks.count > 2 { id |= UInt32(marks[2]) << 24 }
		guard id != 0 else { return nil }

		return (id, marks.count > 0 ? marks[0] : nil, marks.count > 1 ? marks[1] : nil)
	}

	/// The runs on one row of the screen.
	///
	/// - Parameter row: the cells, left to right.
	/// - Parameter screenRow: what to record as their row.
	public static func runs(in row: [TerminalCell], screenRow: Int) -> [Run] {
		var found: [Run] = []
		var current: Run?
		// The cell before, whether or not it belongs to the run being built:
		// what a cell leaves out continues from here.
		var previous: (id: UInt32, imageRow: Int, imageColumn: Int)?

		func flush() {
			if let current { found.append(current) }
			current = nil
		}

		for (column, cell) in row.enumerated() {
			guard let read = decode(
				scalar: cell.scalar, combining: cell.combining,
				foreground: cell.attributes.foreground
			) else {
				flush()
				previous = nil
				continue
			}

			let imageRow = read.row ?? (previous?.id == read.imageID ? previous?.imageRow : nil) ?? 0
			let imageColumn: Int
			if let stated = read.column {
				imageColumn = stated
			} else if let previous, previous.id == read.imageID, previous.imageRow == imageRow {
				imageColumn = previous.imageColumn + 1
			} else {
				imageColumn = 0
			}

			// Joined to the run being built only where both the screen and the
			// image carry straight on; anything else starts a new strip.
			if var run = current,
			   run.imageID == read.imageID,
			   run.imageRow == imageRow,
			   run.column + run.length == column,
			   run.imageColumn + run.length == imageColumn {
				run.length += 1
				current = run
			} else {
				flush()
				current = Run(
					imageID: read.imageID, screenRow: screenRow, column: column,
					length: 1, imageRow: imageRow, imageColumn: imageColumn
				)
			}
			previous = (read.imageID, imageRow, imageColumn)
		}
		flush()
		return found
	}
}
