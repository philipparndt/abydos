import Foundation

/// Every container this app has started, by the name it was given, so that all
/// of them can be removed again.
///
/// `ToolProcesses` ends the *processes* — and that turned out not to be the
/// same thing at all. Killing the `docker run` that started a container leaves
/// the container running: `--rm` never fires, `kill -9` on the CLI changes
/// nothing, and ten seconds after a `SIGTERM` the container is still up. Eleven
/// of them were found on one machine that way, the oldest a day old, and enough
/// of them wedge a runtime's service that everything asked of it afterwards
/// hangs too.
///
/// Ending a container means asking the runtime to remove it, and that means
/// knowing which one it is. So every container this app starts is given a name
/// beginning `abydos-`, the name is registered here, and removing it is a
/// command sent to the runtime rather than a signal sent to a process.
///
/// Deliberately not an actor, for the same reason `ToolProcesses` is not: the
/// thing this must do above all is run on the way out of an uncaught exception,
/// where there is no waiting for an actor's turn.
public final class ToolContainers: @unchecked Sendable {
	public static let shared = ToolContainers()

	/// What every container of ours is called.
	///
	/// The prefix is the whole point of the name: anything matching it is ours,
	/// which makes it both findable and obviously safe to remove.
	public static let prefix = "abydos-"

	/// How long the runtime gets to answer a removal.
	///
	/// Short, because every caller of this is either finishing with a tool or
	/// quitting, and neither is a moment to wait on a service that has stopped
	/// answering. A removal that misses its deadline leaves the container up —
	/// which is where we were before, so it is a lost improvement rather than a
	/// new failure.
	public static let removalDeadline: TimeInterval = 10

	private let lock = NSLock()
	private var running: [String: ContainerRuntime] = [:]
	/// The number given to the last name minted, so two containers started in
	/// the same second cannot collide.
	private static let counter = Counter()

	public init() {}

	// MARK: - Names

	/// A name for a container about to be started: `abydos-<role>-<pid>-<n>`.
	///
	/// The process id is in it so that a name found later can be asked the one
	/// question that matters after a crash — is whatever started this still
	/// alive? — without keeping a file anywhere. The counter is what makes it
	/// unique within a run.
	public static func mint(_ role: String) -> String {
		"\(prefix)\(sanitised(role))-\(ProcessInfo.processInfo.processIdentifier)-\(counter.next())"
	}

	/// Whether a name is one of ours.
	public static func isOurs(_ name: String) -> Bool { name.hasPrefix(prefix) }

	/// The process id a name carries, or nil when it carries none.
	///
	/// Nil is not "nobody owns it": a name of ours whose shape is not understood
	/// is one written by an older version of this app, and the safe reading of
	/// that is the same as a dead owner — nothing here is running it now.
	public static func owner(of name: String) -> pid_t? {
		guard isOurs(name) else { return nil }
		let parts = name.split(separator: "-")
		guard parts.count >= 3, let pid = pid_t(parts[parts.count - 2]) else { return nil }
		return pid
	}

	/// Docker's names allow rather less than a tool key might contain.
	private static func sanitised(_ role: String) -> String {
		let kept = role.lowercased().map { character -> Character in
			character.isLetter || character.isNumber ? character : "-"
		}
		let name = String(kept).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		return name.isEmpty ? "tool" : name
	}

	// MARK: - The commands

