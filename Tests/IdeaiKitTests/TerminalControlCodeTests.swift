import Foundation
import Testing
@testable import IdeaiKit

/// The sequences a program uses to talk to the terminal about something other
/// than drawing: the clipboard, the colours, its own cursor, and links.
struct TerminalControlCodeTests {
	private func emulator() -> TerminalEmulator {
		TerminalEmulator(rows: 10, columns: 40)
	}

	// MARK: - OSC 52, the clipboard

	@Test func aProgramCanPutSomethingOnTheClipboard() {
		let terminal = emulator()
		var written: String?
		terminal.onClipboardWrite = { written = $0 }

		let payload = Data("copied from tmux".utf8).base64EncodedString()
		terminal.write("\u{1B}]52;c;\(payload)\u{1B}\\")
		#expect(written == "copied from tmux")
	}

	@Test func theBellAlsoEndsTheSequence() {
		let terminal = emulator()
		var written: String?
		terminal.onClipboardWrite = { written = $0 }
		terminal.write("\u{1B}]52;c;\(Data("bell".utf8).base64EncodedString())\u{07}")
		#expect(written == "bell")
	}

	/// Reading is refused. Anything that can run in a terminal could otherwise
	/// take whatever was last copied, which is a password as often as not.
	@Test func aProgramCannotReadTheClipboard() {
		let terminal = emulator()
		var written: String?
		var answered: String?
		terminal.onClipboardWrite = { written = $0 }
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}]52;c;?\u{1B}\\")
		#expect(written == nil)
		#expect(answered == nil, "silence, not an answer")
	}

	// MARK: - Colour queries

	@Test func theBackgroundCanBeAskedAbout() {
		let terminal = emulator()
		terminal.colourLookup = { query in
			query == .background ? (red: 0.1, green: 0.2, blue: 0.3) : nil
		}
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}]11;?\u{1B}\\")
		#expect(answered == "\u{1B}]11;rgb:199a/3333/4ccd\u{1B}\\")
	}

	@Test func aPaletteEntryCanBeAskedAbout() {
		let terminal = emulator()
		terminal.colourLookup = { query in
			query == .palette(4) ? (red: 0, green: 0, blue: 1) : nil
		}
		var answered: String?
		terminal.onResponse = { answered = $0 }

		terminal.write("\u{1B}]4;4;?\u{1B}\\")
		#expect(answered == "\u{1B}]4;4;rgb:0000/0000/ffff\u{1B}\\")
	}

	// MARK: - Focus

	@Test func focusIsOnlyReportedWhenAskedFor() {
		let terminal = emulator()
		#expect(!terminal.reportsFocus)
		terminal.write("\u{1B}[?1004h")
		#expect(terminal.reportsFocus)
		terminal.write("\u{1B}[?1004l")
		#expect(!terminal.reportsFocus)
	}

	// MARK: - Cursor shape

	@Test func aProgramCanAskForABarOrAnUnderline() {
		let terminal = emulator()
		#expect(terminal.cursorShape == .block)

		terminal.write("\u{1B}[5 q")
		#expect(terminal.cursorShape == .bar, "vim in insert mode")

		terminal.write("\u{1B}[3 q")
		#expect(terminal.cursorShape == .underline)

		terminal.write("\u{1B}[2 q")
		#expect(terminal.cursorShape == .block)

		// 0 means "whatever the terminal likes", which here is a block.
		terminal.write("\u{1B}[0 q")
		#expect(terminal.cursorShape == .block)
	}

	// MARK: - Hyperlinks

	@Test func textBetweenTheMarkersBelongsToTheAddress() {
		let terminal = emulator()
		terminal.write("\u{1B}]8;;https://example.com/x\u{1B}\\link\u{1B}]8;;\u{1B}\\ plain")

		let line = terminal.screen.line(at: 0)
		let cells = line?.cells ?? []
		#expect(cells.count >= 10)

		let linked = cells[0].attributes.link
		#expect(linked != 0)
		#expect(terminal.link(for: linked) == "https://example.com/x")

		// `link` is four cells; what follows belongs to nobody.
		#expect(cells[4].attributes.link == 0, "the marker closed the link")
	}

	/// The same address twice is one entry, not two: a page of links to the
	/// same place should not grow the table by a page.
	@Test func theSameAddressIsRemembered() {
		let terminal = emulator()
		terminal.write("\u{1B}]8;;https://example.com\u{1B}\\a\u{1B}]8;;\u{1B}\\")
		terminal.write("\u{1B}]8;;https://example.com\u{1B}\\b\u{1B}]8;;\u{1B}\\")

		let cells = terminal.screen.line(at: 0)?.cells ?? []
		#expect(cells[0].attributes.link == cells[1].attributes.link)
	}
}

/// Telling one key from another.
///
/// Enter and Shift+Enter are the same byte, as are Tab and Ctrl+I; a program
/// that wants to tell them apart has to ask, in one of two protocols.
struct TerminalKeyProtocolTests {
	private func emulator() -> TerminalEmulator {
		TerminalEmulator(rows: 10, columns: 40)
	}

