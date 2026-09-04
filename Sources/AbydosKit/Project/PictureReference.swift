import Foundation

/// Where a picture pasted into a document goes, what it is called, and what
/// the document says about it.
///
/// The arithmetic of the editor's picture paste, kept out of the view so every
/// decision in it is a test: the folder is `images` beside the document, the
/// name is the document's stem with the first free number, the reference is
/// in the document's own syntax, and the caret goes where the description is
/// typed. `CodeView` reads the board, writes the bytes and replaces the text;
/// this says what with.
public struct PictureReference: Equatable {
	/// `images`, beside the document. Made by the caller if it is not there.
	public let folder: URL
	/// `images/notes-1.png` for `notes.md`: named for the document, so a folder
	/// shared by every document beside it still says which one a picture
	/// belongs to.
	public let file: URL
	/// What goes into the document, with the path relative to it.
	public let text: String
	/// Where the caret lands inside `text`, in UTF-16 units from its start:
	/// between `[` and `]`, or inside `alt=""`, so the next thing typed is the
	/// description.
	public let caretOffset: Int

	/// The languages that have a syntax for a picture, and the two halves the
	/// path goes between. A table rather than a switch so a third language is a
	/// row — and a language not on it pastes nothing, because a ⌘V aimed at the
	/// wrong tab would otherwise write a file into the source tree that
	/// nothing references, and the file is the expensive half of the mistake.
	static let syntaxes: [String: (opening: String, closing: String, caret: Int)] = [
		"markdown": (opening: "![](", closing: ")", caret: 2),
		"html": (opening: "<img src=\"", closing: "\" alt=\"\">", caret: 0),
	]

	/// Whether a document in this language can take a picture at all — what
	/// menu validation asks, and it asks on every opening of the Edit menu.
	public static func hasSyntax(_ language: String?) -> Bool {
		language.map { syntaxes[$0] != nil } ?? false
	}

	/// The reference for a picture pasted into `document`, or nil when the
	/// language has no syntax for one.
	///
	/// `isTaken` is injected so the naming is testable against a folder that
	/// does not exist: the caller asks the disk, a test asks a list.
	public static func make(
		for document: URL, language: String?, isTaken: (URL) -> Bool
	) -> PictureReference? {
		guard let language, let syntax = syntaxes[language] else { return nil }
		let folder = document.deletingLastPathComponent().appendingPathComponent("images")
		let stem = document.deletingPathExtension().lastPathComponent
		let file = FileTransfer.freeName(stem: stem, extension: "png", in: folder, isTaken: isTaken)
		let relative = "images/" + file.lastPathComponent
		let text = syntax.opening + relative + syntax.closing
		// HTML's caret is inside `alt=""`, which is after the path; Markdown's is
		// before it. The table says which by counting from the front for the
		// opening and from the back for the closing.
		let caret = syntax.caret > 0
			? syntax.caret
			: (text as NSString).length - 2
		return PictureReference(folder: folder, file: file, text: text, caretOffset: caret)
	}
}
