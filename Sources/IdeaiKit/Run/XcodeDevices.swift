import Foundation

/// The devices `devicectl` knows about, and how each one is attached.
///
/// `xcodebuild -showdestinations` lists devices but says nothing about how they
/// are reached, which is the thing somebody standing at a desk wants to know: a
/// phone paired over the network is offered exactly like the one on the cable,
/// and when it is asleep in another room the run fails several minutes in with
/// a message about a tunnel. `devicectl` knows, so it is asked.
///
/// Merged by UDID, because the two tools disagree about identifiers:
/// `xcodebuild` uses the device's UDID (`00008140-…`) and `devicectl` shows its
/// own (`A5D45677-…`) while accepting either.
public enum XcodeDevices {
	public struct Device: Equatable, Sendable {
		/// The UDID, which is what `xcodebuild` destinations are keyed by.
		public let udid: String
		public let name: String
		/// `wired`, `localNetwork`, or whatever else a future one reports.
		public let transport: String
		/// Whether it can be reached right now.
		public let isConnected: Bool

		public init(udid: String, name: String, transport: String, isConnected: Bool) {
			self.udid = udid
			self.name = name
			self.transport = transport
			self.isConnected = isConnected
		}

		/// How to say where it is, in a menu.
		public var attachment: String? {
			switch transport {
			case "wired": return isConnected ? "USB" : "USB, unplugged"
			case "localNetwork": return isConnected ? "Wi-Fi" : "Wi-Fi, not reachable"
			default: return isConnected ? nil : "not reachable"
			}
		}
	}

	/// Reads `devicectl list devices --json-output`.
	///
	/// Simulators come back too, as `sameMachine`; they are left out, because a
	/// simulator is not a device anybody is asking about the attachment of.
	public static func parse(_ data: Data) -> [Device] {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let result = object["result"] as? [String: Any],
		      let devices = result["devices"] as? [[String: Any]]
		else { return [] }

		return devices.compactMap { entry in
			let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
			let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
			let properties = entry["deviceProperties"] as? [String: Any] ?? [:]

			guard let udid = hardware["udid"] as? String,
			      let transport = connection["transportType"] as? String,
			      transport != "sameMachine"
			else { return nil }

			return Device(
				udid: udid,
				name: properties["name"] as? String ?? udid,
				transport: transport,
				// The tunnel rather than the pairing: paired is a lasting fact
				// about a device, and connected is whether it can be installed
				// to in the next minute.
				isConnected: (connection["tunnelState"] as? String) == "connected"
			)
		}
	}

	/// What to say when a run is aimed at a device that cannot be reached.
	///
	/// Named for what it is rather than "an error occurred": everything after
	/// this point takes minutes — a build, then an install that times out — so
	/// the sentence has to arrive before the build does.
	public static func unreachable(_ device: Device) -> String {
		switch device.transport {
		case "localNetwork":
			return """
			\(device.name) is paired over Wi-Fi but cannot be reached. \
			Wake it and put it on this network, or connect it by cable.
			"""
		default:
			return """
			\(device.name) is not connected. Plug it in, unlock it, and trust this Mac \
			— or pair it for Wi-Fi in Xcode's Devices window to run without the cable.
			"""
		}
	}
}
