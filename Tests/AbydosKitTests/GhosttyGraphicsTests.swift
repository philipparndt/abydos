import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AbydosKit

/// **Item 0485, step one**: our placeholder layer on libghostty-vt's grid and
/// placement store.
///
/// 0474 concluded that the `U=1` unicode-placeholder protocol — the one `icat`
/// uses inside tmux, which is where this app is nearly all the time — could not
/// work behind libghostty-vt without something new being exported, because the
/// part that turns placeholder cells into picture fragments is not in the C API
/// and `placement_rect`/`placement_viewport_pos` refuse virtual placements
/// outright.
///
/// These tests are the disproof. The two calls that refuse a virtual placement
/// are the two that answer "where on the screen is this picture", and for a
/// placeholder picture the *cells* answer that — which is the entire point of
/// the indirection. Everything else is exported: the codepoint, the graphemes,
/// the raw style colour, the placement's columns and rows, and the image's
/// pixels by bare id.
struct GhosttyGraphicsTests {
	/// The placeholder character followed by the diacritics for a row and a
	/// column, exactly as `icat` writes them.
	private func placeholder(row: Int?, column: Int?, idHighByte: Int? = nil) -> String {
		var text = String(UnicodeScalar(UnicodePlaceholder.scalar)!)
		for index in [row, column, idHighByte] {
			guard let index else { break }
			text.unicodeScalars.append(UnicodeScalar(UnicodePlaceholder.diacritics[index])!)
		}
		return text
	}

	private func engine(columns: Int = 40, rows: Int = 10) -> GhosttyTerminalEngine {
		let engine = GhosttyTerminalEngine(rows: rows, columns: columns)
		engine.cellPixelSize = (width: 10, height: 20)
		return engine
	}

	/// A sixteen-by-eight picture as a virtual placement four cells by two, the
	/// same shape `UnicodePlaceholderTests` sends to our own engine.
	private func transmitVirtual(
		id: UInt32, columns: Int, rows: Int, in engine: GhosttyTerminalEngine
	) {
		let pixels = Data([UInt8](repeating: 0x40, count: 16 * 8 * 3)).base64EncodedString()
		engine.write(
			"\u{1B}_Ga=T,q=2,f=24,U=1,s=16,v=8,c=\(columns),r=\(rows),i=\(id);\(pixels)\u{1B}\\"
		)
	}

	/// Writes the placeholder cells for one strip of an image, in the colour that
	/// carries its id.
	private func writeStrip(
		imageID: UInt32, imageRow: Int, columns: Range<Int>, in engine: GhosttyTerminalEngine
	) {
		let red = (imageID >> 16) & 0xFF, green = (imageID >> 8) & 0xFF, blue = imageID & 0xFF
		var text = "\u{1B}[38;2;\(red);\(green);\(blue)m"
		for column in columns {
			text += placeholder(row: imageRow, column: column)
		}
		engine.write(text + "\u{1B}[0m")
	}

	// MARK: - The three things the decoder needs off a cell

	/// **The load-bearing test.** A placeholder cell written into libghostty-vt
	/// comes back out of its grid with all three of the things our decoder reads:
	/// the U+10EEEE base codepoint, the diacritics after it, and the raw
	/// foreground colour the id lives in.
	///
	/// If any one of these had been lost — the codepoint replaced by a
	/// replacement character, the graphemes dropped, the colour resolved through
	/// the palette — step one of 0485 would have been a "no" and the item would
	/// have needed an upstream export. None of them is.
	@Test func aPlaceholderCellSurvivesLibghosttysGrid() throws {
		let engine = engine()
		try #require(engine.isUsable)
		writeStrip(imageID: 1234, imageRow: 0, columns: 0..<4, in: engine)

		let grid = engine.grid
		let line = try #require(grid.line(at: grid.scrollbackCount))
		let cell = line.cells[0]
		#expect(cell.scalar == UnicodePlaceholder.scalar)
		#expect(cell.combining != nil)
		// 1234 == 0x0004D2, and it has to still be an RGB triple rather than
		// something resolved: the id *is* the colour.
		#expect(cell.attributes.foreground == .rgb(0x00, 0x04, 0xD2))

		let read = UnicodePlaceholder.decode(
			scalar: cell.scalar, combining: cell.combining,
			foreground: cell.attributes.foreground)
		#expect(read?.imageID == 1234)
		#expect(read?.row == 0)
		#expect(read?.column == 0)
	}

	/// The decoder over a whole row of libghostty-vt's cells finds one run, which
	/// is what a picture actually looks like on the wire.
	@Test func theRunsOnARowAreFoundInLibghosttysGrid() throws {
		let engine = engine()
		try #require(engine.isUsable)
		writeStrip(imageID: 1234, imageRow: 1, columns: 0..<4, in: engine)

		let grid = engine.grid
		let line = try #require(grid.line(at: grid.scrollbackCount))
		let runs = UnicodePlaceholder.runs(in: line.cells, screenRow: grid.scrollbackCount)
		#expect(runs.count == 1)
		#expect(runs.first?.imageID == 1234)
		#expect(runs.first?.imageRow == 1)
		#expect(runs.first?.length == 4)
	}

	// MARK: - The two things it needs off the store

	/// A `U=1` transmit leaves libghostty-vt holding a virtual placement with the
	/// picture's size in cells, and the bridge brings it across.
	///
	/// `placement_grid_size` refuses a virtual placement; the raw `COLUMNS` and
	/// `ROWS` getters do not, and they are what `c=`/`r=` on the transmit landed
	/// in. That distinction is the whole of why this works.
	@Test func aVirtualPlacementComesAcrossWithItsSizeInCells() throws {
		let engine = engine()
		try #require(engine.isUsable)
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: engine)

