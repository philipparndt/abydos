import Foundation
import Testing
@testable import AbydosKit

/// The Claude status cmanager writes onto a tmux window.
struct TmuxClaudeStatusTests {
	/// The line tmux prints with `@ai_status` in the format: index, active,
	/// command, status, then the name, which can hold anything.
	private static let now = Date(timeIntervalSince1970: 1_785_772_000)
	private var stamp: String { String(Int(Self.now.timeIntervalSince1970)) }

	@Test func aWindowCarriesWhatItsSessionIsDoing() {
		let windows = TmuxMirror.parse("""
		0;1;node;working;\(stamp);/Users/x/dev/ideai;ideai
		1;0;zsh;needs;\(stamp);/Users/x/dev/docscanner;docscanner
		2;0;node;done;\(stamp);/Users/x/dev/pulse;pulse
		3;0;zsh;;\(stamp);/Users/x/dev/plain shell;plain shell
		""", now: Self.now)

		#expect(windows.map(\.aiStatus) == [.working, .needsInput, .done, nil])
		#expect(windows.map(\.name) == ["ideai", "docscanner", "pulse", "plain shell"])
		// And where each pane is, which is what a record seeded from a badge is
		// filed under: a tmux session's windows sit in many projects.
		#expect(windows.map(\.directory) == [
			"/Users/x/dev/ideai", "/Users/x/dev/docscanner", "/Users/x/dev/pulse", "/Users/x/dev/plain shell",
		])
	}

	/// The shape before the pane's path was asked for is one field short, and
	/// is not guessed at either: its name would be taken for a path.
	@Test func theOlderShapeWithoutAPathIsNotGuessedAt() {
		#expect(TmuxMirror.parse("0;1;node;working;\(stamp);ideai", now: Self.now).isEmpty)
	}

	/// A name with a semicolon in it still arrives whole: the status field is
	/// counted before the name, not after it.
	@Test func theNameIsStillEverythingThatIsLeft() {
		let windows = TmuxMirror.parse("0;1;node;working;\(stamp);/Users/x/dev/ship;fix; then ship", now: Self.now)
		#expect(windows.first?.name == "fix; then ship")
		#expect(windows.first?.aiStatus == .working)
	}

	/// Without cmanager the option is unset and every window reads the same as
	/// it always did.
	@Test func noStatusIsNotAFailureToParse() {
		let windows = TmuxMirror.parse("0;1;zsh;;\(stamp);/Users/x;zsh\n1;0;vim;;\(stamp);/Users/x/notes;notes", now: Self.now)
		#expect(windows.count == 2)
		#expect(windows.allSatisfy { $0.aiStatus == nil })
	}

	/// A line short of the full format is not read at all: a window called
	/// "one; two" is a real thing, and guessing which semicolon separates a
	/// field from a name would cut such a name in half.
	@Test func aShortLineIsNotGuessedAt() {
		#expect(TmuxMirror.parse("0;1;zsh;ideai").isEmpty)
		#expect(TmuxMirror.parse("0;1;zsh;working;ideai").isEmpty)
	}

	/// A badge is a memory of the last event, and events go missing: a session
	/// that was working when the app was closed, one that was already running
	/// before the hooks were installed, a Claude killed mid-turn. Claude prints
	/// constantly while it works, so a working window that has said nothing for
	/// half a minute is not working.
	@Test func aWorkingWindowThatHasGoneQuietIsNotBelieved() {
		let quiet = String(Int(Self.now.timeIntervalSince1970) - 120)
		let windows = TmuxMirror.parse("""
		0;1;node;working;\(quiet);/Users/x/stale;stale
		1;0;node;working;\(stamp);/Users/x/dev/really working;really working
		2;0;node;needs;\(quiet);/Users/x/waiting;waiting for me
		3;0;node;done;\(quiet);/Users/x/finished;finished ages ago
		""", now: Self.now)

		#expect(windows[0].shownStatus == nil, "silent for two minutes")
		#expect(windows[1].shownStatus == .working)
		// These two are states a session sits in quietly until somebody comes
		// back to it, so time says nothing about them.
		#expect(windows[2].shownStatus == .needsInput)
		#expect(windows[3].shownStatus == .done)
	}

	/// Anything cmanager has not written — a value from a newer version, or
	/// somebody else's use of the same option — is not guessed at.
	@Test func anUnknownValueIsNoStatus() {
		#expect(TmuxMirror.parse("0;1;node;thinking;\(stamp);/Users/x/ideai;ideai", now: Self.now)
			.first?.aiStatus == nil)
	}
}

/// Carrying a window's state across a change of which one is active.
struct TmuxWindowCopyTests {
	/// A tab switch rebuilds the list with a different window marked active,
	/// and everything else has to survive that. It did not: the badges blanked
	/// on every switch until the next poll, which read as the tabs jumping.
	@Test func markingOneActiveKeepsTheRest() {
		let before = TmuxMirror.Window(
			index: 2, name: "docscanner", isActive: false,
			command: "node", aiStatus: .needsInput, silentFor: 12
		)
		let after = TmuxMirror.Window(
			index: before.index, name: before.name, isActive: true,
			command: before.command, aiStatus: before.aiStatus, silentFor: before.silentFor
		)

		#expect(after.isActive)
		#expect(after.aiStatus == .needsInput)
		#expect(after.silentFor == 12)
		#expect(after.shownStatus == .needsInput)
	}
}

