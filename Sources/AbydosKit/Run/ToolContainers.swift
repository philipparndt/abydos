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
			// Proven now, against `container` 1.2.2, the same way docker's was:
			// a named container started by a CLI, that CLI killed with `SIGKILL`,
			// the container still `running` three seconds later — and then gone,
			// from `inspect` and from `ls --all` both, the moment this command was
			// run. `ToolContainerAppleLiveTests` is that transcript as a test.
			return (runtime.path, ["rm", "--force"] + names)
		}
	}

	/// The command that lists the containers on the machine.
	///
	/// Both are asked for names and nothing else, so neither answer has to be
	/// parsed out of a table. Docker's `--format` says exactly that; Apple's
	/// `--quiet` prints one container id per line, and for everything this app
	/// starts the id *is* the name, because `--name` on its `run` is documented
	/// as "use the specified name as the container ID".
	///
	/// **`--all` on both, and it is the whole point.** Each of them lists only
	/// running containers otherwise, and what a crashed run leaves behind is
	/// mostly stopped ones — a sweep that cannot see those sweeps nothing.
	///
	/// Apple's has no `--filter`, so its list arrives with everything else on the
	/// machine in it. That costs nothing: `stale(among:)` already keeps only the
	/// `abydos-` names, because docker's filter is a prefix match rather than a
	/// promise and was never trusted on its own.
	///
	/// `container ls` also offers `--format json`, which is the fuller answer and
	/// the one to reach for if a state or an address is ever wanted here. It is
	/// not wanted here: names are the whole of what a sweep needs, and a line per
	/// name cannot be misparsed.
	public static func listing(
		using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String])? {
		switch runtime {
		case .docker:
			return (runtime.path, ["ps", "-a", "--format", "{{.Names}}", "--filter", "name=\(prefix)"])
		case .apple:
			return (runtime.path, ["ls", "--all", "--quiet"])
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
		remove(all)
	}

	// There was a `release(withPrefixes:)` here, and it is gone on purpose.
	//
	// It was written to narrow `removeAll` after that took a devcontainer out
	// from under the suite running beside it: instead of every container this
	// process registered, only the ones playing the caller's own *role* —
	// `abydos-plantuml-server-`, `abydos-devcontainer-`. That is one step short
	// of the answer, and the step it is short of is the whole of 0435.
	//
	// A role is not an owner. In the app it happens to be one, because one type
	// keeps the servers and one type keeps the devcontainers. In the test bundle
	// it is not: `PlantUMLServerLiveTests` and `DiagramExportLiveTests` both keep
	// a container called `abydos-plantuml-server-<pid>-<n>`, they run at once in
	// the one process, and both names carry that process's pid. So "mine" and
	// "everyone playing my part" were the same set in the only place the method
	// was ever called from, and each suite's tidying up removed the other's
	// server mid-render. Docker's event log has both names on one `rm -f`.
	//
	// Nothing in `Sources/` ever called it. What the callers wanted is the names
	// they started, and every one of them already knows those — a kept server is
	// held by the actor that started it, and `PlantUMLServers.stopAll` removes
	// exactly that set. So there is nothing to replace this with.

	/// Asks each runtime, once, to remove the containers registered against it.
	private func remove(_ containers: [String: ContainerRuntime]) {
		guard !containers.isEmpty else { return }
		var byRuntime: [String: (ContainerRuntime, [String])] = [:]
		for (name, runtime) in containers {
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

	/// The same, with the runtime each belongs to.
	///
	/// Read-only, and for the list of what this app has started and not ended:
	/// asking a runtime what a container costs means knowing which runtime to
	/// ask, and `names` on its own does not say.
	public var registrations: [(name: String, runtime: ContainerRuntime)] {
		lock.lock()
		defer { lock.unlock() }
		return running.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
	}

	/// The part of a name that says what started it: `plantuml-server`,
	/// `devcontainer`, `lsp-gopls`.
	///
	/// The inverse of `mint`, and the same reading as `owner(of:)` — everything
	/// between the prefix and the two trailing numbers. Nil when the name is not
	/// one of ours or was written by a version of this app that spelled them
	/// differently.
	public static func role(of name: String) -> String? {
		guard isOurs(name) else { return nil }
		let parts = name.dropFirst(prefix.count).split(separator: "-")
		guard parts.count >= 3, Int(parts[parts.count - 1]) != nil,
		      Int(parts[parts.count - 2]) != nil
		else { return nil }
		return parts.dropLast(2).joined(separator: "-")
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
	/// - Parameter inRole: which roles to consider — `lsp-jdtls`,
	///   `plantuml-server` — and by default every one of ours. Narrowing it is
	///   for the test bundle and for nothing in the app: a suite in there starts
	///   a container owned by a pid it has *declared* dead in order to watch a
	///   sweep take it, and a sweep of every role running beside that test
	///   removes it first and fails it. Somebody's app, by contrast, wants
	///   everything an earlier one of it left, whatever role that was in.
	@discardableResult
	public func sweep(
		using runtime: ContainerRuntime,
		inRole matches: (String) -> Bool = { _ in true },
		isAlive: (pid_t) -> Bool = ToolContainers.isAlive
	) -> [String] {
		guard let listing = Self.listing(using: runtime) else { return [] }
		let listed = RuntimeCommand.run(listing, deadline: Self.removalDeadline)
		guard listed.succeeded else { return [] }
		let names = listed.output
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		// A name of ours in a shape this version does not understand has no role,
		// and the empty string is the honest answer to ask the predicate about:
		// the app's accepts it, and a caller that named the roles it started did
		// not name that one.
		let dead = Self.stale(among: names, isAlive: isAlive)
			.filter { matches(Self.role(of: $0) ?? "") }
		guard !dead.isEmpty else { return [] }
		_ = RuntimeCommand.run(
			Self.removal(of: dead, using: runtime), deadline: Self.removalDeadline
		)
		return dead
	}

	/// The command that says what a container is doing, and where it is.
	///
	/// Docker answers one field at a time and Apple's answers the whole record;
	/// `AppleInspection` is what reads the second, and `stateCommand` on
	/// `DevContainers` is what asks the first.
	public static func inspection(
		of name: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		(runtime.path, ["inspect", name])
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

/// Reading what Apple's `container inspect` says about a container.
///
/// Its `inspect` has no `--format`, so there is no asking it for one field the
/// way docker's is asked: it prints the whole record as JSON and the two things
/// wanted out of it are picked here. Docker's answers stay one-field commands
/// and never come through this.
///
/// Everything is nil rather than thrown. Each caller's answer to "the runtime
/// said something I could not read" is the same as its answer to "the container
/// is not there", and both are already handled.
enum AppleInspection {
	/// Whether the container is running.
	static func isRunning(_ output: String) -> Bool {
		state(output) == "running"
	}

	/// What it says the container is doing — `running`, `stopped`.
	static func state(_ output: String) -> String? {
		guard let record = first(in: output),
		      let status = record["status"] as? [String: Any]
		else { return nil }
		return status["state"] as? String
	}

	/// The address the container answers on, without the prefix length.
	///
	/// Apple's runtime gives every container an address of its own on the
	/// machine's `bridge100` — `192.168.64.14` — which is how a server inside one
	/// is reached, since its published ports do not work here.
	static func address(_ output: String) -> String? {
		guard let record = first(in: output),
		      let status = record["status"] as? [String: Any],
		      let networks = status["networks"] as? [[String: Any]]
		else { return nil }
		for network in networks {
			guard let address = network["ipv4Address"] as? String else { continue }
			let bare = address.split(separator: "/").first.map(String.init) ?? address
			if !bare.isEmpty { return bare }
		}
		return nil
	}

	/// The first record in the array the CLI prints.
	///
	/// What arrives here is both of the command's streams together — that is how
	/// `RuntimeCommand` hands back a result, since the runtimes disagree about
	/// which stream a failure goes to — so the JSON has whatever the CLI wrote to
	/// standard error in front of it. Its progress lines are `[6/6] Starting
	/// container`, which is to say they start with the same bracket the array
	/// does, so "from the first `[`" is not good enough.
	///
	/// Every `[` is tried instead, and the first one that parses as an array of
	/// records is the answer. The output is one container's description, so there
	/// is nothing here worth being cleverer about.
	private static func first(in output: String) -> [String: Any]? {
		var searched = output.startIndex
		while let start = output[searched...].firstIndex(of: "[") {
			if let parsed = try? JSONSerialization.jsonObject(with: Data(output[start...].utf8)),
			   let array = parsed as? [[String: Any]] {
				return array.first
			}
			searched = output.index(after: start)
		}
		return nil
	}
}
