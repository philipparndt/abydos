import Testing
import Foundation
@testable import AbydosKit

/// Scanning for checkouts, the way tmuxctl finds them.
struct ProjectDiscoveryTests {
	/// Builds a directory tree; entries ending in "/.git" become checkouts.
	private func makeTree(_ paths: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-discovery-\(UUID().uuidString)")
		for path in paths {
			try FileManager.default.createDirectory(
				at: root.appendingPathComponent(path),
				withIntermediateDirectories: true
			)
		}
		return root
	}

	@Test func findsCheckoutsBelowARoot() throws {
		let root = try makeTree(["alpha/.git", "beta/.git", "notaproject/src"])
		let found = ProjectDiscovery.scan(roots: [root], maxDepth: 3)
		#expect(Set(found.map(\.name)) == ["alpha", "beta"])
	}

	@Test func findsCheckoutsNestedUnderPlainDirectories() throws {
		let root = try makeTree(["group/nested/.git"])
		let found = ProjectDiscovery.scan(roots: [root], maxDepth: 3)
		#expect(found.map(\.name) == ["nested"])
	}

	/// A repository's subdirectories are not themselves projects, and a monorepo
	/// with submodules would otherwise flood the list.
	@Test func doesNotDescendIntoACheckout() throws {
		let root = try makeTree(["outer/.git", "outer/inner/.git"])
		let found = ProjectDiscovery.scan(roots: [root], maxDepth: 3)
		#expect(found.map(\.name) == ["outer"])
	}

	@Test func stopsAtTheDepthLimit() throws {
		let root = try makeTree(["a/b/c/deep/.git"])
		#expect(ProjectDiscovery.scan(roots: [root], maxDepth: 2).isEmpty)
		#expect(ProjectDiscovery.scan(roots: [root], maxDepth: 5).map(\.name) == ["deep"])
	}

	/// node_modules alone can hold hundreds of vendored checkouts.
	@Test func skipsDependencyAndOutputDirectories() throws {
		let root = try makeTree([
			"app/node_modules/dep/.git",
			"app/vendor/lib/.git",
			"app/target/thing/.git",
			"app/real/.git",
		])
		#expect(ProjectDiscovery.scan(roots: [root], maxDepth: 4).map(\.name) == ["real"])
	}

	@Test func skipsHiddenDirectories() throws {
		let root = try makeTree([".cache/hidden/.git", "shown/.git"])
		#expect(ProjectDiscovery.scan(roots: [root], maxDepth: 3).map(\.name) == ["shown"])
	}

	/// A worktree's .git is a file, and a worktree is a project like any other.
	@Test func aGitFileCountsAsACheckout() throws {
		let root = try makeTree(["worktree"])
		let marker = root.appendingPathComponent("worktree/.git")
		try "gitdir: /elsewhere".write(to: marker, atomically: true, encoding: .utf8)
		#expect(ProjectDiscovery.isProjectRoot(root.appendingPathComponent("worktree")))
		#expect(ProjectDiscovery.scan(roots: [root], maxDepth: 3).map(\.name) == ["worktree"])
	}

	@Test func mostRecentlyWorkedOnComesFirst() throws {
		let root = try makeTree(["old/.git", "new/.git"])
		let now = Date()
		for (name, age) in [("old", 5000.0), ("new", 10.0)] {
			try FileManager.default.setAttributes(
				[.modificationDate: now.addingTimeInterval(-age)],
				ofItemAtPath: root.appendingPathComponent("\(name)/.git").path
			)
		}
		#expect(ProjectDiscovery.scan(roots: [root], maxDepth: 3).map(\.name) == ["new", "old"])
	}

	/// Unreadable metadata all reports the same distant past, so the tie-breaks
	/// have to keep the order stable rather than arbitrary.
	@Test func tiesFallBackToDepthThenPath() {
		let base = Date.distantPast
		let deep = DiscoveredProject(url: URL(fileURLWithPath: "/a/b/c/z"), lastActivity: base)
		let shallow = DiscoveredProject(url: URL(fileURLWithPath: "/a/z"), lastActivity: base)
		let sibling = DiscoveredProject(url: URL(fileURLWithPath: "/a/a"), lastActivity: base)

		let sorted = ProjectDiscovery.sorted([deep, shallow, sibling])
		#expect(sorted.map(\.url.path) == ["/a/a", "/a/z", "/a/b/c/z"])
	}

	/// Two roots can reach the same checkout; a duplicate row is worse than none.
	@Test func theSameCheckoutIsListedOnce() throws {
		let root = try makeTree(["only/.git"])
		let found = ProjectDiscovery.scan(roots: [root, root], maxDepth: 3)
		#expect(found.count == 1)
	}