/// Remembering which window somebody was in.
struct TmuxWindowIdentityTests {
	@Test func theWindowIdIsReadWhenItIsThere() throws {
		let windows = TmuxMirror.parse("@7;2;1;zsh;;0;/Users/x;editing\n@9;3;0;vim;;0;/Users/x;notes")
		#expect(windows.count == 2)
		#expect(windows.first?.windowID == "@7")
		#expect(windows.first?.index == 2)
		#expect(windows.first?.name == "editing")
		#expect(windows.last?.windowID == "@9")
	}

	/// A line without one is the older shape, and still reads.
	@Test func aLineWithoutAnIdStillReads() {
		let windows = TmuxMirror.parse("2;1;zsh;;0;/Users/x;editing")
		#expect(windows.first?.index == 2)
		#expect(windows.first?.name == "editing")
		#expect(windows.first?.windowID == "")
	}

	/// A name can hold a semicolon, so the id is taken off by recognising it
	/// rather than by counting fields — which is how the first attempt at this
	/// dropped every window whose name had one in it.
	@Test func aNameWithSeparatorsSurvivesEitherShape() {
		let withID = TmuxMirror.parse("@4;1;1;zsh;;0;/Users/x;one; two; three")
		#expect(withID.first?.windowID == "@4")
		#expect(withID.first?.name == "one; two; three")

		let without = TmuxMirror.parse("1;1;zsh;;0;/Users/x;one; two; three")
		#expect(without.first?.name == "one; two; three")
	}

	/// And a name that merely starts with an at sign is a name, not an id.
	@Test func aNameBeginningWithAnAtSignIsNotAnId() {
		let windows = TmuxMirror.parse("1;1;zsh;;0;/Users/x;@home")
		#expect(windows.first?.name == "@home")
		#expect(windows.first?.windowID == "")
	}
}

/// Remembering the window a project was left in.
struct SessionTmuxWindowTests {
	private func roundTrip(_ session: ProjectSession) throws -> ProjectSession? {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("session-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		try SessionStore.write(session, in: root)
		return SessionStore.read(in: root)
	}

	@Test func theWindowSurvivesBeingWrittenAndRead() throws {
		let written = ProjectSession(
			terminals: [ProjectSession.OpenTerminal(name: "tmux")],
			tmuxWindow: "@7"
		)
		#expect(try roundTrip(written)?.tmuxWindow == "@7")
	}

	/// On its own it is still worth keeping: coming back to the window somebody
	/// was in should work for a project with nothing else open.
	@Test func aWindowOnItsOwnIsWorthWriting() throws {
		let written = ProjectSession(tmuxWindow: "@3")
		#expect(!written.isEmpty)
		#expect(try roundTrip(written)?.tmuxWindow == "@3")
	}

	/// A session saved before any of this existed reads as having none, rather
	/// than failing to read.
	@Test func anOlderSessionSimplyHasNoWindow() throws {
		let written = ProjectSession(terminals: [ProjectSession.OpenTerminal(name: "tmux")])
		#expect(written.tmuxWindow == nil)
		#expect(try roundTrip(written)?.tmuxWindow == nil)
	}

	/// Leaving a project by hand records the window that was on screen.
	@Test func closingAProjectRemembersTheWindowShowing() {
		#expect(ProjectSession.rememberedWindow(
			showing: "@2", stored: "@2", followingTerminal: false
		) == "@2")
	}

	/// And leaving it because the terminal moved records nothing new.
	///
	/// This is the ping-pong: the window showing (`@2`) belongs to the project
	/// being *opened*, since selecting it is what caused the switch. Written
	/// down here, the project being closed would select `@2` when it next
	/// opened, moving the shell into the other checkout, switching the project
	/// back, and round again about once a second.
	@Test func followingTheTerminalDoesNotRecordTheWindowItMovedTo() {
		#expect(ProjectSession.rememberedWindow(
			showing: "@2", stored: "@0", followingTerminal: true
		) == "@0")
	}

	/// Nothing stored and nothing to keep: better no window than the wrong one.
	@Test func followingWithNothingRememberedStaysNothing() {
		#expect(ProjectSession.rememberedWindow(
			showing: "@2", stored: nil, followingTerminal: true
		) == nil)
	}
}

/// What this app runs to put a terminal into a project's session.
struct TmuxAttachTests {
	/// `new -A` — attach if it exists, make it if it does not — and then the
	/// session is told to carry escapes through.
	///
	/// Both commands this app ships talk to the window through an escape tmux
	/// would otherwise eat, and `allow-passthrough` is off unless somebody has
	/// turned it on. Without this, `abydos <file>` and `abydos-icat` do nothing
	/// in the terminal this app starts — the one they are certain to be run in.
	@Test func attachingAsksTheSessionToCarryEscapes() {
		#expect(TmuxMirror.attachArguments(to: "abydos") == [
			"new", "-A", "-s", "abydos",
			";", "set-option", "-q", "-t", "abydos", "allow-passthrough", "on",
		])
	}

	/// One session, not the server: nothing is written to anybody's config and
	/// no session this app did not bring up is touched. `-g` here would take the
	/// decision for every session on the machine, including the ones somebody
	/// was already working in.
	@Test func onlyForTheSessionItBringsUp() {
		let arguments = TmuxMirror.attachArguments(to: "notes")
		#expect(!arguments.contains("-g"))
		#expect(arguments.filter { $0 == "notes" }.count == 2)
	}

	/// Quietly, because tmux learned `allow-passthrough` in 3.3. On anything
	/// older the right outcome is the behaviour there has always been, not an
	/// error printed into somebody's shell.
	@Test func anOlderTmuxIsNotToldOff() {
		#expect(TmuxMirror.attachArguments(to: "x").contains("-q"))
	}
}
