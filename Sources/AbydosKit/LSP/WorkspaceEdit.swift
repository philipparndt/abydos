import Foundation

/// One replacement inside a document, as a server describes it.
///
/// The range is against the document *as the server last saw it*, and every
/// edit in one `TextDocumentEdit` is against that same original — they are not
/// applied one after another with the later ones seeing the earlier ones' work.
/// That is why `applied(to:)` below goes backwards through the file.
public struct LSPTextEdit: Equatable, Sendable {
	public var range: LSPRange
	public var newText: String

	public init(range: LSPRange, newText: String) {
		self.range = range
		self.newText = newText
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let range = LSPRange(json: dictionary["range"]),
		      let text = dictionary["newText"] as? String
		else { return nil }
		self.init(range: range, newText: text)
	}

	/// `AnnotatedTextEdit` is a `TextEdit` with a label on it for a client that
	/// offers to apply half an edit. This one does not, so the label is dropped
	/// and the edit is an edit — which is why nothing here looks at
	/// `annotationId`.
	public static func list(from result: Any?) -> [LSPTextEdit] {
		guard let array = result as? [Any] else { return [] }
		return array.compactMap { LSPTextEdit(json: $0) }
	}
}

/// What a server says is renameable at a position.
///
/// The answer to `prepareRename`, and the reason to ask it: a server that says
/// nothing is here says so, and the editor never offers a rename that would
/// come back as an error. Where a server *is* willing, it also says what to put
/// in the field and how much of the file to highlight, both of which the editor
/// would otherwise have to guess by scanning for a word.
public struct LSPRenameTarget: Equatable, Sendable {
	/// What would be replaced. Nil when the server said only that renaming is
	/// allowed here and left the editor to work the extent out.
	public var range: LSPRange?
	/// The text the field starts with. Nil for the same reason.
	///
	/// Not always the source text: a server may offer `foo` for a symbol
	/// written `` `foo` `` or `@foo`, which is what somebody would want to type
	/// over.
	public var placeholder: String?

	public init(range: LSPRange? = nil, placeholder: String? = nil) {
		self.range = range
		self.placeholder = placeholder
	}

	public init?(json: Any?) {
		// `null` is the server saying there is nothing here to rename. An
		// answer, not a failure, and the difference is whether anything is said
		// out loud.
		guard let dictionary = json as? [String: Any] else { return nil }

		// `{ defaultBehavior: true }` — renameable, and the extent is the
		// editor's business. False would mean not renameable, which is `null`
		// said the long way.
		if let behaviour = dictionary["defaultBehavior"] as? Bool {
			guard behaviour else { return nil }
			self.init()
			return
		}
		// `{ range, placeholder }`, or a bare `Range`.
		if let range = LSPRange(json: dictionary["range"]) {
			self.init(range: range, placeholder: dictionary["placeholder"] as? String)
			return
		}
		guard let range = LSPRange(json: dictionary) else { return nil }
		self.init(range: range)
	}
}

/// Everything a server wants done to the project, in the order it wants it.
///
/// Two shapes on the wire and one type here. `changes` is a map from URI to
/// edits and carries text only; `documentChanges` is an ordered list that can
/// also create, rename and delete files — which is how a Java rename moves
/// `Foo.java` to `Bar.java` as part of renaming the class in it.
///
/// **`documentChanges` wins when a server sends both.** They are the same edit
/// said twice for clients that understand only the older shape, and applying
/// both would apply everything twice. The protocol says a client that
/// understands the newer one must ignore the older, and this one says so in its
/// capabilities.
///
/// A map has no order, so `changes` is sorted by URI. Nothing depends on it —
/// the files are disjoint by construction — but a plan that comes out in a
/// different order on two runs is a plan nobody can write a test about.
public struct WorkspaceEdit: Equatable, Sendable {
	/// One thing to do, and the four are all a server can ask for.
	public enum Change: Equatable, Sendable {
		/// Text inside one document.
		case edits(uri: String, [LSPTextEdit])
		case create(uri: String, overwrite: Bool, ignoreIfExists: Bool)
		case rename(from: String, to: String, overwrite: Bool, ignoreIfExists: Bool)
		case delete(uri: String, recursive: Bool, ignoreIfNotExists: Bool)

