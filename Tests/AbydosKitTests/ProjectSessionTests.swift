import Foundation
import Testing
@testable import AbydosKit

/// Remembering what was open in each project.
struct ProjectSessionTests {
	private func root(_ name: String) -> URL { URL(fileURLWithPath: "/projects/\(name)") }

	private func session(_ paths: String...) -> ProjectSession {
		ProjectSession(
			files: paths.map { ProjectSession.OpenFile(path: $0) },
			activePath: paths.first
		)
	}

	@Test func remembersWhatWasOpen() {
		var sessions = ProjectSessions()
		sessions.store(session("/a/one.swift", "/a/two.swift"), for: root("a"))

		let recalled = sessions.session(for: root("a"))
		#expect(recalled?.files.map(\.path) == ["/a/one.swift", "/a/two.swift"])
		#expect(recalled?.activePath == "/a/one.swift")
		#expect(sessions.session(for: root("b")) == nil)
	}

	/// The same project by another spelling is the same project.
	@Test func matchesRootsRegardlessOfSpelling() {
		var sessions = ProjectSessions()
		sessions.store(session("/a/one.swift"), for: URL(fileURLWithPath: "/projects/a/"))

		#expect(sessions.session(for: URL(fileURLWithPath: "/projects/a")) != nil)
		#expect(sessions.session(for: URL(fileURLWithPath: "/projects/./a")) != nil)
	}

	@Test func storingAgainReplacesWhatWasThere() {
		var sessions = ProjectSessions()
		sessions.store(session("/a/one.swift"), for: root("a"))
		sessions.store(session("/a/two.swift"), for: root("a"))

		#expect(sessions.session(for: root("a"))?.files.map(\.path) == ["/a/two.swift"])
		#expect(sessions.count == 1)
	}

	/// Wandering around a machine must not collect every project ever seen.
	@Test func forgetsTheLeastRecentlyUsedOnceFull() {
		var sessions = ProjectSessions(limit: 3)
		for name in ["a", "b", "c"] { sessions.store(session("/\(name)/f"), for: root(name)) }

		sessions.store(session("/d/f"), for: root("d"))
		#expect(sessions.count == 3)
		#expect(sessions.session(for: root("a")) == nil, "the oldest goes first")
		#expect(sessions.session(for: root("d")) != nil)
	}

	/// Going back to a project makes it recent again, so it is not the next to go.
	@Test func returningToAProjectKeepsIt() {
		var sessions = ProjectSessions(limit: 3)
		for name in ["a", "b", "c"] { sessions.store(session("/\(name)/f"), for: root(name)) }

		_ = sessions.take(for: root("a"))
		sessions.store(session("/d/f"), for: root("d"))

		#expect(sessions.session(for: root("a")) != nil, "just returned to")
		#expect(sessions.session(for: root("b")) == nil, "now the oldest")
	}

	@Test func aProjectWithNothingOpenIsRememberedAsSuch() {
		var sessions = ProjectSessions()
		sessions.store(ProjectSession(), for: root("a"))

		let recalled = sessions.session(for: root("a"))
		#expect(recalled != nil)
		#expect(recalled?.isEmpty == true)
	}
}

/// How a tab was being shown, which used not to be remembered at all: a `.scad`
/// put in Split Right so the model sat beside the source came back as the source
/// alone on the next project switch, and the same for every other file with a
/// rendered form. See 0454.
struct PreviewModeSessionTests {
	private func temporaryRoot() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("session-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func theModeAndTheDividerSurviveBeingWrittenDown() throws {
		let root = try temporaryRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(files: [
				ProjectSession.OpenFile(
					path: "/p/case.scad", line: 12,
					previewMode: .splitRight, dividerFraction: 0.7
				),
			]),
			in: root
		)

