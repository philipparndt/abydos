import Foundation

/// Commenting whole lines out and taking the comment off again, which is what
/// ⌘/ does.
///
/// A value rather than anything in a view, the shape `LineIndent` already uses
/// for ⇥ over a block: the lines go in, the lines come back out with the edits
/// that made them, and the editor's whole job is to replace the range and put
/// the selection back. That is what lets every rule below be a test rather than
/// something somebody checks by hand once.
///
/// The rules, each of which is a way this goes subtly wrong if it is not stated:
///
///  - **One direction for the whole block.** If every non-blank line in the
///    range is already commented, the press uncomments; otherwise it comments
///    all of them. Toggling each line on its own inverts a half-commented block,
///    which is a thing nobody wants twice.
///  - **The token goes at the shallowest indent the range shares**, not at
///    column zero, or commenting an indented block flattens the shape somebody
///    is reading it by.
///  - **Blank lines are left alone and do not count**, either way. A `//` on an
///    empty line is trailing rubbish, and one empty line inside a commented
///    block must not be the thing that decides the block is not commented.
///  - **Uncommenting removes exactly what commenting inserts** — the token, and
///    the one space after it only if it is there. A file whose author wrote
///    `//code` comes back as `code`, never as ` code`.
public enum LineComment {
	/// What one press comes to.
	public enum Outcome: Equatable, Sendable {
		/// The block, rewritten, and enough to put the selection back over the
		/// same characters.
		case toggled(Toggle)
		/// Nothing to do. An empty range, or one with nothing but blank lines in
		/// it — see the rule about blank lines above.
		case nothing
		/// The language has no line comment. The sentence is `CommentSyntax`'s
		/// and is meant to be said out loud once, because a keystroke that
		/// silently does nothing is worse than either a refusal or a mangling.
		case unavailable(String)
	}

	/// The rewritten block, and the arithmetic for anything that was sitting in
	/// it.
	public struct Toggle: Equatable, Sendable {
		/// One line's change: at `column` — UTF-16 units into that line —
		/// `removed` units go and `inserted` arrives in their place.
		///
		/// UTF-16 because that is the unit the view counts offsets in, so the
		/// column needs no conversion at the point it is used.
		public struct Edit: Equatable, Sendable {
			public let column: Int
			public let removed: Int
			public let inserted: String

			public init(column: Int, removed: Int, inserted: String) {
				self.column = column
				self.removed = removed
				self.inserted = inserted
			}

			/// A line nothing happens to. Every blank line is one of these.
			static let none = Edit(column: 0, removed: 0, inserted: "")

			var isEmpty: Bool { removed == 0 && inserted.isEmpty }
		}

		/// The block as it now reads, ready to replace the range it came from —
		/// one replacement and therefore one undo, however many lines it was.
		public let text: String
		/// Which way this press went. The only thing that reads it is whatever
		/// names the undo entry.
		public let commenting: Bool
		/// One per line of the block, in order, **including the lines nothing
		/// happened to**. Index-aligned rather than sparse, so a caret's line
		/// finds its edit without a search and a test can read the list next to
		/// the block it came from.
		public let edits: [Edit]

		public init(text: String, commenting: Bool, edits: [Edit]) {
			self.text = text
			self.commenting = commenting
			self.edits = edits
		}

		/// Where a UTF-16 offset into the old block lands in the new one.
		///
		/// This is what keeps the selection over the same characters and stops
		/// the second ⌘/ acting on something else. Offsets are relative to the
		/// start of the block at both ends, so the caller adds the block's own
		/// start back on.
		///
		/// - Parameter isStartOfSelection: whether an offset sitting exactly where
		///   the token goes stays put instead of being carried along by it. The
		///   two ends of a gesture want opposite answers here, and a Makefile is
		///   where that shows: the token goes at column zero, and a caret at the
		///   front of the line belongs in front of the *code* afterwards — which
		///   is where somebody about to type expects to be — while the *start* of
		///   a whole-line selection has to stay at the front of the line, or three
		///   selected lines come back with the first two characters of the first
		///   one no longer highlighted.
		public func offset(_ offset: Int, isStartOfSelection: Bool = false) -> Int {
			var oldStart = 0
			var newStart = 0
			for (index, line) in text.components(separatedBy: "\n").enumerated() {
				let edit = index < edits.count ? edits[index] : Edit.none
				// The old line's length, from the new one and what happened to
				// it. Keeping the old lines as well would be a second copy of
				// the block that could come to disagree with this one.
				let oldLength = line.utf16.count - (edit.inserted.utf16.count - edit.removed)
				if offset <= oldStart + oldLength {
					return newStart + column(
						offset - oldStart, in: edit, isStartOfSelection: isStartOfSelection
					)
				}
				// Past this line's break, which neither side ever changes.
				oldStart += oldLength + 1
				newStart += line.utf16.count + 1
			}
			return text.utf16.count
		}

