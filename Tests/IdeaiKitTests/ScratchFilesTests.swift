import Foundation
import Testing
@testable import IdeaiKit

/// Unnamed buffers belonging to a project.
struct ScratchFilesTests {
	private func makeRoot() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("scratch-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	@Test func createsNumberedScratches() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a"), root: root)

		let first = try scratches.create()
		let second = try scratches.create()

		#expect(first.lastPathComponent == "scratch-1.md")
		// Markdown by default: notes with code in them, not code with notes.
		#expect(second.lastPathComponent == "scratch-2.md")
		#expect(scratches.all().count == 2)
	}

	/// They are what comes back when the project is opened again.
	@Test func listsWhatWasLeftBehind() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: "/projects/a")

		let first = ScratchFiles(projectRoot: project, root: root)
		try first.create()
		try first.create()

		// A different instance, as a later launch would be.
		let later = ScratchFiles(projectRoot: project, root: root)
		#expect(later.all().map(\.lastPathComponent) == ["scratch-1.md", "scratch-2.md"])
	}

	/// One project's scratches are not another's.
	@Test func keepsProjectsApart() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let a = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a"), root: root)
		let b = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/b"), root: root)
		try a.create()

		#expect(a.all().count == 1)
		#expect(b.all().isEmpty)
		#expect(a.directory.path != b.directory.path)
	}

	@Test func matchesAProjectHoweverItsPathIsSpelled() {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let plain = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a"), root: root)
		let trailing = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a/"), root: root)
		#expect(plain.directory.path == trailing.directory.path)
	}

	/// Nothing of a scratch belongs in the project it was opened from.
	@Test func livesOutsideTheProject() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: "/projects/a")
		let scratches = ScratchFiles(projectRoot: project, root: root)

		let file = try scratches.create()
		#expect(!file.path.hasPrefix(project.path))
		#expect(ScratchFiles.isScratch(file, root: root))
		#expect(!ScratchFiles.isScratch(URL(fileURLWithPath: "/projects/a/main.swift"), root: root))
	}

	@Test func recognisesItsOwnFiles() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a"), root: root)

		let file = try scratches.create()
		#expect(scratches.contains(file))
		#expect(!scratches.contains(URL(fileURLWithPath: "/elsewhere/scratch-1.md")))
	}

	@Test func namesThemForTheTab() {
		#expect(ScratchFiles.title(for: URL(fileURLWithPath: "/x/scratch-3.txt")) == "Scratch 3")
		#expect(ScratchFiles.title(for: URL(fileURLWithPath: "/x/scratch-12.md")) == "Scratch 12")
		// Anything else keeps whatever it is called.
		#expect(ScratchFiles.title(for: URL(fileURLWithPath: "/x/notes.md")) == "notes")
	}

	@Test func removesOnlyItsOwn() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a"), root: root)

		let file = try scratches.create()
		try scratches.remove(file)
		#expect(scratches.all().isEmpty)

		// A file somewhere else is left alone rather than deleted.
		let outsider = root.appendingPathComponent("keep-me.txt")
		try Data().write(to: outsider)
		try scratches.remove(outsider)
		#expect(FileManager.default.fileExists(atPath: outsider.path))
	}
}
