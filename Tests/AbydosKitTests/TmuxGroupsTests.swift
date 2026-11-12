import Foundation
import Testing
@testable import AbydosKit

/// Two Abydos windows on one tmux server without moving each other: which
/// session a terminal attaches to, and how the session list reads a group.
struct TmuxGroupsTests {
	private func session(_ name: String, group: String? = nil, attached: Bool = false, created: Int = 0, windows: Int = 3) -> TmuxMirror.SessionSummary {
		.init(name: name, windowCount: windows, isAttached: attached, created: created, group: group)
	}

	@Test func aSessionNobodyElseIsOnIsAttachedItself() {
		let attach = TmuxGroups.attach(to: "AbydosDev", sessions: [session("AbydosDev")], heldElsewhere: ["Presentation"])
		#expect(attach == .session("AbydosDev"))
	}

	@Test func aSessionThatIsNotThereYetIsMade() {
		#expect(TmuxGroups.attach(to: "website", sessions: [], heldElsewhere: []) == .session("website"))
	}

	/// The report: two windows on one session were two clients of it, and a tab
	/// chosen in either switched both.
	@Test func aSessionAnotherWindowIsOnIsJoinedAsAGroup() {
		let attach = TmuxGroups.attach(to: "AbydosDev", sessions: [session("AbydosDev")], heldElsewhere: ["AbydosDev"])
		#expect(attach == .grouped(joining: "AbydosDev", as: "AbydosDev~2"))
	}

	@Test func aGroupedNameIsOneNothingHas() {
		let names: Set = ["AbydosDev", "AbydosDev~2", "AbydosDev~3"]
		#expect(TmuxGroups.freeName(for: "AbydosDev", among: names) == "AbydosDev~4")
		#expect(TmuxGroups.freeName(for: "AbydosDev", among: ["AbydosDev", "AbydosDev~3"]) == "AbydosDev~2")
	}

	/// Killed while a grouped session still held its windows: the group is joined
	/// under the session's own name, not a new, empty session made beside it.
	@Test func aSessionWhoseGroupOutlivedItRejoinsTheGroup() {
		let sessions = [session("AbydosDev~2", group: "AbydosDev")]
		let attach = TmuxGroups.attach(to: "AbydosDev", sessions: sessions, heldElsewhere: ["AbydosDev~2"])
		#expect(attach == .rejoined(member: "AbydosDev~2", as: "AbydosDev"))
	}

	@Test func aProjectRemembersTheGroupNotItsOwnView() {
		let sessions = [session("AbydosDev", group: "AbydosDev"), session("AbydosDev~2", group: "AbydosDev"), session("notes")]
		#expect(TmuxGroups.base(of: "AbydosDev~2", in: sessions) == "AbydosDev")
		#expect(TmuxGroups.base(of: "AbydosDev", in: sessions) == "AbydosDev")
		#expect(TmuxGroups.base(of: "notes", in: sessions) == "notes")
	}

	@Test func aGroupIsOneRowUnderTheSessionItIsNamedAfter() {
		let sessions = [
			session("AbydosDev", group: "AbydosDev", created: 100),
			session("notes", created: 150),
			session("AbydosDev~2", group: "AbydosDev", attached: true, created: 200),
		]
		let shown = TmuxGroups.shownAsOne(sessions)
		#expect(shown.map(\.name) == ["AbydosDev", "notes"])
		#expect(shown[0].isAttached, "attached through its grouped session")
	}

	@Test func aGroupWhoseNamesakeIsGoneIsShownUnderItsOldestMember() {
		let sessions = [
			session("AbydosDev~3", group: "AbydosDev", created: 300),
			session("AbydosDev~2", group: "AbydosDev", created: 200),
		]
		#expect(TmuxGroups.shownAsOne(sessions).map(\.name) == ["AbydosDev~2"])
	}

	@Test func groupMatesAreTheOtherSessionsOfTheGroup() {
		let sessions = [session("AbydosDev", group: "AbydosDev"), session("AbydosDev~2", group: "AbydosDev"), session("notes")]
		#expect(TmuxGroups.groupMates(of: "AbydosDev~2", in: sessions) == ["AbydosDev"])
		#expect(TmuxGroups.groupMates(of: "notes", in: sessions).isEmpty)
	}

	/// Joining a view of a session is another view of that session, named
	/// after it: `AbydosDev~2~2` would be read as a view of a session that goes
	/// with its window.
	@Test func joiningOneOfOurViewsIsNamedAfterTheSessionItIsAViewOf() {
		let sessions = [session("AbydosDev~2", group: "AbydosDev", attached: true)]
		let attach = TmuxGroups.attach(to: "AbydosDev~2", sessions: sessions, heldElsewhere: ["AbydosDev~2"])
		#expect(attach == .grouped(joining: "AbydosDev~2", as: "AbydosDev~3"))
	}

