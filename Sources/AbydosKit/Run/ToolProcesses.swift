import Foundation

/// Every subprocess started to run a tool, so they can be ended together.
///
/// A child is not killed when its parent goes: it is handed to launchd and
/// keeps running. So an app that quits — and above all one that crashes, where
/// no `deinit` runs at all — leaves every renderer and every language server it
/// started still going. Eleven `container run` processes were found on one
/// machine that way, the oldest a day old, and enough of them wedge a container
/// runtime's service that everything started afterwards hangs too, which starts
/// more of them.
///
/// So they are all registered here, and ending the app ends them.
///
/// **Two kinds, two lists, one ending.** A render, an export and a build are
/// short: they are started, they finish, and they are let go of. A language
/// server is started once per project and kept for the session. Both are held
/// here because both have to be ended; only the first kind is counted against
/// the cap. They shared one array until 0538, which made every server spend a
/// slot for the rest of the session and refused the first Cadova build of the
/// day on a machine with a few languages open. The lists are separate and
/// `terminateAll` walks both — that it walks both is the claim worth testing,
/// because it is the whole of what this type is for.
///
/// Deliberately not an actor: the two things this must do — count, and end
/// everything — have to work from a signal handler's neighbourhood, where there
/// is no waiting for an actor's turn.
public final class ToolProcesses: @unchecked Sendable {
	public static let shared = ToolProcesses()

	/// How many *short* tools may run at once.
	///
	/// A backstop rather than a budget, and what it is a backstop against is a
	/// runaway: every render starting a container that hangs, thirty seconds
	/// apart, for an afternoon. Each of the things it counts has a deadline of
	/// its own and is let go of when it ends, and a preview pane runs one at a
	/// time — so twelve in flight at once is not a workload anybody has, it is
	/// twelve that are not coming back.
	///
	/// Twelve is unchanged by 0538 and did not need changing: what was wrong was
	/// the population, not the number. It used to count the long-lived processes
	/// too, and a project of several languages starts a dozen servers on its
	/// own, so the budget was spent before any tool ran. With servers out of it,
	/// reaching twelve means twelve renders, exports or builds are outstanding
	/// at one moment, and that is the thing worth stopping.
	public static let limit = 12

	/// One short-lived process, with what to call it in a sentence.
	///
	/// The word comes from whoever started it, because nothing here can work it
	/// out afterwards: a Cadova build is `/bin/zsh -lc "swift run …"` and a
	/// PlantUML render is `container run …`, so the executable's name would say
	/// "zsh" and "container" to somebody trying to find out what is stuck.
	private struct Tool {
		let process: Process
		/// Singular, lower case, as it reads mid-sentence: `diagram render`.
		let what: String
		/// Whether this one runs in a container. The refusal only mentions a
		/// container runtime when there is one in the picture — the message
		/// blamed one for a `swift run` before 0538, and somebody reading it
		/// goes and restarts a runtime that was never involved.
		let fromImage: Bool
	}

	private let lock = NSLock()
	/// The short ones. These are what the cap counts.
	private var tools: [Tool] = []
	/// The long ones — servers, kept for the session. Ended with everything
	/// else, counted against nothing.
	private var kept: [Process] = []

	public init() {}

	/// Whether a process this is holding has been and gone.
	///
	/// Not `!isRunning`, and the difference is a real bug rather than a nicety.
	/// A caller registers a process *before* starting it — `LSPClient` does,
	/// deliberately, so that there is no instant in which a running child is
	/// unknown to the thing that ends it — and in that instant `isRunning` is
	/// false because it has not started yet. Every method here that tidies the
	/// list used `!isRunning`, so a second caller registering its own process in
	/// that window swept the first one out. It then ran untracked for the life of
	/// the app: not ended when the app quit, which is the whole thing this type
	/// exists to prevent.
	///
	/// Seen as a red in `aServerIsHandedToTheThingThatEndsItWithTheApp` at 5.1
	/// runnable threads per core, where the window is wide enough to lose
	/// against. It is a race, not a deadline, and it was hiding among 0435's
	/// deadline failures — which is exactly what that item warns happens when a
	/// suite's reds stop being read.
	///
	/// A `Process` that has never run has a process id of nought.
	private static func hasFinished(_ process: Process) -> Bool {
		process.processIdentifier != 0 && !process.isRunning
	}

	private static func hasFinished(_ tool: Tool) -> Bool {
		hasFinished(tool.process)
	}

