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

	/// One per *category*, not per platform.
	///
	/// An iPhone and an iPad are both `iOS Simulator`, so keying on the
	/// platform offered one between them — and somebody whose app runs on both
	/// expects to see both. That is what this pins.
	@Test func thereIsOneOfEachKindOfMachine() {
		let all = [
			simulator("iPhone 17", "26.0"),
			simulator("iPhone 17", "27.0"),
			simulator("iPad Air 13-inch (M4)", "26.5"),
			simulator("Apple TV 4K", "26.1", platform: "tvOS Simulator"),
			XcodeDestination(id: "mac", name: "My Mac", platform: "macOS"),
		]
		let newest = XcodeDestinationMenu.newestOfEachFamily(among: all)
		let names = newest.map(\.name)
		#expect(names.contains("iPhone 17"))
		#expect(names.contains("iPad Air 13-inch (M4)"))
		#expect(names.contains("Apple TV 4K"))
		#expect(newest.count == 3)
		// The Mac is not a simulator and is not shortlisted as one.
		#expect(!newest.contains { $0.kind == .mac })
		// The iPhone picked is the newest runtime of that model.
		#expect(newest.first { $0.name == "iPhone 17" }?.os == "27.0")
		// iPhone before iPad, and both before the rest.
		#expect(names.first == "iPhone 17")
	}

	/// The name says which machine it is; the platform cannot.
	@Test func theCategoryComesFromTheName() {
		#expect(XcodeDestinationMenu.category(of: simulator("iPhone 17 Pro", "27.0")) == "iPhone")
		#expect(XcodeDestinationMenu.category(of: simulator("iPad mini (A17 Pro)", "26.5")) == "iPad")
		#expect(XcodeDestinationMenu.category(
			of: simulator("Apple Watch Series 10", "26.0", platform: "watchOS Simulator")
		) == "Apple Watch")
		// Something nobody has seen still gets a category of its own rather
		// than vanishing into another one.
		#expect(XcodeDestinationMenu.category(
			of: simulator("Apple Fridge", "1.0", platform: "fridgeOS Simulator")
		) == "fridgeOS")
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

	/// "Latest" is the newest runtime the *model* has, not the newest installed.
	///
	/// A watch simulator's newest runtime is years behind an iPhone's, and they
	/// are not the same number line. Picking by the newest runtime installed
	/// would leave the menu with no watch on it at all — the rule is inside a
	/// family, which is what this pins.
	@Test func aFamilyWhoseRuntimesAreAllOlderIsStillOnTheMenu() {
		let all = [
			simulator("iPhone 17", "27.0"),
			simulator("iPad Air 13-inch (M4)", "26.5"),
			simulator("Apple Watch Series 10 (46mm)", "12.0", platform: "watchOS Simulator"),
			simulator("Apple Watch Ultra 3", "11.5", platform: "watchOS Simulator"),
		]
		let newest = XcodeDestinationMenu.newestOfEachFamily(among: all)

		let watch = newest.first { XcodeDestinationMenu.category(of: $0) == "Apple Watch" }
		#expect(watch != nil, "the watch was dropped for being older than an iPhone")
		#expect(watch?.os == "12.0")
		#expect(newest.first { $0.name == "iPad Air 13-inch (M4)" }?.os == "26.5")
	}

	/// A model that stopped shipping offers its last runtime rather than
	/// vanishing because something newer exists without it.
	///
	/// `iPhone 16e` is in 26.0 and gone by 27.0. The family shows the model that
	/// gets furthest — that is what "latest" buys — and the one that stopped is
	/// still there behind the dialog, at the last runtime it ever had, never at
	/// one it does not have.
	@Test func aModelThatStoppedShippingKeepsItsLastRuntime() {
		let all = [
			simulator("iPhone 16e", "26.0"),
			simulator("iPhone 17", "26.0"),
			simulator("iPhone 17", "27.0"),
		]
		let shown = XcodeDestinationMenu.newestOfEachFamily(among: all)
		#expect(shown.map(\.name) == ["iPhone 17"])
		#expect(shown.first?.os == "27.0")

		let rest = XcodeDestinationMenu.rest(among: all, shown: shown)
		let old = rest.filter { $0.name == "iPhone 16e" }
		#expect(old.map(\.os) == ["26.0"])
	}

	/// The rule as an invariant, over a list shaped like a real machine's:
	/// whatever is offered is that model at the newest runtime that model has.
	///
	/// Written as "no destination of the same name has a newer OS" rather than
	/// as an expected list, because that is the rule itself — an expected list
	/// would also pass if the answer were right for the wrong reason.
	@Test func whatIsOfferedIsAlwaysItsModelsOwnNewestRuntime() {
		let all = [
			simulator("iPhone 16e", "26.0"),
			simulator("iPhone 17", "26.0"),
			simulator("iPhone 17", "27.0"),
			simulator("iPhone Air", "27.0"),
			simulator("iPad (A16)", "26.5"),
			simulator("iPad Pro 13-inch (M5)", "26.5"),
			simulator("iPad Pro 13-inch (M5)", "27.0"),
			simulator("Apple TV 4K", "26.1", platform: "tvOS Simulator"),
			simulator("Apple Watch Series 10 (46mm)", "12.0", platform: "watchOS Simulator"),
		]

		for offered in XcodeDestinationMenu.newestOfEachFamily(among: all) {
			let sameModel = all.filter { $0.name == offered.name }
			#expect(!sameModel.contains { XcodeDestinationMenu.isNewer($0, than: offered) },
			        "\(offered.title) is not the newest runtime \(offered.name) has")
		}
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

/// Noticing a device that was plugged in after the first look.
///
/// `xcodebuild -showdestinations` costs about twelve seconds, so its answer is
/// kept — and kept for ever meant a phone connected later never appeared in the
/// menu at all, with nothing on screen saying why. `devicectl` is asked every
/// time the menu opens and is quick, so it is the one that notices.
struct DestinationStalenessTests {
	private func device(_ udid: String) -> XcodeDevices.Device {
		XcodeDevices.Device(
			udid: udid, name: "a phone", transport: "wired", isConnected: true
		)
	}

	@Test func aDeviceThatIsNotInTheKeptAnswerMakesItStale() {
		let known = [
			XcodeDestination(id: "phone-1", name: "iPhone", platform: "iOS"),
			XcodeDestination(id: "sim-1", name: "iPhone 17", platform: "iOS Simulator", os: "27.0"),
		]
		// The one it already knows about: nothing to do.
		#expect(!XcodeDestinations.hasUnknownDevice(among: [device("phone-1")], known: known))
		// One it does not: the kept answer is out of date.
		#expect(XcodeDestinations.hasUnknownDevice(among: [device("phone-2")], known: known))
		// Nothing attached at all is not a reason to ask again.
		#expect(!XcodeDestinations.hasUnknownDevice(among: [], known: known))
	}

	/// Simulator ids are not device ids, and must not be mistaken for them.
	///
	/// Matching a `devicectl` udid against every destination rather than only
	/// the devices would compare it with simulator identifiers too — the same
	/// shape of string — and a coincidence there would mean never refreshing.
	@Test func onlyDevicesAreComparedWithDevices() {
		let simulatorsOnly = [
			XcodeDestination(id: "abc", name: "iPhone 17", platform: "iOS Simulator", os: "27.0")
		]
		#expect(XcodeDestinations.hasUnknownDevice(among: [device("abc")], known: simulatorsOnly))
	}
}
