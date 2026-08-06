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
		0;1;node;working;\(stamp);ideai
		1;0;zsh;needs;\(stamp);docscanner
		2;0;node;done;\(stamp);pulse
		3;0;zsh;;\(stamp);plain shell
		""", now: Self.now)

		#expect(windows.map(\.aiStatus) == [.working, .needsInput, .done, nil])
		#expect(windows.map(\.name) == ["ideai", "docscanner", "pulse", "plain shell"])
	}

	/// A name with a semicolon in it still arrives whole: the status field is
	/// counted before the name, not after it.
	@Test func theNameIsStillEverythingThatIsLeft() {
		let windows = TmuxMirror.parse("0;1;node;working;\(stamp);fix; then ship", now: Self.now)
		#expect(windows.first?.name == "fix; then ship")
		#expect(windows.first?.aiStatus == .working)
	}

	/// Without cmanager the option is unset and every window reads the same as
	/// it always did.
	@Test func noStatusIsNotAFailureToParse() {
		let windows = TmuxMirror.parse("0;1;zsh;;\(stamp);zsh\n1;0;vim;;\(stamp);notes", now: Self.now)
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
		0;1;node;working;\(quiet);stale
		1;0;node;working;\(stamp);really working
		2;0;node;needs;\(quiet);waiting for me
		3;0;node;done;\(quiet);finished ages ago
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
		#expect(TmuxMirror.parse("0;1;node;thinking;\(stamp);ideai", now: Self.now)
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
