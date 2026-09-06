import Foundation

/// Asking Claude what a file, or a selection of it, is.
///
/// In `ClaudeDraft`'s shape where it can be: the same command, the same stdin
/// prompt, the same *absent without the command*. What it sends is bounded
/// by construction — the head, the tail, the selection up to a limit, the
/// statistics' summary, the strings found and the parsed tree when there is
/// one — so Claude extends the parsed structure rather than re-deriving it,
/// and it never sends the file. What comes back is a paragraph and rows in
/// the tree's own shape, every one marked as Claude's, because an answer
/// about a sample is a reading and not a fact.
public enum HexAnalysis {
	/// How much of the file goes: the head, the tail, and the selection when
	/// the ask is about one. Characters of hex dump are about three times
	/// these, which is a request of a few tens of kilobytes at most.
	public static let headBytes = 4096
	public static let tailBytes = 1024
	public static let selectionBytes = 8192
	/// How many strings and how many tree rows are worth sending.
	public static let stringsSent = 60
	public static let treeRowsSent = 200

	/// What would be sent.
	public struct Ask: Sendable, Equatable {
		public let prompt: String
		/// The selection the ask is about, or nil for the file.
		public let about: Range<Int>?
		/// How many of the file's bytes were dumped into it.
		public let sampledBytes: Int
	}

	/// What came back, parsed.
	public struct Answer: Sendable, Equatable {
		public let summary: String
		/// Rows in the tree's shape, `source: .claude`, in file order, none
		/// outside the file.
		public let nodes: [StructureNode]
		/// The prompt it answered, for *Show what was asked*.
		public let prompt: String
	}

	public enum Failure: Error, Sendable, Equatable {
		case notInstalled
		case cancelled
		/// The command ran and said something that was not an answer.
		case said(String)

		public var said: String {
			switch self {
			case .notInstalled: return "The claude command is not installed."
			case .cancelled: return "Cancelled."
			case .said(let text): return text
			}
		}
	}

	public static var isAvailable: Bool { ClaudeCommand.isAvailable }

	// MARK: - What is sent

	public static func ask(
		_ snapshot: ByteDocument.Snapshot,
		fileName: String,
		selection: Range<Int>? = nil,
		statistics: ByteStatistics? = nil,
		strings: PrintableStrings.Listing? = nil,
		structure: StructureNode? = nil
	) -> Ask {
		var sampled = 0
		var parts: [String] = []

		let about = selection.flatMap { $0.isEmpty ? nil : $0 }
		parts.append(about == nil
			? "Say what the file below is and how its bytes are laid out."
			: "Say what the selected bytes of the file below are, in the context of the file around them.")
		parts.append("""
		The file is \(fileName), \(ByteSize.said(Int64(snapshot.count))) (\(snapshot.count) bytes). \
		You are shown a sample of it, not the whole file: say only what the bytes shown support, \
		and give an offset and length only for a field whose bytes you can see.
		""")

		if let statistics {
			parts.append(statisticsSaid(statistics))
		}
		if let structure {
			parts.append("A parser that knows the format already read this much; extend it rather than repeat it:\n\n" + described(structure))
		} else {
			parts.append("No built-in parser recognised the format.")
		}
		if let strings, !strings.strings.isEmpty {
			let shown = strings.strings.prefix(stringsSent).map { "  0x\(String($0.offset, radix: 16, uppercase: true)): \($0.text.prefix(80))" }
			parts.append("Printable strings found (offset: text), the first \(shown.count) of \(strings.strings.count + strings.unlisted):\n" + shown.joined(separator: "\n"))
		}

		let head = 0..<min(headBytes, snapshot.count)
		parts.append("The first \(head.count) bytes:\n\n" + dump(snapshot, head))
		sampled += head.count
		if snapshot.count > headBytes + tailBytes {
			let tail = (snapshot.count - tailBytes)..<snapshot.count
			parts.append("The last \(tail.count) bytes:\n\n" + dump(snapshot, tail))
			sampled += tail.count
		} else if snapshot.count > headBytes {
			let rest = headBytes..<snapshot.count
			parts.append("The rest, \(rest.count) bytes:\n\n" + dump(snapshot, rest))
			sampled += rest.count
		}
		if let about {
			let shown = about.lowerBound..<min(about.upperBound, about.lowerBound + selectionBytes)
			let note = shown.count < about.count ? " (the first \(shown.count) of \(about.count) selected)" : ""
			parts.append("The selection, 0x\(String(about.lowerBound, radix: 16, uppercase: true))–0x\(String(about.upperBound - 1, radix: 16, uppercase: true))\(note):\n\n" + dump(snapshot, shown))
			sampled += shown.count
		}

		parts.append("""
		Answer with one JSON object and nothing else — no preamble, no code fences:

		{"summary": "<one or two paragraphs, plain text>",
		 "fields": [{"name": "<short name>", "offset": <byte offset as a number>, "length": <bytes>, "meaning": "<what it is and what its value means>"}]}

		Offsets are from the start of the file, in decimal. Order the fields by offset. Give at most forty. \
		If you cannot tell what the file is, say so in the summary and give no fields.
		""")

		return Ask(prompt: parts.joined(separator: "\n\n"), about: about, sampledBytes: sampled)
	}

