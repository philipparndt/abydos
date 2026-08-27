import Foundation
import Testing
@testable import AbydosKit

/// Ticks that outlive the window they were made in.
///
/// A review takes more than one sitting. Coming back to a pull request whose
/// list has forgotten which four files you read is coming back to the beginning,
/// which is exactly the thing a checklist is for.
struct ReviewTickSessionTests {
	private func scratch() -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-review-ticks-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func theTicksComeBackWithTheirTokens() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		let session = ProjectSession(
			reviewTicks: ["41": ["a.swift": "aaa", "dir/b.swift": "bbb"], "42": ["c.swift": "ccc"]]
		)
		// `driven: false`, because a driven run deliberately reads and writes
		// nothing beside somebody's project — see `SessionStore`.
		try SessionStore.write(session, in: root, driven: false)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.reviewTicks["41"]?["a.swift"] == "aaa")
		#expect(read.reviewTicks["41"]?["dir/b.swift"] == "bbb")
		#expect(read.reviewTicks["42"] == ["c.swift": "ccc"])
	}

	/// **The token has to travel.** Without it the ticks cannot be checked when
	/// the page opens again, and a set of ticks that cannot be checked is the
	/// false record the whole feature is against.
	@Test func aRememberedTickIsACheckedTick() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(reviewTicks: ["7": ["a.swift": "old", "b.swift": "same"]]),
			in: root, driven: false
		)
		let stored = try #require(SessionStore.read(in: root, driven: false)?.reviewTicks["7"])

		var list = Checklist(done: Set(stored.keys), tokens: stored)
		let cleared = list.revalidate(against: ["a.swift": "rewritten", "b.swift": "same"])

		#expect(cleared == ["a.swift"])
		#expect(list.isDone("b.swift"))
	}

	/// **The mark is this program's state, not a fact about the repository.**
	/// Writing it into `.git` would be writing somebody else's file: git has no
	/// notion of a worktree belonging to anything, and a `git worktree remove`
	/// from a terminal would leave the note behind.
	@Test func theCheckoutMarksComeBackToo() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(reviewCheckouts: ["/tmp/thing-pr-7": 7]), in: root, driven: false
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.reviewCheckouts == ["/tmp/thing-pr-7": 7])
		// And nothing at all is written into the repository's own state.
		#expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path))
	}

	@Test func aCheckoutMarkIsHeldByPathAndForgotten() {
		let marks = ReviewCheckouts()
		let path = URL(fileURLWithPath: "/tmp/abydos-pr-9")

		marks.mark(path, as: 9)
		#expect(marks.number(of: path) == 9)
		// The same directory said a different way is the same directory.
		#expect(marks.number(of: URL(fileURLWithPath: "/tmp/./abydos-pr-9")) == 9)

		marks.forget(path)
		#expect(marks.number(of: path) == nil)
	}

	/// Restoring keeps what the window already knows: a mark made a moment ago
	/// is newer than one read off disk.
	@Test func restoringDoesNotOverwriteWhatIsKnown() {
		let marks = ReviewCheckouts()
		marks.mark(URL(fileURLWithPath: "/tmp/a"), as: 1)
		marks.restore(["/tmp/a": 2, "/tmp/b": 3])

		#expect(marks.number(of: URL(fileURLWithPath: "/tmp/a")) == 1)
		#expect(marks.number(of: URL(fileURLWithPath: "/tmp/b")) == 3)
	}

	/// The local branch is named for the number and not for the head branch: a
	/// pull request from a fork is called `patch-1`, and so are the other four.
	@Test func theBranchIsNamedForTheNumber() {
		#expect(PullRequestCheckout.branchName(for: 41) == "pr-41")
		let root = URL(fileURLWithPath: "/tmp/dev/thing")
		#expect(PullRequestCheckout.path(for: 41, in: root).lastPathComponent == "thing-pr-41")
		// Beside the repository, never inside it — a worktree within the work
		// tree shows up as an untracked directory in its own status.
		#expect(
			PullRequestCheckout.path(for: 41, in: root).deletingLastPathComponent().path
				== "/tmp/dev"
		)
	}

	/// Ticks alone are worth writing a session file for: somebody who has read
	/// half a pull request and closed every tab has still read half of it.
	@Test func ticksAloneAreASessionWorthKeeping() {
		#expect(!ProjectSession(reviewTicks: ["1": ["a": "b"]]).isEmpty)
		#expect(ProjectSession().isEmpty)
	}

	/// This is JSON on disk that anything may have written. A number that is not
	/// one, a tick that is not a string: dropped, which shows the file as unread
	/// — and showing is the safe direction.
	@Test func nonsenseInTheFileIsDroppedRatherThanBelieved() {
		#expect(SessionStore.readReviewTicks(nil).isEmpty)
		#expect(SessionStore.readReviewTicks("not an object at all").isEmpty)
		#expect(SessionStore.readReviewTicks(["notanumber": ["a": "b"]]).isEmpty)
		#expect(SessionStore.readReviewTicks(["3": ["a": 7]]).isEmpty)
		#expect(SessionStore.readReviewTicks(["3": [:]]).isEmpty)
		#expect(SessionStore.readReviewTicks(["3": ["a": "b", "c": 7]]) == ["3": ["a": "b"]])
	}

	/// A session written before any of this existed says nothing about reading,
	/// which reads as nobody having read anything.
	@Test func anOlderSessionHasNoOpinion() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try AbydosFolder.create(in: root)
		try Data(#"{"files":[{"path":"main.swift","line":3}]}"#.utf8)
			.write(to: AbydosFolder.sessionFile(in: root))

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.files.first?.path == "main.swift")
		#expect(read.reviewTicks.isEmpty)
	}
}
