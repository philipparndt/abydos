import Foundation

/// A project's Makefile, read well enough to run something out of it.
///
/// Not a make implementation: no pattern rules, no conditionals, no includes.
/// What it takes from a Makefile is what a person takes when they read one —
/// which targets exist, what each one says it does, what it depends on, and
/// what its recipe runs — because that is enough to offer the goals as things
/// to run and to work out what a goal would have started.
public struct Makefile: Equatable, Sendable {
	public struct Target: Equatable, Sendable, Identifiable {
		public let name: String
		/// The `## comment` beside the target, which is how a Makefile with a
		/// help target documents itself.
		public let summary: String
		public let prerequisites: [String]
		/// The recipe, with the leading tab and the `@` removed.
		public let recipe: [String]

		public var id: String { name }

		public init(name: String, summary: String = "", prerequisites: [String] = [], recipe: [String] = []) {
			self.name = name
			self.summary = summary
			self.prerequisites = prerequisites
			self.recipe = recipe
		}
	}

	public let path: URL
	public let variables: [String: String]
	public let targets: [Target]

	public init(path: URL, variables: [String: String], targets: [Target]) {
		self.path = path
		self.variables = variables
		self.targets = targets
	}

	/// Where make would run: the directory holding the file.
	public var directory: URL { path.deletingLastPathComponent() }

	public func target(named name: String) -> Target? {
		targets.first { $0.name == name }
	}

	/// Every target reached from this one, deepest first.
	///
	/// The order make would build them in, which is also the order they have
	/// to be looked at to find out what a goal actually does.
	public func chain(from name: String) -> [Target] {
		var seen: Set<String> = []
		var ordered: [Target] = []

		func visit(_ name: String) {
			guard seen.insert(name).inserted, let target = target(named: name) else { return }
			for prerequisite in target.prerequisites { visit(prerequisite) }
			ordered.append(target)
		}
		visit(name)
		return ordered
	}

	// MARK: - Reading

	public static func read(at url: URL) -> Makefile? {
		guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
		return parse(text, path: url)
	}

