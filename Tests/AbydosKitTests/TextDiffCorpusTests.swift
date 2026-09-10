import Foundation
import Testing
@testable import AbydosKit

/// What `TextDiff` makes of edits somebody actually wrote, beside what git makes
/// of the same ones.
///
/// The design left one question open: whether patience or histogram refinement
/// is worth its cost over plain Myers. Myers is minimal and occasionally silly —
/// a closing brace matched to the wrong function, splitting one edit into two
/// around a line that means nothing. The question cannot be answered on taste,
/// and it cannot be answered on the corpus `Scripts/corpus.sh` clones either:
/// those clones are `--depth 1`, so they hold exactly one version of everything
/// and a diff is of two. **A revision pair is the subject** — a file as one
/// commit found it and as that commit left it — and any repository with history
/// is full of them.
///
/// git implements all three algorithms, so what they do differently is asked of
/// git rather than written twice here. What this suite adds is the fourth row:
/// where our own diff sits beside them on the same pairs.
///
/// Three numbers per algorithm, none of them a duration:
///
/// - **changes** — the maximal runs of non-equal rows, which is what the reader
///   walks with the two arrows and what a curve is drawn for.
/// - **changed lines** — removals and additions together. A shorter diff of the
///   same edit is a better description of it.
/// - **lone anchors** — an unchanged *trivial* line with a change on either
///   side of it: a brace, a bracket, a blank, a comment terminator. This is the
///   silly match the design worried about, made countable. The diff claimed the
///   brace closing one function is the brace closing another and split the edit
///   around it.
///
/// Asked for rather than merely possible, like the rest of the corpus work: it
/// spawns two processes per pair to read the pair and three more to ask git,
/// which is minutes rather than seconds.
///
///     make test SCALE=1 FILTER=TextDiffCorpusTests
struct TextDiffCorpusTests {
	/// A file as a commit found it and as that commit left it.
	struct Pair {
		let path: String
		let commit: String
		let before: String
		let after: String
	}

	/// What one algorithm made of a corpus of pairs.
	struct Tally {
		var changes = 0
		var lines = 0
		var lone = 0
		var seconds = 0.0

		mutating func add(changes: Int, lines: Int, lone: Int) {
			self.changes += changes
			self.lines += lines
			self.lone += lone
		}
	}

	// MARK: - The subject