		/// Where a column within one line ends up.
		private func column(_ column: Int, in edit: Edit, isStartOfSelection: Bool) -> Int {
			guard edit.removed > 0 else {
				// An insertion carries along everything after it, and everything
				// *at* it as well unless this is the start of a selection: the
				// caret was in front of that character and belongs in front of it
				// still, which is what makes ⌘/ over a caret feel like the line
				// moved rather than the caret.
				let carried = isStartOfSelection ? column > edit.column : column >= edit.column
				return carried ? column + edit.inserted.utf16.count : column
			}
			if column <= edit.column { return column }
			if column >= edit.column + edit.removed {
				return column - edit.removed + edit.inserted.utf16.count
			}
			// Inside what went. There is nowhere else for a caret that was
			// sitting in the middle of the token to be.
			return edit.column + edit.inserted.utf16.count
		}
	}

	/// Comments the block out, or takes the comment off.
	///
	/// - Parameter block: whole lines, joined by `\n` and without a trailing
	///   break — the range a selection touches, which is what the caller has
	///   already had to work out to replace it. The same shape `LineIndent`
	///   takes, deliberately: the line range lives in the rope, and a second
	///   copy of "which lines does this selection touch" in here would be a
	///   second place for that answer to be wrong.
	public static func toggle(_ block: String, syntax: CommentSyntax) -> Outcome {
		let token: String
		switch syntax {
		case let .line(value): token = value
		case let .unavailable(reason): return .unavailable(reason)
		}

		let lines = block.components(separatedBy: "\n")
		let content = Set(lines.indices.filter { !isBlank(lines[$0]) })
		guard !content.isEmpty else { return .nothing }

		// The one decision for the whole block, taken over the non-blank lines
		// only. A blank line has no comment and never will have, so counting it
		// as uncommented would make one empty line in the middle of a commented
		// block flip the press back to *comment again*.
		let commenting = !content.allSatisfy { isCommented(lines[$0], token: token) }

		let edits = lines.indices.map { index -> Toggle.Edit in
			guard content.contains(index) else { return .none }
			return commenting
				? insertion(at: commonIndentWidth(of: lines, at: content), token: token)
				: removal(from: lines[index], token: token)
		}
		guard edits.contains(where: { !$0.isEmpty }) else { return .nothing }

		return .toggled(Toggle(
			text: applied(edits, to: lines), commenting: commenting, edits: edits
		))
	}

	/// Blank means nothing but whitespace, empty included.
	private static func isBlank(_ line: String) -> Bool {
		line.allSatisfy(\.isWhitespace)
	}

	/// Whether a line is already commented, which is the token being the first
	/// thing on it.
	///
	/// Deliberately not "the token followed by a space or the end of the line":
	/// `//code` has to count, or uncommenting a file somebody else commented
	/// leaves the `//` behind. The cost is that Swift's `/// doc` counts too and
	/// uncomments to `/ doc` — which is what Xcode and VS Code both do, and the
	/// alternative is this table knowing every language's doc-comment forms.
	private static func isCommented(_ line: String, token: String) -> Bool {
		line.drop(while: \.isWhitespace).hasPrefix(token)
	}

	/// The indentation every non-blank line in the range shares, as UTF-16 units.
	///
	/// The longest common *prefix* of their indents rather than the smallest
	/// visual width, and the difference is a file with both tabs and spaces in
	/// it: a width would name a column that falls inside a tab on one line and
	/// after two spaces on another, and inserting there splits the indentation
	/// it was meant to preserve. A shared prefix is by construction a position
	/// every one of these lines actually has.
	private static func commonIndentWidth(of lines: [String], at indices: Set<Int>) -> Int {
		var common: String?
		for index in indices.sorted() {
			let indent = String(lines[index].prefix { $0 == " " || $0 == "\t" })
			common = common.map { String($0.commonPrefix(with: indent)) } ?? indent
		}
		return common?.utf16.count ?? 0
	}

	/// The token and one space, which is what every uncomment then looks for.
	private static func insertion(at column: Int, token: String) -> Toggle.Edit {
		Toggle.Edit(column: column, removed: 0, inserted: token + " ")
	}

	/// Exactly what an insertion put there, and no more.
	///
	/// At the line's *own* indent rather than at the range's shared one: a file
	/// commented by another editor has its tokens at column zero, and this has
	/// to be able to take those off too.
	private static func removal(from line: String, token: String) -> Toggle.Edit {
		let indent = line.prefix { $0 == " " || $0 == "\t" }
		let rest = line[indent.endIndex...]
		guard rest.hasPrefix(token) else { return .none }

		// The single following space only if it is there. `//code` comes back as
		// `code`; taking a space that was never inserted would come back as
		// ` code` and quietly reindent somebody's file one column at a time.
		let removed = token.utf16.count + (rest.dropFirst(token.count).first == " " ? 1 : 0)
		return Toggle.Edit(column: indent.utf16.count, removed: removed, inserted: "")
	}

	private static func applied(_ edits: [Toggle.Edit], to lines: [String]) -> String {
		lines.indices.map { index -> String in
			let edit = edits[index]
			guard !edit.isEmpty else { return lines[index] }

			var units = Array(lines[index].utf16)
			units.replaceSubrange(
				edit.column..<(edit.column + edit.removed), with: Array(edit.inserted.utf16)
			)
			return String(decoding: units, as: UTF16.self)
		}.joined(separator: "\n")
	}
}
