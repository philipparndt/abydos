import Foundation

/// Getting an image onto the machine before something is asked to run from it.
///
/// A named image that is not there is the ordinary case, not the exception: it
/// is what happens the first time anybody opens a project that names one. Until
/// now nothing fetched it, so the first render failed in whatever words the
/// runtime chose — and a pull that takes two minutes with nothing on screen is
/// indistinguishable from a tool that has hung.
///
/// So: ask whether it is there, fetch it once if it is not, and say what went
/// wrong in one sentence rather than passing the runtime's output through.
public enum ContainerImages {
	/// The command that says whether an image is already on the machine.
	///
	/// The noun is **singular in both** — `container image inspect`, `docker
	/// image inspect`. This said the opposite and sent Apple's runtime a plural
	/// that does not exist, which is worth spelling out because of how it
	/// failed: `container` resolves an unknown subcommand as a plugin, so the
	/// answer was `Plugin 'container-images' not found`, and `isUnknownImage`
	/// read the words "not found" and reported a perfectly correct image name as
	/// wrong. Nothing image-backed had ever worked on Apple's runtime.
	public static func inspect(
		_ image: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .apple:  return (runtime.path, ["image", "inspect", image])
		case .docker: return (runtime.path, ["image", "inspect", image])
		}
	}

	/// The command that fetches it.
	///
	/// Here they do differ: docker's `pull` is a verb of its own, and Apple's
	/// lives under `image` with the rest of them.
	public static func pull(
		_ image: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .apple:  return (runtime.path, ["image", "pull", image])
		case .docker: return (runtime.path, ["pull", image])
		}
	}
	// Nothing here lists the images on the machine, so there is no command for
	// it. If something ever needs one, Apple's `container image list --quiet`
	// prints one `repository:tag` per line and `--format json` prints the whole
	// record — both were checked while the two above were being fixed.

	/// Why a pull failed, in a sentence somebody can act on.
	///
	/// The runtimes' own words are long, differently worded from each other and
	/// mostly about themselves. What matters is which of four things happened,
	/// because each has a different answer: fix the name, sign in, get a
	/// network, or start the runtime.
	public static func explain(_ output: String, image: String) -> String {
		let text = output.lowercased()

		if isUnknownImage(output) {
			return "There is no image called \(image). Check the name and the tag."
		}
		if text.contains("unauthorized") || text.contains("authentication required")
			|| text.contains("denied") || text.contains("login") {
			return "\(image) is private, or the registry wants a sign-in. "
				+ "Log in with the runtime's own command and try again."
		}
		if text.contains("no such host") || text.contains("dial tcp")
			|| text.contains("network is unreachable") || text.contains("timeout")
			|| text.contains("temporary failure in name resolution") {
			return "Could not reach the registry to fetch \(image). "
				+ "That usually means no network, or one that needs a proxy."
		}
		if isRuntimeDown(output) {
			return "The container runtime is not running, so \(image) could not be fetched."
		}

		let first = output
			.split(separator: "\n", omittingEmptySubsequences: true)
			.first
			.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
		return first.isEmpty
			? "Could not fetch \(image), and the runtime said nothing about why."
			: "Could not fetch \(image): \(first)"
	}

	/// Whether the runtime's words mean it has never heard of the image.
	///
	/// Its own sentence, because two different answers turn on it: an image that
	/// is genuinely nowhere, and one that is on the machine in the *other*
	/// runtime's store.
	///
	/// A bare "not found" is not enough, and getting that wrong was expensive:
	/// Apple's CLI answers an unknown subcommand with `Plugin 'container-images'
	/// not found`, so a spelling mistake in this app's own command line came back
	/// to somebody as "there is no image called plantuml/plantuml:1.2026.6.
	/// Check the name and the tag" — a confident falsehood about a name that was
	/// correct, and one that also stopped the cross-runtime hint from ever being
	/// reached. So "not found" counts only when the sentence is about a manifest,
	/// a reference, an image or a tag, and never when it is about the runtime's
	/// own plumbing.
	/// Whether the runtime is installed but not answering.
	///
	/// Separate from the sentence above because two callers need the fact rather
	/// than the wording. `discover` only asks whether the command is on the
	/// PATH, which is the right first question for the app — it can then say
	/// which of four things went wrong — and the wrong one for a test, which
	/// wants to know whether there is anything to talk to before asserting about
	/// the answer. A suite run with the daemon stopped was otherwise two red
	/// tests that looked like a code fault.
	public static func isRuntimeDown(_ output: String) -> Bool {
		let text = output.lowercased()
		return text.contains("cannot connect") || text.contains("daemon")
			|| text.contains("is the docker daemon running")
			// Apple's runtime stopped, in its own words: the CLI answers
			// `interrupted: "XPC connection error: Connection invalid"` and
			// advises `container system start`. Neither says "daemon", so a
			// machine with the service off read as a wrong verb rather than
			// as a runtime that is not up.
			|| text.contains("xpc connection error")
			|| text.contains("container system start")
	}

	public static func isUnknownImage(_ output: String) -> Bool {
		let text = output.lowercased()
		if text.contains("plugin") || text.contains("command not found")
			|| text.contains("executable file not found") || text.contains("no such file") {
			return false
		}
		if text.contains("manifest unknown") || text.contains("no such image")
			|| text.contains("repository does not exist") {
			return true
		}
		guard text.contains("not found") else { return false }
		return ["manifest", "reference", "image", "tag", "repository"].contains {
			text.contains($0)
		}
	}

	/// The other runtime on this machine, if there is one.
	///
	/// Apple's and docker's are the two families, and what makes them worth
	/// telling apart here is that neither can see into the other's store.
	public static func alternative(
		to runtime: ContainerRuntime,
		locate: (String) -> String? = { Executables.locate($0) }
	) -> ContainerRuntime? {
		switch runtime {
		case .apple:
			return ContainerRuntime.discover(preference: .docker, locate: locate)
		case .docker:
			return ContainerRuntime.discover(preference: .apple, locate: locate)
		}
	}

	/// What to say when the image is missing here and present in the other one.
	///
	/// The case somebody actually hits: an image built locally with docker, and
	/// Apple's `container` preferred because it needs no daemon. It is not on
	/// the machine as far as that runtime is concerned, so it says the name is
	/// wrong and then tries to fetch something that is already here — two
	/// sentences that are both true and together point the wrong way.
	///
	/// A local build is the likely reason for a name no registry has, so the
	/// first thing offered is the one that needs no push.
	public static func visibleElsewhere(
		_ image: String,
		missingFrom: ContainerRuntime,
		presentIn: ContainerRuntime
	) -> String {
		"\(missingFrom.name) has no image called \(image), but \(presentIn.name) does — "
			+ "they keep separate stores and neither can see into the other. "
			+ "Choose \(presentIn.name) as the container runtime in settings, "
			+ "or push \(image) somewhere both can pull it from."
	}

	/// What to say about a runtime that has stopped answering at all.
	///
	/// Not a failure of the image or of the network: the command was accepted
	/// and nothing came back. Apple's `container` does this when its service is
	/// down — every subcommand waits, `container ls` included — and docker does
	/// it when its daemon is starting or wedged. The answer is the same shape
	/// for both, and it is not something this app can do anything about.
	public static func notAnswering(_ runtime: ContainerRuntime, after seconds: Int) -> String {
		"\(runtime.name) did not answer within \(seconds) seconds, so nothing can be run "
			+ "from an image until it does. Its service is usually the reason: "
			+ (runtime.name == "container"
				? "`container system start` brings Apple's back."
				: "starting Docker brings it back.")
	}

	/// What to say while it is happening.
	///
	/// A pull is the one part of this that takes long enough to need saying,
	/// and the size is not known in advance — so it says what it is doing and
	/// which image, and nothing it would have to invent.
	public static func progressMessage(for image: String) -> String {
		"Fetching \(image)…"
	}
}

