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
		/// Whether a tunnel to it happens to be up.
		///
		/// Not whether it can be reached: the tunnel is established when
		/// something needs it and torn down when idle, so a phone sitting on
		/// the desk paired over Wi-Fi reads `disconnected` most of the time.
		/// Treating this as reachability refused runs to a device that was
		/// perfectly available.
		public let isConnected: Bool

		public init(udid: String, name: String, transport: String, isConnected: Bool) {
			self.udid = udid
			self.name = name
			self.transport = transport
			self.isConnected = isConnected
		}

		/// How to say where it is, in a menu.
		///
		/// The transport and nothing more. Whether the thing can be reached in
		/// the next minute is not knowable from here — only `devicectl` trying
		/// it knows that — and a menu that claims otherwise is a menu that
		/// tells somebody their phone is away while it is in their hand.
		public var attachment: String? {
			switch transport {
			case "wired": return "USB"
			case "localNetwork": return "Wi-Fi"
			default: return nil
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
				// Recorded, but only as a tiebreak. The tunnel comes up when
				// something needs it, so this says whether one is up now and
				// not whether the device is there.
				isConnected: (connection["tunnelState"] as? String) == "connected"
			)
		}
	}

	/// What to say when `devicectl` could not reach a device it was given.
	///
	/// Said after an attempt rather than instead of one: whether a device can
	/// be reached is only known by trying, and the run is the trying.
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
