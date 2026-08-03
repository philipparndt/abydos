import Testing
@testable import IdeaiKit

/// The Claude status cmanager writes onto a tmux window.
struct TmuxClaudeStatusTests {
	/// The line tmux prints with `@ai_status` in the format: index, active,
	/// command, status, then the name, which can hold anything.
	@Test func aWindowCarriesWhatItsSessionIsDoing() {
		let windows = TmuxMirror.parse("""
		0;1;node;working;ideai
		1;0;zsh;needs;docscanner
		2;0;node;done;pulse
		3;0;zsh;;plain shell
		""")

		#expect(windows.map(\.aiStatus) == [.working, .needsInput, .done, nil])
		#expect(windows.map(\.name) == ["ideai", "docscanner", "pulse", "plain shell"])
	}

	/// A name with a semicolon in it still arrives whole: the status field is
	/// counted before the name, not after it.
	@Test func theNameIsStillEverythingThatIsLeft() {
		let windows = TmuxMirror.parse("0;1;node;working;fix; then ship")
		#expect(windows.first?.name == "fix; then ship")
		#expect(windows.first?.aiStatus == .working)
	}

	/// Without cmanager the option is unset and every window reads the same as
	/// it always did.
	@Test func noStatusIsNotAFailureToParse() {
		let windows = TmuxMirror.parse("0;1;zsh;;zsh\n1;0;vim;;notes")
		#expect(windows.count == 2)
		#expect(windows.allSatisfy { $0.aiStatus == nil })
	}

	/// A line short of the full format is not read at all: a window called
	/// "one; two" is a real thing, and guessing which semicolon separates a
	/// field from a name would cut such a name in half.
	@Test func aShortLineIsNotGuessedAt() {
		#expect(TmuxMirror.parse("0;1;zsh;ideai").isEmpty)
	}

	/// Anything cmanager has not written — a value from a newer version, or
	/// somebody else's use of the same option — is not guessed at.
	@Test func anUnknownValueIsNoStatus() {
		#expect(TmuxMirror.parse("0;1;node;thinking;ideai").first?.aiStatus == nil)
	}
}