		/// The document this is about, for saying what an edit touches without
		/// caring which kind it is. A rename names the file it starts as.
		public var uri: String {
			switch self {
			case let .edits(uri, _): return uri
			case let .create(uri, _, _): return uri
			case let .rename(from, _, _, _): return from
			case let .delete(uri, _, _): return uri
			}
		}
	}

	public var changes: [Change]

	public init(changes: [Change]) {
		self.changes = changes
	}

	public var isEmpty: Bool { changes.isEmpty }

	/// Every file this edit says anything about, in the order it says it, with
	/// no file named twice. What a summary counts.
	public var files: [String] {
		var seen: Set<String> = []
		var order: [String] = []
		for change in changes {
			for uri in [change.uri] + (change.renamedTo.map { [$0] } ?? []) {
				guard seen.insert(uri).inserted else { continue }
				order.append(uri)
			}
		}
		return order
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any] else { return nil }

		if let documentChanges = dictionary["documentChanges"] as? [Any] {
			// All of it or none of it. An entry this client cannot read — a kind
			// added to the protocol since, a shape a server got wrong — dropped
			// quietly would apply most of somebody's refactoring and leave the
			// rest, which is the halfway state this whole mechanism exists to
			// avoid. Refusing here means the offer never appears, and the person
			// still has their project.
			let changes = documentChanges.compactMap(Self.change(from:))
			guard changes.count == documentChanges.count else { return nil }
			self.init(changes: changes)
			return
		}
		guard let table = dictionary["changes"] as? [String: Any] else { return nil }
		self.init(changes: table
			.sorted { $0.key < $1.key }
			.map { .edits(uri: $0.key, LSPTextEdit.list(from: $0.value)) })
	}

	/// One entry of `documentChanges`, which is either a `TextDocumentEdit` or
	/// one of the three file operations.
	///
	/// A `TextDocumentEdit` has no `kind`, which is what tells the two apart —
	/// the file operations are a tagged union and the text one is not.
	private static func change(from entry: Any) -> Change? {
		guard let dictionary = entry as? [String: Any] else { return nil }

		guard let kind = dictionary["kind"] as? String else {
			guard let document = dictionary["textDocument"] as? [String: Any],
			      let uri = document["uri"] as? String
			else { return nil }
			return .edits(uri: uri, LSPTextEdit.list(from: dictionary["edits"]))
		}

		// The three flags live in an `options` object, and a server that sends no
		// options means the defaults: do not overwrite, do not skip, and a
		// delete is of one file rather than a tree.
		let options = dictionary["options"] as? [String: Any] ?? [:]
		let overwrite = options["overwrite"] as? Bool ?? false
		let ignoreIfExists = options["ignoreIfExists"] as? Bool ?? false

		switch kind {
		case "create":
			guard let uri = dictionary["uri"] as? String else { return nil }
			return .create(uri: uri, overwrite: overwrite, ignoreIfExists: ignoreIfExists)
		case "rename":
			guard let from = dictionary["oldUri"] as? String,
			      let to = dictionary["newUri"] as? String
			else { return nil }
			return .rename(from: from, to: to, overwrite: overwrite, ignoreIfExists: ignoreIfExists)
		case "delete":
			guard let uri = dictionary["uri"] as? String else { return nil }
			return .delete(
				uri: uri,
				recursive: options["recursive"] as? Bool ?? false,
				ignoreIfNotExists: options["ignoreIfNotExists"] as? Bool ?? false
			)
		default:
			// A kind this client has never heard of. Dropping it silently would
			// apply most of somebody's refactoring, so the plan refuses the whole
			// edit rather than part of it — see `WorkspaceEditPlan`, which is why
			// this is `nil` and not an empty list of edits.
			return nil
		}
	}
}

public extension WorkspaceEdit.Change {
	/// Where a rename puts the file, and nil for everything else.
	var renamedTo: String? {
		guard case let .rename(_, to, _, _) = self else { return nil }
		return to
	}
}

