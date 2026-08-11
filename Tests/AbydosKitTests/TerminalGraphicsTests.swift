import Foundation
import Testing
@testable import AbydosKit

/// The kitty graphics protocol: a program putting a real picture on the grid.
///
/// All of it headless. What makes an image right — where it lands, how many
/// cells it covers, which part of it is shown — is arithmetic on bytes that
/// arrived, and none of it needs a window to check.
struct TerminalGraphicsTests {
	private func emulator(rows: Int = 10, columns: Int = 40) -> TerminalEmulator {
		let terminal = TerminalEmulator(rows: rows, columns: columns)
		// Something has to say how large a cell is; nothing can be placed until
		// it does, because a picture is measured in pixels and shown in cells.
		terminal.cellPixelSize = (width: 10, height: 20)
		return terminal
	}

	/// `s`×`v` pixels of solid colour, as the raw formats carry them.
	private func rawRGB(width: Int, height: Int) -> String {
		Data([UInt8](repeating: 0x40, count: width * height * 3)).base64EncodedString()
	}

	private func graphics(_ body: String) -> String { "\u{1B}_G\(body)\u{1B}\\" }

	// MARK: - The handshake

	/// What `kitten icat --detect-support` sends, near enough exactly.
	@Test func aProgramCanAskWhetherPicturesWork() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write(graphics("i=31,s=1,v=1,a=q,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(answered == "\u{1B}_Gi=31;OK\u{1B}\\")
	}

	/// A query is a rehearsal: it checks the bytes and keeps nothing.
	@Test func askingDoesNotStoreThePicture() {
		let terminal = emulator()
		terminal.write(graphics("i=31,s=1,v=1,a=q,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(terminal.graphics.images.isEmpty)
	}

	@Test func aBadlySizedPayloadIsRefusedRatherThanGuessedAt() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		// Says 4x4 RGB — 48 bytes — and sends one pixel.
		terminal.write(graphics("i=7,s=4,v=4,a=q,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(answered?.contains("EINVAL") == true)
	}

	/// A reply nobody can match to a command is worse than no reply: it falls
	/// through to the shell, which echoes it.
	@Test func nothingIsSaidWhenTheCommandNamedNoImage() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write(graphics("s=1,v=1,a=t,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(answered == nil)
	}

	@Test func aQuietProgramIsNotToldItSucceeded() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write(graphics("i=5,q=1,s=1,v=1,a=t,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(answered == nil)
	}

	@Test func aQuietProgramIsStillToldWhenItAsksOutright() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write(graphics("i=5,q=2,s=1,v=1,a=q,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(answered == "\u{1B}_Gi=5;OK\u{1B}\\")
	}

	// MARK: - Transmission

	@Test func rawPixelsArriveAtTheSizeTheyClaim() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=4,v=3,a=t,t=d,f=24;\(rawRGB(width: 4, height: 3))"))

		let image = terminal.graphics.images[1]
		#expect(image?.width == 4)
		#expect(image?.height == 3)
		// Widened to RGBA on the way in, so both renderers get one layout.
		#expect(image?.pixels.count == 4 * 3 * 4)
	}

	@Test func transparencyIsMultipliedInOnArrival() {
		let terminal = emulator()
		// One pixel, half-transparent white.
		let payload = Data([0xFF, 0xFF, 0xFF, 0x80]).base64EncodedString()
		terminal.write(graphics("i=1,s=1,v=1,a=t,t=d,f=32;\(payload)"))

		let pixels = terminal.graphics.images[1]?.pixels
		#expect(pixels?[0] == 0x80)
		#expect(pixels?[3] == 0x80)
	}

	/// A picture too large for one escape sequence arrives in pieces, and only
	/// the first piece says what it is.
	@Test func aPictureCanArriveInChunks() {
		let terminal = emulator()
		let encoded = rawRGB(width: 4, height: 4)
		let half = encoded.index(encoded.startIndex, offsetBy: encoded.count / 2)

		terminal.write(graphics("i=9,s=4,v=4,a=t,t=d,f=24,m=1;\(encoded[..<half])"))
		#expect(terminal.graphics.images.isEmpty, "nothing is stored until the last chunk")

		terminal.write(graphics("m=0;\(encoded[half...])"))
		#expect(terminal.graphics.images[9]?.width == 4)
	}

	@Test func aCompressedPayloadIsInflated() throws {
		let terminal = emulator()
		let raw = Data([UInt8](repeating: 0x40, count: 4 * 4 * 3))
		let compressed = try #require(zlib(raw))

		terminal.write(graphics("i=11,s=4,v=4,a=t,t=d,f=24,o=z;\(compressed.base64EncodedString())"))
		#expect(terminal.graphics.images[11]?.width == 4)
	}

	/// kitty leaves the `=` off the end of its base64, and Foundation refuses
	/// anything whose length is not a multiple of four. `icat` sending a file
	/// path hits this every time a path is not a multiple of three bytes long.
	@Test func base64WithoutItsPaddingIsStillRead() throws {
		let terminal = emulator()
		// Two pixels of RGB — six bytes, which is a multiple of three, so the
		// path below is what carries the odd length.
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-unpadded-\(UUID().uuidString)")
		try Data([UInt8](repeating: 0x40, count: 2 * 1 * 3)).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		var encoded = Data(url.path.utf8).base64EncodedString()
		while encoded.hasSuffix("=") { encoded.removeLast() }
		#expect(encoded.count % 4 != 0, "the test means nothing if it stayed aligned")

		terminal.write(graphics("i=21,s=2,v=1,a=t,t=f,f=24;\(encoded)"))
		#expect(terminal.graphics.images[21]?.width == 2)
	}

	@Test func aPictureCanArriveAsAFileOnDisk() throws {
		let terminal = emulator()
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-graphics-\(UUID().uuidString)")
		try Data([UInt8](repeating: 0x40, count: 2 * 2 * 3)).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let path = Data(url.path.utf8).base64EncodedString()
		terminal.write(graphics("i=12,s=2,v=2,a=t,t=f,f=24;\(path)"))
		#expect(terminal.graphics.images[12]?.width == 2)
		#expect(FileManager.default.fileExists(atPath: url.path), "t=f is not ours to delete")
	}

	/// `t=t` hands over a scratch file and expects it gone afterwards.
	@Test func aTemporaryFileIsClearedAwayOnceRead() throws {
		let terminal = emulator()
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-graphics-\(UUID().uuidString)")
		try Data([UInt8](repeating: 0x40, count: 2 * 2 * 3)).write(to: url)

		let path = Data(url.path.utf8).base64EncodedString()
		terminal.write(graphics("i=13,s=2,v=2,a=t,t=t,f=24;\(path)"))
		#expect(terminal.graphics.images[13] != nil)
		#expect(!FileManager.default.fileExists(atPath: url.path))
	}

	/// A program can name any path it likes, and `t=t` says "delete this". Only
	/// the scratch directories are ours to delete from.
	@Test func aTemporaryFileOutsideTheScratchDirectoriesSurvives() throws {
		let terminal = emulator()
		// Somewhere that is emphatically not a scratch directory. A program can
		// name any path it likes on a `t=t`, and "delete this when you have read
		// it" must not be a way to have the terminal remove someone's files.
		let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
			.appendingPathComponent("ideai-graphics-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let url = directory.appendingPathComponent("precious")
		try Data([UInt8](repeating: 0x40, count: 2 * 2 * 3)).write(to: url)

		let path = Data(url.path.utf8).base64EncodedString()
		terminal.write(graphics("i=14,s=2,v=2,a=t,t=t,f=24;\(path)"))

		#expect(terminal.graphics.images[14] != nil, "it is still read")
		#expect(FileManager.default.fileExists(atPath: url.path), "but not deleted")
	}

	@Test func sharedMemoryIsRefusedRatherThanIgnored() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write(graphics("i=3,s=1,v=1,a=q,t=s,f=24;\(rawRGB(width: 1, height: 1))"))
		#expect(answered?.contains("EBADF") == true)
	}

	// MARK: - Placing

	@Test func aPictureLandsWhereTheCursorIs() {
		let terminal = emulator()
		terminal.write("\u{1B}[3;5H") // row 3, column 5, counting from one
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		let placement = terminal.graphics.placements.first
		#expect(placement?.row == 2)
		#expect(placement?.column == 4)
	}

	/// Two cells wide and two tall, at ten by twenty pixels a cell.
	@Test func aPictureCoversTheCellsItsPixelsComeTo() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		let placement = terminal.graphics.placements.first
		#expect(placement?.columns == 2)
		#expect(placement?.rows == 2)
	}

	/// A part cell counts as a whole one; the picture has to go somewhere.
	@Test func aPictureThatDoesNotDivideEvenlyTakesTheNextCell() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=25,v=41,a=T,t=d,f=24;\(rawRGB(width: 25, height: 41))"))

		let placement = terminal.graphics.placements.first
		#expect(placement?.columns == 3)
		#expect(placement?.rows == 3)
	}

	@Test func aProgramCanSayHowManyCellsToUseInstead() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,c=8,r=4,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		let placement = terminal.graphics.placements.first
		#expect(placement?.columns == 8)
		#expect(placement?.rows == 4)
	}

	@Test func onlyPartOfAPictureCanBeShown() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=40,v=40,x=10,y=5,w=20,h=15,a=T,t=d,f=24;\(rawRGB(width: 40, height: 40))"))

		let source = terminal.graphics.placements.first?.source
		#expect(source == .init(x: 10, y: 5, width: 20, height: 15))
	}

	@Test func theCursorEndsUpPastThePicture() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		// Two rows down means one row of movement, and two columns across.
		#expect(terminal.cursorRow == 1)
		#expect(terminal.cursorColumn == 2)
	}

	@Test func theCursorCanBeAskedToStayWhereItIs() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		#expect(terminal.cursorRow == 0)
		#expect(terminal.cursorColumn == 0)
	}

