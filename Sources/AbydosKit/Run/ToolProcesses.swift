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
/// Deliberately not an actor: the two things this must do — count, and end
/// everything — have to work from a signal handler's neighbourhood, where there
/// is no waiting for an actor's turn.
public final class ToolProcesses: @unchecked Sendable {
	public static let shared = ToolProcesses()

	/// How many may run at once.
	///
	/// A backstop rather than a budget: one preview pane renders one diagram at
	/// a time and a project starts a handful of servers, so nothing legitimate
	/// comes near this. What it stops is the runaway — every render starting a
	/// container that hangs, thirty seconds apart, for an afternoon.
	public static let limit = 12

	private let lock = NSLock()
	private var running: [Process] = []

	public init() {}

	/// Takes charge of a process, or refuses when too many are already running.
	///
	/// The caller is told which, because "no" is worth reporting: a tool that
	/// will not start because a dozen are stuck is a different sentence from a
	/// tool that failed.
	@discardableResult
	public func adopt(_ process: Process) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		running.removeAll { !$0.isRunning }
		guard running.count < Self.limit else { return false }
		running.append(process)
		return true
	}

	/// Takes charge of a process that is not subject to the cap.
	///
	/// For the long-lived ones — a language server is started once per language
	/// per project and stays for the session. Refusing to start one because a
	/// dozen renders are stuck would be answering the wrong question, and an
	/// untracked process is the thing this type exists to prevent.
	public func track(_ process: Process) {
		lock.lock()
		running.removeAll { !$0.isRunning }
		running.append(process)
		lock.unlock()
	}

	public func forget(_ process: Process) {
		lock.lock()
		running.removeAll { $0 === process || !$0.isRunning }
		lock.unlock()
	}

	public var count: Int {
		lock.lock()
		defer { lock.unlock() }
		running.removeAll { !$0.isRunning }
		return running.count
	}

	/// Ends everything still running, politely and then not.
	///
	/// Called when the app is going, including on the way out of an uncaught
	/// exception — which is the case that left the processes behind. The wait
	/// between the two signals is short: this runs while an app is quitting,
	/// and a quit that visibly hangs is its own bug.
	public func terminateAll() {
		lock.lock()
		let processes = running
		running.removeAll()
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
	public static var tooManyMessage: String {
		"\(limit) tools are already running from images and none of them has finished. "
			+ "That usually means the container runtime has stopped answering."
	}
}
