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

	/// Removing takes it out of the collection — via the Trash, so it can be
	/// put back. This is the only place a note can leave from.
	@Test func removesOnlyItsOwn() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/projects/a"), root: root)

		let file = try scratches.create()
		let trashed = try scratches.remove(file)
		defer { if let trashed { try? FileManager.default.removeItem(at: trashed) } }

		#expect(scratches.all().isEmpty)
		#expect(!FileManager.default.fileExists(atPath: file.path))
		// Wherever it went, it still exists — unless the volume has no Trash.
		if let trashed { #expect(FileManager.default.fileExists(atPath: trashed.path)) }

		// A file somewhere else is left alone rather than removed.
		let outsider = root.appendingPathComponent("keep-me.txt")
		try Data().write(to: outsider)
		#expect(try scratches.remove(outsider) == nil)
		#expect(FileManager.default.fileExists(atPath: outsider.path))
	}
}

/// Every scratch on the machine, whichever project it came from.
struct ScratchLibraryTests {
	private func makeRoot() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("library-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	private func write(_ text: String, to url: URL) throws {
		try text.write(to: url, atomically: true, encoding: .utf8)
	}

	@Test func groupsGlobalFirstThenProjectsByName() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		try ScratchFiles.global(root: root).create()
		try ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/zebra"), root: root).create()
		try ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/apple"), root: root).create()

		let collections = ScratchLibrary(root: root).collections()
		#expect(collections.map(\.title) == ["Global", "apple", "zebra"])
		#expect(collections.first?.isGlobal == true)
	}

	/// A digest cannot be read backwards, so which project a folder belongs to
	/// has to be written down when it is made.
	@Test func remembersWhichProjectAFolderIsFor() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: "/dev/ideai")

		try ScratchFiles(projectRoot: project, root: root).create()

		let collection = ScratchLibrary(root: root).collections().first
		#expect(collection?.projectRoot?.path == project.path)
		#expect(collection?.title == "ideai")
	}

	/// The marker is not a scratch.
	@Test func doesNotListTheMarkerAsANote() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)
		try scratches.create()

		#expect(scratches.all().count == 1)
		#expect(ScratchLibrary(root: root).all().count == 1)
	}

	@Test func findsWhatIsWrittenInside() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)

		let first = try scratches.create()
		try write("# notes\nselect * from orders\n", to: first)
		let second = try scratches.create()
		try write("nothing to see\n", to: second)

		let matches = ScratchLibrary(root: root).search("from orders")
		#expect(matches.count == 1)
		// Resolved: a temporary directory is reached through a symlink, and the
		// two spellings are the same file.
		#expect(matches.first?.entry.url.resolvingSymlinksInPath() == first.resolvingSymlinksInPath())
		#expect(matches.first?.line == 2)
		#expect(matches.first?.excerpt == "select * from orders")
	}

	@Test func searchesAcrossProjectsAndGlobals() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let a = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)
		let global = ScratchFiles.global(root: root)
		try write("kubectl get pods\n", to: try a.create())
		try write("kubectl drain node\n", to: try global.create())

		let matches = ScratchLibrary(root: root).search("kubectl")
		#expect(matches.count == 2)
		#expect(matches.contains { $0.entry.isGlobal })
		#expect(matches.contains { $0.entry.projectRoot?.lastPathComponent == "a" })
	}

	/// A named scratch is findable by that name.
	@Test func matchesTheNameToo() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)

		let file = try scratches.create()
		try write("body text\n", to: file)
		let renamed = try scratches.rename(file, to: "deployment steps")

		let matches = ScratchLibrary(root: root).search("deployment")
		#expect(matches.first?.entry.url.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath())
		#expect(matches.first?.line == nil)
		#expect(matches.first?.excerpt == "body text")
	}

	@Test func anEmptyQueryListsEverything() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)
		try scratches.create()
		try scratches.create()

		#expect(ScratchLibrary(root: root).search("   ").count == 2)
	}
}

/// Renaming and moving, which is how a scratch stops being a scratch.
struct ScratchEditingTests {
	private func makeRoot() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("edit-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	/// A name given to it is what it is called from then on.
	@Test func renamingChangesTheTitle() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)

		let file = try scratches.create()
		#expect(ScratchFiles.title(for: file) == "Scratch 1")

		let renamed = try scratches.rename(file, to: "release checklist")
		#expect(renamed.lastPathComponent == "release checklist.md")
		#expect(ScratchFiles.title(for: renamed) == "release checklist")
		#expect(!FileManager.default.fileExists(atPath: file.path))
	}

	/// Renaming must not quietly change what the file is.
	@Test func renamingKeepsTheExtension() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let scratches = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)

		let file = try scratches.create()
		#expect(try scratches.rename(file, to: "notes").pathExtension == "md")

		let other = try scratches.create()
		#expect(try scratches.rename(other, to: "query.sql").pathExtension == "sql")
	}

	/// Something learned in one checkout is often worth keeping when it is gone.
	@Test func movesAProjectNoteToGlobal() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)
		let global = ScratchFiles.global(root: root)

		let file = try project.create()
		try "worth keeping\n".write(to: file, atomically: true, encoding: .utf8)

		let moved = try project.move(file, to: global)
		#expect(global.contains(moved))
		#expect(project.all().isEmpty)
		#expect(try String(contentsOf: moved, encoding: .utf8) == "worth keeping\n")
	}

	/// Moving must never overwrite a note already there.
	@Test func movingSidestepsACollision() throws {
		let root = makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = ScratchFiles(projectRoot: URL(fileURLWithPath: "/dev/a"), root: root)
		let global = ScratchFiles.global(root: root)

		try "the global one\n".write(to: try global.create(), atomically: true, encoding: .utf8)
		let mine = try project.create()
		try "mine\n".write(to: mine, atomically: true, encoding: .utf8)

		// Both are called scratch-1.md.
		let moved = try project.move(mine, to: global)
		#expect(moved.lastPathComponent == "scratch-1-2.md")
		#expect(global.all().count == 2)
		#expect(try String(contentsOf: moved, encoding: .utf8) == "mine\n")
	}
}