	// MARK: - A picture that does not fit under the cursor

	/// A picture placed where there is not room for it scrolls the screen, the
	/// way printing that many lines would.
	///
	/// This is the whole of 0468. `icat` outside tmux places a picture at the
	/// cursor and lets the *terminal* make room for it — it prints no rows of
	/// its own and it is told nothing about how tall the pane is. The cursor
	/// advance was a `moveCursor`, which clamps at the last row, so nothing
	/// scrolled and the picture kept the rows it had been given: rows below the
	/// bottom of the screen, which are never drawn and never will be.
	@Test func aPictureTooTallForWhatIsLeftScrollsTheScreen() throws {
		let terminal = emulator(rows: 10, columns: 40)
		// Eight rows of output, so the cursor sits two rows from the bottom.
		terminal.write(String(repeating: "line\r\n", count: 8))
		#expect(terminal.cursorRow == 8)

		// 30×100 pixels at 10×20 a cell is three columns by five rows, and only
		// two of those five rows are left.
		terminal.write(graphics("a=T,s=30,v=100,f=24;\(rawRGB(width: 30, height: 100))"))

		let placement = try #require(terminal.graphics.placements.last)
		#expect(placement.rows == 5)
		// Three rows had to be made, so three went into the scrollback.
		#expect(terminal.screen.scrollback.count == 3)
		// Which puts every row of the picture on the screen.
		let firstOnScreen = terminal.screen.scrollback.count
		let lastOnScreen = firstOnScreen + terminal.screen.rows - 1
		#expect(placement.rowRange.lowerBound >= firstOnScreen)
		#expect(placement.rowRange.upperBound <= lastOnScreen)
	}

