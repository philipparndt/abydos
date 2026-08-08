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
	/// Both runtimes take a subcommand and a reference; they differ only in
	/// whether the noun is singular.
	public static func inspect(
		_ image: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .apple:  return (runtime.path, ["images", "inspect", image])
		case .docker: return (runtime.path, ["image", "inspect", image])
		}
	}

	/// The command that fetches it.
	public static func pull(
		_ image: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .apple:  return (runtime.path, ["images", "pull", image])
		case .docker: return (runtime.path, ["pull", image])
		}
	}

	/// Why a pull failed, in a sentence somebody can act on.
	///
	/// The runtimes' own words are long, differently worded from each other and
	/// mostly about themselves. What matters is which of four things happened,
	/// because each has a different answer: fix the name, sign in, get a
	/// network, or start the runtime.
	public static func explain(_ output: String, image: String) -> String {
		let text = output.lowercased()

		if text.contains("manifest unknown") || text.contains("not found")
			|| text.contains("no such image") || text.contains("manifest for")
			&& text.contains("not found") {
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
		if text.contains("cannot connect") || text.contains("daemon")
			|| text.contains("is the docker daemon running") {
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
		/// It is not here and could not be got, with a sentence saying why.
		case failed(String)
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

	/// - Parameters:
	///   - inspectDeadline: given so a test can watch this happen in a second
	///     rather than in twenty. Nothing in the app passes either.
	public init(
		inspectDeadline: TimeInterval = ContainerImageStore.inspectDeadline,
		pullDeadline: TimeInterval = ContainerImageStore.pullDeadline
	) {
		self.inspectDeadline = inspectDeadline
		self.pullDeadline = pullDeadline
	}

	/// Forgets what is on the machine, for a test or after somebody has been
	/// deleting images behind our back.
	public func forgetAll() {
		known.removeAll()
		silent.removeAll()
	}

	public func ensure(
		_ image: String,
		using runtime: ContainerRuntime,
		progress: (@Sendable (String) -> Void)? = nil
	) async -> Outcome {
		guard !image.isEmpty else { return .failed("No image was named.") }
		if known.contains(image) { return .present }
		// A runtime that has already been found not to answer is not asked
		// again, and the second asker is told the same thing as the first.
		if let said = silent[runtime.path] { return .failed(said) }
		if let running = inFlight[image] { return await running.value }

		let task = Task<Outcome, Never> { [runtime, inspectDeadline, pullDeadline] in
			let inspect = Self.run(
				ContainerImages.inspect(image, using: runtime), deadline: inspectDeadline
			)
			if inspect.timedOut {
				return .failed(ContainerImages.notAnswering(runtime, after: Int(inspectDeadline)))
			}
			if inspect.exitCode == 0 { return .present }

			progress?(ContainerImages.progressMessage(for: image))
			let pull = Self.run(
				ContainerImages.pull(image, using: runtime), deadline: pullDeadline
			)
			if pull.timedOut {
				return .failed(ContainerImages.notAnswering(runtime, after: Int(pullDeadline)))
			}
			guard pull.exitCode == 0 else {
				return .failed(ContainerImages.explain(pull.output, image: image))
			}
			return .fetched
		}
		inFlight[image] = task
		let outcome = await task.value
		inFlight[image] = nil
		if outcome == .present || outcome == .fetched {
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
	/// The deadline is the whole point: a runtime whose service is down accepts
	/// the command and then waits for something that is not coming, and a
	/// process waiting on that outlives whatever asked for it. Terminated
	/// first and killed after, because a program stuck in a system call does
	/// not always get round to noticing the polite one.
	private static func run(
		_ command: (executable: String, arguments: [String]),
		deadline: TimeInterval
	) -> (output: String, exitCode: Int32, timedOut: Bool) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		// Nothing on standard input, and said in the one way that means it.
		//
		// A `Pipe()` here reads as "no input" and is the opposite: this process
		// holds the write end, so the child sees an input that never ends. Apple's
		// `container` then waits for it — `container images inspect` with a pipe
		// held open never answers at all — and every caller waits with it.
		process.standardInput = FileHandle.nullDevice
		do { try process.run() } catch {
			return ("\(error.localizedDescription)", -1, false)
		}

		// Whether the deadline is what ended it, recorded where both threads can
		// see it: `terminationReason` cannot tell a program this killed from one
		// that died of its own accord.
		let expired = Expired()
		let watchdog = DispatchWorkItem {
			guard process.isRunning else { return }
			expired.record()
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
		}
		DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: watchdog)

		let captured = ProcessPipes.drainText(process, out: out, err: err)
		watchdog.cancel()
		// Both, since the runtimes disagree about which one a failure goes to.
		return (captured.stderr + captured.stdout, process.terminationStatus, expired.happened)
	}

	/// One bool, written by the deadline and read by whoever was waiting.
	private final class Expired: @unchecked Sendable {
		private let lock = NSLock()
		private var value = false

		func record() {
			lock.lock()
			value = true
			lock.unlock()
		}

		var happened: Bool {
			lock.lock()
			defer { lock.unlock() }
			return value
		}
	}
}