// MARK: - Applying edits to text

public extension LSPTextEdit {
	/// The text with these edits in it, or nil when one of them names a place
	/// the text does not have.
	///
	/// **Backwards, by start position.** Every edit in a set is against the same
	/// original text, so applying them front to back would have each one shifted
	/// by however much the ones before it grew or shrank the file. Going from
	/// the end means no edit has moved by the time it is applied, and no offsets
	/// have to be adjusted — which is the arithmetic this would otherwise have
	/// to get right for every one of forty files.
	///
	/// Overlapping edits are refused rather than resolved. The protocol forbids
	/// them and a server that sends them is confused about the file; picking a
	/// winner would write something neither the server nor the person asked for.
	static func applied(_ edits: [LSPTextEdit], to text: String) -> String? {
		guard !edits.isEmpty else { return text }

		let units = Array(text.utf16)
		let starts = lineStarts(in: units)

		var resolved: [(range: Range<Int>, text: String)] = []
		resolved.reserveCapacity(edits.count)
		for edit in edits {
			guard let start = offset(
				of: edit.range.start, lineStarts: starts, count: units.count, units: units
			),
			let end = offset(
				of: edit.range.end, lineStarts: starts, count: units.count, units: units
			),
			start <= end
			else { return nil }
			resolved.append((start..<end, edit.newText))
		}

		// Sorted by where they start, so overlap is a comparison with the one
		// before rather than a search. A zero-width insertion at the same place
		// as another is not an overlap — two servers do it for imports — so the
		// test is on ranges that actually cover a shared character.
		resolved.sort { $0.range.lowerBound < $1.range.lowerBound }
		for (earlier, later) in zip(resolved, resolved.dropFirst()) {
			if later.range.lowerBound < earlier.range.upperBound { return nil }
		}

		var result = units
		for edit in resolved.reversed() {
			result.replaceSubrange(edit.range, with: Array(edit.text.utf16))
		}
		return String(decoding: result, as: UTF16.self)
	}

	/// Where each line begins, counted in UTF-16 units.
	///
	/// The protocol's three terminators, because a file with Windows line
	/// endings is a file somebody has: `\n`, `\r\n` and a bare `\r`. Getting
	/// `\r\n` wrong by one would put every edit in the file one character early,
	/// which is a rename that eats the character before each use of the symbol.
	private static func lineStarts(in units: [UInt16]) -> [Int] {
		var starts = [0]
		var index = 0
		while index < units.count {
			let unit = units[index]
			if unit == 0x0A {
				starts.append(index + 1)
			} else if unit == 0x0D {
				let isPair = index + 1 < units.count && units[index + 1] == 0x0A
				starts.append(index + (isPair ? 2 : 1))
				if isPair { index += 1 }
			}
			index += 1
		}
		return starts
	}

	/// A protocol position as an offset into the UTF-16 units.
	///
	/// A character past the end of its line is clamped to the end of that line
	/// rather than refused: servers name the end of a line as a very large
	/// character number, and the protocol says to clamp. A *line* past the end
	/// of the file is refused, because that is a server talking about a document
	/// it no longer has — the case worth failing on.
	///
	/// **Clamped to the text of the line and not past its newline.** The
	/// difference is one character and it is the whole edit: a server naming the
	/// end of a line as character 999 would otherwise get an offset after the
	/// terminator, and a rename there swallows the line break and joins two
	/// lines of somebody's file together.
	private static func offset(
		of position: LSPPosition, lineStarts: [Int], count: Int, units: [UInt16]
	) -> Int? {
		guard position.line >= 0, position.character >= 0 else { return nil }
		// One past the last line means the very end of the file, which is what a
		// server sends for an edit that appends.
		if position.line == lineStarts.count { return position.character == 0 ? count : nil }
		guard position.line < lineStarts.count else { return nil }

		let start = lineStarts[position.line]
		var end = position.line + 1 < lineStarts.count ? lineStarts[position.line + 1] : count
		while end > start, units[end - 1] == 0x0A || units[end - 1] == 0x0D { end -= 1 }
		return min(start + position.character, end)
	}
}