	/// The prompt that follows such a picture does not erase it.
	///
	/// This is the symptom as it was reported — "shows the picture and loses it
	/// while still reserving the space". A placement whose rows run past the
	/// bottom of the screen overlaps whatever the shell erases from the prompt
	/// downwards, so `ESC[J` — which zsh writes before every prompt, and which
	/// tmux swallows, which is why no measurement taken inside tmux ever saw
	/// this — took the picture with it.
	@Test func thePromptAfterSuchAPictureDoesNotEraseIt() {
		let terminal = emulator(rows: 10, columns: 40)
		terminal.write(String(repeating: "line\r\n", count: 8))

		// Exactly what `icat` writes with no tmux in the way: back to the left
		// edge, across to the picture's indent, the placement, a newline.
		terminal.write("\r\u{1B}[18C")
		terminal.write(graphics("a=T,q=2,s=30,v=100,f=24;\(rawRGB(width: 30, height: 100))"))
		terminal.write("\r\n")
		#expect(terminal.graphics.placements.count == 1)

		// And what the shell writes next: its partial-line mark, then the erase.
		terminal.write("%" + String(repeating: " ", count: 39) + "\r \r\u{1B}[J")
		#expect(terminal.graphics.placements.count == 1)
	}

	@Test func somethingSentEarlierCanBeShownAgainElsewhere() {
		let terminal = emulator()
		terminal.write(graphics("i=4,s=20,v=40,a=t,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		#expect(terminal.graphics.placements.isEmpty)

		terminal.write("\u{1B}[5;1H")
		terminal.write(graphics("i=4,p=2,a=p"))
		#expect(terminal.graphics.placements.count == 1)
		#expect(terminal.graphics.placements.first?.row == 4)
	}

	@Test func showingSomethingThatWasNeverSentSaysSo() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write(graphics("i=99,a=p"))
		#expect(answered?.contains("ENOENT") == true)
	}

	/// A program redrawing a plot sends the same placement again; it replaces
	/// what was there rather than stacking on top of it.
	@Test func placingTheSamePictureTwiceLeavesOneOfIt() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		terminal.write("\u{1B}[5;1H")
		terminal.write(graphics("i=1,a=p"))

		#expect(terminal.graphics.placements.count == 1)
		#expect(terminal.graphics.placements.first?.row == 4)
	}

