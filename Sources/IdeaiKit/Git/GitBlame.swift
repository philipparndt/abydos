import Foundation

/// Who last touched each line, and when.
///
/// Read from `git blame --line-porcelain`, which repeats the whole header for
/// every line rather than abbreviating after the first — more output, and no
/// state to carry between lines while parsing, which is where the subtle bugs
/// in a blame parser live.
public enum GitBlame {
	/// One line's history.
	public struct Line: Equatable, Sendable {
		public let commit: String
		public let author: String
		public let date: Date
		public let summary: String

		/// Written but not committed: git says so with a commit of all zeroes.
		public var isUncommitted: Bool { commit.allSatisfy { $0 == "0" } }

		public var shortCommit: String { String(commit.prefix(8)) }

		public init(commit: String, author: String, date: Date, summary: String) {
			self.commit = commit
			self.author = author
			self.date = date
			self.summary = summary
		}

		/// What the column shows: a name and how long ago, kept short because
		/// the column sits beside the code and must not crowd it.
		public func label(width: Int, now: Date = Date()) -> String {
			guard !isUncommitted else { return "Uncommitted" }
			let when = Self.age(from: date, to: now)
			let room = max(3, width - when.count - 1)
			return "\(Self.shorten(author, to: room)) \(when)"
		}

		/// A first name, or an initial and a surname — whatever fits.
		static func shorten(_ author: String, to width: Int) -> String {
			guard author.count > width else { return author }
			let parts = author.split(separator: " ")
			if parts.count > 1 {
				let compact = "\(parts[0].prefix(1)). \(parts[parts.count - 1])"
				if compact.count <= width { return compact }
			}
			guard width > 1 else { return String(author.prefix(width)) }
			return String(author.prefix(width - 1)) + "…"
		}

		/// How long ago, in the words git itself uses.
		static func age(from date: Date, to now: Date) -> String {
			let seconds = max(0, now.timeIntervalSince(date))
			let day = 60.0 * 60 * 24

			switch seconds {
			case ..<(60 * 60): return "\(max(1, Int(seconds / 60)))m"
			case ..<day: return "\(Int(seconds / 3600))h"
			case ..<(day * 30): return "\(Int(seconds / day))d"
			case ..<(day * 365): return "\(max(1, Int(seconds / (day * 30))))mo"
			default: return "\(max(1, Int(seconds / (day * 365))))y"
			}
		}
	}

	/// Blames a file, one entry per line of it.
	///
	/// The file as it stands on disk, so uncommitted lines are marked as such
	/// rather than silently attributed to whoever last committed there.
	public static func lines(for file: URL, in root: URL) async -> [Line] {
		let path = relativePath(of: file, in: root)
		let result = await GitRepository.run(
			["blame", "--line-porcelain", "--", path], in: root
		)
		guard result.exitCode == 0 else { return [] }
		return parse(result.stdout)
	}

	/// Reads `--line-porcelain` output.
	///
	/// Internal so it can be tested against what git actually prints, including
	/// the shapes that are easy to get wrong: a commit with no summary, an
	/// author whose name contains spaces, and the all-zero commit of a line
	/// nobody has committed.
	static func parse(_ output: String) -> [Line] {
		var lines: [Line] = []

		var commit = ""
		var author = ""
		var summary = ""
		var timestamp: TimeInterval = 0

		for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
			// The content of the blamed line, which ends its block.
			if raw.hasPrefix("\t") {
				guard !commit.isEmpty else { continue }
				lines.append(Line(
					commit: commit,
					author: author,
					date: Date(timeIntervalSince1970: timestamp),
					summary: summary
				))
				commit = ""
				author = ""
				summary = ""
				timestamp = 0
				continue
			}

			let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
			guard let keyword = parts.first else { continue }
			let value = parts.count > 1 ? String(parts[1]) : ""

			switch keyword {
			case "author": author = value
			case "summary": summary = value
			case "author-time": timestamp = TimeInterval(value) ?? 0
			default:
				// A header line: `<sha> <original> <final> [count]`, which is
				// the only place a 40-character hex word starts a line.
				if keyword.count == 40, keyword.allSatisfy(\.isHexDigit) {
					commit = String(keyword)
				}
			}
		}
		return lines
	}

	private static func relativePath(of file: URL, in root: URL) -> String {
		let base = root.standardizedFileURL.path
		let path = file.standardizedFileURL.path
		guard path.hasPrefix(base + "/") else { return path }
		return String(path.dropFirst(base.count + 1))
	}
}
