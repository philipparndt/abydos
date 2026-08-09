import Foundation
import Testing
@testable import AbydosKit

/// Which destinations belong in a menu and which behind a dialog.
///
/// The numbers are from a real project: 79 eligible destinations, of which 75
/// were simulators — 23 models against every installed runtime.
struct XcodeDestinationMenuTests {
	private func simulator(_ name: String, _ os: String, platform: String = "iOS Simulator")
		-> XcodeDestination {
		XcodeDestination(id: "\(name)-\(os)", name: name, platform: platform, os: os)
	}

	/// One per family, and the newest runtime of it.
	@Test func theNewestOfEachFamilyIsOfferedDirectly() {
		let all = [
			simulator("iPhone 17", "26.0"),
			simulator("iPhone 17", "27.0"),
			simulator("iPad Air 13-inch (M4)", "26.5"),
			simulator("Apple TV 4K", "26.1", platform: "tvOS Simulator"),
			XcodeDestination(id: "mac", name: "My Mac", platform: "macOS"),
		]
		let newest = XcodeDestinationMenu.newestOfEachFamily(among: all)
		#expect(newest.count == 2 || newest.count == 3)
		// The Mac is not a simulator and is not shortlisted as one.
		#expect(!newest.contains { $0.kind == .mac })
		// iOS picked the 27.0 one.
		let ios = newest.first { $0.platform == "iOS Simulator" }
		#expect(ios?.os == "27.0")
	}

	/// Compared as numbers, not as text.
	///
	/// "9.0" against "10.0" is the case that decides this: as strings the nine
	/// wins, and the menu would offer a runtime two years old as the newest.
	@Test func runtimesCompareAsNumbers() {
		#expect(XcodeDestinationMenu.version("26.4.1") == [26, 4, 1])
		#expect(XcodeDestinationMenu.isNewer(simulator("x", "10.0"), than: simulator("x", "9.0")))
		#expect(XcodeDestinationMenu.isNewer(simulator("x", "27.0"), than: simulator("x", "26.5")))
		#expect(!XcodeDestinationMenu.isNewer(simulator("x", "26.5"), than: simulator("x", "27.0")))
	}

	/// Everything not shown is still reachable — nothing is dropped.
	@Test func theRestIsEverythingElseAndNothingMore() {
		let all = [
			simulator("iPhone 17", "26.0"),
			simulator("iPhone 17", "27.0"),
			simulator("iPad", "26.0"),
		]
		let shown = XcodeDestinationMenu.newestOfEachFamily(among: all)
		let rest = XcodeDestinationMenu.rest(among: all, shown: shown)
		#expect(Set(shown.map(\.id)).isDisjoint(with: Set(rest.map(\.id))))
		#expect(shown.count + rest.count == all.count)
	}

	/// Every word, anywhere, in any order.
	@Test func theFilterTakesWordsInAnyOrder() {
		let pad = simulator("iPad Pro 13-inch (M5)", "27.0")
		#expect(XcodeDestinationMenu.matches(pad, "pro 27"))
		#expect(XcodeDestinationMenu.matches(pad, "27 pro"))
		#expect(XcodeDestinationMenu.matches(pad, "IPAD"))
		#expect(XcodeDestinationMenu.matches(pad, ""))
		#expect(!XcodeDestinationMenu.matches(pad, "iphone"))
	}
}

/// The Mac that was missing from every project with Catalyst enabled.
struct MacCatalystDestinationTests {
	/// Taken from `xcodebuild -showdestinations` for a real iOS app: the only
	/// two macOS lines it answers with, both carrying a variant.
	@Test func aCatalystMacIsADestinationRatherThanNothing() {
		let output = """
		Available destinations for the "WallDisplay2" scheme:
			{ platform:macOS, arch:arm64, variant:Mac Catalyst, id:00006001-0002, name:My Mac }
			{ platform:iOS Simulator, id:ABC, OS:26.5, name:iPad (A16) }
			{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:00006001-0002, name:My Mac }
		"""
		let found = XcodeDestination.parse(output)
		let mac = found.first { $0.kind == .mac }
		#expect(mac != nil, "the Catalyst Mac was dropped again")
		#expect(mac?.isMacCatalyst == true)
		// "Designed for" is still left out: it shares this Mac's name and id
		// with the line above and is a different product directory.
		#expect(found.filter { $0.kind == .mac }.count == 1)
	}

	/// Both halves, since one without the other builds into the wrong place.
	@Test func catalystSaysWhereItsProductIsAndWhichMacItMeans() {
		let mac = XcodeDestination(
			id: "0001", name: "My Mac", platform: "macOS", variant: "Mac Catalyst"
		)
		#expect(mac.productDirectorySuffix == "-maccatalyst")
		#expect(mac.destinationArgument == "platform=macOS,variant=Mac Catalyst,id=0001")
		#expect(mac.title == "My Mac (Mac Catalyst)")

		// A plain Mac is unchanged, and an id is all it needs.
		let plain = XcodeDestination(id: "0002", name: "My Mac", platform: "macOS")
		#expect(plain.productDirectorySuffix == "")
		#expect(plain.destinationArgument == "id=0002")
	}
}
