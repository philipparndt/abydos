import Foundation
import Testing
@testable import IdeaiKit

/// Getting back to where you were.
struct NavigationHistoryTests {
	private func place(_ name: String, _ line: Int) -> NavigationHistory.Place {
		NavigationHistory.Place(file: URL(fileURLWithPath: "/p/\(name)"), line: line)
	}

	@Test func startsWithNowhereToGo() {
		let history = NavigationHistory()
		#expect(history.current == nil)
		#expect(!history.canGoBack)
		#expect(!history.canGoForward)
	}

	@Test func walksBackAndForwardAgain() {
		var history = NavigationHistory()
		history.record(place("a.swift", 10))
		history.record(place("b.swift", 20))
		history.record(place("c.swift", 30))

		#expect(history.back() == place("b.swift", 20))
		#expect(history.back() == place("a.swift", 10))
		#expect(!history.canGoBack)
		#expect(history.back() == nil)

		#expect(history.forward() == place("b.swift", 20))
		#expect(history.forward() == place("c.swift", 30))
		#expect(!history.canGoForward)
	}

	/// Going back and then somewhere new ends the future that was there: it is
	/// no longer where "forward" leads.
	@Test func jumpingFromTheMiddleDropsTheForwardTail() {
		var history = NavigationHistory()
		history.record(place("a.swift", 1))
		history.record(place("b.swift", 1))
		history.record(place("c.swift", 1))
		_ = history.back()

		history.record(place("d.swift", 1))
		#expect(!history.canGoForward)
		#expect(history.back() == place("b.swift", 1))
	}

	/// Opening the file you are already looking at should not make going back
	/// take two presses.
	@Test func doesNotRecordStandingStill() {
		var history = NavigationHistory()
		history.record(place("a.swift", 10))
		history.record(place("a.swift", 12))
		history.record(place("a.swift", 10))

		#expect(!history.canGoBack)
		// The newest line wins, so coming back lands where you were reading.
		#expect(history.current == place("a.swift", 10))
	}

	/// Far enough apart in the same file is still somewhere else.
	@Test func treatsADistantLineAsAnotherPlace() {
		var history = NavigationHistory()
		history.record(place("a.swift", 10))
		history.record(place("a.swift", 400))

		#expect(history.canGoBack)
		#expect(history.back() == place("a.swift", 10))
	}

	@Test func forgetsAFileThatIsGone() {
		var history = NavigationHistory()
		history.record(place("a.swift", 1))
		history.record(place("b.swift", 1))
		history.record(place("a.swift", 90))

		history.forget(file: URL(fileURLWithPath: "/p/a.swift"))
		#expect(history.current == place("b.swift", 1))
		#expect(!history.canGoBack)
		#expect(!history.canGoForward)
	}

	/// A long session must not grow without bound.
	@Test func keepsOnlyTheRecentPast() {
		var history = NavigationHistory()
		for index in 0..<(NavigationHistory.limit + 20) {
			history.record(place("f\(index).swift", 1))
		}
		#expect(history.places.count == NavigationHistory.limit)
		#expect(history.current == place("f\(NavigationHistory.limit + 19).swift", 1))
	}
}
