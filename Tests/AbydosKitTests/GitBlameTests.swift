import Foundation
import Testing
@testable import AbydosKit

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
		#expect(lines.first?.path == "main.swift")
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


/// What git is asked, over a repository made here: moved code keeps its
/// author, and a formatting commit listed in the ignore file owns nothing.
struct GitBlameArgumentsTests {
	private func repository() throws -> URL {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("blame-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		_ = GitRepository.runSync(["config", "user.email", "a@example.org"], in: root)
		_ = GitRepository.runSync(["config", "user.name", "Ada"], in: root)
		return root
	}

	private func commit(_ message: String, as author: String, in root: URL) {
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(
			["-c", "user.name=\(author)", "-c", "user.email=\(author.lowercased())@example.org", "commit", "-q", "-m", message],
			in: root
		)
	}

	@Test func theArgumentsFollowMovesAndNameTheIgnoreFileOnlyWhenItIsThere() throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("main.swift")
		#expect(GitBlame.arguments(for: file, in: root) == ["blame", "--line-porcelain", "-M", "-C", "--", "main.swift"])
		try "".write(to: root.appendingPathComponent(".git-blame-ignore-revs"), atomically: true, encoding: .utf8)
		#expect(GitBlame.arguments(for: file, in: root) == [
			"blame", "--line-porcelain", "-M", "-C", "--ignore-revs-file", ".git-blame-ignore-revs", "--", "main.swift",
		])
	}

	@Test func aMovedBlockKeepsTheAuthorWhoWroteIt() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("main.swift")
		let block = (1...6).map { "let value\($0) = \($0) * \($0) + \($0)" }.joined(separator: "\n")
		try ("import Foundation\n\n" + block + "\n\nprint(value1)\n").write(to: file, atomically: true, encoding: .utf8)
		commit("the block", as: "Ada", in: root)
		try ("import Foundation\n\nprint(value1)\n\n" + block + "\n").write(to: file, atomically: true, encoding: .utf8)
		commit("moved the block down", as: "Grace", in: root)

		let lines = await GitBlame.lines(for: file, in: root)
		#expect(lines.count == 10)
		// The block is now lines 5 to 10, and still Ada's.
		#expect(lines[4...9].allSatisfy { $0.author == "Ada" }, "\(lines.map(\.author))")
	}

	@Test func aFormattingCommitInTheIgnoreFileOwnsNothing() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("main.swift")
		try "func a() {\nreturn 1\n}\n".write(to: file, atomically: true, encoding: .utf8)
		commit("the function", as: "Ada", in: root)
		try "func a() {\n\treturn 1\n}\n".write(to: file, atomically: true, encoding: .utf8)
		commit("indented", as: "Formatter", in: root)
		let formatting = GitRepository.runSync(["rev-parse", "HEAD"], in: root).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

		let without = await GitBlame.lines(for: file, in: root)
		#expect(without[1].author == "Formatter")

		try (formatting + "\n").write(to: root.appendingPathComponent(".git-blame-ignore-revs"), atomically: true, encoding: .utf8)
		let with = await GitBlame.lines(for: file, in: root)
		#expect(with[1].author == "Ada", "\(with.map(\.author))")
	}
}
