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

	/// Where a devcontainer being made says what it is doing.
	///
	/// Two sinks rather than one, because they are two different things and are
	/// wanted in different places. `step` is one sentence naming what is
	/// starting now — `ContainerImages.progressMessage`'s bargain, short enough
	/// for a toast. `output` is what the runtime or the command itself printed,
	/// as it prints it: a pull's layers, a Dockerfile's steps, a
	/// `postCreateCommand` counting to ten.
	///
	/// Anything with a terminal to put this in wants both, and that is the whole
	/// of what makes the first minutes of a devcontainer visible rather than a
	/// pane that sits empty until it is over. Anything with only a toast takes
	/// the first and leaves the second, which still goes to
	/// `~/Library/Logs/Abydos/devcontainer.log` for the lifecycle commands.
	///
	/// Both are called off the main thread, from wherever the subprocess is
	/// being read.
	public struct Progress: Sendable {
		public var step: (@Sendable (String) -> Void)?
		public var output: (@Sendable (String) -> Void)?

		public init(
			step: (@Sendable (String) -> Void)? = nil,
			output: (@Sendable (String) -> Void)? = nil
		) {
			self.step = step
			self.output = output
		}

		/// Nobody is watching, which is the ordinary case for a test.
		public static let silent = Progress()
	}

	/// Everyone listening to one container coming up, which is more than one
	/// often enough to matter.
	///
	/// A project's container is started once however many things ask for it, and
	/// the second asker used to hear nothing at all: the start already running
	/// carried the *first* caller's sink and no other. In this app the first
	/// caller is usually the language servers — they start the container as soon
	/// as a file is opened — and the second is somebody opening a terminal in
	/// it, who would then watch an empty pane for as long as the pull takes.
	/// So the sinks are collected rather than replaced.
	private final class Audience: @unchecked Sendable {
		private let lock = NSLock()
		private var listeners: [Progress] = []

		init(_ first: Progress) { listeners = [first] }

		func add(_ another: Progress) {
			lock.lock()
			listeners.append(another)
			lock.unlock()
		}

		private var current: [Progress] {
			lock.lock()
			defer { lock.unlock() }
			return listeners
		}

		/// The sink to hand to the work, which says everything to everyone.
		var progress: Progress {
			Progress(
				step: { [self] message in for one in current { one.step?(message) } },
				output: { [self] text in for one in current { one.output?(text) } }
			)
		}
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

	/// How long one lifecycle command gets.
	///
	/// Half an hour, which is longer than anything else here waits for anything,
	/// because this is the one command whose length is somebody else's decision:
	/// `postCreateCommand` is where `npm ci`, `go mod download` and `bundle
	/// install` live, on whatever network the machine is on. Ending one early
	/// leaves a container that came up without what it was told to install,
	/// which is the failure this whole step exists to prevent — so the deadline
	/// is here to stop a wedged command holding a project open for ever, not to
	/// judge how long an install ought to take.
	public static let lifecycleDeadline: TimeInterval = 1800

	/// Where a container records that its creation commands have been run.
	///
	/// **Inside the container, not on the bind mount, and not in `.abydos/`.**
	/// The question being asked is "has *this container* been created?", and the
	/// only thing whose lifetime is the container's is the container's own
	/// writable layer. A marker beside the checkout survives `docker rm`, so the
	/// next container — a rebuild, a machine restarted, a crash swept up by
	/// 0406 — would skip an installer it has never run, and a container missing
	/// its tools with nothing on screen saying so is exactly the "looks like a
	/// broken editor" this feature is about.
	///
	/// `/tmp` because it is the one directory every image has and every user can
	/// write to, and because its lifetime is exactly right: it survives a stop
	/// and start, which is not creation, and dies with the container, which is.
	static let creationMarker = "/tmp/.abydos-devcontainer"

	/// Where the lifecycle commands' own output goes.
	///
	/// On screen there is one line per command, because that is what somebody
	/// watching wants. Everything the command printed goes here, because that is
	/// what somebody debugging wants, and a `postCreateCommand` is the one thing
	/// in this app that can print for ten minutes.
	public static let logName = "devcontainer"
	public static let logPath = DiagnosticLog.path(logName)

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
	/// Who is listening to each start that is under way.
	private var audiences: [String: Audience] = [:]

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
	/// - Parameter workingDirectory: where to run it, in the container's own
	///   names, when it is not the workspace folder. A language server is rooted
	///   where the manifest is, which is commonly a directory or two down.
	public static func execCommand(
		_ session: Session,
		arguments: [String],
		interactive: Bool = false,
		workingDirectory: String? = nil
	) -> (executable: String, arguments: [String]) {
		let configuration = session.configuration
		var line = ["exec"]
		line.append(interactive ? "-it" : "-i")
		line += ["-w", workingDirectory ?? configuration.workspaceFolder]
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

	/// Why a lifecycle command did not finish, naming the command and what the
	/// runtime made of it.
	///
	/// The same job `ContainerImages.explain` does for a pull, and the thing it
	/// has to get right is different: a pull has four ways to fail and this has
	/// one, so what matters is not classifying it but *naming it* — which
	/// command, out of six that all look alike from outside, and what it said
	/// before it gave up. "The container could not be created" is the message
	/// that sends somebody to read a log nobody kept.
	///
	/// - Parameter label: the field name, with the member in brackets when the
	///   file used the object form — `postCreateCommand (install)`.
	static func explainLifecycle(
		label: String,
		line: String,
		result: RuntimeCommand.Result,
		project: String
	) -> String {
		let what = result.timedOut
			? "took longer than \(Int(lifecycleDeadline / 60)) minutes and was stopped"
			: "exited \(result.exitCode)"
		// Standard error first: a command that fails writes the reason there and
		// its progress to standard output, so the last line of the one it was
		// printing to is "step 3 of 3" and the line worth reading is beside it.
		let said = lastLine(result.errorOutput) ?? lastLine(result.output)
		let saying = said.map { ": \($0)" } ?? ""
		return "\(project)'s \(label) \(what)\(saying). The container was removed and nothing "
			+ "after it was run — fix `\(shortened(line))` in the devcontainer.json and open the "
			+ "project again."
	}

	/// The last line of some output that has anything in it.
	private static func lastLine(_ output: String) -> String? {
		output
			.split(separator: "\n", omittingEmptySubsequences: true)
			.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
			.map { $0.trimmingCharacters(in: .whitespaces) }
	}

	/// A command short enough to read in one line of a message.
	static func shortened(_ line: String, to limit: Int = 80) -> String {
		let collapsed = line
			.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.joined(separator: " ")
		return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
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
	/// The project's *preferred* devcontainer, which is its only one in nearly
	/// every project. A project offering several is asked for one of them by
	/// name — `session(for:in:using:)` — because which one somebody means is a
	/// question, and this call has nowhere to ask it.
	///
	/// Nil means the project has no devcontainer at all, which is not a failure
	/// and must not be reported as one — most projects do not have one.
	public func session(
		for project: URL,
		using runtime: ContainerRuntime,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		progress: Progress = .silent
	) async -> Outcome? {
		guard let reading = DevContainerFile.read(project: project, environment: environment)
		else { return nil }
		return await session(reading, using: runtime, progress: progress)
	}

	/// The container one named `devcontainer.json` describes, started if it is
	/// not up yet.
	///
	/// A project with several has one container per file, up at the same time and
	/// independent of each other: somebody may be working in the Go one and the
	/// Alpine one at once, and each holds its own shell. What keeps them apart is
	/// that a session is remembered against **the file**, not against the project
	/// — the two share a checkout, a mount and a name, and the file is the only
	/// thing that differs.
	public func session(
		for file: URL,
		in project: URL,
		using runtime: ContainerRuntime,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		progress: Progress = .silent
	) async -> Outcome {
		await session(
			DevContainerFile.read(file, project: project, environment: environment),
			using: runtime,
			progress: progress
		)
	}

	private func session(
		_ reading: DevContainerFile.Reading,
		using runtime: ContainerRuntime,
		progress: Progress
	) async -> Outcome {
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
		progress: Progress = .silent
	) async -> Outcome {
		if let unsupported = Self.unsupported(configuration, on: runtime) {
			return .refused(unsupported)
		}
		let key = Self.key(for: configuration)
		if let existing = sessions[key] {
			if await isUp(existing) { return .running(existing) }
			// Removed behind our back, or the runtime was restarted. Forget it and
			// start another, rather than handing out a name nothing answers to.
			forget(key)
		}
		if let already = beingStarted[key] {
			// Joined rather than merely waited on: whoever asked second has
			// somewhere to show this too, and the pull they are waiting behind is
			// the same pull.
			audiences[key]?.add(progress)
			return await already.value
		}

		let audience = Audience(progress)
		audiences[key] = audience
		let task = Task { await start(configuration, using: runtime, progress: audience.progress) }
		beingStarted[key] = task
		let outcome = await task.value
		beingStarted[key] = nil
		audiences[key] = nil
		if case let .running(session) = outcome { sessions[key] = session }
		return outcome
	}

	/// What a session is remembered against.
	///
	/// **The file, not the project.** A project offering several devcontainers
	/// has one container per file, and somebody may have a shell in each; keyed
	/// by project, the second one asked for would be handed the first one's
	/// container — the same name, the wrong image — and the second `run` would
	/// never happen. Canonical, because the same file reached through a symlink
	/// and directly must not be two containers.
	private static func key(for configuration: DevContainerConfiguration) -> String {
		FilePath.canonical(configuration.file)
	}

	/// The containers this project already has up, without starting one.
	///
	/// Several, because a project may offer several and have more than one going
	/// at once. In the order their files are preferred, so that the first is the
	/// one `session(for project:)` would have started.
	public func existingSessions(for project: URL) -> [Session] {
		let root = FilePath.canonical(project)
		return sessions.values
			.filter { FilePath.canonical($0.configuration.project) == root }
			.sorted { $0.configuration.file.path < $1.configuration.file.path }
	}

	/// The container this project already has up, without starting one.
	public func existingSession(for project: URL) -> Session? {
		existingSessions(for: project).first
	}

	/// Removes the containers for one project — every one of them, since a
	/// project that is being closed is done with all of the ones it offered.
	public func stop(project: URL) {
		let root = FilePath.canonical(project)
		for (key, session) in sessions
		where FilePath.canonical(session.configuration.project) == root {
			forget(key)
		}
	}

	/// Removes every devcontainer this has kept.
	public func stopAll() {
		for key in sessions.keys { forget(key) }
	}

	/// Which devcontainers have one up, by the file each came from, for a test.
	public var containerFiles: [String] { sessions.keys.sorted() }

	private func forget(_ key: String) {
		guard let session = sessions.removeValue(forKey: key) else { return }
		ToolContainers.shared.releaseInBackground(session.name)
	}

	// MARK: - Starting one

	private func start(
		_ configuration: DevContainerConfiguration,
		using runtime: ContainerRuntime,
		progress: Progress
	) async -> Outcome {
		// On this machine, before anything else exists — which is what the spec
		// says of it and why it is here rather than with the other five.
		if let failure = await runInitialize(configuration, progress: progress) {
			return .refused(failure)
		}

		// The image first, through the store that fetches one once however many
		// things ask for it — or a build, when the file names a Dockerfile.
		if configuration.build != nil {
			if let failure = await build(configuration, using: runtime, progress: progress) {
				return .refused(failure)
			}
		} else if let image = configuration.image {
			switch await ContainerImageStore.shared.ensure(
				image, using: runtime, progress: progress.step, output: progress.output
			) {
			case .present, .fetched: break
			case let .failed(reason): return .refused(reason)
			}
		}

		let name = ToolContainers.mint("devcontainer")
		let command = Self.startCommand(configuration, name: name, using: runtime)
		progress.step?("Starting the devcontainer for \(configuration.project.lastPathComponent)…")

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

		let session = Session(name: name, configuration: configuration, runtime: runtime)
		// Everything the file asked to have run before anybody works in it. A
		// failure takes the container with it: a half-installed container that the
		// next open would find running and reuse is the state this refuses into
		// existence rather than out of it.
		if let failure = await runLifecycle(session, progress: progress) {
			ToolContainers.shared.releaseInBackground(name)
			return .refused(failure)
		}
		return .running(session)
	}

	private func build(
		_ configuration: DevContainerConfiguration,
		using runtime: ContainerRuntime,
		progress: Progress
	) async -> String? {
		guard let command = Self.buildCommand(configuration, using: runtime),
		      let dockerfile = configuration.build?.dockerfile
		else { return nil }
		progress.step?("Building \(configuration.builtImageName) from "
			+ "\((dockerfile as NSString).lastPathComponent)…")
		let built = await offMainThread { [output = progress.output] in
			RuntimeCommand.run(command, deadline: Self.buildDeadline, onOutput: output)
		}
		guard built.succeeded else {
			return Self.explainBuild(built.output, dockerfile: dockerfile)
		}
		return nil
	}

	// MARK: - The lifecycle commands

	/// Everything the file asked to have run, at the moment it asked for it.
	///
	/// Two groups, and telling them apart is the whole of this: the three
	/// creation commands run once for the life of a container, and
	/// `postStartCommand` runs every time it starts. Which group a command is in
	/// is decided by the marker inside the container — see `creationMarker`,
	/// where the reason for putting it there is written down — and the marker is
	/// written *after* they have all succeeded, so a `postCreateCommand` that
	/// failed is tried again next time rather than skipped for ever.
	///
	/// **`waitFor` is honoured as a floor rather than as a starting gun.** The
	/// spec has it name the command after which the container may be handed to
	/// somebody, with anything later still running behind them; VS Code needs
	/// that because it has already opened a window. This app hands the container
	/// out at the moment somebody asks to work in it — a terminal, a language
	/// server — so it waits for all of them, which is never less than the file
	/// asked for, and never gives anybody a shell in a container that is still
	/// installing the toolchain they are about to use.
	///
	/// Returns nil when everything ran, or the sentence saying which command did
	/// not.
	@discardableResult
	func runLifecycle(
		_ session: Session, progress: Progress = .silent
	) async -> String? {
		let lifecycle = session.configuration.lifecycle
		if lifecycle.hasCreationCommands, await !hasBeenCreated(session) {
			for stage in DevContainerStage.creation {
				guard let command = lifecycle[stage] else { continue }
				if let failure = await run(command, at: stage, in: .container(session), progress: progress) {
					return failure
				}
			}
			await markCreated(session)
		}
		guard let onStart = lifecycle[.postStartCommand] else { return nil }
		return await run(onStart, at: .postStartCommand, in: .container(session), progress: progress)
	}

	/// What runs each time something attaches to the container.
	///
	/// Its own call rather than part of `runLifecycle` because it is the one
	/// stage whose moment is not the container's: a second terminal is a second
	/// attach, and the container did not start again in between.
	@discardableResult
	public func attach(
		to session: Session, progress: Progress = .silent
	) async -> String? {
		guard let command = session.configuration.lifecycle[.postAttachCommand] else { return nil }
		return await run(command, at: .postAttachCommand, in: .container(session), progress: progress)
	}

	/// Whether this container has already had its creation commands run.
	private func hasBeenCreated(_ session: Session) async -> Bool {
		let command = Self.execCommand(
			session, arguments: ["/bin/sh", "-c", "test -f \(Self.creationMarker)"]
		)
		return await offMainThread { RuntimeCommand.run(command, deadline: 30) }.succeeded
	}

	private func markCreated(_ session: Session) async {
		let stamp = ISO8601DateFormatter().string(from: Date())
		let command = Self.execCommand(session, arguments: [
			"/bin/sh", "-c",
			"printf '%s\\n' 'created by Abydos at \(stamp)' > \(Self.creationMarker)",
		])
		let written = await offMainThread { RuntimeCommand.run(command, deadline: 30) }
		if !written.succeeded {
			// Not fatal, and said rather than swallowed: the cost is running the
			// creation commands again on a container that has already had them,
			// which is slow rather than wrong.
			log("could not write \(Self.creationMarker) in \(session.name): \(written.output)")
		}
	}

	/// The two places a lifecycle command can run, which is five stages against
	/// one.
	private enum Place {
		case container(Session)
		/// This machine, which is `initializeCommand` and only that.
		case host(DevContainerConfiguration)

		var configuration: DevContainerConfiguration {
			switch self {
			case let .container(session): return session.configuration
			case let .host(configuration): return configuration
			}
		}

		/// What to write in the log beside each line.
		var name: String {
			switch self {
			case let .container(session): return session.name
			case let .host(configuration): return configuration.project.lastPathComponent
			}
		}
	}

	/// One stage, which is one command or several named ones.
	private func run(
		_ command: DevContainerCommand,
		at stage: DevContainerStage,
		in place: Place,
		progress: Progress
	) async -> String? {
		let members = command.members
		guard members.count > 1 else {
			guard let only = members.first else { return nil }
			return await runOne(
				only.command, at: stage, named: only.name, in: place, progress: progress
			)
		}
		// The object form runs in parallel, which the spec is explicit about —
		// it is how a file says "these two do not depend on each other". The
		// actor is left at each subprocess, so they really do overlap.
		return await withTaskGroup(of: String?.self) { group in
			for member in members {
				group.addTask { [self] in
					await runOne(
						member.command, at: stage, named: member.name, in: place, progress: progress
					)
				}
			}
			var firstFailure: String?
			for await failure in group where firstFailure == nil {
				firstFailure = failure
			}
			return firstFailure
		}
	}

	/// One command, wherever it runs.
	private func runOne(
		_ command: DevContainerCommand,
		at stage: DevContainerStage,
		named member: String?,
		in place: Place,
		progress: Progress
	) async -> String? {
		let configuration = place.configuration
		let project = configuration.project.lastPathComponent
		let label = member.map { "\(stage.rawValue) (\($0))" } ?? stage.rawValue
		// Once, with what it is doing, which is `ContainerImages.progressMessage`'s
		// bargain: a `postCreateCommand` can take minutes and a minute with
		// nothing on screen is indistinguishable from a hung editor. The one that
		// runs out here says so, because where it runs is the thing about it
		// somebody would want to have been told.
		let running: String
		let invocation: (executable: String, arguments: [String])
		let directory: URL?
		switch place {
		case let .container(session):
			running = "Running \(project)'s \(label)"
			invocation = Self.execCommand(session, arguments: command.invocation)
			directory = nil
		case .host:
			running = "Running \(project)'s \(label) on this machine"
			// `/usr/bin/env` for the argv form, because `Process` wants a path and
			// a file that says `["npm", "ci"]` means the npm on the PATH.
			let parts = command.invocation
			if case .shell = command {
				invocation = ("/bin/sh", Array(parts.dropFirst()))
			} else {
				invocation = ("/usr/bin/env", parts)
			}
			directory = configuration.project
		}
		progress.step?("\(running): \(Self.shortened(command.line))…")
		log("\(place.name) \(label): \(command.line)")

		// What it prints, while it prints it, as well as all of it in the log
		// afterwards: `postCreateCommand` is the one thing here that can take ten
		// minutes, and the lines it writes as it goes are the only evidence
		// anybody has that it is getting on with it.
		let result = await offMainThread { [output = progress.output] in
			RuntimeCommand.run(
				invocation,
				deadline: Self.lifecycleDeadline,
				directory: directory,
				onOutput: output
			)
		}
		logOutput(result.output, of: label, in: place.name)
		guard result.succeeded else {
			log("\(place.name) \(label) failed: exit \(result.exitCode)"
				+ (result.timedOut ? " (deadline)" : ""))
			return Self.explainLifecycle(
				label: label, line: command.line, result: result, project: project
			)
		}
		return nil
	}

	/// `initializeCommand`, which runs here rather than in the container.
	///
	/// **This is a command out of somebody's repository executing on their
	/// machine, and it is worth being deliberate about.** It is run, for two
	/// reasons. The app already runs command lines a project supplies — a run
	/// configuration out of `launch.json`, a `make` target, a build scheme — so
	/// this is not a new kind of trust, it is the same one. And a file whose
	/// `initializeCommand` creates the directory its `mounts` bind, which is the
	/// common use, does not work at all without it: the container would come up
	/// missing what the file said it needed, which is the failure this step
	/// exists to remove.
	///
	/// What is different is that this one is not inside anything, so it is the
	/// one that is *named on screen before it runs* rather than only logged.
	/// Nothing here runs unseen. And it runs only when somebody has asked for
	/// the devcontainer — opening a project does not start one.
	///
	/// A real answer is a trust prompt for a checkout nobody has vouched for,
	/// the way VS Code has one. This app has no such concept and inventing one
	/// here would be the wrong place for it; it is its own item.
	private func runInitialize(
		_ configuration: DevContainerConfiguration,
		progress: Progress
	) async -> String? {
		guard let command = configuration.lifecycle[.initializeCommand] else { return nil }
		return await run(
			command, at: .initializeCommand, in: .host(configuration), progress: progress
		)
	}

	// MARK: - What is in there

	/// Which of these commands the container has on its PATH.
	///
	/// Asked once, for all of them, because the answer decides which language
	/// servers this project gets and the alternative is finding out one failed
	/// handshake at a time — ten seconds each, and the message at the end is the
	/// runtime's `executable file not found` rather than anything about the
	/// project. One `exec` is a fraction of a second and turns that into a
	/// sentence naming the server and the file that would have to carry it.
	public func provides(_ commands: [String], in session: Session) async -> Set<String> {
		// Names, not a command line: a devcontainer.json cannot reach this, but a
		// language server's definition is a table in this app and a table is a
		// thing somebody edits.
		let safe = commands.filter { name in
			!name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || "-_.+".contains($0) }
		}
		guard !safe.isEmpty else { return [] }
		// `exit 0` at the end, and it is not decoration: the loop's status is the
		// last `command -v`, so a list whose final name is missing — which is the
		// ordinary case — would come back a failure and be read as "none of
		// them". The answer is the lines, not the status.
		let script = "for c in \(safe.joined(separator: " ")); do "
			+ "command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done; exit 0"
		let exec = Self.execCommand(session, arguments: ["/bin/sh", "-c", script])
		let answer = await offMainThread { RuntimeCommand.run(exec, deadline: 60) }
		guard answer.succeeded else { return [] }
		let found = Set(
			answer.output
				.split(separator: "\n", omittingEmptySubsequences: true)
				.map { $0.trimmingCharacters(in: .whitespaces) }
		)
		return found.intersection(safe)
	}

	/// A line in `~/Library/Logs/Abydos/devcontainer.log`.
	private nonisolated func log(_ message: String) {
		DiagnosticLog.write(message, to: Self.logName)
	}

	/// Everything a command printed, kept where somebody debugging can read it.
	private nonisolated func logOutput(_ output: String, of label: String, in name: String) {
		for line in output.split(separator: "\n", omittingEmptySubsequences: true)
		where !line.trimmingCharacters(in: .whitespaces).isEmpty {
			DiagnosticLog.write("\(name) \(label) | \(line)", to: Self.logName)
		}
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