	@Test func resolveExpandsTildeAndDropsWhatIsNotThere() throws {
		let root = try makeTree(["here"])
		let resolved = ProjectDiscovery.resolve(searchPaths: [
			root.appendingPathComponent("here").path,
			root.appendingPathComponent("missing").path,
			"~",
		])
		#expect(resolved.count == 2)
		#expect(!resolved.contains { $0.path.contains("missing") })
		#expect(resolved.contains { $0.path == NSHomeDirectory() })
	}

	@Test func aMissingRootIsNotAnError() {
		#expect(ProjectDiscovery.scan(roots: [URL(fileURLWithPath: "/no/such/place")], maxDepth: 3).isEmpty)
	}
}

/// Naming a new folder. Checked before the file system is touched so a
/// rejection reads as a sentence rather than a POSIX error.
struct FolderNameTests {
	private func problem(_ name: String, hidden: Bool = true) -> String? {
		FolderName.problem(name, showingHiddenFiles: hidden)
	}

	@Test func ordinaryNamesAreFine() {
		#expect(problem("Sources") == nil)
		#expect(problem("my folder") == nil)
		#expect(problem("v1.2-beta") == nil)
	}

	@Test func aNameIsRequired() {
		#expect(problem("") != nil)
	}

	@Test func reservedNamesAreRejected() {
		#expect(problem(".") != nil)
		#expect(problem("..") != nil)
	}

	/// A slash would silently create something somewhere else, or fail.
	@Test func pathSeparatorsAreRejected() {
		#expect(problem("a/b") != nil)
		#expect(problem("a:b") != nil)
	}

	/// Creating a hidden folder while dotfiles are hidden makes it appear to
	/// vanish, so it is refused with an explanation rather than silently done.
	@Test func hiddenNamesDependOnTheSetting() {
		#expect(problem(".config", hidden: false) != nil)
		#expect(problem(".config", hidden: true) == nil)
	}

	@Test func theMessageSaysWhatToDo() {
		#expect(problem(".config", hidden: false)?.contains("Show hidden files") == true)
	}
}

/// What the field on the row opens with, for both gestures: the draft name a
/// brand-new row starts from, and how much of any name is selected.
///
/// Here rather than in the view because it is a rule and not a drawing — and
/// because renaming and creating have to agree about it, which is easier to
/// state once than to check twice.
struct EntryNameDraftTests {
	/// The Finder's two words, and the reason they are words at all: Return
	/// pressed straight after New has to make something rather than report an error.
	@Test func aNewRowStartsWithAName() {
		#expect(EntryName.draftName(kind: .file) == "untitled")
		#expect(EntryName.draftName(kind: .folder) == "untitled folder")
		for kind in [EntryName.Kind.file, .folder] {
			#expect(EntryName.problem(
				EntryName.draftName(kind: kind), kind: kind, showingHiddenFiles: false
			) == nil)
		}
	}

	/// The whole point of the kinds submenu: `main.py` arrives with `main`
	/// selected, so typing replaces the name and keeps the extension.
	@Test func onlyTheStemOfAFileIsSelected() {
		#expect(EntryName.stemLength(of: "main.py", kind: .file) == 4)
		#expect(EntryName.stemLength(of: "README.md", kind: .file) == 6)
		#expect(EntryName.stemLength(of: "Makefile", kind: .file) == 8)
	}

	/// A folder has no extension to protect, so all of it is selected.
	@Test func theWholeNameOfAFolderIsSelected() {
		#expect(EntryName.stemLength(of: "Sources", kind: .folder) == 7)
		// Even one that looks like it has an extension. `v1.2-beta` is a folder
		// called `v1.2-beta`, not `v1` of kind `2-beta`.
		#expect(EntryName.stemLength(of: "v1.2-beta", kind: .folder) == 9)
	}

	/// A dotfile is a whole name rather than a stem and an extension:
	/// `.gitignore` is not an entry of kind `gitignore`.
	@Test func aDotfileIsAllStem() {
		#expect(EntryName.stemLength(of: ".gitignore", kind: .file) == 10)
		#expect(EntryName.stemLength(of: ".env.local", kind: .file) == 10)
	}

	/// In UTF-16 units, because that is what a field editor's selected range is
	/// measured in — and an emoji is two of them.
	@Test func theLengthIsWhatAFieldEditorCounts() {
		#expect(EntryName.stemLength(of: "🙂.txt", kind: .file) == 2)
	}
}

/// Which files have a rendered form, and how they open.
struct FilePreviewTests {
	private func url(_ name: String) -> URL { URL(fileURLWithPath: "/p/\(name)") }

