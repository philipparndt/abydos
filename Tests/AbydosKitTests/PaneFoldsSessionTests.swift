import Foundation
import Testing
@testable import AbydosKit

/// The shape somebody arranged the panes into, kept beside the project.
///
/// Reported as the git panel's "Working copy" section being shut again every
/// time somebody comes back to a project. It was shut again several times
/// *within* a sitting, because the pane holding the fold is thrown away and
/// rebuilt — on a project switch, when `readGit()` lands on a different work
/// tree, and when a tool shown over the terminal is put away.
struct PaneFoldsSessionTests {
	private func scratch() -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-folds-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	/// `driven: false` throughout, because a driven run deliberately reads and
	/// writes nothing beside somebody's project — see `SessionStore`.
	@Test func aTreesFoldsComeBack() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(
				files: [.init(path: root.appendingPathComponent("a.swift").path)],
				folds: [
					"refs": .init(shut: ["working"], opened: ["section:origin"]),
					"tree": .init(opened: ["Sources", "Sources/AbydosKit"]),
				]
			),
			in: root, driven: false
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.folds["refs"]?.shut == ["working"])
		#expect(read.folds["refs"]?.opened == ["section:origin"])
		#expect(read.folds["tree"]?.opened == ["Sources", "Sources/AbydosKit"])
		#expect(read.folds["tree"]?.shut.isEmpty == true)
	}

	/// **Both ways round, and that is the point of two lists.** A refs tree
	/// arrives open and records what was shut; `origin` and `Tags` arrive shut
	/// and record what was opened. One list of "expanded things" would have to
	/// guess which rule each key was under.
	@Test func theTwoSetsDoNotBecomeOne() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		let folds = ProjectSession.TreeFolds(shut: ["working"], opened: ["section:Tags"])
		try SessionStore.write(
			ProjectSession(files: [.init(path: "/x")], folds: ["refs": folds]),
			in: root, driven: false
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.folds["refs"] == folds)
	}

	@Test func theToolInFrontComesBack() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(files: [.init(path: "/x")], sidebarTool: "git"),
			in: root, driven: false
		)
		#expect(try #require(SessionStore.read(in: root, driven: false)).sidebarTool == "git")
	}

	/// By name and not by index, for the reason the tmux window is an id: the
	/// list is rebuilt, and a terminal that failed to start shifts everything
	/// after it.
	@Test func theTerminalInFrontComesBack() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(terminals: [
				.init(name: "one"),
				.init(name: "two"),
				.init(name: "three", isInFront: true),
			]),
			in: root, driven: false
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.terminals.map(\.name) == ["one", "two", "three"])
		#expect(read.terminals.filter(\.isInFront).map(\.name) == ["three"])
	}

	/// **A file from before any of this existed still reads.** Which is what
	/// makes the fields safe to add: absent means nothing was folded, and the
	/// panes arrive the way they always did.
	@Test func aFileWrittenBeforeTheseKeysExistedStillReads() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }

		let folder = root.appendingPathComponent(".abydos", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try #"""
		{
		  "active" : "/x/main.swift",
		  "files" : [ { "path" : "/x/main.swift", "line" : 12 } ],
		  "terminals" : [ { "name" : "Local" } ]
		}
		"""#.write(
			to: folder.appendingPathComponent("session.json"), atomically: true, encoding: .utf8
		)

		let read = try #require(SessionStore.read(in: root, driven: false))
		#expect(read.files.count == 1)
		#expect(read.folds.isEmpty)
		#expect(read.sidebarTool == nil)
		#expect(read.terminals.allSatisfy { !$0.isInFront })
	}

	/// Nearest the root first: a fold near the root is the shape somebody
	/// arranged, and one twelve levels down is where they happened to end up.
	@Test func theCapKeepsTheShallowestFolds() {
		let deep = (0..<600).map { index in
			(0...(index % 12)).map { "level\($0)" }.joined(separator: "/") + "/folder\(index)"
		}
		let session = ProjectSession(folds: ["tree": .init(opened: deep)])
		let kept = try? #require(session.folds["tree"]?.opened)

		#expect(kept?.count == ProjectSession.TreeFolds.cap)
		// Nothing deeper than the shallowest kept, which is what "shallowest
		// first" means without asserting an order the sort does not promise.
		let depths = (kept ?? []).map { $0.filter { $0 == "/" }.count }
		#expect((depths.max() ?? 0) <= 11)
	}

	/// A folder in no working copy shares one session file with every other
	/// such folder, so a fold keyed by a path relative to one of them names
	/// nothing in the next.
	@Test func aFolderKeepsNoneOfIt() {
		let session = ProjectSession(
			files: [.init(path: "/x/notes.md")],
			terminals: [.init(name: "one", isInFront: true)],
			folds: ["tree": .init(opened: ["Sources"])],
			sidebarTool: "git"
		)
		let folder = session.filesOnly

		#expect(folder.files.count == 1)
		#expect(folder.folds.isEmpty)
		#expect(folder.sidebarTool == nil)
		#expect(folder.terminals.isEmpty)
	}

	/// A session holding nothing but the shape of an empty pane is still empty,
	/// so the file is removed rather than written.
	@Test func foldsAloneDoNotMakeASession() {
		#expect(ProjectSession(folds: ["refs": .init(shut: ["working"])]).isEmpty)
		#expect(ProjectSession(sidebarTool: "git").isEmpty)
	}
}
