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

	@Test func oneServerKeepsOneSessionAndAnotherGetsItsOwn() {
		let a = VboardPage.dataStoreID(for: URL(string: "https://boards.example.org")!)
		#expect(a == VboardPage.dataStoreID(for: URL(string: "HTTPS://Boards.Example.org/some/path")!))
		#expect(a != VboardPage.dataStoreID(for: URL(string: "https://boards.example.org:8443")!))
		#expect(a != VboardPage.dataStoreID(for: URL(string: "https://other.example.org")!))
	}
}
