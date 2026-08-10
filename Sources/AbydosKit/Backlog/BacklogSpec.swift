import Foundation

/// One thing the project does, as the spec states it.
public struct SpecRequirement: Equatable, Sendable {
	/// What comes after `## Requirement:`, which is how a delta names the one
	/// it is changing.
	public let name: String
	/// Everything under the heading, up to the next one.
	public let body: String

	public init(name: String, body: String) {
		self.name = name
		self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	public var text: String {
		body.isEmpty ? "## Requirement: \(name)" : "## Requirement: \(name)\n\n\(body)"
	}
}

/// One capability of the project, as it behaves today.
///
/// This is the half a backlog does not have. A backlog says what to do and then
/// forgets — a finished item is a paragraph in `completed/` about a day in
/// March, and the only remaining account of what the program actually does is
/// the program. The spec is the other account, and it is worth keeping because
/// it is the one somebody can read in an afternoon and an agent can be handed
/// before it starts.
public struct SpecDocument: Equatable, Sendable {
	/// The file's own name, without `.md`: `terminal`, `editor`, `git`.
	public let capability: String
	/// The title and whatever prose comes before the first requirement, kept
	/// exactly as it was written.
	public let preamble: String
	public var requirements: [SpecRequirement]

	public init(capability: String, preamble: String, requirements: [SpecRequirement]) {
		self.capability = capability
		self.preamble = preamble
		self.requirements = requirements
	}

	public func requirement(named name: String) -> SpecRequirement? {
		requirements.first { $0.name == name }
	}

	/// The document as a file again.
	public var text: String {
		var parts: [String] = []
		let head = preamble.trimmingCharacters(in: .whitespacesAndNewlines)
		if !head.isEmpty { parts.append(head) }
		parts += requirements.map(\.text)
		return parts.joined(separator: "\n\n") + "\n"
	}

	public static func read(_ url: URL) throws -> SpecDocument {
		let text = try String(contentsOf: url, encoding: .utf8)
		return parse(text, capability: url.deletingPathExtension().lastPathComponent)
	}

	public static func parse(_ text: String, capability: String) -> SpecDocument {
		var preamble: [String] = []
		var requirements: [SpecRequirement] = []
		var name: String?
		var body: [String] = []

		func flush() {
			guard let current = name else { return }
			requirements.append(SpecRequirement(name: current, body: body.joined(separator: "\n")))
			body = []
		}

		for line in text.components(separatedBy: "\n") {
			if let heading = SpecHeading(line: line), heading.change == nil {
				flush()
				name = heading.name
			} else if name == nil {
				preamble.append(line)
			} else {
				body.append(line)
			}
		}
		flush()

		return SpecDocument(
			capability: capability,
			preamble: preamble.joined(separator: "\n"),
			requirements: requirements
		)
	}
}

/// What a delta does to one requirement.
public enum SpecChange: String, Sendable, CaseIterable {
	case added = "ADDED"
	case modified = "MODIFIED"
	case removed = "REMOVED"
}

/// A `## ADDED Requirement: …` line, or a plain `## Requirement: …` one.
///
/// The three verbs are openspec's, and there are three rather than four
/// because a rename is a `REMOVED` and an `ADDED` and saying so keeps the fold
/// honest: a renamed requirement whose text also changed, folded by a rule
/// that only moves the heading, silently keeps the old sentence.
struct SpecHeading {
	let change: SpecChange?
	let name: String

	init?(line: String) {
		guard line.hasPrefix("## ") else { return nil }
		let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)

		if let change = SpecChange.allCases.first(where: { rest.hasPrefix($0.rawValue + " Requirement:") }) {
			self.change = change
			self.name = String(rest.dropFirst((change.rawValue + " Requirement:").count))
				.trimmingCharacters(in: .whitespaces)
			return
		}
		guard rest.hasPrefix("Requirement:") else { return nil }
		self.change = nil
		self.name = String(rest.dropFirst("Requirement:".count)).trimmingCharacters(in: .whitespaces)
	}
}

/// What one item proposes to change about one capability.
public struct SpecDelta: Equatable, Sendable {
	public struct Entry: Equatable, Sendable {
		public let change: SpecChange
		public let requirement: SpecRequirement
	}

	public let capability: String
	public let entries: [Entry]

	public init(capability: String, entries: [Entry]) {
		self.capability = capability
		self.entries = entries
	}

	public static func read(_ url: URL) throws -> SpecDelta {
		let text = try String(contentsOf: url, encoding: .utf8)
		return parse(text, capability: url.deletingPathExtension().lastPathComponent)
	}

	public static func parse(_ text: String, capability: String) -> SpecDelta {
		var entries: [Entry] = []
		var change: SpecChange?
		var name: String?
		var body: [String] = []

		func flush() {
			guard let change, let name else { return }
			entries.append(Entry(change: change, requirement: SpecRequirement(name: name, body: body.joined(separator: "\n"))))
			body = []
		}

		for line in text.components(separatedBy: "\n") {
			if let heading = SpecHeading(line: line), let kind = heading.change {
				flush()
				change = kind
				name = heading.name
			} else if name != nil {
				body.append(line)
			}
		}
		flush()

		return SpecDelta(capability: capability, entries: entries)
	}
}

