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