		let file = try #require(SessionStore.read(in: root)?.files.first)
		#expect(file.previewMode == .splitRight)
		#expect(file.dividerFraction == 0.7)
		#expect(file.line == 12)
	}

	/// A split whose mode is remembered but whose divider is at its default is
	/// still not the tab somebody left, so the fraction goes beside the mode —
	/// and only where there is a divider to have.
	@Test func aTabThatWasNotSplitWritesNoDivider() throws {
		let root = try temporaryRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(files: [
				ProjectSession.OpenFile(path: "/p/notes.md", previewMode: .preview),
			]),
			in: root
		)

		let file = try #require(SessionStore.read(in: root)?.files.first)
		#expect(file.previewMode == .preview)
		#expect(file.dividerFraction == nil)
	}

	/// Every tab open on the day this shipped was written by a version that did
	/// not record the mode. Read as `.source`, every diagram and every picture
	/// would have come back as text once, and blamed the change that added it.
	@Test func aSessionFromBeforeTheModeWasRecordedGetsTheKindsDefault() {
		#expect(FilePreview.restoredMode(nil, for: URL(fileURLWithPath: "/p/flow.puml")) == .splitRight)
		#expect(FilePreview.restoredMode(nil, for: URL(fileURLWithPath: "/p/shot.png")) == .preview)
		#expect(FilePreview.restoredMode(nil, for: URL(fileURLWithPath: "/p/notes.md")) == .source)
	}

	@Test func aRememberedModeIsWhatTheTabComesBackIn() {
		let model = URL(fileURLWithPath: "/p/case.scad")
		#expect(FilePreview.restoredMode(.splitRight, for: model) == .splitRight)
		#expect(FilePreview.restoredMode(.preview, for: model) == .preview)
		// The source of a diagram, which its kind does not open as: a choice
		// somebody made, not an absence.
		#expect(FilePreview.restoredMode(.source, for: URL(fileURLWithPath: "/p/flow.puml")) == .source)
	}

	/// A mode is only meaningful where there is something to show. A `.swift` has
	/// no rendered form, and a `.drawio` has no source half — its own editor owns
	/// the document — so neither can honour a split written against it.
	@Test func aModeTheFileCannotBeShownInIsIgnored() {
		#expect(FilePreview.restoredMode(.splitRight, for: URL(fileURLWithPath: "/p/main.swift")) == .source)
		#expect(FilePreview.restoredMode(.preview, for: URL(fileURLWithPath: "/p/main.swift")) == .source)
		#expect(FilePreview.restoredMode(.splitRight, for: URL(fileURLWithPath: "/p/plan.drawio")) == .preview)
		#expect(FilePreview.restoredMode(.source, for: URL(fileURLWithPath: "/p/part.stl")) == .preview)
	}

	/// The session file is JSON on disk that anything may have written.
	@Test func aDividerThatIsNotAFractionOfAPaneIsRefused() {
		#expect(SessionStore.dividerFraction(0.35) == 0.35)
		#expect(SessionStore.dividerFraction(nil) == nil)
		#expect(SessionStore.dividerFraction(0) == nil)
		#expect(SessionStore.dividerFraction(1) == nil)
		#expect(SessionStore.dividerFraction(-0.5) == nil)
		#expect(SessionStore.dividerFraction(Double.nan) == nil)
		#expect(SessionStore.dividerFraction("half") == nil)
	}

	/// A mode this version has never heard of — a session written by a later one
	/// — means nothing rather than something wrong, and the kind decides.
	@Test func aModeThisVersionDoesNotKnowIsNotGuessedAt() throws {
		let root = try temporaryRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(files: [ProjectSession.OpenFile(path: "/p/flow.puml")]),
			in: root
		)
		let file = AbydosFolder.sessionFile(in: root)
		let object = try #require(
			try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
		)
		var files = try #require(object["files"] as? [[String: Any]])
		files[0]["mode"] = "splitDiagonally"
		var edited = object
		edited["files"] = files
		try JSONSerialization.data(withJSONObject: edited).write(to: file)

		let read = try #require(SessionStore.read(in: root)?.files.first)
		#expect(read.previewMode == nil)
		#expect(
			FilePreview.restoredMode(read.previewMode, for: URL(fileURLWithPath: read.path))
				== .splitRight
		)
	}
}