	/// The Makefile a project runs, if it has one.
	///
	/// Beside the project, or one level down — `app/Makefile` is where a Go
	/// program lives in a repository that also holds its charts and its docs.
	public static func find(in root: URL, maxDepth: Int = 2) -> [URL] {
		let manager = FileManager.default
		var found: [URL] = []

		func scan(_ directory: URL, depth: Int) {
			let candidate = directory.appendingPathComponent("Makefile")
			if manager.fileExists(atPath: candidate.path) { found.append(candidate) }
			guard depth < maxDepth else { return }

			let skipped: Set<String> = [
				"node_modules", "vendor", ".git", "build", "dist", ".build", "target",
			]
			let contents = (try? manager.contentsOfDirectory(
				at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
			)) ?? []
			for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
				guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
				      !skipped.contains(entry.lastPathComponent)
				else { continue }
				scan(entry, depth: depth + 1)
			}
		}
		scan(root, depth: 0)
		return found
	}

	static func parse(_ text: String, path: URL) -> Makefile {
		var variables: [String: String] = [:]
		var targets: [Target] = []

		var currentName: String?
		var currentSummary = ""
		var currentPrerequisites: [String] = []
		var currentRecipe: [String] = []

		func flush() {
			guard let name = currentName else { return }
			targets.append(Target(
				name: name,
				summary: currentSummary,
				prerequisites: currentPrerequisites,
				recipe: currentRecipe
			))
			currentName = nil
			currentSummary = ""
			currentPrerequisites = []
			currentRecipe = []
		}

		// Continuation lines are joined first: a recipe or a variable split
		// over three lines with backslashes is one thing, and reading it as
		// three loses the parts that matter.
		for rawLine in joinContinuations(text) {
			// A recipe line starts with a tab, and only a tab.
			if rawLine.hasPrefix("\t") {
				guard currentName != nil else { continue }
				var command = String(rawLine.dropFirst())
				// `@` hides the echo, `-` ignores failure, `+` runs even under
				// -n. None of them are part of the command.
				while let first = command.first, "@-+".contains(first) {
					command.removeFirst()
				}
				currentRecipe.append(command)
				continue
			}

			let line = rawLine.trimmingCharacters(in: .whitespaces)
			if line.isEmpty || line.hasPrefix("#") {
				// A blank line ends a recipe, which is where make ends it too.
				if line.isEmpty { flush() }
				continue
			}

			if let (name, value) = assignment(in: line) {
				flush()
				variables[name] = value
				continue
			}

			guard let colon = ruleColon(in: line) else { continue }
			flush()

			let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
			// `.PHONY` and friends declare things about targets rather than
			// being targets.
			guard !name.hasPrefix("."), !name.contains("%"), !name.isEmpty else { continue }

			var rest = String(line[line.index(after: colon)...])
			if rest.hasPrefix("=") { continue } // `x := y` that slipped through

			var summary = ""
			if let marker = rest.range(of: "##") {
				summary = String(rest[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
				rest = String(rest[..<marker.lowerBound])
			}

			currentName = name
			currentSummary = summary
			currentPrerequisites = rest
				.split(whereSeparator: { $0 == " " || $0 == "\t" })
				.map(String.init)
				.filter { !$0.isEmpty }
			currentRecipe = []
		}
		flush()

		return Makefile(path: path, variables: variables, targets: targets)
	}

	/// Joins lines ending in a backslash, keeping a leading tab on the result
	/// so a continued recipe is still a recipe.
	static func joinContinuations(_ text: String) -> [String] {
		var lines: [String] = []
		var pending: String?

		for line in text.components(separatedBy: "\n") {
			let joined = (pending ?? "") + (pending == nil ? line : line.trimmingCharacters(in: .whitespaces))
			if joined.hasSuffix("\\") {
				pending = String(joined.dropLast()) + " "
				continue
			}
			pending = nil
			lines.append(joined)
		}
		if let pending { lines.append(pending) }
		return lines
	}

	/// `NAME = value`, `NAME := value`, `NAME ?= value`, `NAME += value`.
	static func assignment(in line: String) -> (String, String)? {
		guard let equals = line.firstIndex(of: "=") else { return nil }
		var nameEnd = equals
		// The operator's first character belongs to it, not to the name.
		if equals > line.startIndex {
			let previous = line.index(before: equals)
			if ":?+".contains(line[previous]) { nameEnd = previous }
		}

		let name = String(line[line.startIndex..<nameEnd]).trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
		else { return nil }

		var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
		// A trailing `## comment` documents the variable rather than being part
		// of it.
		if let marker = value.range(of: " ##") { value = String(value[..<marker.lowerBound]) }
		return (name, value.trimmingCharacters(in: .whitespaces))
	}

	/// The colon that makes a line a rule, ignoring the ones inside `$(...)`
	/// and `${...}` and after a `#`.
	static func ruleColon(in line: String) -> String.Index? {
		var depth = 0
		var index = line.startIndex
		while index < line.endIndex {
			let character = line[index]
			switch character {
			case "$":
				let next = line.index(after: index)
				if next < line.endIndex, line[next] == "(" || line[next] == "{" { depth += 1 }
			case ")", "}":
				depth = max(0, depth - 1)
			case "#":
				return nil
			case ":" where depth == 0:
				// `::` is a double-colon rule; `:=` is an assignment, which the
				// caller has already tried.
				let next = line.index(after: index)
				if next < line.endIndex, line[next] == "=" { return nil }
				return index
			default:
				break
			}
			index = line.index(after: index)
		}
		return nil
	}

	// MARK: - Expansion

	/// A line with `$(VAR)` and `${VAR}` replaced by what the file said they
	/// are, and `$(PWD)` by where the file is.
	///
	/// Recursive, because make's own variables are: `$(BUILD_DIR)/$(BINARY)`
	/// where `BUILD_DIR = build` and `BINARY = $(NAME)-cli`. Bounded, because
	/// a Makefile can define a variable in terms of itself.
	public func expand(_ text: String, depth: Int = 0) -> String {
		guard depth < 8, text.contains("$") else { return text }

		var result = ""
		var index = text.startIndex
		while index < text.endIndex {
			guard text[index] == "$", text.index(after: index) < text.endIndex else {
				result.append(text[index])
				index = text.index(after: index)
				continue
			}

			let openIndex = text.index(after: index)
			let open = text[openIndex]

			// `$$` is how a Makefile writes a dollar for the shell that runs
			// the recipe: make eats one and passes the other on, and so does
			// this. Leaving both turns `$$(sops -d x)` into the shell's own
			// process id followed by some words.
			if open == "$" {
				result.append("$")
				index = text.index(after: openIndex)
				continue
			}
			guard open == "(" || open == "{" else {
				// `$X` is a one-letter variable, which nobody uses for this.
				result.append(text[index])
				index = text.index(after: index)
				continue
			}

			let close: Character = open == "(" ? ")" : "}"
			guard let end = matching(close, from: openIndex, in: text) else {
				result.append(text[index])
				index = text.index(after: index)
				continue
			}

			let name = String(text[text.index(after: openIndex)..<end])
			// A shell substitution or a make function — `$(shell date)`,
			// `$(wildcard *.go)` — is left as it is: it has to be run, not
			// looked up, and whoever runs the line can do that.
			if name.contains(" ") {
				result.append(String(text[index...end]))
			} else if name == "PWD" || name == "CURDIR" {
				result.append(directory.path)
			} else if let value = variables[name] {
				result.append(expand(value, depth: depth + 1))
			} else {
				result.append(ProcessInfo.processInfo.environment[name] ?? "")
			}
			index = text.index(after: end)
		}
		return result
	}

	private func matching(_ close: Character, from openIndex: String.Index, in text: String) -> String.Index? {
		let open = text[openIndex]
		var depth = 0
		var index = openIndex
		while index < text.endIndex {
			if text[index] == open { depth += 1 }
			if text[index] == close {
				depth -= 1
				if depth == 0 { return index }
			}
			index = text.index(after: index)
		}
		return nil
	}
}