		#expect(engine.graphics.hasVirtualPlacements)
		// Nowhere by itself: a virtual placement belongs to no position, and
		// drawing it at the cursor as well is what "the image blinks and is gone"
		// was in our own engine.
		#expect(engine.graphics.placements.isEmpty)
		let virtual = try #require(engine.graphics.virtualPlacements.values.first)
		#expect(virtual.columns == 4)
		#expect(virtual.rows == 2)
		#expect(virtual.source == .init(x: 0, y: 0, width: 16, height: 8))

		let image = try #require(engine.graphics.images[1234])
		#expect(image.width == 16)
		#expect(image.height == 8)
		// Widened to premultiplied RGBA, which is the one form both of our drawing
		// paths take.
		#expect(image.pixels.count == 16 * 8 * 4)
		#expect(image.pixels[0] == 0x40)
		#expect(image.pixels[3] == 0xFF)
	}

	// MARK: - The whole path

	/// **The answer to step one, end to end**: a picture transmitted as `icat`
	/// transmits it and placed as `icat` places it comes out as fragments at the
	/// rows the characters are on, with libghostty-vt as the engine.
	///
	/// This is the same assertion `UnicodePlaceholderTests`
	/// `thePictureIsBuiltFromWhereTheCharactersAre` makes about our own engine, so
	/// the two engines are being held to one standard.
	@Test func thePictureIsBuiltFromWhereTheCharactersAreUnderLibghostty() throws {
		let engine = engine()
		try #require(engine.isUsable)
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: engine)

		// Two rows of placeholders, which is how a two-row picture is written.
		writeStrip(imageID: 1234, imageRow: 0, columns: 0..<4, in: engine)
		engine.write("\r\n")
		writeStrip(imageID: 1234, imageRow: 1, columns: 0..<4, in: engine)

		let grid = engine.grid
		var runs: [UnicodePlaceholder.Run] = []
		for index in grid.scrollbackCount..<grid.totalLineCount {
			guard let line = grid.line(at: index) else { continue }
			runs += UnicodePlaceholder.runs(in: line.cells, screenRow: index)
		}
		#expect(runs.count == 2)

		let placements = engine.graphics.placements(for: runs)
		#expect(placements.count == 2)
		let top = try #require(placements.first)
		#expect(top.columns == 4)
		#expect(top.rows == 1)
		// The top half of a sixteen-by-eight image, across its full width.
		#expect(top.source == .init(x: 0, y: 0, width: 16, height: 4))
		let bottom = try #require(placements.last)
		#expect(bottom.row == top.row + 1)
		#expect(bottom.source == .init(x: 0, y: 4, width: 16, height: 4))
	}

	/// The picture moves with the characters, which is the reason the protocol is
	/// built this way and the reason it survives tmux.
	@Test func scrollingMovesThePictureBecauseItMovesTheCharacters() throws {
		let engine = engine(rows: 6)
		try #require(engine.isUsable)
		transmitVirtual(id: 1234, columns: 4, rows: 2, in: engine)
		writeStrip(imageID: 1234, imageRow: 0, columns: 0..<4, in: engine)

		func placementRow() -> Int? {
			let grid = engine.grid
			var runs: [UnicodePlaceholder.Run] = []
			for index in 0..<grid.totalLineCount {
				guard let line = grid.line(at: index) else { continue }
				runs += UnicodePlaceholder.runs(in: line.cells, screenRow: index)
			}
			return engine.graphics.placements(for: runs).first?.row
		}

		let before = try #require(placementRow())
		// Enough newlines to push the row into history.
		engine.write(String(repeating: "\r\n", count: 10))
		let after = try #require(placementRow())
		// The absolute row is unchanged, because the characters are the same
		// characters — they are simply in scrollback now.
		#expect(after == before)
	}

	// MARK: - PNG, which is what icat actually sends

	/// `icat` sends `f=100`. libghostty-vt has no PNG decoder of its own and
	/// rejects every PNG transmit until one is installed through
	/// `GHOSTTY_SYS_OPT_DECODE_PNG` — so this is not a detail, it is the
	/// difference between the tmux path working and silently doing nothing.
	@Test func aPngTransmitIsDecodedThroughTheDecoderWeInstall() throws {
		let engine = engine()
		try #require(engine.isUsable)

		// A four-by-two PNG, built here so the test carries no fixture.
		let png = try #require(Self.smallPng(width: 4, height: 2))
		engine.write(
			"\u{1B}_Ga=T,q=2,f=100,U=1,c=2,r=1,i=77;\(png.base64EncodedString())\u{1B}\\")

		let image = try #require(
			engine.graphics.images[77],
			"libghostty-vt rejected the PNG — the sys decoder is not installed")
		#expect(image.width == 4)
		#expect(image.height == 2)
		#expect(image.pixels.count == 4 * 2 * 4)
	}

	/// A solid opaque PNG of the given size, through ImageIO.
	private static func smallPng(width: Int, height: Int) -> Data? {
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		for pixel in 0..<(width * height) {
			pixels[pixel * 4] = 0x20
			pixels[pixel * 4 + 1] = 0x40
			pixels[pixel * 4 + 2] = 0x60
			pixels[pixel * 4 + 3] = 0xFF
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData),
		      let image = CGImage(
		      	width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
		      	bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
		      	bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
		      	provider: provider, decode: nil, shouldInterpolate: false,
		      	intent: .defaultIntent)
		else { return nil }

		let output = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(
			output, "public.png" as CFString, 1, nil)
		else { return nil }
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return output as Data
	}
}
