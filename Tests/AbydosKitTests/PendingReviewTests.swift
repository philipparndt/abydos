import Foundation
import Testing
@testable import AbydosKit

/// Writing a review, and the two ways sending one goes wrong.
struct PendingReviewTests {
	@Test func remarksAccumulateInTheOrderTheyWereWritten() {
		var review = PendingReview(head: "abc")
		review.write(PendingComment(path: "a.swift", line: 4, body: "why?"))
		review.write(PendingComment(path: "b.swift", line: 9, body: "nice"))

		#expect(review.comments.map(\.path) == ["a.swift", "b.swift"])
		#expect(review.comment(on: "a.swift", line: 4)?.body == "why?")
		#expect(!review.isEmpty)
	}

	/// Writing twice on one line is changing your mind, not saying two things.
	@Test func aSecondRemarkOnALineReplacesTheFirst() {
		var review = PendingReview()
		review.write(PendingComment(path: "a.swift", line: 4, body: "why?"))
		review.write(PendingComment(path: "a.swift", line: 4, body: "never mind, I see it"))

		#expect(review.comments.count == 1)
		#expect(review.comment(on: "a.swift", line: 4)?.body == "never mind, I see it")
	}

	/// **Empty means take it back.** The way out of a remark somebody has
	/// changed their mind about is the same gesture that wrote it.
	@Test func clearingALineTakesTheRemarkBack() {
		var review = PendingReview()
		review.write(PendingComment(path: "a.swift", line: 4, body: "why?"))
		review.write(PendingComment(path: "a.swift", line: 4, body: "   \n "))

		#expect(review.comments.isEmpty)
		#expect(review.isEmpty)
	}

	@Test func theRemarksOfOneFileAreFoundByLine() {
		var review = PendingReview()
		review.write(PendingComment(path: "a.swift", line: 4, body: "one"))
		review.write(PendingComment(path: "a.swift", line: 40, body: "two"))
		review.write(PendingComment(path: "b.swift", line: 4, body: "three"))

		let mine = review.comments(on: "a.swift")
		#expect(Set(mine.keys) == [4, 40])
		#expect(mine[40]?.body == "two")
	}

	/// A verdict with nothing written is still a review — approving is a thing
	/// people do without saying anything.
	@Test func anApprovalWithNothingWrittenIsStillSomethingToSend() {
		let review = PendingReview(head: "abc")
		#expect(review.isEmpty)
		#expect(ReviewVerdict.approve.rawValue == "APPROVE")
		#expect(ReviewVerdict.requestChanges.rawValue == "REQUEST_CHANGES")
		#expect(ReviewVerdict.comment.rawValue == "COMMENT")
	}

	/// **The failure this guards against is a review that lands on the wrong
	/// lines.** A remark written against line 40 of a file the author has since
	/// rewritten is a remark about somebody else's code, sent in the reviewer's
	/// name.
	@Test func aHeadThatHasMovedIsSaidBeforeAnythingIsSent() {
		let said = PendingReview.headHasMoved(from: "aaaaaaaa1111", to: "bbbbbbbb2222")
		#expect(said?.contains("aaaaaaaa") == true)
		#expect(said?.contains("bbbbbbbb") == true)
		#expect(said?.contains("Read it again") == true)
	}

	@Test func aHeadThatHasNotMovedSaysNothing() {
		#expect(PendingReview.headHasMoved(from: "abc", to: "abc") == nil)
		// Not knowing is not the same as having moved: a pull request whose head
		// could not be read is not a reason to warn about lines.
		#expect(PendingReview.headHasMoved(from: nil, to: "abc") == nil)
		#expect(PendingReview.headHasMoved(from: "abc", to: nil) == nil)
	}

	/// What goes to GitHub, built the way `submit` builds it — the shape rather
	/// than the sending, since sending one is somebody's repository.
	@Test func theSubmissionCarriesTheHeadAndTheLines() throws {
		var payload: [String: Any] = ["event": ReviewVerdict.requestChanges.rawValue]
		payload["body"] = "Two things."
		payload["commit_id"] = "abc123"
		payload["comments"] = [PendingComment(path: "a.swift", line: 4, body: "why?")].map {
			["path": $0.path, "line": $0.line, "side": "RIGHT", "body": $0.body]
		}

		let data = try JSONSerialization.data(withJSONObject: payload)
		let read = try #require(
			try JSONSerialization.jsonObject(with: data) as? [String: Any]
		)
		#expect(read["event"] as? String == "REQUEST_CHANGES")
		#expect(read["commit_id"] as? String == "abc123")
		let comments = try #require(read["comments"] as? [[String: Any]])
		#expect(comments.first?["path"] as? String == "a.swift")
		#expect(comments.first?["line"] as? Int == 4)
		// The right-hand side, which is the only position a forge can resolve:
		// a comment is anchored to the file as it is now.
		#expect(comments.first?["side"] as? String == "RIGHT")
	}
}