	@Test func markdownAndModelsHavePreviews() {
		#expect(FilePreview.kind(for: url("a.md")) == .markdown)
		#expect(FilePreview.kind(for: url("a.markdown")) == .markdown)
		#expect(FilePreview.kind(for: url("a.scad")) == .model)
		#expect(FilePreview.kind(for: url("a.stl")) == .model)
		#expect(FilePreview.kind(for: url("a.3mf")) == .model)
	}

	@Test func ordinarySourceHasNone() {
		#expect(FilePreview.kind(for: url("a.swift")) == nil)
		#expect(!FilePreview.hasPreview(url("a.go")))
	}

	@Test func extensionMatchingIgnoresCase() {
		#expect(FilePreview.kind(for: url("A.STL")) == .model)
	}

	/// A mesh has no source worth reading — an STL is a list of triangles — so
	/// it opens rendered. Anything handwritten opens as what it is.
	@Test func meshesOpenRenderedAndSourceOpensAsText() {
		#expect(FilePreview.defaultMode(for: url("a.stl")) == .preview)
		#expect(FilePreview.defaultMode(for: url("a.3mf")) == .preview)
		#expect(FilePreview.defaultMode(for: url("a.scad")) == .source)
		#expect(FilePreview.defaultMode(for: url("a.md")) == .source)
	}

	/// Offering "Source" for a binary mesh would show a screen of noise.
	@Test func aMeshOffersOnlyThePreview() {
		#expect(FilePreview.availableModes(for: url("a.stl")) == [.preview])
		#expect(FilePreview.availableModes(for: url("a.scad")) == PreviewMode.allCases)
		#expect(FilePreview.availableModes(for: url("a.md")) == PreviewMode.allCases)
	}

	/// Both directions are offered, and named the way the editor's own splits
	/// are — the preview goes where the name says.
	@Test func bothSplitDirectionsAreAvailable() {
		let modes = FilePreview.availableModes(for: url("a.md"))
		#expect(modes.contains(.splitRight))
		#expect(modes.contains(.splitDown))
		#expect(PreviewMode.splitRight.splitsSideBySide)
		#expect(!PreviewMode.splitDown.splitsSideBySide)
	}

	@Test func bothSplitsShowBothHalves() {
		for mode in [PreviewMode.splitRight, .splitDown] {
			#expect(mode.isSplit, "\(mode)")
			#expect(mode.showsSource && mode.showsPreview, "\(mode)")
		}
		#expect(!PreviewMode.source.isSplit)
		#expect(!PreviewMode.preview.isSplit)
	}

	@Test func aFileWithNoPreviewOffersNothing() {
		#expect(FilePreview.availableModes(for: url("a.swift")).isEmpty)
	}

	@Test func modesSayWhichHalvesTheyShow() {
		#expect(PreviewMode.source.showsSource && !PreviewMode.source.showsPreview)
		#expect(!PreviewMode.preview.showsSource && PreviewMode.preview.showsPreview)
	}
}

/// One way of naming a file, which is what makes two parts of the app agree
/// they mean the same one.
struct FilePathTests {
	/// `/tmp` and `/var` are symlinks on macOS, so canonicalising is not a
	/// formality here: it is the difference between two names for one directory.
	@Test func resolvesADirectoryReachedThroughASymlink() throws {
		let base = URL(
			fileURLWithPath: FilePath.canonical(try JavaTestDirectory.make()), isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: base) }
		let real = base.appendingPathComponent("checkout")
		try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
		let link = base.appendingPathComponent("through-a-link")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

		#expect(FilePath.canonical(link) == real.path)
		#expect(FilePath.canonical(link.appendingPathComponent("x")) != real.path + "/x")
		// Which is the whole reason for the one below: `realpath` answers about
		// files that are there, and `x` is not.
		#expect(FilePath.canonicalEvenIfMissing(link.appendingPathComponent("x"))
			== real.path + "/x")
		#expect(FilePath.canonicalEvenIfMissing(link.appendingPathComponent("a/b/c"))
			== real.path + "/a/b/c")
	}

	/// A path that is entirely there is answered by `realpath` alone, and one
	/// that is nowhere at all comes back as it went in rather than as "/".
	@Test func leavesWhatItCannotResolveAlone() throws {
		let base = URL(
			fileURLWithPath: FilePath.canonical(try JavaTestDirectory.make()), isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: base) }

		#expect(FilePath.canonicalEvenIfMissing(base) == base.path)
		#expect(FilePath.canonicalEvenIfMissing("/no-such-root-here/and/below")
			== "/no-such-root-here/and/below")
	}
}