/// Finding the projects inside a project.
struct SubprojectTests {
	private func make(_ layout: [String: [String]]) throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("sub-\(UUID().uuidString)")
		for (directory, files) in layout {
			let url = root.appendingPathComponent(directory)
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			for file in files {
				try "".write(to: url.appendingPathComponent(file), atomically: true, encoding: .utf8)
			}
		}
        return root
	}

	@Test func aFolderWithAModuleInItIsAProject() throws {
		let root = try make([
			"go-service": ["go.mod"],
			"native/zig-hello": ["build.zig"],
			"docs": ["README.md"],
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found.contains("go-service"))
		#expect(found.contains("native/zig-hello"))
		// A folder of documents is a folder.
		#expect(!found.contains("docs"))
	}

	/// What is inside a module belongs to that module: a repository with a
	/// vendor directory in it must not offer fifty subprojects.
	@Test func itDoesNotLookInsideAProjectItFound() throws {
		let root = try make([
			"service": ["go.mod"],
			"service/internal/thing": ["go.mod"],
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found == ["service"])
	}

	@Test func theUsualBuildOutputIsSkipped() throws {
		let root = try make([
			"app": ["package.json"],
			"node_modules/left-pad": ["package.json"],
			"target/debug": ["Cargo.toml"],
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found == ["app"])
	}

	/// 0516 could read both kinds and could not photograph them side by side,
	/// because neither folder counted as a project of its own.
	@Test func aNestedBazelWorkspaceOrConanRecipeIsAProject() throws {
		let root = try make([
			"services/build-farm": ["MODULE.bazel", "MODULE.bazel.lock"],
			"tools/legacy-farm": ["WORKSPACE"],
			"native/fmt": ["conanfile.py", "conan.lock"],
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found == ["native/fmt", "services/build-farm", "tools/legacy-farm"])
	}

	/// `conanfile.txt` says what a directory *consumes*, which is not the same
	/// claim as being a project. Conan's own layout puts one in the `examples/`
	/// beside a recipe, and a scope pill over somebody's samples folder is the
	/// failure this list is careful about.
	@Test func aConanfileTxtOnItsOwnIsNotAProject() throws {
		let root = try make([
			"fmt": ["conanfile.py"],
			"fmt/examples": ["conanfile.txt"],
			"samples": ["conanfile.txt"],
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found == ["fmt"])
	}

	/// And the other half of that argument: a directory that consumes packages
	/// *and* is a project says so with a build file, and is found by that one.
	@Test func aConanfileTxtBesideABuildFileIsFoundByTheBuildFile() throws {
		let root = try make(["app": ["conanfile.txt", "CMakeLists.txt"]])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found == ["app"])
	}

	/// A marker is a name on disk and not a question for the file system: a Mac
	/// is formatted case-insensitively, so `fileExists(…/WORKSPACE)` is true for
	/// every folder with a `workspace/` in it. Every one of those would have got
	/// a scope pill, a language-server root and a Bazel row.
	@Test func aFolderCalledWorkspaceIsNotABazelWorkspace() throws {
		let root = try make([
			"eclipse-thing/workspace": ["notes.txt"],
			"real": ["WORKSPACE"],
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = Subprojects.find(in: root).map { Subprojects.relativePath($0, to: root) }
		#expect(found == ["real"])
		#expect(ExternalDependencies.kinds(at: root.appendingPathComponent("eclipse-thing")).isEmpty)
	}

	/// A session file is on disk and can say anything; a subproject outside the
	/// project would scope the window to somewhere the tree does not show.
	@Test func aPathOutsideTheProjectIsRefused() throws {
		let root = try make(["inside": ["go.mod"]])
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(Subprojects.resolve("inside", in: root) != nil)
		#expect(Subprojects.resolve("../elsewhere", in: root) == nil)
		#expect(Subprojects.resolve("/etc", in: root) == nil)
		#expect(Subprojects.resolve("nowhere", in: root) == nil)
		#expect(Subprojects.resolve("", in: root) == nil)
	}

	@Test func theSubprojectSurvivesBeingWrittenDown() throws {
		let root = try make(["go-service": ["go.mod"]])
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(ProjectSession(subprojectPath: "go-service"), in: root)
		let read = try #require(SessionStore.read(in: root))
		#expect(read.subprojectPath == "go-service")
	}
}
