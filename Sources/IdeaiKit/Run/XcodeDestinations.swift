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

	public init() {}

	/// The destinations for a scheme, from the cache unless asked to look again.
	public func destinations(
		for target: XcodeTarget,
		workingDirectory: URL,
		refresh: Bool = false
	) async -> [XcodeDestination] {
		let key = "\(target.project.path):\(target.scheme.name)"
		if !refresh, let known = cache[key] { return known }

		let found = await Self.ask(for: target, workingDirectory: workingDirectory)
		// A failed question is not an answer: keeping an empty list would make
		// the menu permanently empty for a project whose first scan happened
		// while Xcode was updating.
		if !found.isEmpty { cache[key] = found }
		return found
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
	nonisolated public static func preferred(among destinations: [XcodeDestination]) -> XcodeDestination? {
		destinations.first { $0.kind == .mac }
			?? destinations.first { $0.kind == .device }
			?? destinations.first { $0.kind == .simulator }
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
