import Foundation
import Testing
@testable import IdeaiKit

/// Reading a project the way this app reads one: off disk, without running
/// `xcodebuild`, because discovery happens on every scan and `xcodebuild` takes
/// about twelve seconds to answer.
struct XcodeProjectTests {
	/// A project laid out the way Xcode lays one out, with a shared scheme that
	/// launches an app and one that only builds a library.
	static func project(schemes: [String: String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("xcode-\(UUID().uuidString)")
		let shared = root.appendingPathComponent("Thing.xcodeproj/xcshareddata/xcschemes")
		try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)

		for (name, contents) in schemes {
			try contents.write(
				to: shared.appendingPathComponent("\(name).xcscheme"),
				atomically: true,
				encoding: .utf8
			)
		}
		return root
	}

	static func runnableScheme(product: String, configuration: String = "Debug") -> String {
		"""
		<?xml version="1.0" encoding="UTF-8"?>
		<Scheme LastUpgradeVersion = "2600" version = "1.7">
		   <LaunchAction buildConfiguration = "\(configuration)" launchStyle = "0">
		      <BuildableProductRunnable runnableDebuggingMode = "0">
		         <BuildableReference
		            BuildableIdentifier = "primary"
		            BuildableName = "\(product)"
		            BlueprintName = "Thing"
		            ReferencedContainer = "container:Thing.xcodeproj">
		         </BuildableReference>
		      </BuildableProductRunnable>
		   </LaunchAction>
		</Scheme>
		"""
	}

	static let libraryScheme = """
	<?xml version="1.0" encoding="UTF-8"?>
	<Scheme LastUpgradeVersion = "2600" version = "1.7">
	   <LaunchAction buildConfiguration = "Debug" launchStyle = "0">
	   </LaunchAction>
	</Scheme>
	"""

