import Foundation

/// Where a scheme can run, asked of `xcodebuild` and then remembered.
///
/// Asking takes about twelve seconds, which is why it is not part of finding
/// the schemes: a project is scanned whenever it is opened or its files change,
/// and a scan nobody asked for must not cost twelve seconds of a laptop's fan.
/// It is asked when somebody opens the destination menu, and the answer is kept
/// until they ask for it again — a simulator that was installed since is one
/// refresh away, and a phone that was plugged in since is the same.
///
/// On the main actor rather than an actor of its own, because what asks is a
/// menu: it has to draw immediately with whatever is known and fill in when the
/// answer arrives, and a cache it can only read by awaiting is one it cannot
/// draw from at all.
@MainActor
public final class XcodeDestinations {
	public static let shared = XcodeDestinations()

	private var cache: [String: [XcodeDestination]] = [:]
	/// How each device is attached, by UDID, from the last time it was asked.
	private var attachments: [String: XcodeDevices.Device] = [:]

	public init() {}

	/// The destinations for a scheme, from the cache unless asked to look again.
	public func destinations(
		for target: XcodeTarget,
		workingDirectory: URL,
		refresh: Bool = false
	) async -> [XcodeDestination] {
		let key = "\(target.project.path):\(target.scheme.name)"
		if !refresh, let known = cache[key] { return known }

		// Both questions at once: what this scheme can run on, and how each of
		// those is attached. A phone on a cable and one asleep in another room
		// look identical in `xcodebuild`'s answer.
		async let asked = Self.ask(for: target, workingDirectory: workingDirectory)
		async let devices = Self.askDevices()
		let found = await asked
		for device in await devices { attachments[device.udid] = device }
		// A failed question is not an answer: keeping an empty list would make
		// the menu permanently empty for a project whose first scan happened
		// while Xcode was updating.
		if !found.isEmpty { cache[key] = found }
		return found
	}

	/// How a destination is attached, when it is a device and the answer is
	/// known. Nil for simulators and for this Mac, which are not attached to
	/// anything and need no saying so.
	public func attachment(of destination: XcodeDestination) -> XcodeDevices.Device? {
		guard destination.kind == .device else { return nil }
		return attachments[destination.id]
	}

	/// What is already known, for drawing a menu before the answer arrives.
	public func known(for target: XcodeTarget) -> [XcodeDestination] {
		cache["\(target.project.path):\(target.scheme.name)"] ?? []
	}

	public func forget() {
		cache.removeAll()
	}

	/// The default when nobody has chosen: this Mac, then a device on the desk,
	/// then a simulator.
	///
	/// The device before the simulator because a phone that is plugged in is a
	/// phone somebody plugged in — and because the alternative is arbitrary.
	/// Simulators come back in `xcodebuild`'s order, which is alphabetical by
	/// model, so preferring them means running an iPhone app on whichever iPad
	/// simulator happens to sort first. A device that is locked or unprovisioned
	/// fails with a message about that; a run on the wrong simulator succeeds
	/// and looks like the app is fine.
	nonisolated public static func preferred(
		among destinations: [XcodeDestination],
		attached: [String: XcodeDevices.Device] = [:]
	) -> XcodeDestination? {
		// A device that can be reached beats one that cannot. Without this the
		// default lands on whichever device sorts first — an iPad asleep in
		// another room — while the phone on the desk sits below it, and the
		// first run of the day fails on a device nobody chose.
		func reachable(_ destination: XcodeDestination) -> Bool {
			attached[destination.id].map(\.isConnected) ?? true
		}

		return destinations.first { $0.kind == .mac }
			?? destinations.first { $0.kind == .device && reachable($0) }
			?? destinations.first { $0.kind == .simulator }
			?? destinations.first { $0.kind == .device }
	}

	/// The same, using what is known about how each device is attached.
	public func preferred(among destinations: [XcodeDestination]) -> XcodeDestination? {
		Self.preferred(among: destinations, attached: attachments)
	}

	/// Asks `devicectl` how the devices it knows about are attached.
	nonisolated static func askDevices() async -> [XcodeDevices.Device] {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let output = URL(fileURLWithPath: NSTemporaryDirectory())
					.appendingPathComponent("ideai-devices-\(ProcessInfo.processInfo.processIdentifier).json")
				defer { try? FileManager.default.removeItem(at: output) }

				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
				// `--json-output` writes a file rather than printing, so there
				// is nothing to read from a pipe here.
				process.arguments = [
					"devicectl", "list", "devices", "--json-output", output.path,
				]
				process.standardOutput = FileHandle.nullDevice
				process.standardError = FileHandle.nullDevice

				do {
					try process.run()
					process.waitUntilExit()
				} catch {
					continuation.resume(returning: [])
					return
				}

				let data = (try? Data(contentsOf: output)) ?? Data()
				continuation.resume(returning: XcodeDevices.parse(data))
			}
		}
	}

	nonisolated static func ask(for target: XcodeTarget, workingDirectory: URL) async -> [XcodeDestination] {
		var arguments = target.project.xcodebuildArguments
		arguments += ["-scheme", target.scheme.name, "-showdestinations"]

		return await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
				process.arguments = arguments
				process.currentDirectoryURL = workingDirectory

				let out = Pipe()
				process.standardOutput = out
				// Where `xcodebuild` says a scheme cannot be resolved at all,
				// which is not a list of destinations and not worth parsing.
				process.standardError = FileHandle.nullDevice

				do {
					try process.run()
				} catch {
					continuation.resume(returning: [])
					return
				}

				let data = out.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				continuation.resume(
					returning: XcodeDestination.parse(String(decoding: data, as: UTF8.self))
				)
			}
		}
	}
}
