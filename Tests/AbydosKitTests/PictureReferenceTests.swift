import Foundation
import Testing
@testable import AbydosKit

/// A picture pasted into a document: where it goes, what it is called, and
/// what the document says about it.
struct PictureReferenceTests {
	private let notes = URL(fileURLWithPath: "/p/docs/notes.md")
	private func taken(_ paths: String...) -> (URL) -> Bool {
		let set = Set(paths)
		return { set.contains($0.standardizedFileURL.path) }
	}

	@Test func aMarkdownDocumentGetsAnImageReferenceWithTheCaretInTheBrackets() {
		let made = PictureReference.make(for: notes, language: "markdown", isTaken: taken())
		#expect(made?.text == "![](images/notes-1.png)")
		#expect(made?.caretOffset == 2)
	}

	@Test func theFolderIsImagesBesideTheDocument() {
		let made = PictureReference.make(for: notes, language: "markdown", isTaken: taken())
		#expect(made?.folder.path == "/p/docs/images")
		#expect(made?.file.path == "/p/docs/images/notes-1.png")
	}

	@Test func anHtmlDocumentGetsAnImgTagWithTheCaretInsideAlt() {
		let index = URL(fileURLWithPath: "/p/docs/index.html")
		let made = PictureReference.make(for: index, language: "html", isTaken: taken())
		#expect(made?.text == "<img src=\"images/index-1.png\" alt=\"\">")
		// Inside the quotes of `alt`, so what is typed next is the description.
		let text = made?.text ?? ""
		let caret = made?.caretOffset ?? 0
		#expect((text as NSString).substring(to: caret).hasSuffix("alt=\""))
		#expect((text as NSString).substring(from: caret) == "\">")
	}

	@Test func aSecondPictureIsNumberedTwo() {
		let made = PictureReference.make(
			for: notes, language: "markdown", isTaken: taken("/p/docs/images/notes-1.png")
		)
		#expect(made?.file.lastPathComponent == "notes-2.png")
	}

	/// The name is the only thing that says which document a picture belongs
	/// to once the folder is shared.
	@Test func twoDocumentsInOneFolderDoNotShareNames() {
		let readme = URL(fileURLWithPath: "/p/docs/readme.md")
		let a = PictureReference.make(for: notes, language: "markdown", isTaken: taken())
		let b = PictureReference.make(for: readme, language: "markdown", isTaken: taken())
		#expect(a?.file.lastPathComponent == "notes-1.png")
		#expect(b?.file.lastPathComponent == "readme-1.png")
	}

	/// Pixels into a Swift file would be a stray screenshot in the source tree.
	@Test func aLanguageWithNoPictureSyntaxGetsNothing() {
		let main = URL(fileURLWithPath: "/p/Sources/main.swift")
		#expect(PictureReference.make(for: main, language: "swift", isTaken: taken()) == nil)
		#expect(PictureReference.make(for: main, language: nil, isTaken: taken()) == nil)
		#expect(!PictureReference.hasSyntax("swift"))
		#expect(PictureReference.hasSyntax("markdown"))
	}

	@Test func thePathIsRelativeToTheDocumentHoweverDeepItIs() {
		let deep = URL(fileURLWithPath: "/p/a/b/c/guide.md")
		let made = PictureReference.make(for: deep, language: "markdown", isTaken: taken())
		#expect(made?.text == "![](images/guide-1.png)")
		#expect(made?.folder.path == "/p/a/b/c/images")
	}
}