/// Folding a delta into the spec, and saying so when it will not go.
public enum SpecFold {
	/// A delta that does not describe the spec it is being folded into.
	///
	/// Every one of these means the item and the spec disagree about what the
	/// project currently does, which is worth a sentence rather than a merge:
	/// an `ADDED` for something that is already there is usually two people
	/// having written the same requirement twice, and quietly overwriting one
	/// with the other is how the second person's wording disappears.
	public struct Problem: Equatable, Sendable, CustomStringConvertible {
		public let capability: String
		public let change: SpecChange
		public let requirement: String
		public let reason: String

		public var description: String {
			"\(capability): \(change.rawValue) \u{201C}\(requirement)\u{201D} — \(reason)"
		}
	}

	public struct Result: Sendable {
		public let document: SpecDocument
		public let problems: [Problem]
		/// Whether anything actually changed, so a fold that is entirely
		/// problems does not rewrite the file with itself.
		public let changed: Bool
	}

	/// Applies a delta to a document, in the order the delta is written.
	///
	/// Nothing is applied halfway: an entry that cannot be applied is reported
	/// and skipped, and the rest go in. The alternative — refusing the whole
	/// delta over one stale heading — makes the honest thing (fold as you
	/// finish) worse than the dishonest one (never fold at all).
	public static func apply(_ delta: SpecDelta, to document: SpecDocument) -> Result {
		var result = document
		var problems: [Problem] = []
		var changed = false

		for entry in delta.entries {
			let existing = result.requirements.firstIndex { $0.name == entry.requirement.name }
			switch entry.change {
			case .added:
				guard existing == nil else {
					problems.append(Problem(
						capability: delta.capability,
						change: .added,
						requirement: entry.requirement.name,
						reason: "the spec already has a requirement by that name — MODIFIED, or a different name"
					))
					continue
				}
				result.requirements.append(entry.requirement)
				changed = true

			case .modified:
				guard let index = existing else {
					problems.append(Problem(
						capability: delta.capability,
						change: .modified,
						requirement: entry.requirement.name,
						reason: "the spec has no requirement by that name — ADDED, or the name has drifted"
					))
					continue
				}
				guard result.requirements[index] != entry.requirement else { continue }
				result.requirements[index] = entry.requirement
				changed = true

			case .removed:
				guard let index = existing else {
					problems.append(Problem(
						capability: delta.capability,
						change: .removed,
						requirement: entry.requirement.name,
						reason: "the spec has no requirement by that name — already folded, or never there"
					))
					continue
				}
				result.requirements.remove(at: index)
				changed = true
			}
		}

		return Result(document: result, problems: problems, changed: changed)
	}
}

/// The global spec as a whole: the files under `backlog/spec/`, and folding an
/// item's deltas into them.
public struct BacklogSpecStore: Sendable {
	public let backlog: Backlog

	public init(backlog: Backlog) {
		self.backlog = backlog
	}

	/// Every capability, in name order.
	public func documents() -> [SpecDocument] {
		let manager = FileManager.default
		guard let names = try? manager.contentsOfDirectory(atPath: backlog.specDirectory.path) else { return [] }
		return names.sorted()
			// The folder's own README explains what the format is. It is not a
			// capability, and counting it as one made a fresh project report a
			// spec with one capability and no requirements in it.
			.filter { $0.hasSuffix(".md") && $0 != "README.md" }
			.compactMap { try? SpecDocument.read(backlog.specDirectory.appendingPathComponent($0)) }
	}

	public func url(for capability: String) -> URL {
		backlog.specDirectory.appendingPathComponent("\(capability).md")
	}

	/// The capability as it stands, or an empty one when the delta is the first
	/// thing anybody has said about it.
	public func document(for capability: String) -> SpecDocument {
		let file = url(for: capability)
		if let existing = try? SpecDocument.read(file) { return existing }
		return SpecDocument(
			capability: capability,
			preamble: "# \(BacklogItem.titleFromSlug(capability))\n",
			requirements: []
		)
	}

	/// What folding this item's deltas in would do, without doing it.
	///
	/// The point of being able to ask: `ready` means an agent may pick the item
	/// up, and a delta that cannot be folded is not ready — it is a description
	/// of a spec that has moved on since it was written.
	public func check(_ item: BacklogItem) -> [SpecFold.Problem] {
		item.specDeltas().flatMap { file -> [SpecFold.Problem] in
			guard let delta = try? SpecDelta.read(file) else { return [] }
			return SpecFold.apply(delta, to: document(for: delta.capability)).problems
		}
	}

	/// Folds every delta an item carries into the spec, and says what would not
	/// go. The item's own delta files are left where they are: they are the
	/// record of what this change was, the same way its prose is.
	@discardableResult
	public func fold(_ item: BacklogItem) throws -> [SpecFold.Problem] {
		var problems: [SpecFold.Problem] = []
		try FileManager.default.createDirectory(at: backlog.specDirectory, withIntermediateDirectories: true)

		for file in item.specDeltas() {
			let delta = try SpecDelta.read(file)
			let result = SpecFold.apply(delta, to: document(for: delta.capability))
			problems += result.problems
			guard result.changed else { continue }
			try result.document.text.write(to: url(for: delta.capability), atomically: true, encoding: .utf8)
		}
		return problems
	}
}