/// Which scratches a project had open, remembered between launches.
struct OpenScratchesTests {
	/// A suite of its own per test, removed again so the machine is not left
	/// with a preference domain for every test that has ever run.
	private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
		let suite = "open-scratches-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		try body(defaults)
	}

	/// Never having said is not the same as saying none.
	@Test func distinguishesNoRecordFromNoneOpen() {
		withDefaults { defaults in
			let store = OpenScratches(defaults: defaults)
			let project = URL(fileURLWithPath: "/dev/a")

			#expect(store.paths(forProject: project) == nil)
			store.record([], forProject: project)
			#expect(store.paths(forProject: project) == [])
		}
	}

	@Test func keepsProjectsApart() {
		withDefaults { defaults in
			let store = OpenScratches(defaults: defaults)

			store.record(["/x/one.md"], forProject: URL(fileURLWithPath: "/dev/a"))
			store.record(["/x/two.md"], forProject: URL(fileURLWithPath: "/dev/b"))
			store.record(["/x/three.md"], forProject: nil)

			#expect(store.paths(forProject: URL(fileURLWithPath: "/dev/a")) == ["/x/one.md"])
			#expect(store.paths(forProject: URL(fileURLWithPath: "/dev/b")) == ["/x/two.md"])
			#expect(store.paths(forProject: nil) == ["/x/three.md"])
		}
	}

	/// One deleted since simply stops coming back.
	@Test func skipsScratchesThatAreGone() throws {
		try withDefaults { defaults in
		let store = OpenScratches(defaults: defaults)
		let project = URL(fileURLWithPath: "/dev/a")

		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("open-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let kept = directory.appendingPathComponent("kept.md")
		try Data().write(to: kept)
		let gone = directory.appendingPathComponent("gone.md")

		store.record([kept.path, gone.path], forProject: project)
		#expect(store.existing(forProject: project) == [kept])
		}
	}

	/// The same project reached by a different spelling of its path.
	@Test func matchesAProjectHoweverItsPathIsSpelled() {
		withDefaults { defaults in
			let store = OpenScratches(defaults: defaults)

			store.record(["/x/one.md"], forProject: URL(fileURLWithPath: "/dev/a/"))
			#expect(store.paths(forProject: URL(fileURLWithPath: "/dev/a")) == ["/x/one.md"])
		}
	}
}

/// Scratches written before the store moved to ~/.config.
struct ScratchMigrationTests {
	private func makeDirectory(_ prefix: String) -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	@Test func carriesEveryCollectionOver() throws {
		let old = makeDirectory("legacy")
		let new = makeDirectory("config")
		defer {
			try? FileManager.default.removeItem(at: old)
			try? FileManager.default.removeItem(at: new)
		}

		let project = URL(fileURLWithPath: "/dev/a")
		try "project note\n".write(to: try ScratchFiles(projectRoot: project, root: old).create(),
			atomically: true, encoding: .utf8)
		try "global note\n".write(to: try ScratchFiles.global(root: old).create(),
			atomically: true, encoding: .utf8)

		#expect(ScratchFiles.migrateLegacyStore(from: old, to: new) == 2)

		let moved = ScratchLibrary(root: new)
		#expect(moved.collections().count == 2)
		#expect(moved.search("global note").count == 1)
		// Which project each folder belongs to travels with it.
		#expect(moved.collections().contains { $0.projectRoot?.path == project.path })
		// And the old place is gone, so it cannot be migrated twice.
		#expect(!FileManager.default.fileExists(atPath: old.path))
	}

	/// A note already at the destination is never written over.
	@Test func leavesCollisionsAlone() throws {
		let old = makeDirectory("legacy")
		let new = makeDirectory("config")
		defer {
			try? FileManager.default.removeItem(at: old)
			try? FileManager.default.removeItem(at: new)
		}

		let project = URL(fileURLWithPath: "/dev/a")
		try "the old one\n".write(to: try ScratchFiles(projectRoot: project, root: old).create(),
			atomically: true, encoding: .utf8)
		let existing = try ScratchFiles(projectRoot: project, root: new).create()
		try "the new one\n".write(to: existing, atomically: true, encoding: .utf8)

		#expect(ScratchFiles.migrateLegacyStore(from: old, to: new) == 0)
		#expect(try String(contentsOf: existing, encoding: .utf8) == "the new one\n")
	}

	@Test func doesNothingWhenThereIsNothingToMove() {
		let new = makeDirectory("config")
		defer { try? FileManager.default.removeItem(at: new) }
		let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

		#expect(ScratchFiles.migrateLegacyStore(from: missing, to: new) == 0)
	}
}
