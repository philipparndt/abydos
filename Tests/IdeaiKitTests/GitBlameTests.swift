import Foundation
import Testing
@testable import IdeaiKit

/// Reading `git blame --line-porcelain`.
///
/// The fixtures are what git prints, awkward parts included: an author whose
/// name has spaces in it, a line nobody has committed, and a commit with no
/// summary at all.
struct GitBlameTests {
	private let output = """
	3fa1b2c4d5e6f708192a3b4c5d6e7f8091a2b3c4 1 1 1
	author Philipp Arndt
	author-mail <pa@example.com>
	author-time 1750000000
	author-tz +0200
	committer Philipp Arndt
	committer-time 1750000000
	summary the first line
	filename main.swift
		import Foundation
	3fa1b2c4d5e6f708192a3b4c5d6e7f8091a2b3c4 2 2 1
	author Philipp Arndt
	author-mail <pa@example.com>
	author-time 1750000000
	author-tz +0200
	summary the first line
	filename main.swift
		
	0000000000000000000000000000000000000000 3 3 1
	author Not Committed Yet
	author-mail <not.committed.yet>
	author-time 1750003600
	author-tz +0200
	summary Version of main.swift from main.swift
	filename main.swift
		let x = 1
	"""

	@Test func everyLineIsAccountedFor() {
		let lines = GitBlame.parse(output)
		#expect(lines.count == 3)
	}

	@Test func aLineKnowsItsCommitAndAuthor() {
		let lines = GitBlame.parse(output)
		#expect(lines.first?.author == "Philipp Arndt")
		#expect(lines.first?.summary == "the first line")
		#expect(lines.first?.commit.hasPrefix("3fa1b2c4") == true)
		#expect(lines.first?.date == Date(timeIntervalSince1970: 1_750_000_000))
	}

	/// The line being typed right now belongs to nobody yet, and saying it
	/// belongs to whoever last committed there would be a lie.
	@Test func anUncommittedLineIsMarkedAsSuch() {
		let lines = GitBlame.parse(output)
		#expect(lines.last?.isUncommitted == true)
		#expect(lines.last?.label(width: 20) == "Uncommitted")
		#expect(lines.first?.isUncommitted == false)
	}

	@Test func nothingToBlameYieldsNothing() {
		#expect(GitBlame.parse("").isEmpty)
	}

	// MARK: - What the column says

	@Test func theAgeIsSaidTheWayGitSaysIt() {
		let now = Date(timeIntervalSince1970: 1_750_000_000)
		func age(_ seconds: TimeInterval) -> String {
			GitBlame.Line.age(from: now - seconds, to: now)
		}
		#expect(age(30) == "1m")
		#expect(age(60 * 45) == "45m")
		#expect(age(60 * 60 * 5) == "5h")
		#expect(age(60 * 60 * 24 * 3) == "3d")
		#expect(age(60 * 60 * 24 * 60) == "2mo")
		#expect(age(60 * 60 * 24 * 800) == "2y")
	}

	/// The column sits beside the code, so a long name gives way rather than
	/// pushing the text along.
	@Test func aLongNameIsShortenedRatherThanTruncatingTheDate() {
		let line = GitBlame.Line(
			commit: "abc", author: "Bartholomew Cunningham",
			date: Date(timeIntervalSince1970: 1_750_000_000), summary: "x"
		)
		let label = line.label(width: 16, now: Date(timeIntervalSince1970: 1_750_000_000 + 3600 * 5))
		#expect(label.hasSuffix("5h"))
		#expect(label.count <= 16)
		#expect(label.contains("Cunningham"), "the surname is what identifies somebody")
	}

	@Test func aShortNameIsLeftAlone() {
		#expect(GitBlame.Line.shorten("Philipp", to: 12) == "Philipp")
		#expect(GitBlame.Line.shorten("Philipp Arndt", to: 8) == "P. Arndt")
	}
}