	@Test func nothingChangesUntilAProgramAsks() {
		let terminal = emulator()
		#expect(!terminal.reportsModifiedKeys)
		#expect(terminal.encodeModifiedKey(code: 13, shift: true) == nil)
	}

	@Test func theKittyProtocolSaysWhichKeyAndWhichModifiers() {
		let terminal = emulator()
		terminal.write("\u{1B}[>1u")
		#expect(terminal.keyboardFlags == 1)

		#expect(terminal.encodeModifiedKey(code: 13, shift: true) == "\u{1B}[13;2u")
		#expect(terminal.encodeModifiedKey(code: 9, control: true) == "\u{1B}[9;5u")
		#expect(terminal.encodeModifiedKey(code: 13, option: true) == "\u{1B}[13;3u")
	}

	/// An unmodified key is what it always was. A protocol that changed those
	/// would break every program that only asked about the modified ones.
	@Test func aPlainKeyIsLeftAlone() {
		let terminal = emulator()
		terminal.write("\u{1B}[>1u")
		#expect(terminal.encodeModifiedKey(code: 13) == nil)
	}

	@Test func theFlagsCanBePushedAndPutBack() {
		let terminal = emulator()
		terminal.write("\u{1B}[>1u")
		terminal.write("\u{1B}[>15u")
		#expect(terminal.keyboardFlags == 15)
		terminal.write("\u{1B}[<1u")
		#expect(terminal.keyboardFlags == 1, "a program puts back what it found")
	}

	@Test func theProgramCanAskWhatIsSet() {
		let terminal = emulator()
		var answered: String?
		terminal.onResponse = { answered = $0 }
		terminal.write("\u{1B}[>5u")
		terminal.write("\u{1B}[?u")
		#expect(answered == "\u{1B}[?5u")
	}

	/// xterm's older spelling, which is what several programs still send.
	@Test func modifyOtherKeysUsesTheOlderForm() {
		let terminal = emulator()
		terminal.write("\u{1B}[>4;2m")
		#expect(terminal.modifyOtherKeys == 2)
		#expect(terminal.reportsModifiedKeys)
		#expect(terminal.encodeModifiedKey(code: 13, shift: true) == "\u{1B}[27;2;13~")

		terminal.write("\u{1B}[>4m")
		#expect(terminal.modifyOtherKeys == 0)
		#expect(!terminal.reportsModifiedKeys)
	}
}

/// Reading tmux's window list, for the mode where the tabs are its windows.
struct TmuxMirrorTests {
	@Test func readsIndexNameAndWhichIsActive() {
		let windows = TmuxMirror.parse("""
		0;0;zsh;;shell
		1;1;nvim;;editing
		2;0;go;;build
		""")

		#expect(windows.count == 3)
		#expect(windows[1].index == 1)
		#expect(windows[1].name == "editing")
		#expect(windows[1].isActive)
		#expect(windows[1].command == "nvim")
		#expect(!windows[0].isActive)
	}

	/// The name is whatever is left of the line, because a window can be called
	/// anything — semicolons included.
	@Test func aNameCanContainTheSeparator() {
		let windows = TmuxMirror.parse("3;1;zsh;;one; two; three")
		#expect(windows.first?.name == "one; two; three")
	}

	/// tmux numbers windows as it likes: a session with 1, 4 and 9 in it is
	/// ordinary, and the position on the strip is not the number.
	@Test func indexesAreNotPositions() {
		let windows = TmuxMirror.parse("1;0;zsh;;a\n4;0;zsh;;b\n9;1;zsh;;c")
		#expect(windows.map(\.index) == [1, 4, 9])
		#expect(windows.last?.isActive == true)
	}

	@Test func nothingAtAllIsNoWindows() {
		#expect(TmuxMirror.parse("").isEmpty)
		#expect(TmuxMirror.parse("nonsense\n").isEmpty)
	}
}

/// Reading tmux's session list, for switching between them from the tag.
struct TmuxSessionListTests {
	@Test func readsNameWindowsAndWhetherItIsAttached() {
		let sessions = TmuxMirror.parseSessions("""
		3;1;100;work
		1;0;200;notes
		""")

		#expect(sessions.count == 2)
		#expect(sessions[0] == .init(name: "work", windowCount: 3, isAttached: true, created: 100))
		#expect(sessions[1] == .init(name: "notes", windowCount: 1, isAttached: false, created: 200))
	}

	/// A session can be called anything, semicolons included, so the name is
	/// whatever is left of the line.
	@Test func aNameCanContainTheSeparator() {
		#expect(TmuxMirror.parseSessions("2;0;100;a;b").first?.name == "a;b")
	}

	/// tmux's own order: oldest first, which is what `C-b (` and `C-b )` walk
	/// through — not alphabetical, which would put a session called `0` in
	/// front of everything however long ago it was made.
	@Test func theyComeBackInTheOrderTmuxCyclesThem() {
		let sessions = TmuxMirror.parseSessions("""
		1;0;300;zshutil
		1;0;100;ahead
		2;1;200;ideai
		""")
		#expect(sessions.map(\.name) == ["ahead", "ideai", "zshutil"])
	}

	@Test func nothingAtAllIsNoSessions() {
		#expect(TmuxMirror.parseSessions("").isEmpty)
	}
}
