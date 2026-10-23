import Foundation
import Testing
@testable import AbydosKit

/// What a board tab makes of the `vboard.server` setting.
struct VboardServerAddressTests {
	@Test func nothingNamedIsNoServerAndTheSettingStartsEmpty() {
		#expect(VboardServerAddress("") == .none)
		#expect(VboardServerAddress("   \n") == .none)
		#expect(Settings(defaults: TestDefaults.make()).vboardServer == "")
	}

	@Test func anHTTPSAddressIsAServer() {
		let url = URL(string: "https://boards.example.org")!
		#expect(VboardServerAddress(" https://boards.example.org ") == .server(url, isPlainOverNetwork: false))
	}

	@Test func plainHTTPToThisMachineIsFineAndToAnotherIsSaid() {
		#expect(VboardServerAddress("http://localhost:7480") == .server(URL(string: "http://localhost:7480")!, isPlainOverNetwork: false))
		#expect(VboardServerAddress("http://127.0.0.1:7480") == .server(URL(string: "http://127.0.0.1:7480")!, isPlainOverNetwork: false))
		#expect(VboardServerAddress("http://boards.example.org") == .server(URL(string: "http://boards.example.org")!, isPlainOverNetwork: true))
	}

	@Test func whatIsNotAServerAddressSaysWhy() {
		for typed in ["boards.example.org", "ftp://boards.example.org", "https://boards.example.org/b/b_0123456789abcdef#k=secret", "https://boards.example.org/?token=x"] {
			guard case .unusable(let why) = VboardServerAddress(typed) else {
				Issue.record("\(typed) was taken for a server")
				continue
			}
			#expect(why.contains(typed))
		}
	}
}

/// What the board tab hears from vboard's page, and where it keeps its session.
struct VboardPageTests {
	private let board = "b_0123456789abcdef"

	@Test func theMessagesTheTabActsOnAreRead() {
		#expect(VboardPage.Message(["board": board, "type": "snapshot", "people": 3], board: board) == .snapshot(people: 3))
		#expect(VboardPage.Message(["board": board, "type": "presence", "people": 1], board: board) == .presence(people: 1))
		for type in ["items", "entries", "board"] {
			#expect(VboardPage.Message(["board": board, "type": type], board: board) == .changed)
		}
		#expect(VboardPage.Message(["board": board, "type": "deleted", "reason": "expired"], board: board) == .deleted(reason: "expired"))
		#expect(VboardPage.Message(["board": board, "type": "replaced"], board: board) == .replaced)
	}

	@Test func anotherBoardsSocketIsIgnored() {
		#expect(VboardPage.Message(["board": "b_fedcba9876543210", "type": "items"], board: board) == nil)
		#expect(VboardPage.Message(["board": board, "type": "cursor"], board: board) == nil)
		#expect(VboardPage.Message("items", board: board) == nil)
	}

	@Test func theWatcherNeverReadsWhatThePageSends() {
		#expect(!VboardPage.socketWatcher.contains(".send"))
		#expect(VboardPage.socketWatcher.contains(VboardPage.handlerName))
	}

	@Test func oneServerKeepsOneStoreAndOnePortAndAnotherGetsItsOwn() {
		let server = URL(string: "https://boards.example.org")!
		let same = URL(string: "HTTPS://Boards.Example.org/some/path")!
		let other = URL(string: "https://other.example.org")!
		#expect(VboardPage.dataStoreID(for: server) == VboardPage.dataStoreID(for: same))
		#expect(VboardPage.dataStoreID(for: server) != VboardPage.dataStoreID(for: URL(string: "https://boards.example.org:8443")!))
		#expect(VboardPage.dataStoreID(for: server) != VboardPage.dataStoreID(for: other))
		#expect(VboardPage.preferredPort(for: server) == VboardPage.preferredPort(for: same))
		#expect((47_300..<47_700).contains(VboardPage.preferredPort(for: other)))
	}

	@Test func theThemeSetsVboardsColoursAheadOfItsOwnInBothThemes() {
		let css = VboardPage.themeStyle(["--vb-canvas": "#1e1e1e", "--ring": "#ffb86c"])
		#expect(css.contains(":root:root[data-theme='dark']"))
		#expect(css.contains(":root:root[data-theme='light']"))
		#expect(css.contains("--vb-canvas: #1e1e1e !important;"))
		#expect(css.contains("--ring: #ffb86c !important;"))
	}

	@Test func aColourCannotCloseTheRuleItIsIn() {
		let css = VboardPage.themeStyle(["--vb-canvas": "red; } body { display: none", "color": "red", "--ring": "#fff"])
		#expect(!css.contains("display: none"))
		#expect(!css.contains("  color:"))
		#expect(css.contains("--ring: #fff"))
	}
}