	@Test func readsSchemesWithoutRunningXcodebuild() throws {
		let root = try Self.project(schemes: [
			"App": Self.runnableScheme(product: "Thing.app"),
			"Library": Self.libraryScheme,
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let project = try #require(XcodeProject.find(in: root))
		#expect(project.container == .project)
		#expect(project.name == "Thing")
		#expect(project.xcodebuildArguments.first == "-project")

		let schemes = project.schemes()
		#expect(schemes.count == 2)
		#expect(schemes.first { $0.name == "App" }?.product == "Thing.app")
		#expect(schemes.first { $0.name == "Library" }?.isRunnable == false)
	}

	/// The configuration comes from the scheme rather than from a default, so a
	/// scheme that launches Release is built as Release — otherwise the run
	/// installs a build nobody asked for.
	@Test func takesTheConfigurationTheSchemeLaunches() throws {
		let root = try Self.project(schemes: [
			"App": Self.runnableScheme(product: "Thing.app", configuration: "Release"),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(XcodeProject.find(in: root)?.schemes().first?.configuration == "Release")
	}

	/// Only the schemes that launch something reach the run list: a project with
	/// package dependencies has a scheme per package, and a library scheme there
	/// is an entry that builds and then has nowhere to go.
	@Test func offersOnlyWhatCanBeLaunched() throws {
		let root = try Self.project(schemes: [
			"App": Self.runnableScheme(product: "Thing.app"),
			"Library": Self.libraryScheme,
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.xcodeSchemes(in: root)
		#expect(found.map(\.name) == ["App"])
		#expect(found.first?.source == .xcodeScheme)
		#expect(found.first?.xcode?.scheme.product == "Thing.app")
	}

	/// A workspace wins over a project beside it: a project that has one is
	/// usually one that cannot be built alone.
	@Test func prefersTheWorkspace() throws {
		let root = try Self.project(schemes: ["App": Self.runnableScheme(product: "Thing.app")])
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("Thing.xcworkspace"), withIntermediateDirectories: true
		)

		let project = try #require(XcodeProject.find(in: root))
		#expect(project.container == .workspace)
		#expect(project.xcodebuildArguments == ["-workspace", project.path])
	}

	@Test func findsNothingWhereThereIsNoProject() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("empty-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(XcodeProject.find(in: root) == nil)
		#expect(RunConfigurationDiscovery.xcodeSchemes(in: root).isEmpty)
	}
}

/// Reading `xcodebuild -showdestinations`, which is the part of this that a
/// machine with several simulator runtimes installed makes interesting: most of
/// what it prints cannot be run on.
struct XcodeDestinationTests {
	/// Verbatim from `xcodebuild -project docscanner.xcodeproj -scheme
	/// docscanner-ios -showdestinations`, trimmed to one of each kind.
	static let output = """
		Available destinations for the "docscanner-ios" scheme:
			{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:00006001-0002716A3C41801E, name:My Mac }
			{ platform:iOS, arch:arm64, id:00008140-000E45CC3690801C, name:p.iphone }
			{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
			{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
			{ platform:iOS Simulator, arch:arm64, id:9BCD3E34-D29A-4EBE-B8D9-43A37959F15D, OS:26.0, name:iPad (A16) }

		Ineligible destinations for the "docscanner-ios" scheme:
			{ platform:iOS Simulator, arch:arm64, id:476129E8-ADC1-497B-B093-25C71A5363F5, OS:18.0, name:iPhone 16 Plus, error:iPhone 16 Plus’s iOS Simulator 18.0 doesn’t match docscanner.app’s iOS Simulator 26.0  deployment target. Upgrade iPhone 16 Plus’s iOS Simulator version or lower docscanner.app’s deployment target. }
		"""

	@Test func keepsOnlyWhatCanBeRunOn() {
		let destinations = XcodeDestination.parse(Self.output)

		// The device and the simulator; not the placeholders, not the
		// "Designed for iPad" variant, and nothing from the ineligible list.
		#expect(destinations.map(\.name) == ["p.iphone", "iPad (A16)"])
		#expect(destinations.first?.kind == .device)
		#expect(destinations.last?.kind == .simulator)
	}

	/// An ineligible simulator is a build that is going to fail, and on a
	/// machine with several runtimes installed there are dozens of them.
	@Test func leavesOutTheOnesThatCannotWork() {
		let ineligible = XcodeDestination.parse(Self.output)
			.first { $0.id == "476129E8-ADC1-497B-B093-25C71A5363F5" }
		#expect(ineligible == nil)
	}

	/// The other spelling. `xcodebuild` says "Ineligible destinations for the
	/// … scheme" for one project here and "Destinations incompatible with the
	/// … scheme" for another, and matching one of them was matching whichever
	/// project was open when this was written.
	@Test func stopsAtEitherSpellingOfTheSecondList() {
		let output = """
			Destinations compatible with the "Yacal" scheme:
				{ platform:iOS, arch:arm64, id:PHONE, name:p.iphone }

			Destinations incompatible with the "Yacal" scheme:
				{ platform:iOS Simulator, arch:arm64, id:OLD, OS:17.5, name:iPhone 15 }
			"""
		#expect(XcodeDestination.parse(output).map(\.id) == ["PHONE"])
	}

	/// A device that is plugged in beats a simulator chosen by sorting order:
	/// simulators come back alphabetically by model, so preferring them runs an
	/// iPhone app on whichever iPad simulator sorts first, which succeeds and
	/// looks like the app is fine.
	@Test func prefersThisMacThenADeviceThenASimulator() {
		let mac = XcodeDestination(id: "M", name: "My Mac", platform: "macOS")
		let device = XcodeDestination(id: "D", name: "p.iphone", platform: "iOS")
		let simulator = XcodeDestination(id: "S", name: "iPad (A16)", platform: "iOS Simulator", os: "26.0")

		#expect(XcodeDestinations.preferred(among: [simulator, device, mac])?.id == "M")
		#expect(XcodeDestinations.preferred(among: [simulator, device])?.id == "D")
		#expect(XcodeDestinations.preferred(among: [simulator])?.id == "S")
		#expect(XcodeDestinations.preferred(among: []) == nil)
	}

	@Test func tellsTwoSimulatorsOfTheSameModelApart() {
		let simulator = XcodeDestination(id: "x", name: "iPhone 17 Pro", platform: "iOS Simulator", os: "26.2")
		let device = XcodeDestination(id: "y", name: "p.iphone", platform: "iOS")
		#expect(simulator.title == "iPhone 17 Pro (26.2)")
		#expect(device.title == "p.iphone")
	}

	@Test func knowsWhereEachPlatformPutsItsProduct() {
		#expect(XcodeDestination(id: "1", name: "My Mac", platform: "macOS").productDirectorySuffix == "")
		#expect(XcodeDestination(id: "2", name: "p", platform: "iOS").productDirectorySuffix == "-iphoneos")
		#expect(XcodeDestination(id: "3", name: "s", platform: "iOS Simulator")
			.productDirectorySuffix == "-iphonesimulator")
	}

	/// A name with a comma in it must not swallow the field after it — that is
	/// a destination pointed at the wrong machine, or at none.
	@Test func readsAValueHoldingASeparator() {
		let fields = XcodeDestination.fields(in: "{ platform:iOS, id:0001, name:Phone, spare }")
		#expect(fields["id"] == "0001")
		#expect(fields["name"] == "Phone")
		#expect(fields["platform"] == "iOS")
	}
}

/// The command a run turns into. Nothing here starts anything: what is checked
/// is that the steps are in the order that works and name the paths the build
/// actually writes to, since a wrong one fails after a full build has run.
struct XcodeRunTests {
	static let project = XcodeProject(path: "/p/Thing.xcodeproj", container: .project)
	static let scheme = XcodeScheme(name: "App", product: "Thing.app")

	@Test func buildsInstallsAndLaunchesOnASimulator() throws {
		let command = try #require(XcodeRun.command(
			project: Self.project,
			scheme: Self.scheme,
			destination: XcodeDestination(id: "UDID", name: "iPhone", platform: "iOS Simulator", os: "26.2"),
			derivedData: "/dd"
		))

		let steps = command.components(separatedBy: " && ")
		#expect(steps.count == 5)
		#expect(steps[0].hasPrefix("xcodebuild "))
		#expect(steps[0].contains("-destination 'id=UDID'"))
		// The path quoted, the flag itself not.
		#expect(steps[0].contains("xcodebuild -project '/p/Thing.xcodeproj'"))
		#expect(steps[1].contains("simctl bootstatus"))
		#expect(steps[2] == "open -a Simulator")
		#expect(steps[3].contains("simctl install 'UDID' '/dd/Build/Products/Debug-iphonesimulator/Thing.app'"))
		#expect(steps[4].contains("simctl launch --console-pty"))
		// The identifier is read from what was just built rather than written
		// in, so a scheme that changes it cannot install one app and launch
		// another.
		#expect(steps[4].contains("PlistBuddy -c 'Print :CFBundleIdentifier'"))
	}

	@Test func installsOnADeviceWithProvisioningAllowed() throws {
		let command = try #require(XcodeRun.command(
			project: Self.project,
			scheme: Self.scheme,
			destination: XcodeDestination(id: "PHONE", name: "p.iphone", platform: "iOS"),
			derivedData: "/dd"
		))

		#expect(command.contains("-allowProvisioningUpdates"))
		#expect(command.contains("devicectl device install app --device 'PHONE'"))
		#expect(command.contains("devicectl device process launch --device 'PHONE' --console"))
		#expect(command.contains("/dd/Build/Products/Debug-iphoneos/Thing.app"))
	}

