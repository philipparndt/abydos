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
		if !refresh, let known = cache[key] {
			// The destinations keep, the attachments do not: a phone moves
			// between the cable and the network, and a label from twenty
			// minutes ago is how a menu comes to describe somewhere the device
			// no longer is.
			for device in await Self.askDevices() { attachments[device.udid] = device }
			return known
		}

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
		// A device on a cable is certainly there. One paired over the network
		// probably is, and only trying finds out — which is why this orders
		// them rather than ruling any out.
		func isWired(_ destination: XcodeDestination) -> Bool {
			attached[destination.id]?.transport == "wired"
		}

		return destinations.first { $0.kind == .mac }
			?? destinations.first { $0.kind == .device && isWired($0) }
			?? destinations.first { $0.kind == .device }
			?? destinations.first { $0.kind == .simulator }
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

				let data = ProcessPipes.drain(process, out: out)
				continuation.resume(
					returning: XcodeDestination.parse(String(decoding: data, as: UTF8.self))
				)
			}
		}
	}
}

/// Which destinations a menu shows, and which belong behind a dialog.
///
/// A real project answered with 79 of them: two devices, two Macs, and 75
/// simulators — 23 models against every installed runtime. That is not a menu,
/// it is a list that runs off the screen, and a menu cannot have a filter field
/// to make it one.
///
/// So the menu is what somebody picks by name — this Mac, the phones on the
/// desk, and the newest simulator of each family — and everything else is
/// reachable through a dialog that can be typed into.
public enum XcodeDestinationMenu {
	/// The kind of machine a simulator pretends to be.
	///
	/// From the name, which is the only place it is said. The platform will not
	/// do it: an iPhone and an iPad are both `iOS Simulator`, so keying on the
	/// platform offered one iOS simulator between them — and somebody with an
	/// app that runs on both expects one of each, which is what this is for.
	///
	/// The platform is the fallback rather than the rule, so a machine Apple
	/// names differently next year still gets an entry of its own instead of
	/// disappearing from the menu.
	public static func category(of destination: XcodeDestination) -> String {
		let known = ["iPhone", "iPad", "Apple TV", "Apple Watch", "Apple Vision"]
		if let match = known.first(where: { destination.name.hasPrefix($0) }) { return match }
		return destination.platform.replacingOccurrences(of: " Simulator", with: "")
	}

	/// The order the categories are shown in: the two everybody has first, then
	/// the rest alphabetically so the list does not depend on what happens to
	/// be installed.
	public static func rank(_ category: String) -> Int {
		["iPhone", "iPad", "Apple Watch", "Apple TV", "Apple Vision"]
			.firstIndex(of: category) ?? 99
	}

	/// The newest simulator of each category, one apiece — an iPhone and an
	/// iPad for an app that runs on both.
	///
	/// "Newest" is the runtime, compared as numbers rather than as text: "26.5"
	/// against "27.0" sorts correctly either way, but "9.0" against "10.0" does
	/// not, and an OS numbering that has been to double digits twice will go
	/// there again. A model present in one runtime and absent from another is
	/// not a comparison at all, which is why this picks the newest *runtime*
	/// first and then a model within it.
	public static func newestOfEachFamily(
		among destinations: [XcodeDestination]
	) -> [XcodeDestination] {
		let simulators = destinations.filter { $0.kind == .simulator }
		var best: [String: XcodeDestination] = [:]

		for simulator in simulators {
			let category = self.category(of: simulator)
			guard let previous = best[category] else {
				best[category] = simulator
				continue
			}
			if isNewer(simulator, than: previous) { best[category] = simulator }
		}
		// A stable order, so the menu does not rearrange itself between runs.
		return best.values.sorted {
			let left = category(of: $0), right = category(of: $1)
			let a = rank(left), b = rank(right)
			return a != b ? a < b : left < right
		}
	}

	/// Whether one simulator runs a newer OS than another, and failing that
	/// whether it sorts after it — so two simulators on the same runtime still
	/// have an answer rather than depending on dictionary order.
	static func isNewer(_ left: XcodeDestination, than right: XcodeDestination) -> Bool {
		let a = version(left.os), b = version(right.os)
		if a != b { return a.lexicographicallyPrecedes(b) == false }
		return left.name > right.name
	}

	/// "26.4.1" as [26, 4, 1], so it compares as somebody reads it.
	static func version(_ text: String?) -> [Int] {
		(text ?? "").split(separator: ".").map { Int($0) ?? 0 }
	}

	/// Everything the menu does not show directly.
	public static func rest(
		among destinations: [XcodeDestination], shown: [XcodeDestination]
	) -> [XcodeDestination] {
		let already = Set(shown.map(\.id))
		return destinations.filter { $0.kind == .simulator && !already.contains($0.id) }
	}

	/// Whether a destination matches what somebody has typed into the filter.
	///
	/// Every word, anywhere, in any case — "pro 27" finds "iPad Pro 13-inch
	/// (M5) (27.0)" — because the alternative is remembering whether the
	/// runtime comes before the model.
	public static func matches(_ destination: XcodeDestination, _ query: String) -> Bool {
		let words = query.lowercased().split(separator: " ")
		guard !words.isEmpty else { return true }
		let haystack = "\(destination.title) \(destination.platform)".lowercased()
		return words.allSatisfy { haystack.contains($0) }
	}
}
