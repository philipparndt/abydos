import Foundation
import Testing
@testable import AbydosKit

/// The commit message and the pages a project is left with.
///
/// A commit message is the most expensive text in the app to lose: written once
/// from a diff somebody has just read, and typing it again means reading the
/// diff again. The pages are cheaper and still worth it — a page reopened blank
/// is a page somebody has to find their way back into.
struct ComposedMessageSessionTests {
	private func scratch() -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-composed-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func bothHalvesOfTheMessageComeBack() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		// `driven: false`, because a driven run deliberately reads and writes
		// nothing beside somebody's project — see `SessionStore`.
		try SessionStore.write(
			ProjectSession(composedMessage: .init(
				summary: "feat(navigator): compare a file from its row",
				description: "Both destinations existed and neither was reachable."
			)),
			in: root, driven: false
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.composedMessage?.summary == "feat(navigator): compare a file from its row")
		#expect(read.composedMessage?.description
			== "Both destinations existed and neither was reachable.")
	}

	/// The common shape: a subject and nothing else.
	@Test func aSummaryWithNoDescription() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(composedMessage: .init(summary: "fix: the pane keeps its scroll", description: "")),
			in: root, driven: false
		)
		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.composedMessage?.summary == "fix: the pane keeps its scroll")
		#expect(read.composedMessage?.description.isEmpty == true)
	}

	/// Nothing typed is nothing to remember: a session holding only an empty
	/// pair is empty, and an empty session deletes its file rather than leaving
	/// one behind that says nothing.
	@Test func anEmptyMessageIsNotASession() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(ProjectSession(composedMessage: .init(summary: "  ", description: "\n")).isEmpty)
		try SessionStore.write(
			ProjectSession(composedMessage: .init(summary: "", description: "")),
			in: root, driven: false
		)
		#expect(SessionStore.read(in: root, driven: false) == nil)
	}

	@Test func thePagesComeBackWithWhatTheyWereShowing() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(pages: [
				.init(identifier: "log", showing: ["ref": "origin/main", "path": "Sources/a.swift"]),
				.init(identifier: "commit"),
			]),
			in: root, driven: false
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.pages.count == 2)
		#expect(read.pages.first?.identifier == "log")
		#expect(read.pages.first?.showing["ref"] == "origin/main")
		#expect(read.pages.first?.showing["path"] == "Sources/a.swift")
		#expect(read.pages.last?.identifier == "commit")
		#expect(read.pages.last?.showing.isEmpty == true)
	}

	/// **Additive.** Every session written before these existed lacks the keys,
	/// and that has to read as "nothing typed, no pages" rather than as a
	/// version confused by its own older file.
	@Test func anOlderSessionFileStillReads() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try AbydosFolder.create(in: root)
		let file = AbydosFolder.sessionFile(in: root)
		try #"""
		{
		  "files": [{"path": "a.swift", "line": 12}],
		  "active": "a.swift"
		}
		"""#.write(to: file, atomically: true, encoding: .utf8)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.files.first?.path == "a.swift")
		#expect(read.composedMessage == nil)
		#expect(read.pages.isEmpty)
	}

	/// A page entry with no identifier is nothing to reopen: dropped rather
	/// than guessed at, the way an unknown preview mode is.
	@Test func aPageWithNoIdentifierIsDropped() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try AbydosFolder.create(in: root)
		let file = AbydosFolder.sessionFile(in: root)
		try #"""
		{
		  "files": [{"path": "a.swift", "line": 1}],
		  "pages": [{"showing": {"ref": "main"}}, {"id": "commit"}]
		}
		"""#.write(to: file, atomically: true, encoding: .utf8)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.pages.map(\.identifier) == ["commit"])
	}

	/// A folder in no working copy has nothing to commit and no history to page
	/// through, so neither travels with it.
	@Test func aLooseFolderKeepsNeither() {
		let session = ProjectSession(
			files: [.init(path: "a.txt")],
			composedMessage: .init(summary: "fix: something", description: ""),
			pages: [.init(identifier: "log")]
		)
		#expect(session.filesOnly.composedMessage == nil)
		#expect(session.filesOnly.pages.isEmpty)
		#expect(session.filesOnly.files.count == 1)
	}
}
