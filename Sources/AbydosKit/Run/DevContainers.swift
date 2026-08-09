import Foundation

/// A project's devcontainer, kept up while the project is open, with the
/// checkout bind-mounted into it.
///
/// The shape is `PlantUMLServers`' (0422) rather than a new one: a container
/// that outlives the thing that asked for it, named through `ToolContainers` so
/// that it can be removed again, claimed rather than merely registered, and
/// docker-only for the reason 0406 gives — keeping a container is only
/// defensible where removing it is proven.
///
/// What is deliberately *not* here is a reaper. PlantUML's server can go cold
/// because the worst that happens is one slow render; a devcontainer has
/// somebody's shell in it, and reaping that under them would close the terminal
/// they are typing in. So it lives until the project is closed or the app
/// exits — `ToolContainers.removeAll` on the way out, and 0406's sweep for the
/// exit nothing runs on.
public actor DevContainers {
	public static let shared = DevContainers()

	/// A container that is up, and everything needed to run something in it.
	public struct Session: Equatable, Sendable {
		/// `abydos-devcontainer-<pid>-<n>`.
		public let name: String
		public let configuration: DevContainerConfiguration
		public let runtime: ContainerRuntime
	}

	public enum Outcome: Equatable, Sendable {
		case running(Session)
		/// One sentence saying what could not be done and what to do about it.
		case refused(String)
	}

	/// How long the runtime gets to start the container.
	///
	/// The image is already on the machine by the time this runs — the pull has
	/// its own deadline in `ContainerImageStore` — so this covers `docker run`
	/// and nothing else, which is a second on a well machine.
	public static let startDeadline: TimeInterval = 60

	/// How long a build gets. As long as a pull, and for the same reason: it is
	/// a download plus everything the Dockerfile does.
	public static let buildDeadline: TimeInterval = 900

	/// What the container is told to run so that it stays up.
	///
	/// The image's own command is replaced, which is what every devcontainer
	/// tool does: an image built to run a program exits when it finishes, and
	/// there is then nothing to open a terminal in. `wait` rather than a bare
	/// `sleep` so that the trap runs and `docker stop` takes a moment rather
	/// than ten seconds, and `86400` rather than `infinity` because busybox's
	/// sleep does not take a word.
	static let keepAlive = "trap 'exit 0' TERM INT; while true; do sleep 86400 & wait $!; done"

	private var sessions: [String: Session] = [:]
	private var beingStarted: [String: Task<Outcome, Never>] = [:]

	public init() {}

	// MARK: - Whether this can be done at all

	/// Whether a devcontainer is offered for this runtime at all.
	///
	/// Both, now. This was docker only because a container kept for a whole
	/// editing session is the one that most needs removing again, and that verb
	/// was unproven against Apple's — 0406's decision, and it is proven now.
	/// Everything else a devcontainer is made of was exercised there too: the
	/// bind mount, `-d` with the keep-alive, `--entrypoint`, `-u`, `-e`, `-w`,
	/// and `exec -it` onto a real pty.
	public static func canStart(_ runtime: ContainerRuntime) -> Bool { true }

	/// Why *this* devcontainer cannot be opened on *this* runtime, or nil when it
	/// can.
	///
	/// One thing, and it is not about cleanup: a port published to the host does
	/// not work on Apple's runtime. The container comes up and the forwarder is
	/// made — `container` even listens on the host port — and then every
	/// connection is accepted and reset, because the forwarder cannot reach the
	/// container behind it: `No route to host`, in the runtime's own log, which
	/// is macOS's local-network privacy refusing its helper the way it refuses
	/// this app.
	///
	/// A project that names `forwardPorts` is naming the thing it wants
	/// reachable, so starting it anyway would hand somebody a container that
	/// looks right and a port that silently is not. Refused by name instead,
	/// which is what this file does with everything it cannot honestly do.
	///
	/// A devcontainer with no `forwardPorts` has nothing to be wrong here and is
	/// not stopped — its mount, its shell and its environment are all proven on
	/// Apple's runtime by `DevContainerLiveTests` running against it.
	public static func unsupported(
		_ configuration: DevContainerConfiguration, on runtime: ContainerRuntime
	) -> String? {
		guard case .apple = runtime, !configuration.forwardPorts.isEmpty else { return nil }
		let ports = configuration.forwardPorts.map(String.init).joined(separator: ", ")
		return "This project's devcontainer forwards \(ports), and a port published to the "
			+ "host does not work on Apple's container runtime — the connection is accepted "
			+ "and then reset. Choose Docker as the container runtime in settings to open "
			+ "\(configuration.project.lastPathComponent) in it."
	}

	// MARK: - The commands

	/// The command that builds the image, when the file names a Dockerfile.
	public static func buildCommand(
		_ configuration: DevContainerConfiguration, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String])? {
		guard let build = configuration.build else { return nil }
		var line = ["build", "-t", configuration.builtImageName, "-f", build.dockerfile]
		for key in build.args.keys.sorted() {
			line += ["--build-arg", "\(key)=\(build.args[key] ?? "")"]
		}
		if let target = build.target { line += ["--target", target] }
		line.append(build.context)
		return (runtime.path, line)
	}

	/// The command that starts the container.
	///
	/// The project is bind-mounted where the file says, the container starts in
	/// the workspace folder, and the ports are published on the loopback address
	/// only — a devcontainer's port is for the person at this keyboard, and
	/// putting it on every interface is a decision nobody made.
	public static func startCommand(
		_ configuration: DevContainerConfiguration,
		name: String,
		using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		var line = ["run", "-d", "--name", name]
		line += ["--entrypoint", "/bin/sh"]
		line += ["-v", configuration.paths.mount.flag]
		line += ["-w", configuration.workspaceFolder]
		if let user = configuration.containerUser { line += ["-u", user] }
		for key in configuration.containerEnv.keys.sorted() {
			line += ["-e", "\(key)=\(configuration.containerEnv[key] ?? "")"]
		}
		for port in configuration.forwardPorts {
			line += ["-p", "127.0.0.1:\(port):\(port)"]
		}
		for mount in configuration.extraMounts { line += ["--mount", mount] }
		line += configuration.runArgs
		line.append(configuration.imageReference)
		line += ["-c", keepAlive]
		return (runtime.path, line)
	}

	/// The command that runs something inside a container that is already up.
	///
	/// `remoteUser` and `remoteEnv` rather than the container ones, and that
	/// distinction is the spec's rather than an invention: `containerUser` and
	/// `containerEnv` are what the container itself is, and the remote pair are
	/// what the things attached to it afterwards get — a terminal, a language
	/// server, a build.
	public static func execCommand(
		_ session: Session,
		arguments: [String],
		interactive: Bool = false
	) -> (executable: String, arguments: [String]) {
		let configuration = session.configuration
		var line = ["exec"]
		line.append(interactive ? "-it" : "-i")
		line += ["-w", configuration.workspaceFolder]
		if let user = configuration.remoteUser ?? configuration.containerUser {
			line += ["-u", user]
		}
		for key in configuration.remoteEnv.keys.sorted() {
			line += ["-e", "\(key)=\(configuration.remoteEnv[key] ?? "")"]
		}
		line.append(session.name)
		line += arguments
		return (session.runtime.path, line)
	}

	/// A shell inside the container, for a terminal pane.
	///
	/// bash when the image has one and `sh` when it does not, decided inside the
	/// container rather than out here: which shells an image carries is not
	/// something this side can know, and a terminal that opens onto
	/// "executable file not found" is worse than a plain `sh`.
	public static func terminalCommand(_ session: Session) -> (executable: String, arguments: [String]) {
		execCommand(
			session,
			arguments: [
				"/bin/sh", "-c",
				"if command -v bash >/dev/null 2>&1; then exec bash -l; fi; exec sh -l",
			],
			interactive: true
		)
	}

	/// The command that asks whether a container is still up.
	///
	/// Docker's `inspect` is asked for the one field. Apple's has no `-f` and
	/// prints the whole record as JSON, so it is asked plainly and `isRunning`
	/// reads the answer.
	public static func stateCommand(
		name: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .docker: return (runtime.path, ["inspect", "-f", "{{.State.Running}}", name])
		case .apple:  return ToolContainers.inspection(of: name, using: runtime)
		}
	}

	/// Whether that command's answer means the container is up.
	///
	/// Not a `contains("true")` on both: Apple's answer is the container's entire
	/// configuration, and an image reference or an environment variable with the
	/// word in it would read as running. Its state is read out of the JSON.
	public static func isRunning(_ output: String, using runtime: ContainerRuntime) -> Bool {
		switch runtime {
		case .docker: return output.contains("true")
		case .apple:  return AppleInspection.isRunning(output)
		}
	}

	// MARK: - Why it would not start

	/// Why the runtime refused to start it, in a sentence somebody can act on.
	///
	/// The same job `ContainerImages.explain` does for a pull, and the same
	/// reason for doing it: the runtime's own words are long, and the one thing
	/// worth knowing is which of a few things happened.
	public static func explainStart(
		_ output: String, project: String, runtime: ContainerRuntime? = nil
	) -> String {
		let text = output.lowercased()
		if text.contains("port is already allocated") || text.contains("address already in use") {
			return "A port this project forwards is already in use on this machine, so its "
				+ "devcontainer could not start — stop whatever is listening on it and open "
				+ "\(project) again."
		}
		if text.contains("cannot connect") || text.contains("is the docker daemon running") {
			// Named, because "Docker is not running" said of Apple's runtime sends
			// somebody to start the wrong thing.
			let name = runtime?.name ?? "Docker"
			return "\(name) is not running, so the devcontainer for \(project) could not be started."
		}
		let first = output
			.split(separator: "\n", omittingEmptySubsequences: true)
			.first
			.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
		return first.isEmpty
			? "The devcontainer for \(project) would not start, and the runtime said nothing "
				+ "about why."
			: "The devcontainer for \(project) would not start: \(first)"
	}

	/// Why the image would not build.
	public static func explainBuild(_ output: String, dockerfile: String) -> String {
		let first = output
			.split(separator: "\n", omittingEmptySubsequences: true)
			.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
			.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
		return first.isEmpty
			? "\(dockerfile) would not build, and the runtime said nothing about why."
			: "\(dockerfile) would not build: \(first)"
	}

	// MARK: - Keeping one

	/// The container for this project, started if it is not up yet.
	///
	/// Nil means the project has no devcontainer at all, which is not a failure
	/// and must not be reported as one — most projects do not have one.
	public func session(
		for project: URL,
		using runtime: ContainerRuntime,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		progress: (@Sendable (String) -> Void)? = nil
	) async -> Outcome? {
		guard let reading = DevContainerFile.read(project: project, environment: environment)
		else { return nil }
		switch reading {
		case let .refused(reason):
			return .refused(reason)
		case let .understood(configuration):
			return await session(for: configuration, using: runtime, progress: progress)
		}
	}

	/// The same, for a file already read — which is how every test of this
	/// reaches it, and how a caller that has the configuration in hand avoids
	/// reading it twice.
	public func session(
		for configuration: DevContainerConfiguration,
		using runtime: ContainerRuntime,
		progress: (@Sendable (String) -> Void)? = nil
	) async -> Outcome {
		if let unsupported = Self.unsupported(configuration, on: runtime) {
			return .refused(unsupported)
		}
		let key = configuration.project.path
		if let existing = sessions[key] {
			if await isUp(existing) { return .running(existing) }
			// Removed behind our back, or the runtime was restarted. Forget it and
			// start another, rather than handing out a name nothing answers to.
			forget(key)
		}
		if let already = beingStarted[key] { return await already.value }

		let task = Task { await start(configuration, using: runtime, progress: progress) }
		beingStarted[key] = task
		let outcome = await task.value
		beingStarted[key] = nil
		if case let .running(session) = outcome { sessions[key] = session }
		return outcome
	}

	/// The container this project already has up, without starting one.
	public func existingSession(for project: URL) -> Session? {
		sessions[FilePath.canonical(project)] ?? sessions[project.path]
	}

	/// Removes the container for one project.
	public func stop(project: URL) {
		forget(FilePath.canonical(project))
		forget(project.path)
	}

	/// Removes every devcontainer this has kept.
	public func stopAll() {
		for key in sessions.keys { forget(key) }
	}

	/// Which projects have one up, for a test.
	public var projects: [String] { sessions.keys.sorted() }

	private func forget(_ key: String) {
		guard let session = sessions.removeValue(forKey: key) else { return }
		ToolContainers.shared.releaseInBackground(session.name)
	}

	// MARK: - Starting one

	private func start(
		_ configuration: DevContainerConfiguration,
		using runtime: ContainerRuntime,
		progress: (@Sendable (String) -> Void)?
	) async -> Outcome {
		// The image first, through the store that fetches one once however many
		// things ask for it — or a build, when the file names a Dockerfile.
		if configuration.build != nil {
			if let failure = await build(configuration, using: runtime, progress: progress) {
				return .refused(failure)
			}
		} else if let image = configuration.image {
			switch await ContainerImageStore.shared.ensure(image, using: runtime, progress: progress) {
			case .present, .fetched: break
			case let .failed(reason): return .refused(reason)
			}
		}

		let name = ToolContainers.mint("devcontainer")
		let command = Self.startCommand(configuration, name: name, using: runtime)
		progress?("Starting the devcontainer for \(configuration.project.lastPathComponent)…")

		let started = await offMainThread {
			// Claimed rather than registered: this one is meant to outlive whatever
			// asked for it, so its name is worth being certain is free.
			ToolContainers.shared.claim(name, runtime: runtime)
			return RuntimeCommand.run(command, deadline: Self.startDeadline)
		}
		guard started.succeeded else {
			ToolContainers.shared.releaseInBackground(name)
			return .refused(Self.explainStart(
				started.output, project: configuration.project.lastPathComponent, runtime: runtime
			))
		}
		return .running(Session(name: name, configuration: configuration, runtime: runtime))
	}

	private func build(
		_ configuration: DevContainerConfiguration,
		using runtime: ContainerRuntime,
		progress: (@Sendable (String) -> Void)?
	) async -> String? {
		guard let command = Self.buildCommand(configuration, using: runtime),
		      let dockerfile = configuration.build?.dockerfile
		else { return nil }
		progress?("Building \(configuration.builtImageName) from "
			+ "\((dockerfile as NSString).lastPathComponent)…")
		let built = await offMainThread { RuntimeCommand.run(command, deadline: Self.buildDeadline) }
		guard built.succeeded else {
			return Self.explainBuild(built.output, dockerfile: dockerfile)
		}
		return nil
	}

	/// Whether the container behind a session is still running.
	private func isUp(_ session: Session) async -> Bool {
		let command = Self.stateCommand(name: session.name, using: session.runtime)
		let answer = await offMainThread { RuntimeCommand.run(command, deadline: 20) }
		return answer.succeeded && Self.isRunning(answer.output, using: session.runtime)
	}

	/// Waiting on a subprocess is not what a thread from the cooperative pool is
	/// for: a few seconds of `docker run` held there is a few seconds every
	/// other task in the app spends behind it.
	private func offMainThread(
		_ work: @escaping @Sendable () -> RuntimeCommand.Result
	) async -> RuntimeCommand.Result {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: work())
			}
		}
	}
}
