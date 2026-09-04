import Foundation
import Testing
@testable import AbydosKit

/// Where a commit draft waits for the project it was asked for.
///
/// Reported: "as soon as the project is switched to continue the work on
/// something else in the mean time, the commit comment is not written back to
/// the right project." The answer had nowhere to land but the pane that asked,
/// and that pane is neither long-lived nor tied to a project.
struct DraftInboxTests {
	private func draft(_ summary: String) -> ClaudeDraft.Draft {
		ClaudeDraft.Draft(summary: summary, description: "why \(summary)")
	}

	private func root(_ name: String) -> URL {
		URL(fileURLWithPath: "/tmp/abydos-inbox/\(name)", isDirectory: true)
	}

	/// **The whole of the report, as one claim.** A draft asked for in one
	/// project is not found by another, whatever is on screen when it arrives.
	@Test func aDraftHeldForOneProjectIsNotFoundForAnother() {
		let inbox = DraftInbox()
		inbox.hold(draft("feat: a"), for: root("a"))

		#expect(inbox.peek(for: root("a"))?.summary == "feat: a")
		#expect(inbox.peek(for: root("b")) == nil)
	}

	@Test func takingADraftEmptiesItsSlot() {
		let inbox = DraftInbox()
		inbox.hold(draft("feat: a"), for: root("a"))

		#expect(inbox.take(for: root("a"))?.summary == "feat: a")
		#expect(inbox.take(for: root("a")) == nil)
		#expect(inbox.peek(for: root("a")) == nil)
	}

	/// Peeking is what a button's refresh does, several times a second while
	/// somebody types. It must not consume the answer it is asking about.
	@Test func peekingDoesNotTake() {
		let inbox = DraftInbox()
		inbox.hold(draft("feat: a"), for: root("a"))

		#expect(inbox.peek(for: root("a")) != nil)
		#expect(inbox.peek(for: root("a")) != nil)
		#expect(inbox.take(for: root("a")) != nil)
	}

	/// Asking again means the first answer is not the one wanted.
	@Test func asecondHoldReplacesTheFirst() {
		let inbox = DraftInbox()
		inbox.hold(draft("first"), for: root("a"))
		inbox.hold(draft("second"), for: root("a"))

		#expect(inbox.take(for: root("a"))?.summary == "second")
		#expect(inbox.peek(for: root("a")) == nil)
	}

	/// **One checkout named two ways is one project.** The pane's root and the
	/// window's arrive from different places, and a trailing slash is the way
	/// they differ most often.
	@Test func oneCheckoutNamedTwoWaysIsOneProject() {
		let inbox = DraftInbox()
		inbox.hold(draft("feat: a"), for: URL(fileURLWithPath: "/tmp/abydos-inbox/a/"))

		#expect(inbox.peek(for: URL(fileURLWithPath: "/tmp/abydos-inbox/a")) != nil)
		#expect(inbox.peek(for: URL(fileURLWithPath: "/tmp/abydos-inbox/a/")) != nil)
	}

	/// Committing throws the offer away: the message it was offered against is
	/// gone.
	@Test func discardingLeavesNothing() {
		let inbox = DraftInbox()
		inbox.hold(draft("feat: a"), for: root("a"))
		inbox.discard(for: root("a"))

		#expect(inbox.peek(for: root("a")) == nil)
	}

	/// Two projects, two drafts, neither disturbing the other.
	@Test func twoProjectsKeepTheirOwn() {
		let inbox = DraftInbox()
		inbox.hold(draft("in a"), for: root("a"))
		inbox.hold(draft("in b"), for: root("b"))

		#expect(inbox.take(for: root("b"))?.summary == "in b")
		#expect(inbox.peek(for: root("a"))?.summary == "in a")
	}
}