	/// The command that removes containers, whether or not they are still
	/// running.
	///
	/// Force, because the container being removed is usually one this app has
	/// given up waiting for: a polite stop asks it to finish what it is doing,
	/// and what it is doing is the thing that hung.
	public static func removal(
		of names: [String], using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .docker:
			return (runtime.path, ["rm", "-f"] + names)
		case .apple:
			// Unverified, and said so out loud: Apple's `container` was wedged
			// badly enough while this was written that even `--help` never
			// returned, so this spelling is read off its documentation rather
			// than off a machine. If it is wrong the command fails and nothing is
			// worse than it is today — which is why the runtime it is *proven*
			// for is the one now preferred. See 0406's decision.
			return (runtime.path, ["rm", "--force"] + names)
		}
	}

	/// The command that lists the containers on the machine, when there is one
	/// whose output can be read.
	///
	/// Docker's `--format` says exactly what is wanted and nothing else. Apple's
	/// prints a table whose columns could not be checked here for the same
	/// reason the removal verb could not, and a sweep that parses a format
	/// nobody has seen would remove either nothing or the wrong thing. So it
	/// returns nil, and a container left behind by Apple's runtime stays until
	/// somebody removes it by hand — set aside, rather than half-supported.
	public static func listing(
		using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String])? {
		switch runtime {
		case .docker:
			return (runtime.path, ["ps", "-a", "--format", "{{.Names}}", "--filter", "name=\(prefix)"])
		case .apple:
			return nil
		}
	}

	// MARK: - The register

	/// Notes that a container by this name is about to be started, so that
	/// whatever happens next it can still be found.
	public func register(_ name: String, runtime: ContainerRuntime) {
		lock.lock()
		running[name] = runtime
		lock.unlock()
	}

	/// The same, for a container whose name is stable across runs of this app —
	/// a kept server rather than one render — removing a stale one of that name
	/// first.
	///
	/// A name has to be free before it can be reused, and after a crash it is
	/// not: the runtime answers `run` with "name already in use" and the feature
	/// looks broken until somebody clears it by hand.
	public func claim(_ name: String, runtime: ContainerRuntime) {
		register(name, runtime: runtime)
		_ = RuntimeCommand.run(
			Self.removal(of: [name], using: runtime), deadline: Self.removalDeadline
		)
	}

	/// Removes one container, now, and forgets it.
	///
	/// Called when a tool is done with — a render that has its picture, a
	/// language server that has stopped. `--rm` has usually already taken it,
	/// and the removal then fails with "no such container", which is the right
	/// outcome arriving by a different route.
	public func release(_ name: String) {
		lock.lock()
		let runtime = running.removeValue(forKey: name)
		lock.unlock()
		guard let runtime else { return }
		_ = RuntimeCommand.run(
			Self.removal(of: [name], using: runtime), deadline: Self.removalDeadline
		)
	}

	/// The same, without waiting for the runtime to get round to it.
	///
	/// For the callers that have what they wanted — a picture, an answer — and
	/// should not be held up by the tidying.
	public func releaseInBackground(_ name: String) {
		DispatchQueue.global(qos: .utility).async { [self] in release(name) }
	}

	/// Removes everything still registered, in one command per runtime.
	///
	/// Called when the app is going, including out of the uncaught exception
	/// handler — which is the exit that left the eleven. One command rather than
	/// one per container because this runs while an app is quitting, and a quit
	/// that visibly hangs is its own bug.
	public func removeAll() {
		lock.lock()
		let all = running
		running.removeAll()
		lock.unlock()
		guard !all.isEmpty else { return }

		var byRuntime: [String: (ContainerRuntime, [String])] = [:]
		for (name, runtime) in all {
			byRuntime[runtime.path, default: (runtime, [])].1.append(name)
		}
		for (runtime, names) in byRuntime.values {
			_ = RuntimeCommand.run(
				Self.removal(of: names.sorted(), using: runtime), deadline: Self.removalDeadline
			)
		}
	}

	/// What is still registered, for a test and for anybody asking whether this
	/// is doing anything.
	public var names: [String] {
		lock.lock()
		defer { lock.unlock() }
		return running.keys.sorted()
	}

	// MARK: - What a previous run left

	/// The containers of ours on this machine that nothing is running any more.
	///
	/// A name carries the process id that started it, so a container is stale
	/// exactly when that process is gone. Two copies of this app running at once
	/// is then not a problem: each leaves the other's alone, because the other's
	/// owner is alive.
	public static func stale(
		among names: [String],
		isAlive: (pid_t) -> Bool = ToolContainers.isAlive
	) -> [String] {
		names.filter { name in
			guard isOurs(name) else { return false }
			guard let owner = owner(of: name) else { return true }
			return !isAlive(owner)
		}
	}

	/// Whether a process id belongs to something still running.
	///
	/// `EPERM` counts as alive: it means the process is there and belongs to
	/// somebody else, which is a reason not to touch it rather than a reason to
	/// think it gone.
	public static func isAlive(_ pid: pid_t) -> Bool {
		guard pid > 0 else { return false }
		if kill(pid, 0) == 0 { return true }
		return errno == EPERM
	}

	/// Removes what a previous run left behind, and says how many that was.
	///
	/// This is the half of the fix that survives the exit nothing runs on: an
	/// app killed outright removes nothing on the way out, so the next one to
	/// start does it. Cheap — one listing and, only when there is something to
	/// remove, one removal.
	@discardableResult
	public func sweep(
		using runtime: ContainerRuntime,
		isAlive: (pid_t) -> Bool = ToolContainers.isAlive
	) -> [String] {
		guard let listing = Self.listing(using: runtime) else { return [] }
		let listed = RuntimeCommand.run(listing, deadline: Self.removalDeadline)
		guard listed.succeeded else { return [] }
		let names = listed.output
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		let dead = Self.stale(among: names, isAlive: isAlive)
		guard !dead.isEmpty else { return [] }
		_ = RuntimeCommand.run(
			Self.removal(of: dead, using: runtime), deadline: Self.removalDeadline
		)
		return dead
	}

	/// A number that only goes up, for the names.
	private final class Counter: @unchecked Sendable {
		private let lock = NSLock()
		private var value = 0

		func next() -> Int {
			lock.lock()
			defer { lock.unlock() }
			value += 1
			return value
		}
	}
}
