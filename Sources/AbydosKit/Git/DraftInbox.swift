import Foundation

/// Where a commit draft waits for the project it was asked for.
///
/// **A draft's answer used to have nowhere to land but the pane that asked for
/// it**, and that pane is neither long-lived nor tied to a project. `ChangesPane`
/// is thrown away and rebuilt whenever the sidebar tool is; a project switch
/// closes the commit page's tab and rebuilds the sidebar only once the new
/// project's branch read has finished. So a draft that came back after a switch
/// was lost one of two ways: the pane was gone and the answer was dropped
/// without a word, or the pane still on screen was the *old* project's, took the
/// draft, and the next session save wrote one project's words into another
/// project's file.
///
/// Keyed by repository root, so the answer belongs to the thing it describes
/// rather than to a view that happens to be alive. The pane hands its answer
/// here and asks here when it is built; a pane whose own root does not match
/// leaves the draft where it is.
///
/// **In memory, deliberately.** A draft describes the staged diff at the moment
/// it was asked for. After a quit and a reopen that diff may be anything, and a
/// stale draft offered as though it were fresh would describe a commit that no
/// longer exists. A project the window never returns to keeps its draft until
/// the app stops, and loses it then, which is the honest lifetime of an answer
/// about a moment.
public final class DraftInbox: @unchecked Sendable {
	private let lock = NSLock()
	private var drafts: [String: ClaudeDraft.Draft] = [:]

	public init() {}

	/// The key a root is filed under.
	///
	/// Standardised, so that the same checkout named two ways — a trailing
	/// slash, a `/private` prefix, a symlink somebody's shell resolved — is one
	/// project. The pane's root and the window's arrive from different places
	/// and only agree once this has been applied to both.
	private static func key(for root: URL) -> String {
		root.standardizedFileURL.resolvingSymlinksInPath().path
	}

	/// Keeps a draft for a project. A later one replaces an earlier one: asking
	/// again means the first answer is not the one wanted.
	public func hold(_ draft: ClaudeDraft.Draft, for root: URL) {
		lock.lock()
		drafts[Self.key(for: root)] = draft
		lock.unlock()
	}

	/// What is waiting for a project, without taking it.
	///
	/// For deciding whether a button should offer something, which happens on
	/// every refresh and must not consume the answer.
	public func peek(for root: URL) -> ClaudeDraft.Draft? {
		lock.lock()
		defer { lock.unlock() }
		return drafts[Self.key(for: root)]
	}

	/// Takes what is waiting, leaving the slot empty.
	public func take(for root: URL) -> ClaudeDraft.Draft? {
		lock.lock()
		defer { lock.unlock() }
		return drafts.removeValue(forKey: Self.key(for: root))
	}

	/// Throws away what is waiting, because the message it was offered against
	/// has been committed.
	public func discard(for root: URL) {
		lock.lock()
		drafts.removeValue(forKey: Self.key(for: root))
		lock.unlock()
	}
}
