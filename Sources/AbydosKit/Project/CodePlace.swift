import Foundation

/// A place in the code, said in a way something else can use.
///
/// **`path:line` is this program's currency and the editor could not produce
/// one.** `ReviewSession` writes its findings in this shape with a comment
/// saying why — so the paste is useful in another tool — `Scripts/abydos` opens
/// it, and every grep, stack trace and compiler error looks like it. All of
/// those are something *else* making a reference into a project; this is the
/// editor's own.
///
/// **Lines are counted from 1**, the way everything that prints one counts:
/// grep, a stack trace, the gutter, and `abydos path:12`. The protocol's
/// positions are counted from 0 and are converted at the edge, once, where the
/// caret is read — a type that is 1-based in some places and 0-based in others
/// is the bug that follows.
///
/// Deliberately spare. No column: a column is noise to every audience a
/// reference has, and `Scripts/abydos` accepts one only because grep prints
/// one. No scheme, no host, no quoted line of code — the whole value of this
/// string is that it can be pasted anywhere without explanation.
public struct CodePlace: Equatable, Sendable {
	/// Relative to the project root, so that it means the same thing in
	/// somebody else's clone.
	public var path: String
	/// Counted from 1.
	public var line: Int
	/// The last line, when a selection covers more than one. **A person who
	/// selected eight lines and is handed the first one has been given the
	/// wrong answer.**
	public var endLine: Int?

	public init(path: String, line: Int, endLine: Int? = nil) {
		self.path = path
		self.line = line
		// A range of one line is a line. Stored that way so that two references
		// to the same place cannot be unequal.
		self.endLine = (endLine ?? line) > line ? endLine : nil
	}

	/// What goes on the pasteboard.
	public var text: String {
		guard let endLine else { return "\(path):\(line)" }
		return "\(path):\(line)-\(endLine)"
	}

	/// How many lines it covers, which is what a sentence about it counts.
	public var lineCount: Int { (endLine ?? line) - line + 1 }

	/// A file's path as a reference writes it: relative to the project, and
	/// absolute when it is not inside one.
	///
	/// An absolute path is right on one machine and no other, and the audience
	/// for a reference is most often an assistant working in this same
	/// checkout. A file genuinely outside the project keeps its absolute path,
	/// because a `../../..` chain is a path nothing can resolve without knowing
	/// where it was written.
	public static func path(of url: URL, in project: URL?) -> String {
		// **`canonicalEvenIfMissing`, not `canonical`.** `realpath` answers only
		// about files that exist, so a project under a symlinked `/tmp` came
		// back as `/private/tmp/probe` while a file inside it that had not been
		// written yet came back as `/tmp/probe/…` — the same directory, two
		// spellings, no shared prefix, and a reference that gave the whole
		// absolute path for a file plainly inside the project.
		let path = FilePath.canonicalEvenIfMissing(url.path)
		guard let project else { return path }
		let base = FilePath.canonicalEvenIfMissing(project.path)
		// The separator is part of the test: `/tmp/probe-2` is not inside
		// `/tmp/probe`, and a bare prefix says it is.
		guard path.hasPrefix(base + "/") else { return path }
		return String(path.dropFirst(base.count + 1))
	}

	public init(url: URL, in project: URL?, line: Int, endLine: Int? = nil) {
		self.init(path: Self.path(of: url, in: project), line: line, endLine: endLine)
	}

	/// Reads one back.
	///
	/// **The other end of the same road**, and it has to be here because the
	/// shapes that arrive are not only the ones this writes: a stack trace says
	/// `path:12`, grep says `path:12:5`, and a reference made here says
	/// `path:12-18`.
	///
	/// A colon is legal in a file name, so the number is only a number when it
	/// is one — the same rule `Scripts/abydos` keeps, one layer up, where it can
	/// also ask the disk. This cannot, so it is a matter of shape alone: what
	/// follows the last colon must be all digits, and a path must be left over.
	public static func parse(_ text: String) -> CodePlace? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		var parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
		guard parts.count >= 2 else { return nil }

		// `path:12:5` — grep's column, dropped. Only when what is left is
		// itself a line number, so `path:12` is not read as a column.
		if parts.count >= 3, isNumber(parts[parts.count - 1]), isNumber(parts[parts.count - 2]) {
			parts.removeLast()
		}

		let last = parts.removeLast()
		let path = parts.joined(separator: ":")
		guard !path.isEmpty else { return nil }

		// `12-18`, which is what a selection copies as.
		let range = last.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
		if range.count == 2, isNumber(range[0]), isNumber(range[1]),
		   let start = Int(range[0]), let end = Int(range[1]), start > 0, end >= start {
			return CodePlace(path: path, line: start, endLine: end)
		}
		guard isNumber(last), let line = Int(last), line > 0 else { return nil }
		return CodePlace(path: path, line: line)
	}

	/// Digits and nothing else. `Int("12 ")` and `Int("+12")` both succeed, and
	/// neither is what a tool printed.
	private static func isNumber(_ text: String) -> Bool {
		!text.isEmpty && text.allSatisfy(\.isASCII) && text.allSatisfy(\.isNumber)
	}

	/// The file this points at, given the project it was written in.
	public func url(in project: URL?) -> URL {
		guard !path.hasPrefix("/"), let project else { return URL(fileURLWithPath: path) }
		return project.appendingPathComponent(path)
	}
}
