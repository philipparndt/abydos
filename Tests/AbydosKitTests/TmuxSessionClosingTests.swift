import Foundation
import Testing
@testable import AbydosKit

/// What "Close Sessions…" offers, lets through and says — without a server.
struct TmuxSessionClosingTests {
	private let server: [TmuxMirror.SessionSummary] = [
		.init(name: "work", windowCount: 8, isAttached: true, created: 1),
		.init(name: "abydos", windowCount: 1, isAttached: false, created: 2),
		.init(name: "other", windowCount: 2, isAttached: true, created: 3),
	]

	/// Every session is listed, in the order the menu showed them, and the one
	/// under the tabs is the one that cannot be ticked.
	@Test func theSessionUnderTheTabsIsListedButNotClosable() {
		let offers = TmuxSessionClosing.offers(server, showing: "work")
		#expect(offers.map(\.name) == ["work", "abydos", "other"])
		#expect(offers.map(\.isClosable) == [false, true, true])
	}

	/// What stands beside each name: how much goes, and who is looking.
	@Test func theDetailSaysWindowsAndWhoIsAttached() {
		let offers = TmuxSessionClosing.offers(server, showing: "work")
		#expect(offers[0].detail == "8 windows · this window's tabs")
		#expect(offers[1].detail == "1 window")
		#expect(offers[2].detail == "2 windows · attached")
	}

	/// A window with no tabs mirroring anything has nothing to protect.
	@Test func withNothingShowingEverythingIsClosable() {
		let offers = TmuxSessionClosing.offers(server, showing: nil)
		let closable = offers.allSatisfy { $0.isClosable }
		#expect(closable)
	}

	/// **The rule holds against a driven run too.** A name for the session
	/// being shown, or one the server never had, is dropped rather than
	/// killed; a name given twice is closed once.
	@Test func onlyClosableNamesGetThrough() {
		let offers = TmuxSessionClosing.offers(server, showing: "work")
		let through = TmuxSessionClosing.closable(
			["work", "abydos", "nonesuch", "other", "abydos"], among: offers
		)
		#expect(through == ["abydos", "other"])
	}

	/// The menu item is there when there is something to close, and not when
	/// the server holds nothing but the session under the tabs.
	@Test func theMenuItemAppearsOnlyWithSomethingToClose() {
		#expect(TmuxSessionClosing.isWorthOffering(server, showing: "work"))
		#expect(TmuxSessionClosing.isWorthOffering(
			[.init(name: "work", windowCount: 8, isAttached: true, created: 1)], showing: "work"
		) == false)
		// Nothing mirrored yet — every session on the server is closable, so
		// the item belongs there.
		#expect(TmuxSessionClosing.isWorthOffering(server, showing: nil))
		#expect(TmuxSessionClosing.isWorthOffering([], showing: nil) == false)
	}

	@Test func theToastCountsWhatHappened() {
		#expect(TmuxSessionClosing.said(closed: 1, refused: 0) == "Closed 1 session")
		#expect(TmuxSessionClosing.said(closed: 3, refused: 0) == "Closed 3 sessions")
		#expect(TmuxSessionClosing.said(closed: 0, refused: 2) == "tmux would not close 2 sessions")
		#expect(TmuxSessionClosing.said(closed: 2, refused: 1)
			== "Closed 2 sessions; tmux would not close 1")
	}
}
