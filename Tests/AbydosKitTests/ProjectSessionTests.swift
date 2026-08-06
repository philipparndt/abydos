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