	/// On this Mac the bundle is opened rather than the binary run. Running the
	/// binary is the obvious thing and it is wrong: a sandboxed app started
	/// from a shell cannot be granted its container and exits immediately with
	/// "sandbox_extension_issue_file_to_process failed", which is most Mac apps.
	@Test func opensTheBundleOnThisMac() throws {
		let command = try #require(XcodeRun.command(
			project: Self.project,
			scheme: Self.scheme,
			destination: XcodeDestination(id: "MAC", name: "My Mac", platform: "macOS"),
			derivedData: "/dd"
		))

		#expect(command.contains("open -W -n"))
		#expect(command.contains("'/dd/Build/Products/Debug/Thing.app'"))
		// Not the binary, which is the mistake this is here to keep out.
		#expect(!command.contains("/Contents/MacOS/"))
	}

	/// `open` refuses a pipe or a tty for its output (-10810), so what the app
	/// prints goes to a file that is followed for as long as it runs — and the
	/// follower is stopped afterwards, or the terminal never looks finished.
	@Test func followsWhatAMacAppPrintsAndStopsFollowing() throws {
		let command = try #require(XcodeRun.command(
			project: Self.project,
			scheme: Self.scheme,
			destination: XcodeDestination(id: "MAC", name: "My Mac", platform: "macOS"),
			derivedData: "/dd"
		))

		#expect(command.contains("tail -f '/dd/run.log'"))
		#expect(command.contains("--stdout '/dd/run.log' --stderr '/dd/run.log'"))
		#expect(command.contains("kill $TAILPID"))
		#expect(command.hasSuffix("2>/dev/null"))
	}

	@Test func aSchemeWithNothingToLaunchStillBuilds() {
		let library = XcodeScheme(name: "Library", product: nil)
		let mac = XcodeDestination(id: "MAC", name: "My Mac", platform: "macOS")

		#expect(XcodeRun.command(
			project: Self.project, scheme: library, destination: mac, derivedData: "/dd"
		) == nil)
		#expect(XcodeRun.build(
			project: Self.project, scheme: library, destination: mac, derivedData: "/dd"
		).contains("-scheme 'Library'"))
	}

	/// A path with a space in it is ordinary, and a project called
	/// `My Thing.xcodeproj` must not become two arguments.
	@Test func quotesPathsWithSpaces() {
		let command = XcodeRun.build(
			project: XcodeProject(path: "/p/My Thing.xcodeproj", container: .workspace),
			scheme: Self.scheme,
			destination: XcodeDestination(id: "MAC", name: "My Mac", platform: "macOS"),
			derivedData: "/dd/My Data"
		)
		#expect(command.contains("'/p/My Thing.xcodeproj'"))
		#expect(command.contains("'/dd/My Data'"))
	}
}
