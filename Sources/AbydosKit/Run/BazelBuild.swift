import Foundation

/// A Bazel workspace, read well enough to offer the things in it as runnable.
///
/// Not a Starlark interpreter. `bazel query` is the correct way to ask what a
/// workspace contains, and it is also a build-graph load that can take a minute
/// on a large repository and needs Bazel installed to answer at all. What this
/// does instead is what a person does when they open a `BUILD` file: read the
/// rule names and the `name = "…"` beside them, which is enough to list what
/// can be run and to write the label for it.
///
/// The commands it produces are Bazel's own, so anything it gets wrong is
/// wrong in a way Bazel will say plainly rather than in a way this has to
/// explain.
public enum BazelBuild {
	/// A target somebody can ask for.
	public struct Target: Equatable, Sendable, Identifiable {
		/// The rule that declared it — `cc_binary`, `go_test`.
		public let rule: String
		/// The label, as Bazel writes it: `//app/server:server`.
		public let label: String
		/// The `BUILD` file it was declared in.
		public let file: URL
		/// 1-based line of the rule, for a marker beside it.
		public let line: Int

		public var id: String { label }

		/// Whether `bazel test` is the verb for it rather than `bazel run`.
		public var isTest: Bool { rule.hasSuffix("_test") }

		public init(rule: String, label: String, file: URL, line: Int) {
			self.rule = rule
			self.label = label
			self.file = file
			self.line = line
		}
	}

	/// The files that mark the root of a workspace.
	///
	/// `MODULE.bazel` is bzlmod, which is how Bazel 7 and later say it;
	/// `WORKSPACE` is the older way and is still everywhere.
	public static let workspaceMarkers = ["MODULE.bazel", "WORKSPACE.bazel", "WORKSPACE", "WORKSPACE.bzlmod"]

	/// What a package's build file may be called.
	public static let buildFileNames = ["BUILD.bazel", "BUILD"]

	/// The workspace a directory belongs to, or nil when it belongs to none.
	public static func workspaceRoot(for directory: URL, fileExists: (String) -> Bool = {
		FileManager.default.fileExists(atPath: $0)
	}) -> URL? {
		var current = URL(fileURLWithPath: FilePath.canonical(directory))
		while true {
			for marker in workspaceMarkers
			where fileExists(current.appendingPathComponent(marker).path) {
				return current
			}
			let parent = current.deletingLastPathComponent()
			guard parent.path != current.path, parent.path != "/" else { return nil }
			current = parent
		}
	}

	/// The label of a build file's package: `//app/server` for
	/// `<workspace>/app/server/BUILD`, and `//` for one at the root.
	public static func packageLabel(of buildFile: URL, workspace: URL) -> String {
		let directory = buildFile.deletingLastPathComponent().path
		let root = workspace.path
		guard directory != root else { return "//" }
		guard directory.hasPrefix(root + "/") else { return "//" }
		return "//" + String(directory.dropFirst(root.count + 1))
	}

	/// The targets declared in one build file.
	///
	/// Only the rules worth offering: something ending in `_binary` can be run,
	/// something ending in `_test` can be tested. A library is a thing to build,
	/// not a thing to start, and listing every one of them would bury the two
	/// or three anybody actually asks for.
	public static func targets(in buildFile: URL, contents: String, workspace: URL) -> [Target] {
		let package = packageLabel(of: buildFile, workspace: workspace)
		var found: [Target] = []

		for declaration in declarations(in: contents) {
			guard declaration.rule.hasSuffix("_binary") || declaration.rule.hasSuffix("_test") else {
				continue
			}
			guard let name = declaration.name else { continue }
			let label = package == "//" ? "//:\(name)" : "\(package):\(name)"
			found.append(Target(rule: declaration.rule, label: label, file: buildFile, line: declaration.line))
		}
		return found
	}

	/// A rule call in a build file: its name, where it starts, and the `name`
	/// attribute if it has one.
	struct Declaration: Equatable {
		let rule: String
		let name: String?
		let line: Int
	}

	/// Finds rule calls without parsing Starlark.
	///
	/// A rule call is an identifier followed by `(` at the start of a line —
	/// which is how `buildifier` formats every one of them, and how everybody
	/// writes them by hand. Anything indented is an argument to something else,
	/// and anything after `#` is a comment.
	static func declarations(in contents: String) -> [Declaration] {
		var found: [Declaration] = []
		let lines = contents.components(separatedBy: "\n")

		var index = 0
		while index < lines.count {
			let line = lines[index]
			guard let rule = ruleName(startingAt: line) else {
				index += 1
				continue
			}

			// The name is inside the call, which runs until the parentheses
			// balance. Bounded, so an unclosed one cannot run to the end of a
			// generated file.
			var depth = 0
			var name: String?
			var cursor = index
			while cursor < lines.count, cursor - index < 200 {
				let current = stripComment(lines[cursor])
				if name == nil, let found = nameAttribute(in: current) { name = found }
				depth += current.filter { $0 == "(" }.count
				depth -= current.filter { $0 == ")" }.count
				if depth <= 0, cursor > index || current.contains(")") { break }
				cursor += 1
			}

			found.append(Declaration(rule: rule, name: name, line: index + 1))
			index = max(index + 1, cursor)
		}
		return found
	}

	/// The rule a line starts a call to, or nil.
	static func ruleName(startingAt line: String) -> String? {
		// Not indented: an indented `name(` is an argument, not a rule.
		guard let first = line.first, first != " ", first != "\t", first != "#" else { return nil }
		guard let open = line.firstIndex(of: "(") else { return nil }

		let identifier = String(line[line.startIndex..<open])
		guard !identifier.isEmpty,
		      identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
		      identifier.first?.isNumber == false
		else { return nil }
		// `load(...)` names the file a rule comes from, not a target.
		guard identifier != "load", identifier != "package", identifier != "exports_files" else {
			return nil
		}
		return identifier
	}

	/// The value of a `name = "…"` attribute on a line.
	static func nameAttribute(in line: String) -> String? {
		guard let range = line.range(of: "name") else { return nil }
		let after = line[range.upperBound...].drop { $0 == " " || $0 == "\t" }
		guard after.first == "=" else { return nil }

		let value = after.dropFirst().drop { $0 == " " || $0 == "\t" }
		guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
		let rest = value.dropFirst()
		guard let end = rest.firstIndex(of: quote) else { return nil }

		// What comes immediately before decides whether this is the attribute or
		// part of another word: `filename = "x"` is not it, and `srcs = [":name"]`
		// is not it, while both `name = "x"` on its own line and the same inside
		// `go_binary(name = "x")` are.
		if let previous = line[line.startIndex..<range.lowerBound].last {
			guard previous == " " || previous == "\t" || previous == "," || previous == "(" else {
				return nil
			}
		}

		let name = String(rest[rest.startIndex..<end])
		return name.isEmpty ? nil : name
	}

	/// Everything before an unquoted `#`.
	static func stripComment(_ line: String) -> String {
		var inQuote: Character?
		for (offset, character) in line.enumerated() {
			if let quote = inQuote {
				if character == quote { inQuote = nil }
				continue
			}
			if character == "\"" || character == "'" { inQuote = character; continue }
			if character == "#" { return String(line.prefix(offset)) }
		}
		return line
	}

	/// How to run a target: `bazel run //app:server`, or `bazel test` for a test.
	public static func command(for target: Target) -> (executable: String, arguments: [String]) {
		("bazel", [target.isTest ? "test" : "run", target.label])
	}
}