	@Test func onlyTheNamesThisAppGivesAreItsOwn() {
		#expect(TmuxGroups.isOurs("main~2", inGroup: "main"))
		#expect(TmuxGroups.isOurs("main~12", inGroup: "main"))
		#expect(!TmuxGroups.isOurs("main-1", inGroup: "main"))
		#expect(!TmuxGroups.isOurs("main~", inGroup: "main"))
		#expect(!TmuxGroups.isOurs("main~x", inGroup: "main"))
		#expect(!TmuxGroups.isOurs("main", inGroup: "main"))

		let sessions = [session("main", group: "main"), session("main-1", group: "main"), session("main~2", group: "main"), session("notes")]
		#expect(TmuxGroups.ownBase(of: "main~2", in: sessions) == "main")
		#expect(TmuxGroups.ownBase(of: "main-1", in: sessions) == nil)
		#expect(TmuxGroups.ownBase(of: "main", in: sessions) == nil)
		#expect(TmuxGroups.ownBase(of: "notes", in: sessions) == nil)
	}

	/// `tmux new -t main` is somebody's own second view, and theirs to switch
	/// to and to close: it keeps its row, and closing `main` does not close it.
	@Test func aSessionSomebodyGroupedThemselvesKeepsItsRow() {
		let sessions = [
			session("main", group: "main", created: 100),
			session("main-1", group: "main", attached: true, created: 200),
			session("main~2", group: "main", created: 300),
		]
		let shown = TmuxGroups.shownAsOne(sessions)
		#expect(shown.map(\.name) == ["main", "main-1"])
		#expect(!shown[0].isAttached, "not attached through somebody's own session")
		#expect(shown[1].isAttached)
		#expect(TmuxGroups.foldedMates(of: "main", in: sessions) == ["main~2"])
		#expect(TmuxGroups.foldedMates(of: "main-1", in: sessions).isEmpty)
	}

	/// With the namesake gone, our views go under the oldest session somebody
	/// made, not under one of themselves.
	@Test func ourViewsFoldIntoSomebodysSessionWhenTheNamesakeIsGone() {
		let sessions = [
			session("main~2", group: "main", attached: true, created: 100),
			session("main-1", group: "main", created: 200),
		]
		let shown = TmuxGroups.shownAsOne(sessions)
		#expect(shown.map(\.name) == ["main-1"])
		#expect(shown[0].isAttached)
		#expect(TmuxGroups.foldedMates(of: "main-1", in: sessions) == ["main~2"])
	}

	// MARK: - Reading the list

	@Test func theListSaysWhichGroupASessionIsIn() {
		let sessions = TmuxMirror.parseSessions("""
		3;0;100;gAbydosDev;AbydosDev
		3;1;200;gAbydosDev;AbydosDev~2
		1;0;300;-;Presentation
		""")
		#expect(sessions.map(\.group) == ["AbydosDev", "AbydosDev", nil])
		#expect(sessions.map(\.name) == ["AbydosDev", "AbydosDev~2", "Presentation"])
	}

	@Test func aNameWithTheSeparatorSurvivesTheGroupField() {
		#expect(TmuxMirror.parseSessions("2;0;100;-;a;b").first?.name == "a;b")
		#expect(TmuxMirror.parseSessions("2;0;100;-;-;b").first?.name == "-;b")
	}

	// MARK: - What the client is told

	@Test func aGroupedSessionGoesWithItsClient() {
		let arguments = TmuxMirror.attachArguments(for: .grouped(joining: "AbydosDev", as: "AbydosDev~2"))
		#expect(arguments.starts(with: ["-T", "RGB,hyperlinks", "new", "-t", "=AbydosDev", "-s", "AbydosDev~2"]))
		#expect(arguments.suffix(7) == [";", "set-option", "-q", "-t", "AbydosDev~2", "destroy-unattached", "on"])
	}

	/// The session a project remembers does not go with its client.
	@Test func aRejoinedSessionStays() {
		let arguments = TmuxMirror.attachArguments(for: .rejoined(member: "AbydosDev~2", as: "AbydosDev"))
		#expect(arguments.contains("destroy-unattached") == false)
		#expect(arguments.starts(with: ["-T", "RGB,hyperlinks", "new", "-t", "=AbydosDev~2", "-s", "AbydosDev"]))
	}
}