	/// Sixteen bytes a row with the offset and the text column, as the
	/// editor shows it, so an offset Claude names is one it read.
	static func dump(_ snapshot: ByteDocument.Snapshot, _ range: Range<Int>) -> String {
		var lines: [String] = []
		var offset = range.lowerBound
		while offset < range.upperBound {
			let end = min(range.upperBound, offset + 16)
			let bytes = snapshot.bytes(in: offset..<end)
			let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
			let text = bytes.map { ($0 >= 0x20 && $0 < 0x7F) ? String(UnicodeScalar($0)) : "." }.joined()
			lines.append(String(format: "%08X  %-47@  %@", offset, hex as NSString, text as NSString))
			offset = end
		}
		return lines.joined(separator: "\n")
	}

	static func statisticsSaid(_ statistics: ByteStatistics) -> String {
		let done = statistics.blocks.compactMap { $0 }
		guard !done.isEmpty else { return "Entropy has not been measured yet." }
		let mean = done.reduce(0.0) { $0 + $1.entropy * Double($1.length) } / Double(max(1, done.reduce(0) { $0 + $1.length }))
		let zero = done.reduce(0) { $0 + $1.zero }, printable = done.reduce(0) { $0 + $1.printable }
		let total = max(1, done.reduce(0) { $0 + $1.length })
		var said = String(
			format: "Entropy over the file averages %.2f bits a byte; %d%% of bytes are zero and %d%% printable ASCII.",
			mean, zero * 100 / total, printable * 100 / total
		)
		let notes = statistics.notes
		if !notes.isEmpty {
			said += "\nRegions that look compressed or encrypted:\n" + notes.prefix(10).map { "  " + $0.said }.joined(separator: "\n")
		}
		return said
	}

	/// The parsed tree as indented lines, capped.
	static func described(_ node: StructureNode) -> String {
		var lines: [String] = []
		func walk(_ node: StructureNode, _ depth: Int) {
			guard lines.count < treeRowsSent else { return }
			var line = String(repeating: "  ", count: depth) + node.name
			if !node.range.isEmpty {
				line += " @0x\(String(node.range.lowerBound, radix: 16, uppercase: true)) +\(node.range.count)"
			}
			if let value = node.value { line += " = \(value)" }
			if let meaning = node.meaning { line += " (\(meaning))" }
			lines.append(line)
			for child in node.children { walk(child, depth + 1) }
		}
		walk(node, 0)
		if node.totalCount > treeRowsSent { lines.append("  … \(node.totalCount - treeRowsSent) more rows not shown") }
		return lines.joined(separator: "\n")
	}

	// MARK: - Reading what comes back

	/// The JSON object out of whatever surrounds it, into an answer. A row
	/// whose range falls outside the file is dropped rather than drawn.
	static func parse(_ text: String, count: Int, prompt: String) -> Answer? {
		var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
		// Fences stripped even though the prompt asks for none.
		if let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close {
			body = String(body[open...close])
		}
		guard let data = body.data(using: .utf8),
			  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }
		let summary = (object["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		var nodes: [StructureNode] = []
		for row in object["fields"] as? [[String: Any]] ?? [] {
			guard let name = row["name"] as? String, !name.isEmpty,
				  let offset = number(row["offset"]), let length = number(row["length"]),
				  offset >= 0, length >= 0, offset + length <= count
			else { continue }
			nodes.append(StructureNode(
				name: name,
				range: offset..<(offset + length),
				meaning: (row["meaning"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
				source: .claude
			))
		}
		nodes.sort { $0.range.lowerBound < $1.range.lowerBound }
		guard !summary.isEmpty || !nodes.isEmpty else { return nil }
		return Answer(summary: summary, nodes: nodes, prompt: prompt)
	}

	/// An offset as a number, or as `"0x10"` or `"16"` — models write both.
	private static func number(_ value: Any?) -> Int? {
		if let int = value as? Int { return int }
		if let double = value as? Double { return Int(double) }
		guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
		if text.lowercased().hasPrefix("0x") { return Int(text.dropFirst(2), radix: 16) }
		return Int(text)
	}

	// MARK: - Doing it

	public static func analyse(_ ask: Ask, count: Int, in root: URL) async -> Result<Answer, Failure> {
		guard let command = ClaudeCommand.executable() else { return .failure(.notInstalled) }
		let outcome = await ClaudeCommand.run(command, prompt: ask.prompt, in: root)
		if Task.isCancelled { return .failure(.cancelled) }
		guard outcome.exitCode == 0 else {
			let said = outcome.stderr.isEmpty ? outcome.stdout : outcome.stderr
			return .failure(.said(said.trimmingCharacters(in: .whitespacesAndNewlines)))
		}
		guard let answer = parse(outcome.stdout, count: count, prompt: ask.prompt) else {
			return .failure(.said("It answered with something that was not an answer:\n\(outcome.stdout.prefix(500))"))
		}
		return .success(answer)
	}
}
