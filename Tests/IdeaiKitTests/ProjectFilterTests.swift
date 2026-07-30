import Testing
import Foundation
@testable import IdeaiKit

struct ProjectFilterTests {
	private let home = FileManager.default.homeDirectoryForCurrentUser.path

	private func entries() -> [RecentProject] {
		[
			RecentProject(path: "\(home)/dev/smarthome/projects/mqtt-sonos", lastOpened: Date(timeIntervalSince1970: 300)),
			RecentProject(path: "\(home)/dev/smarthome/projects/mqtt-bambu", lastOpened: Date(timeIntervalSince1970: 400)),
			RecentProject(path: "\(home)/dev/3d/basketr", lastOpened: Date(timeIntervalSince1970: 500)),
            RecentProject(path: "\(home)/dev/3d/racknex", lastOpened: Date(timeIntervalSince1970: 200)),
			RecentProject(path: "\(home)/dev/ideai", lastOpened: Date(timeIntervalSince1970: 600)),
		]
	}

	@Test func emptyQueryKeepsEverything() {
		#expect(ProjectFilter.match(entries(), query: "").count == 5)
		#expect(ProjectFilter.match(entries(), query: "   ").count == 5)
	}

	@Test func matchesOnName() {
		let names = ProjectFilter.match(entries(), query: "mqtt").map(\.name)
		#expect(names.sorted() == ["mqtt-bambu", "mqtt-sonos"])
	}

	/// Searching the path lets a directory stand in for a group of projects.
	@Test func matchesOnPath() {
		let names = ProjectFilter.match(entries(), query: "3d").map(\.name)
		#expect(Set(names) == ["basketr", "racknex"])
	}

	@Test func isCaseInsensitive() {
		#expect(ProjectFilter.match(entries(), query: "BASKETR").first?.name == "basketr")
	}

	@Test func prefixMatchesRankAboveOtherMatches() {
		// "rack" is a prefix of racknex and appears nowhere else.
		#expect(ProjectFilter.match(entries(), query: "rack").first?.name == "racknex")
	}

	@Test func nameMatchesOutrankPathOnlyMatches() {
		var list = entries()
		// A project whose *path* contains "ideai" but whose name does not.
		list.append(RecentProject(path: "\(home)/dev/ideai-notes/scratch", lastOpened: Date(timeIntervalSince1970: 900)))
		let result = ProjectFilter.match(list, query: "ideai")
		#expect(result.first?.name == "ideai", "the exact name match should lead")
	}

	@Test func tiesBreakOnMostRecent() {
		let result = ProjectFilter.match(entries(), query: "mqtt")
		#expect(result.first?.name == "mqtt-bambu", "more recently opened wins")
	}

	@Test func noMatchesReturnsEmpty() {
		#expect(ProjectFilter.match(entries(), query: "zzzz").isEmpty)
	}
}