/// Somewhere to say how getting a container image is going.
///
/// The three things worth saying, for a caller with somewhere to show them: the
/// one sentence before it starts, the runtime's own output as it arrives, and —
/// the one `ContainerImageStore.ensure` has no need of — the moment the image
/// part settled.
///
/// That third one is here for the callers that get an image in the middle of a
/// longer job and hand the whole job back as one value. `DiagramExport.export`
/// fetches an image and then draws several pictures with it, so its caller
/// cannot tell a registry that refused from a syntax error in a `.puml`; a pane
/// opened to watch a fetch must not end up with the second one written into it
/// in red. Nil means it arrived.
public struct ImageWatch: Sendable {
	public var step: (@Sendable (String) -> Void)?
	public var output: (@Sendable (String) -> Void)?
	public var settled: (@Sendable (String?) -> Void)?

	public init(
		step: (@Sendable (String) -> Void)? = nil,
		output: (@Sendable (String) -> Void)? = nil,
		settled: (@Sendable (String?) -> Void)? = nil
	) {
		self.step = step
		self.output = output
		self.settled = settled
	}

	/// Nobody is watching, which is every use from a test and from the command
	/// line.
	public static let none = ImageWatch()
}

/// Makes sure an image is on the machine, once, however many things ask.
///
/// Kept because the answer is worth remembering and the work is worth not
/// repeating: asking the runtime costs a process launch, and every render of a
/// diagram would otherwise pay it. Two panes opening at once ask for the same
/// image and wait on the same fetch rather than starting two.
public actor ContainerImageStore {
	public static let shared = ContainerImageStore()

	public enum Outcome: Equatable, Sendable {
		/// It was already here; nothing was fetched.
		case present
		/// It was fetched, which took as long as it took.
		case fetched
		/// It was built here, from a Dockerfile this app ships.
		///
		/// Its own case rather than `fetched`, because they are different facts
		/// about where a tool came from and only one of them involves a
		/// registry. Anything that only wants "is it usable now" treats the
		/// three alike; anything saying what happened must not report a build as
		/// a download.
		case built
		/// It is not here and could not be got, with a sentence saying why.
		case failed(String)

		/// Whether the image can be run now, however it got here.
		public var isReady: Bool {
			switch self {
			case .present, .fetched, .built: return true
			case .failed: return false
			}
		}
	}

	private var known: Set<String> = []
	private var inFlight: [String: Task<Outcome, Never>] = [:]
	/// Runtimes that were asked something and never answered, by path.
	///
	/// Asked again would mean waiting again, for every pane and every server
	/// that wants an image, and each wait is a process left behind holding
	/// whatever the runtime is stuck on. One report and then a fast no is the
	/// useful behaviour; the app has to be restarted to try again, by which
	/// time somebody has had the chance to start the service.
	private var silent: [String: String] = [:]

	/// How long a runtime gets to answer.
	///
	/// Asking whether an image is here is a local question and takes
	/// milliseconds when anything is working at all. Fetching one is a download
	/// of a gigabyte or more, so it is given as long as it plausibly needs and
	/// no longer.
	public static let inspectDeadline: TimeInterval = 20
	public static let pullDeadline: TimeInterval = 900

	private let inspectDeadline: TimeInterval
	private let pullDeadline: TimeInterval
	private let alternative: @Sendable (ContainerRuntime) -> ContainerRuntime?

	/// - Parameters:
	///   - inspectDeadline: given so a test can watch this happen in a second
	///     rather than in twenty. Nothing in the app passes either.
	///   - alternative: the other runtime on this machine, asked for only when
	///     an image was not found — so a test can say there is one, or none,
	///     without a runtime being installed.
	public init(
		inspectDeadline: TimeInterval = ContainerImageStore.inspectDeadline,
		pullDeadline: TimeInterval = ContainerImageStore.pullDeadline,
		alternative: @escaping @Sendable (ContainerRuntime) -> ContainerRuntime? = {
			ContainerImages.alternative(to: $0)
		}
	) {
		self.inspectDeadline = inspectDeadline
		self.pullDeadline = pullDeadline
		self.alternative = alternative
	}

	/// Forgets what is on the machine, for a test or after somebody has been
	/// deleting images behind our back.
	public func forgetAll() {
		known.removeAll()
		silent.removeAll()
	}

	/// - Parameter output: what the pull itself printed, as it prints it, for a
	///   caller with somewhere to show it. `progress` says one sentence before a
	///   download that can be a gigabyte; this is the download saying how it is
	///   getting on, in the runtime's own words, which is the only place that
	///   answer exists.
	public func ensure(
		_ image: String,
		using runtime: ContainerRuntime,
		progress: (@Sendable (String) -> Void)? = nil,
		output: (@Sendable (String) -> Void)? = nil
	) async -> Outcome {
		guard !image.isEmpty else { return .failed("No image was named.") }
		if known.contains(image) { return .present }
		// A runtime that has already been found not to answer is not asked
		// again, and the second asker is told the same thing as the first.
		if let said = silent[runtime.path] { return .failed(said) }
		if let running = inFlight[image] { return await running.value }

		let task = Task<Outcome, Never> { [runtime, inspectDeadline, pullDeadline, alternative] in
			let inspect = Self.run(
				ContainerImages.inspect(image, using: runtime), deadline: inspectDeadline
			)
			if inspect.timedOut {
				return .failed(ContainerImages.notAnswering(runtime, after: Int(inspectDeadline)))
			}
			if inspect.exitCode == 0 { return .present }

			// An image this app makes is made rather than fetched, and the name
			// is what says which: `ToolImageRecipes` owns that namespace, and no
			// registry has anything under it. The branch is here rather than at
			// the call sites because every one of them deals in an image and a
			// runtime and nothing else — a language server launch, a diagram
			// pane — and threading a recipe through all of them would be a
			// parameter on each for the sake of the two tools that have one.
			if let recipe = ToolImageRecipes.recipe(forImage: image) {
				progress?(ToolImageRecipes.progressMessage(for: recipe))
				let build = Self.run(
					ToolImageRecipes.build(recipe, using: runtime),
					deadline: ToolImageRecipes.buildDeadline,
					onOutput: output
				)
				if build.timedOut {
					return .failed(ContainerImages.notAnswering(
						runtime, after: Int(ToolImageRecipes.buildDeadline)
					))
				}
				guard build.exitCode == 0 else {
					return .failed(ToolImageRecipes.explain(build.output, recipe: recipe))
				}
				return .built
			}

			progress?(ContainerImages.progressMessage(for: image))
			let pull = Self.run(
				ContainerImages.pull(image, using: runtime),
				deadline: pullDeadline,
				onOutput: output
			)
			if pull.timedOut {
				return .failed(ContainerImages.notAnswering(runtime, after: Int(pullDeadline)))
			}
			guard pull.exitCode == 0 else {
				// Only once it has failed, and only for the one answer that could
				// be a store rather than a name: asking the other runtime costs a
				// process launch, and the ordinary first-run pull should not pay
				// it. A hit here changes the sentence completely.
				if ContainerImages.isUnknownImage(pull.output),
					let other = alternative(runtime),
					Self.run(
						ContainerImages.inspect(image, using: other), deadline: inspectDeadline
					).exitCode == 0 {
					return .failed(ContainerImages.visibleElsewhere(
						image, missingFrom: runtime, presentIn: other
					))
				}
				return .failed(ContainerImages.explain(pull.output, image: image))
			}
			return .fetched
		}
		inFlight[image] = task
		let outcome = await task.value
		inFlight[image] = nil
		if outcome.isReady {
			known.insert(image)
			// It answered, so whatever was wrong with it is over.
			silent.removeValue(forKey: runtime.path)
		}
		if case let .failed(reason) = outcome, reason.contains("did not answer") {
			silent[runtime.path] = reason
		}
		return outcome
	}

	/// Runs a command with a deadline, and does not leave it behind.
	///
	/// `RuntimeCommand` is where that lives now: every command sent to a runtime
	/// needs the same deadline, and removing a container needs it most of all —
	/// a tidy-up that hangs is not a tidy-up.
	private static func run(
		_ command: (executable: String, arguments: [String]),
		deadline: TimeInterval,
		onOutput: (@Sendable (String) -> Void)? = nil
	) -> RuntimeCommand.Result {
		RuntimeCommand.run(command, deadline: deadline, onOutput: onOutput)
	}
}
