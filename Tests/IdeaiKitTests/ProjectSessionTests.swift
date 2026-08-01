import Foundation
import Testing
@testable import IdeaiKit

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