	/// Takes charge of a short-lived process, or refuses when too many are
	/// already running.
	///
	/// The caller is told which, because "no" is worth reporting: a tool that
	/// will not start because a dozen are stuck is a different sentence from a
	/// tool that failed. What to say is `tooManyMessage`, which is built from
	/// what is actually being held.
	///
	/// `what` names the kind of work in a word or two, singular and lower case,
	/// so that the refusal can say what is holding the slots.
	@discardableResult
	public func adopt(_ process: Process, as what: String, fromImage: Bool = false) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		tools.removeAll(where: Self.hasFinished)
		guard tools.count < Self.limit else { return false }
		tools.append(Tool(process: process, what: what, fromImage: fromImage))
		return true
	}

	/// Takes charge of a process that is not subject to the cap.
	///
	/// For the long-lived ones — a language server is started once per language
	/// per project and stays for the session. Refusing to start one because a
	/// dozen renders are stuck would be answering the wrong question, and an
	/// untracked process is the thing this type exists to prevent.
	///
	/// It goes in a list of its own, which is the fix for 0538: appended to the
	/// list `adopt` counts, every one of these spent a slot that nothing ever
	/// gave back, because a server never satisfies `hasFinished` until the app
	/// ends.
	public func track(_ process: Process) {
		lock.lock()
		kept.removeAll(where: Self.hasFinished)
		kept.append(process)
		lock.unlock()
	}

	public func forget(_ process: Process) {
		lock.lock()
		tools.removeAll { $0.process === process || Self.hasFinished($0) }
		kept.removeAll { $0 === process || Self.hasFinished($0) }
		lock.unlock()
	}

	/// Whether a process is one of the ones this will end.
	///
	/// Asked by the process id, because that is what a caller can still get hold
	/// of once the `Process` belongs to whatever started it. Read-only, and there
	/// to prove the handover: a language server is ended by nothing short of the
	/// app ending, so being registered here is the whole of what keeps one from
	/// being left behind. Both lists, because the question is "will this be
	/// ended", and the answer for both kinds is yes.
	public func isTracking(pid: Int32) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return everything.contains { $0.isRunning && $0.processIdentifier == pid }
	}

	/// Everything held, of both kinds. The caller holds the lock.
	private var everything: [Process] {
		tools.map(\.process) + kept
	}

	/// How many processes this would end. Both kinds: what this counts is what
	/// it is holding, which is not the same question as what the cap allows.
	public var count: Int {
		lock.lock()
		defer { lock.unlock() }
		tools.removeAll(where: Self.hasFinished)
		kept.removeAll(where: Self.hasFinished)
		return tools.count + kept.count
	}

	/// How many of the capped kind are running — what `limit` is compared with.
	public var capped: Int {
		lock.lock()
		defer { lock.unlock() }
		tools.removeAll(where: Self.hasFinished)
		return tools.count
	}

	/// Ends everything still running, politely and then not.
	///
	/// Called when the app is going, including on the way out of an uncaught
	/// exception — which is the case that left the processes behind. The wait
	/// between the two signals is short: this runs while an app is quitting,
	/// and a quit that visibly hangs is its own bug.
	///
	/// Both lists. A server is the longest-lived child this app has and the one
	/// most worth ending; being outside the cap says nothing about being outside
	/// this.
	public func terminateAll() {
		lock.lock()
		let processes = everything
		tools.removeAll()
		kept.removeAll()
		lock.unlock()

		for process in processes where process.isRunning {
			process.terminate()
		}
		guard processes.contains(where: \.isRunning) else { return }
		Thread.sleep(forTimeInterval: 0.2)
		for process in processes where process.isRunning {
			kill(process.processIdentifier, SIGKILL)
		}
	}

	/// What to say to somebody whose tool would not start because of the cap.
	///
	/// Built from what is being held rather than written once, because the
	/// sentence that was written once said "running from images" and "the
	/// container runtime has stopped answering" — three claims, all of them
	/// false for the `swift run` of a Cadova preview, and the reader of 0538
	/// went and restarted a container runtime that had never been in the path.
	///
	/// So it names the kinds that are holding the slots and how many of each,
	/// and it only mentions a runtime when every last one of them is in a
	/// container, which is the one case where a runtime that has stopped
	/// answering explains it.
	public var tooManyMessage: String {
		lock.lock()
		tools.removeAll(where: Self.hasFinished)
		let held = tools
		lock.unlock()

		// The refusal and this sentence are two moments, and a tool can finish
		// in between. Saying "nought tools are already running" would be worse
		// than saying what actually happened.
		guard !held.isEmpty else {
			return "No tool could be started while \(Self.limit) others were running. "
				+ "They have finished since, so trying again should work."
		}
		var said = "\(held.count) tools are already running and none of them has finished: "
			+ "\(Self.phrase(held)). Try this one again once one of those has ended."
		if held.allSatisfy(\.fromImage) {
			said += " Every one of them was started from an image, which usually means "
				+ "the container runtime has stopped answering."
		}
		return said
	}

	/// `9 diagram renders and 3 Cadova builds`, biggest group first, so the
	/// first thing read is the thing to go and look at.
	private static func phrase(_ held: [Tool]) -> String {
		var order: [String] = []
		var counts: [String: Int] = [:]
		for tool in held {
			if counts[tool.what] == nil { order.append(tool.what) }
			counts[tool.what, default: 0] += 1
		}
		let parts = order.enumerated().sorted { first, second in
			let left = counts[first.element] ?? 0, right = counts[second.element] ?? 0
			return left == right ? first.offset < second.offset : left > right
		}.map { _, what -> String in
			let many = counts[what] ?? 0
			return "\(many) \(what)\(many == 1 ? "" : "s")"
		}
		guard let last = parts.last else { return "" }
		guard parts.count > 1 else { return last }
		return parts.dropLast().joined(separator: ", ") + " and " + last
	}
}
