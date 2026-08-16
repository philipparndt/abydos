import Foundation

/// A Swift package, and what `swift run` can start in it.
///
/// Read out of `Package.swift` rather than asked of `swift package
/// dump-package`, which is the same choice `XcodeProject` makes about
/// `xcodebuild -list` and `BazelBuild` about `bazel query` — and one more
/// reason than either of them had. A manifest is a program, and `dump-package`
/// compiles and runs it: `ConanProject` already refuses to execute
/// `conanfile.py` to fill in a menu, and there is no difference between the two
/// except which language the build script is written in.
///
/// Measured on this machine, item 0498: `dump-package` is 0.74–0.92 s per
/// manifest whether the cache is warm or not, it leaves a `.build` directory in
/// the project as a side effect of being asked, and it answers with whichever
/// `swift` is first on the PATH — which, one release behind, says "package is
/// using Swift tools version 6.3.0 but the installed version is 6.1.2" and
/// lists nothing at all. Discovery is synchronous and runs once per directory
/// three deep, and again on every write that could change the answer, so all
/// three of those are paid over and over.
///
/// What this cannot see is an executable whose name is not a string literal, in
/// a manifest that computes its targets. That is a missing entry rather than a
/// wrong one. This repository's own manifest computes five targets and all five
/// are libraries; its four executable products are written out.
public struct SwiftPackage: Equatable, Sendable {
	/// Something `swift run` will start, and where the manifest declares it.
	///
	/// The name is the *product's*, not the target's, because that is what
	/// `swift run` takes: a package declaring
	/// `.executable(name: "abydos-hook", targets: ["AbydosHook"])` answers
	/// `error: no executable product named 'AbydosHook'`. An executable target
	/// that no product claims gets an implicit product of its own name, so it
	/// is runnable under the target's name and appears here under it.
	public struct Executable: Equatable, Sendable {
		public let name: String
		/// 1-based line of the declaration this name came from.
		public let line: Int

		public init(name: String, line: Int) {
			self.name = name
			self.line = line
		}
	}

	public let manifest: URL
	public let executables: [Executable]
	/// The line of the first test target, when the package declares one.
	public let testLine: Int?

	/// Where `swift` runs: the directory holding the manifest.
	public var directory: URL { manifest.deletingLastPathComponent() }

	public init(manifest: URL, executables: [Executable], testLine: Int?) {
		self.manifest = manifest
		self.executables = executables
		self.testLine = testLine
	}