	/// What one `git` said, or a stop.
	///
	/// **A failure here is not an empty diff**, and the first version of this
	/// returned `""` for both. Five processes per pair over two thousand pairs
	/// is ten thousand spawns; when one of them failed to start, the pair was
	/// counted as a file git found nothing to say about, and the totals came out
	/// different on every run — 12,852, then 12,727, then 9,342 for the same
	/// corpus, against a number of ours that never moved. A measurement that
	/// reports zero when it means "I could not ask" is worse than one that
	/// stops, because it is believed.
	///
	/// The other half of the same lesson is the stderr sink. It was a `Pipe`
	/// nobody read, which is two descriptors per call held until the object
	/// went away, on top of the two for stdout.
	static func git(_ arguments: [String], in directory: URL) throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", directory.path] + arguments
		let out = Pipe()
		process.standardOutput = out
		process.standardError = FileHandle.nullDevice
		try process.run()
		// The whole pipe read before waiting: a diff larger than the pipe buffer
		// deadlocks the other way round, and a quarter of a megabyte is ordinary
		// here.
		let data = out.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		try out.fileHandleForReading.close()
		return String(data: data, encoding: .utf8) ?? ""
	}

	/// The pairs in a repository's recent history, largest first is not needed —
	/// what matters is that both halves are real text of a size where the
	/// algorithms have room to disagree. A forty-line file is diffed the same
	/// way by all of them.
	static func pairs(in repository: URL, commits: Int, extensions: [String]) throws -> [Pair] {
		let log = try git(["log", "--format=%H", "--no-merges", "-\(commits)"], in: repository)
		var found: [Pair] = []
		for commit in log.split(separator: "\n").map(String.init) {
			let names = try git(
				["diff-tree", "--no-commit-id", "--name-only", "-r", "-M", commit], in: repository)
			for path in names.split(separator: "\n").map(String.init) {
				guard extensions.contains(where: { path.hasSuffix($0) }) else { continue }
				// A file this commit added has no `commit~1:path`, and the
				// oldest commit of a shallow clone has no parent at all: git
				// says so on stderr and prints nothing, which is the one case
				// where nothing back is an answer rather than a failure.
				let before = (try? git(["show", "\(commit)~1:\(path)"], in: repository)) ?? ""
				let after = (try? git(["show", "\(commit):\(path)"], in: repository)) ?? ""
				guard !before.isEmpty, !after.isEmpty, before != after,
				      before.count(where: { $0 == "\n" }) >= 40,
				      after.count(where: { $0 == "\n" }) >= 40
				else { continue }
				found.append(Pair(path: path, commit: String(commit.prefix(8)),
				                  before: before, after: after))
			}
		}
		return found
	}

	// MARK: - The three numbers

	/// A line that says nothing on its own, and so should never be the reason
	/// two edits are shown as two.
	static func isTrivial(_ line: String) -> Bool {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		if trimmed.isEmpty { return true }
		if trimmed.allSatisfy({ "{}()[];,".contains($0) }) { return true }
		return ["*/", "/*", "//", "*", "<!--", "-->", "---", "```"].contains(trimmed)
	}

	/// Our own diff, counted the way the git ones are.
	static func ours(_ pair: Pair) -> (changes: Int, lines: Int, lone: Int) {
		let diff = TextDiff(pair.before, pair.after)
		// A changed pair is a removal and an addition, which is how git counts
		// the same row.
		let lines = diff.counts.additions + diff.counts.deletions + diff.counts.changes * 2
		var lone = 0
		for index in 1..<max(1, diff.rows.count - 1) {
			guard diff.rows[index].kind == .equal,
			      diff.rows[index - 1].kind != .equal,
			      diff.rows[index + 1].kind != .equal,
			      let left = diff.rows[index].left,
			      left < diff.leftLines.count,
			      isTrivial(diff.leftLines[left])
			else { continue }
			lone += 1
		}
		return (diff.changes.count, lines, lone)
	}

	/// What git makes of the same pair, through one of its three algorithms.
	///
	/// `-U0`, so the hunks are the changes and the gaps between them are the
	/// unchanged lines: a gap of exactly one on both sides is the lone anchor.
	static func theirs(_ algorithm: String, left: URL, right: URL, lines leftLines: [String])
		throws -> (changes: Int, lines: Int, lone: Int) {
		let out = try git(
			["diff", "--no-index", "--diff-algorithm=\(algorithm)", "-U0", "--no-color",
			 left.path, right.path],
			in: left.deletingLastPathComponent())
		var hunks: [(Int, Int, Int, Int)] = []
		var changed = 0
		for line in out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
			if line.hasPrefix("@@") {
				// `@@ -l,s +l,s @@`, where a count of one is left out.
				let parts = line.split(separator: " ")
				guard parts.count >= 3 else { continue }
				func span(_ text: Substring) -> (Int, Int) {
					let numbers = text.dropFirst().split(separator: ",").compactMap { Int($0) }
					return (numbers.first ?? 0, numbers.count > 1 ? numbers[1] : 1)
				}
				let (ls, ll) = span(parts[1])
				let (rs, rl) = span(parts[2])
				hunks.append((ls, ll, rs, rl))
			} else if (line.hasPrefix("+") || line.hasPrefix("-")),
			          !line.hasPrefix("+++"), !line.hasPrefix("---") {
				changed += 1
			}
		}
		var lone = 0
		for index in 0..<max(0, hunks.count - 1) {
			let (ls, ll, rs, rl) = hunks[index]
			let (ns, _, nrs, _) = hunks[index + 1]
			// A hunk of length zero is anchored *after* the line it names.
			let leftGap = ns - (ls + ll) - (ll == 0 ? 1 : 0)
			let rightGap = nrs - (rs + rl) - (rl == 0 ? 1 : 0)
			guard leftGap == 1, rightGap == 1 else { continue }
			let between = ls + ll - (ll == 0 ? 1 : 0)
			guard between >= 1, between <= leftLines.count, isTrivial(leftLines[between - 1])
			else { continue }
			lone += 1
		}
		return (hunks.count, changed, lone)
	}

	// MARK: - The measurement

	static func measure(_ name: String, repository: URL, commits: Int, extensions: [String]) throws {
		let found = try pairs(in: repository, commits: commits, extensions: extensions)
		guard !found.isEmpty else {
			print("DIFF \(name): no pairs in \(repository.path)")
			return
		}
		let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-diff-corpus-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: scratch) }

		let algorithms = ["myers", "patience", "histogram"]
		var tallies: [String: Tally] = ["ours": Tally()]
		for algorithm in algorithms { tallies[algorithm] = Tally() }
		var disagreed = 0
		var longer: [(path: String, commit: String, ours: Int, theirs: Int)] = []

		for pair in found {
			let extension_ = (pair.path as NSString).pathExtension
			let left = scratch.appendingPathComponent("a").appendingPathExtension(extension_)
			let right = scratch.appendingPathComponent("b").appendingPathExtension(extension_)
			try pair.before.write(to: left, atomically: true, encoding: .utf8)
			try pair.after.write(to: right, atomically: true, encoding: .utf8)
			let leftLines = TextDiff.lines(of: pair.before)

			let startedOurs = DispatchTime.now().uptimeNanoseconds
			let mine = ours(pair)
			tallies["ours"]!.seconds
				+= Double(DispatchTime.now().uptimeNanoseconds - startedOurs) / 1_000_000_000
			tallies["ours"]!.add(changes: mine.changes, lines: mine.lines, lone: mine.lone)

			var shapes = Set<Int>()
			for algorithm in algorithms {
				let started = DispatchTime.now().uptimeNanoseconds
				let result = try theirs(algorithm, left: left, right: right, lines: leftLines)
				tallies[algorithm]!.seconds
					+= Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
				tallies[algorithm]!.add(
					changes: result.changes, lines: result.lines, lone: result.lone)
				shapes.insert(result.changes &* 31 &+ result.lines)
				// Where we are longer than git's Myers, and by how much. An
				// average hides this: the gap lives in a handful of pairs and
				// is invisible spread over two thousand.
				if algorithm == "myers", mine.lines > result.lines {
					longer.append((pair.path, pair.commit, mine.lines, result.lines))
				}
			}
			if shapes.count > 1 { disagreed += 1 }
		}

		print("DIFF \(name): \(found.count) revision pairs; git's three algorithms "
			+ "describe \(disagreed) of them differently "
			+ String(format: "(%.1f%%). ", 100 * Double(disagreed) / Double(found.count))
			+ MachineLoad.said)
		print(String(format: "DIFF %-12s %10s %14s %13s %10s",
			("subject" as NSString).utf8String!, ("changes" as NSString).utf8String!,
			("changed lines" as NSString).utf8String!, ("lone anchors" as NSString).utf8String!,
			("seconds" as NSString).utf8String!))
		for key in ["ours"] + algorithms {
			let tally = tallies[key]!
			print(String(format: "DIFF %-12s %10d %14d %13d %10.1f",
				((key == "ours" ? "TextDiff" : "git \(key)") as NSString).utf8String!,
				tally.changes, tally.lines, tally.lone, tally.seconds))
		}
		longer.sort { ($0.ours - $0.theirs) > ($1.ours - $1.theirs) }
		print("DIFF \(name): longer than git's Myers on \(longer.count) of \(found.count) pairs"
			+ (longer.isEmpty ? "" : ", worst first:"))
		for row in longer.prefix(8) {
			print("DIFF   \(row.commit) \(row.path): ours \(row.ours), git \(row.theirs)")
		}
	}

	// MARK: - The runs

	/// This repository: Swift, Markdown and shell, edited by the people who
	/// wrote it. The subject nobody has to clone.
	@Test func ourOwnHistoryIsDescribedAsWellAsGitDescribesIt() throws {
		guard ProcessInfo.processInfo.environment["SCALE"] != nil else { return }
		var here = URL(fileURLWithPath: #filePath)
		for _ in 0..<3 { here.deleteLastPathComponent() }
		try Self.measure("abydos", repository: here, commits: 600,
		                 extensions: [".swift", ".md", ".sh"])
	}

	/// Java, which is the shape the silly match is most likely in: a language
	/// where a great many lines are a closing brace and nothing else. One
	/// Eclipse repository with enough history to hold pairs — the clones
	/// `Scripts/corpus.sh` makes are `--depth 1` and hold none.
	///
	///     git clone --depth 300 https://github.com/eclipse-platform/eclipse.platform.ui.git \
	///       ~/dev/abydos-corpus/platform/eclipse.platform.ui
	@Test func javaIsDescribedAsWellAsGitDescribesIt() throws {
		guard ProcessInfo.processInfo.environment["SCALE"] != nil else { return }
		let corpus = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CORPUS"]
			?? NSString(string: "~/dev/abydos-corpus").expandingTildeInPath)
		let repository = corpus.appendingPathComponent("platform/eclipse.platform.ui")
		guard FileManager.default.fileExists(atPath: repository.appendingPathComponent(".git").path)
		else {
			print("DIFF java: no repository at \(repository.path)")
			return
		}
		// Shallow clones have a horizon, and `commit~1` does not exist across
		// it: those pairs are skipped rather than counted as empty.
		try Self.measure("java", repository: repository, commits: 300, extensions: [".java"])
	}
}
