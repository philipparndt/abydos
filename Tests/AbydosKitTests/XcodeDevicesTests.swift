import Foundation
import Testing
@testable import AbydosKit

/// Reading `devicectl`, which is the only tool that says *how* a device is
/// attached. `xcodebuild -showdestinations` offers a phone paired over Wi-Fi
/// exactly as it offers the one on the cable, and the difference only shows up
/// several minutes later as an install that times out.
struct XcodeDevicesTests {
	static func fixture() throws -> Data {
		let url = try #require(Bundle.module.url(
			forResource: "devicectl-devices", withExtension: "json", subdirectory: "Fixtures"
		))
		return try Data(contentsOf: url)
	}

	/// Captured from this machine, with a phone on a cable and an iPad paired
	/// over the network.
	@Test func readsHowEachDeviceIsAttached() throws {
		let devices = XcodeDevices.parse(try Self.fixture())

		let phone = try #require(devices.first { $0.name == "p.iphone" })
		#expect(phone.udid == "00008140-000E45CC3690801C")
		#expect(phone.transport == "wired")
		#expect(phone.isConnected)
		#expect(phone.attachment == "USB")

		let pad = try #require(devices.first { $0.name.contains("iPad von Philipp") })
		#expect(pad.transport == "localNetwork")
		// Paired for Wi-Fi with no tunnel up, which is the resting state of a
		// device that is right there: offered as Wi-Fi, with no claim about
		// whether it can be reached this second.
		#expect(!pad.isConnected)
		#expect(pad.attachment == "Wi-Fi")
	}

	/// Simulators come back from the same command as `sameMachine`. They are
	/// not devices anybody is asking about the attachment of, and listing them
	/// here would double every simulator in the menu.
	@Test func leavesSimulatorsOut() throws {
		let devices = XcodeDevices.parse(try Self.fixture())
		#expect(!devices.contains { $0.transport == "sameMachine" })
	}

	/// The UDID, because that is what a destination is keyed by. `devicectl`
	/// shows an identifier of its own and accepts either, so merging on the
	/// wrong one would match nothing.
	@Test func keysOnTheIdentifierDestinationsUse() throws {
		let devices = XcodeDevices.parse(try Self.fixture())
		#expect(devices.allSatisfy { $0.udid.contains("-") })
		#expect(!devices.contains { $0.udid == "A5D45677-CA24-5BFD-A935-5DCA0360314B" })
	}

	@Test func survivesRubbish() {
		#expect(XcodeDevices.parse(Data()).isEmpty)
		#expect(XcodeDevices.parse(Data("not json".utf8)).isEmpty)
		#expect(XcodeDevices.parse(Data(#"{"result": {}}"#.utf8)).isEmpty)
	}

	/// What is said before a build starts, rather than after an install times
	/// out — and it differs by transport, because what to do about it does.
	@Test func saysWhatToDoAboutEachKindOfAbsence() {
		let wifi = XcodeDevices.Device(
			udid: "1", name: "iPad von Philipp", transport: "localNetwork", isConnected: false
		)
		#expect(XcodeDevices.unreachable(wifi).contains("Wake it"))

		let cable = XcodeDevices.Device(
			udid: "2", name: "p.iphone", transport: "wired", isConnected: false
		)
		#expect(XcodeDevices.unreachable(cable).contains("Plug it in"))
		// And says how to stop needing the cable, since that is the question
		// somebody plugging one in is about to ask.
		#expect(XcodeDevices.unreachable(cable).contains("Devices window"))
	}
}