	/// The package in this directory, if there is one.
	///
	/// `Package.swift` exactly. A version-specific manifest —
	/// `Package@swift-5.9.swift` — is the same package described for an older
	/// toolchain, and reading both would list everything twice.
	public static func find(in directory: URL) -> SwiftPackage? {
		let manifest = directory.appendingPathComponent("Package.swift")
		guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return nil }
		return parse(text, manifest: manifest)
	}

	static func parse(_ text: String, manifest: URL) -> SwiftPackage {
		let calls = calls(in: text)

		// Products first, because a product's name is the runnable one and a
		// target it names must not also be listed under its own.
		var executables: [Executable] = []
		var claimed = Set<String>()
		for call in calls where call.name == ".executable" {
			guard let name = string(labelled: "name", in: call.arguments) else { continue }
			executables.append(Executable(name: name, line: call.line))
			claimed.formUnion(strings(labelled: "targets", in: call.arguments))
		}

		let declared = Set(executables.map(\.name))
		for call in calls where call.name == ".executableTarget" {
			guard let name = string(labelled: "name", in: call.arguments) else { continue }
			guard !claimed.contains(name), !declared.contains(name) else { continue }
			executables.append(Executable(name: name, line: call.line))
		}

		let testLine = calls.first { $0.name == ".testTarget" }?.line

		return SwiftPackage(manifest: manifest, executables: executables, testLine: testLine)
	}

	// MARK: - Reading the manifest

	/// A call written out in the manifest: what it is, the text between its
	/// parentheses, and the 1-based line it starts on.
	struct Call: Equatable {
		var name: String
		var arguments: String
		var line: Int
	}

	/// The declarations worth finding. Spelled with the leading dot they are
	/// written with, so a local variable called `executable` is not one.
	static let wantedCalls: Set<String> = [".executable", ".executableTarget", ".testTarget"]

	/// Every one of those in the manifest, in the order they are written.
	///
	/// A scanner rather than a regular expression, for one reason: a manifest
	/// contains strings holding `//` (every dependency URL) and comments holding
	/// code (this repository's own manifest describes `.unsafeFlags` in prose
	/// above the targets). Both have to be walked past rather than matched, or
	/// a commented-out target becomes an entry in somebody's run list.
	static func calls(in text: String) -> [Call] {
		let characters = Array(text)
		var result: [Call] = []
		var index = 0
		var line = 1

		while index < characters.count {
			if let next = skipPast(characters, from: index, line: &line) {
				index = next
				continue
			}

			guard isIdentifierCharacter(characters[index]) else { index += 1; continue }

			// The whole identifier, and the dot in front of it if there is one.
			let start = index
			while index < characters.count, isIdentifierCharacter(characters[index]) { index += 1 }
			let hasDot = start > 0 && characters[start - 1] == "."
			let name = (hasDot ? "." : "") + String(characters[start..<index])
			guard wantedCalls.contains(name) else { continue }

			// `.executableTarget (name:` is not written by anybody, but the
			// whitespace costs nothing to allow.
			var open = index
			while open < characters.count, characters[open] == " " || characters[open] == "\t" { open += 1 }
			guard open < characters.count, characters[open] == "(" else { continue }

			let declaredAt = line
			var depth = 0
			var cursor = open
			var closed: Int?
			while cursor < characters.count {
				if let next = skipPast(characters, from: cursor, line: &line) {
					cursor = next
					continue
				}
				if characters[cursor] == "(" { depth += 1 }
				if characters[cursor] == ")" {
					depth -= 1
					if depth == 0 { closed = cursor; break }
				}
				cursor += 1
			}
			guard let closed else { break }

			result.append(Call(
				name: name,
				arguments: String(characters[(open + 1)..<closed]),
				line: declaredAt
			))
			index = closed + 1
		}

		return result
	}

	/// If a string literal, a comment or a newline starts here, where it ends —
	/// counting any lines crossed on the way. Nil when it is ordinary code.
	private static func skipPast(_ characters: [Character], from index: Int, line: inout Int) -> Int? {
		let character = characters[index]

		if character == "\n" {
			line += 1
			return index + 1
		}

		if character == "\"" {
			// A multi-line literal ends at its own `"""`, and there is no other
			// way to tell the two apart from the opening quote alone.
			if index + 2 < characters.count, characters[index + 1] == "\"", characters[index + 2] == "\"" {
				var cursor = index + 3
				while cursor + 2 < characters.count {
					if characters[cursor] == "\"", characters[cursor + 1] == "\"", characters[cursor + 2] == "\"" {
						return cursor + 3
					}
					if characters[cursor] == "\n" { line += 1 }
					cursor += 1
				}
				return characters.count
			}

			var cursor = index + 1
			while cursor < characters.count {
				if characters[cursor] == "\\" { cursor += 2; continue }
				if characters[cursor] == "\"" { return cursor + 1 }
				if characters[cursor] == "\n" { line += 1; return cursor + 1 }
				cursor += 1
			}
			return characters.count
		}

		guard character == "/", index + 1 < characters.count else { return nil }

		if characters[index + 1] == "/" {
			var cursor = index
			while cursor < characters.count, characters[cursor] != "\n" { cursor += 1 }
			return cursor
		}

		if characters[index + 1] == "*" {
			// Nested, because Swift's block comments are.
			var depth = 0
			var cursor = index
			while cursor + 1 < characters.count {
				if characters[cursor] == "/", characters[cursor + 1] == "*" { depth += 1; cursor += 2; continue }
				if characters[cursor] == "*", characters[cursor + 1] == "/" {
					depth -= 1
					cursor += 2
					if depth == 0 { return cursor }
					continue
				}
				if characters[cursor] == "\n" { line += 1 }
				cursor += 1
			}
			return characters.count
		}

		return nil
	}

	private static func isIdentifierCharacter(_ character: Character) -> Bool {
		character.isLetter || character.isNumber || character == "_"
	}

	/// The text of one labelled argument, at the top level of an argument list.
	static func value(labelled label: String, in arguments: String) -> String? {
		let characters = Array(arguments)
		var index = 0
		var line = 0
		var depth = 0
		var found: Int?
		var end = characters.count

		while index < characters.count {
			if let next = skipPast(characters, from: index, line: &line) {
				index = next
				continue
			}

			let character = characters[index]
			if character == "(" || character == "[" || character == "{" { depth += 1 }
			if character == ")" || character == "]" || character == "}" { depth -= 1 }

			if depth == 0, found != nil, character == "," {
				end = index
				break
			}

			if depth == 0, found == nil, isIdentifierCharacter(character) {
				let start = index
				while index < characters.count, isIdentifierCharacter(characters[index]) { index += 1 }
				guard String(characters[start..<index]) == label,
				      index < characters.count, characters[index] == ":"
				else { continue }
				found = index + 1
				continue
			}

			index += 1
		}

		guard let found else { return nil }
		return String(characters[found..<max(found, end)])
	}

	/// The first string literal of a labelled argument: `name: "spike"`.
	static func string(labelled label: String, in arguments: String) -> String? {
		value(labelled: label, in: arguments).flatMap { literals(in: $0).first }
	}

	/// Every string literal of a labelled argument: `targets: ["A", "B"]`.
	static func strings(labelled label: String, in arguments: String) -> [String] {
		value(labelled: label, in: arguments).map { literals(in: $0) } ?? []
	}

	/// The plain string literals in a fragment of manifest.
	///
	/// Anything interpolated is dropped rather than guessed at: `"\(prefix)Kit"`
	/// is a name this cannot know, and half of one is worse than none.
	static func literals(in text: String) -> [String] {
		let characters = Array(text)
		var result: [String] = []
		var index = 0

		while index < characters.count {
			guard characters[index] == "\"" else { index += 1; continue }

			var cursor = index + 1
			var literal = ""
			var plain = true
			while cursor < characters.count, characters[cursor] != "\"" {
				// Whatever the escape is — an interpolation or a `\n` — this is
				// no longer a name that can be taken at face value. The scan
				// still has to reach the closing quote, or it resumes inside the
				// literal and reads its contents as code.
				if characters[cursor] == "\\" {
					plain = false
					cursor += 2
					continue
				}
				literal.append(characters[cursor])
				cursor += 1
			}

			if plain, !literal.isEmpty { result.append(literal) }
			index = cursor + 1
		}

		return result
	}
}