	// MARK: - Deleting

	@Test func everythingCanBeTakenOffTheScreenAtOnce() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		terminal.write(graphics("a=d,d=a"))

		#expect(terminal.graphics.placements.isEmpty)
		#expect(terminal.graphics.images[1] != nil, "lower case leaves the picture itself alone")
	}

	@Test func theUpperCaseFormFreesThePictureToo() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		terminal.write(graphics("a=d,d=A"))

		#expect(terminal.graphics.placements.isEmpty)
		#expect(terminal.graphics.images[1] == nil)
	}

	@Test func onePictureCanBeTakenAwayByName() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		terminal.write("\u{1B}[5;1H")
		terminal.write(graphics("i=2,s=20,v=40,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		terminal.write(graphics("a=d,d=i,i=1"))
		#expect(terminal.graphics.placements.map(\.imageID) == [2])
	}

	@Test func whateverTheCursorIsStandingOnCanBeTakenAway() {
		let terminal = emulator()
		terminal.write("\u{1B}[1;1H")
		terminal.write(graphics("i=1,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		terminal.write(graphics("a=d,d=c"))
		#expect(terminal.graphics.placements.isEmpty)
	}

	@Test func aWholeRowCanBeCleared() {
		let terminal = emulator()
		terminal.write("\u{1B}[3;1H")
		terminal.write(graphics("i=1,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		// Row 3, counting from one, which is where it was put.
		terminal.write(graphics("a=d,d=y,y=3"))
		#expect(terminal.graphics.placements.isEmpty)
	}

	@Test func everythingAtOneDepthCanBeCleared() {
		let terminal = emulator()
		terminal.write(graphics("i=1,z=-1,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		terminal.write(graphics("i=2,z=5,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))

		terminal.write(graphics("a=d,d=z,z=-1"))
		#expect(terminal.graphics.placements.map(\.imageID) == [2])
	}

	// MARK: - Living with the text

	/// The row a picture is anchored to counts from the start of history, so it
	/// travels with the line it was printed beside.
	@Test func aPictureStaysWithTheTextItArrivedWith() {
		let terminal = emulator(rows: 4, columns: 20)
		terminal.write("\u{1B}[4;1H") // the last row
		terminal.write(graphics("i=1,s=10,v=20,C=1,a=T,t=d,f=24;\(rawRGB(width: 10, height: 20))"))

		let before = terminal.graphics.placements.first?.row
		// Three newlines from the bottom row push three lines into scrollback.
		terminal.write("\r\n\r\n\r\n")
		#expect(terminal.graphics.placements.first?.row == before)
	}

	/// Lines falling off the top of scrollback move every absolute row, and the
	/// pictures have to move with them or they drift away from their text.
	@Test func discardedHistoryTakesThePicturesWithIt() throws {
		let terminal = emulator(rows: 4, columns: 20)
		terminal.write("\u{1B}[4;1H")
		terminal.write(graphics("i=1,s=10,v=20,C=1,a=T,t=d,f=24;\(rawRGB(width: 10, height: 20))"))

		let before = try #require(terminal.graphics.placements.first?.row)
		// A couple of lines past the end of the history the screen keeps, so the
		// oldest fall off the front and every absolute row shifts under them —
		// but not so far that the picture itself is pushed out.
		terminal.write(String(repeating: "\r\n", count: 5_002))

		let dropped = terminal.screen.discardedLineCount
		#expect(dropped > 0, "the test means nothing unless history was actually dropped")
		#expect(terminal.graphics.placements.first?.row == before - dropped)
	}

	/// Scrolled far enough back, a picture is gone for good — there is no row
	/// left to draw it on, and holding its pixels would be holding them forever.
	@Test func aPictureScrolledOutOfHistoryIsForgotten() {
		let terminal = emulator(rows: 4, columns: 20)
		terminal.write("\u{1B}[4;1H")
		terminal.write(graphics("i=1,s=10,v=20,C=1,a=T,t=d,f=24;\(rawRGB(width: 10, height: 20))"))

		terminal.write(String(repeating: "\r\n", count: 5_200))
		#expect(terminal.graphics.placements.isEmpty)
	}

	/// A picture is put on a screen, and a full-screen program gets a fresh one.
	@Test func aFullScreenProgramDoesNotSeeTheShellsPictures() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		#expect(terminal.graphics.placements.count == 1)

		terminal.write("\u{1B}[?1049h")
		#expect(terminal.graphics.placements.isEmpty)

		terminal.write("\u{1B}[?1049l")
		#expect(terminal.graphics.placements.count == 1)
	}

	@Test func aResetClearsThePicturesAway() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=20,v=40,C=1,a=T,t=d,f=24;\(rawRGB(width: 20, height: 40))"))
		terminal.write("\u{1B}c")

		#expect(terminal.graphics.placements.isEmpty)
		#expect(terminal.graphics.images.isEmpty)
	}

	/// A sequence the terminal does not recognise must not end up on the grid.
	@Test func anUnknownApcSequenceIsSwallowed() {
		let terminal = emulator()
		terminal.write("\u{1B}_Xsomething\u{1B}\\after")
		#expect(terminal.screen[0].text == "after")
	}

	@Test func aGraphicsCommandLeavesNothingOnTheGrid() {
		let terminal = emulator()
		terminal.write(graphics("i=1,s=1,v=1,C=1,a=T,t=d,f=24;\(rawRGB(width: 1, height: 1))"))
		terminal.write("text")
		#expect(terminal.screen[0].text == "text")
	}

	// MARK: - Asking about the size

	@Test func aProgramCanAskHowLargeACellIs() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}[16t")
		#expect(answered == "\u{1B}[6;20;10t")
	}

	@Test func aProgramCanAskHowLargeTheScreenIs() {
		let terminal = emulator(rows: 10, columns: 40)
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}[14t")
		#expect(answered == "\u{1B}[4;200;400t")
	}

	@Test func nothingIsClaimedBeforeTheCellSizeIsKnown() {
		let terminal = TerminalEmulator(rows: 10, columns: 40)
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}[16t")
		#expect(answered == nil)
	}

	/// The size in cells is known whether or not anybody has said how large a
	/// cell is, so that question is always answerable.
	@Test func theSizeInCellsIsAnsweredRegardless() {
		let terminal = TerminalEmulator(rows: 10, columns: 40)
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}[18t")
		#expect(answered == "\u{1B}[8;10;40t")
	}

	// MARK: - Helpers

	/// zlib, for the compressed-payload test — the wrapper `Compression` leaves
	/// off, added by hand exactly as `Gzip` does for its own format.
	private func zlib(_ data: Data) -> Data? {
		guard let deflated = Gzip.compress(data) else { return nil }
		// Gzip's own header is ten bytes and its trailer eight; what is between
		// them is the raw DEFLATE stream a zlib wrapper also carries.
		let body = deflated.dropFirst(10).dropLast(8)
		var output = Data([0x78, 0x9C])
		output.append(body)
		var adler = adler32(data).bigEndian
		withUnsafeBytes(of: &adler) { output.append(contentsOf: $0) }
		return output
	}

	private func adler32(_ data: Data) -> UInt32 {
		var a: UInt32 = 1, b: UInt32 = 0
		for byte in data {
			a = (a + UInt32(byte)) % 65521
			b = (b + a) % 65521
		}
		return (b << 16) | a
	}
	// MARK: - Getting rid of one


	/// Clearing the screen takes the picture with it.
	///
	/// It did not, and that is how a picture printed inside tmux stayed on
	/// screen: tmux repaints over what it cannot see, no program sends a delete
	/// for a picture it drew, and nothing short of restarting the app removed
	/// it.
	@Test func clearingTheScreenRemovesThePicture() {
		let terminal = emulator()
		terminal.write(graphics("a=T,s=20,v=20,f=24;\(rawRGB(width: 20, height: 20))"))
		#expect(!terminal.graphics.placements.isEmpty)

		terminal.write("\u{1B}[2J")
		#expect(terminal.graphics.placements.isEmpty)
	}

	/// Erasing from the cursor down takes the pictures below it, and leaves the
	/// ones above alone — the rows above were not erased.
	@Test func erasingPartOfTheScreenTakesOnlyWhatStoodThere() {
		let terminal = emulator(rows: 20, columns: 40)
		// One at the top, one further down.
		terminal.write(graphics("a=T,s=20,v=20,f=24;\(rawRGB(width: 20, height: 20))"))
		terminal.write("\u{1B}[10;1H")
		terminal.write(graphics("a=T,s=20,v=20,f=24;\(rawRGB(width: 20, height: 20))"))
		#expect(terminal.graphics.placements.count == 2)

		// From row 10 down.
		terminal.write("\u{1B}[10;1H\u{1B}[0J")
		#expect(terminal.graphics.placements.count == 1)
	}

	/// A picture that scrolled up into the scrollback is not erased by clearing
	/// the screen: the rows it stands on are still there to scroll back to.
	@Test func keepsWhatHasScrolledOutOfTheScreen() {
		let terminal = emulator(rows: 5, columns: 40)
		terminal.write(graphics("a=T,s=20,v=20,f=24;\(rawRGB(width: 20, height: 20))"))
		#expect(!terminal.graphics.placements.isEmpty)

		// Ten fresh lines push it into the scrollback.
		terminal.write(String(repeating: "line\r\n", count: 10))
		terminal.write("\u{1B}[2J")
		#expect(!terminal.graphics.placements.isEmpty)
	}
}

/// Sizing a placement, which is where a picture comes out squashed.
struct TerminalGraphicsSizingTests {
	private func emulator() -> TerminalEmulator {
		let terminal = TerminalEmulator(rows: 20, columns: 60)
		// Cells twice as tall as they are wide, which is roughly true of every
		// monospaced font and is what makes the arithmetic interesting.
		terminal.cellPixelSize = (width: 10, height: 20)
		return terminal
	}

	private func rawRGB(width: Int, height: Int) -> String {
		Data([UInt8](repeating: 0x40, count: width * height * 3)).base64EncodedString()
	}

	private func place(_ keys: String, width: Int, height: Int, in terminal: TerminalEmulator) {
		terminal.write(
			"\u{1B}_Gf=24,a=T,s=\(width),v=\(height),\(keys);\(rawRGB(width: width, height: height))\u{1B}\\"
		)
	}

	/// A square image given a width comes out square. Taking the pixel height
	/// instead drew a 32×32 picture twenty columns wide and two rows tall — a
	/// letterbox, which reads as a drawing bug rather than as arithmetic.
	@Test func aWidthAloneKeepsTheAspectRatio() throws {
		let terminal = emulator()
		place("c=20", width: 32, height: 32, in: terminal)

		let placement = try #require(terminal.graphics.placements.last)
		#expect(placement.columns == 20)
		// Twenty columns is 200 pixels wide; square means 200 tall; a cell is
		// 20 tall, so ten rows.
		#expect(placement.rows == 10)
	}

	@Test func aHeightAloneKeepsItToo() throws {
		let terminal = emulator()
		// Small on purpose: one command carries a limited payload, and a
		// hundred pixels of raw RGB is past it.
		place("r=4", width: 20, height: 10, in: terminal)

		let placement = try #require(terminal.graphics.placements.last)
		#expect(placement.rows == 4)
		// Four rows is 80 pixels; twice as wide is 160; a cell is 10 wide.
		#expect(placement.columns == 16)
	}

	/// Both given is both obeyed, however odd the result: a program that asked
	/// for a shape wanted that shape.
	@Test func bothGivenAreBothObeyed() throws {
		let terminal = emulator()
		place("c=8,r=8", width: 32, height: 32, in: terminal)

		let placement = try #require(terminal.graphics.placements.last)
		#expect(placement.columns == 8)
		#expect(placement.rows == 8)
	}

	/// Neither given is the picture at its own size, which is what it always
	/// was and what a program printing an icon expects.
	@Test func neitherGivenIsItsOwnSize() throws {
		let terminal = emulator()
		place("", width: 40, height: 40, in: terminal)

		let placement = try #require(terminal.graphics.placements.last)
		#expect(placement.columns == 4)
		#expect(placement.rows == 2)
	}
}
