import Foundation

/// Whether git can run on this machine at all, and what to say when it cannot.
///
/// `/usr/bin/git` is not git. It is Apple's shim, which finds the active
/// developer directory and runs the git inside it — and when it cannot,
/// because Xcode's licence has not been accepted or no developer tools are
/// installed, it prints why to stderr and **exits 0** with nothing on stdout.
/// Measured 2026-09-15, the morning after an Xcode update:
///
///     $ /usr/bin/git --version >/dev/null 2>&1; echo $?
///     0
///
/// So every git call in this application looked like a success with an empty
/// answer. The remote lookup that trust by host relies on found no remote and
/// every project asked to be trusted again; the git pane read an empty
/// repository; and nothing said why. This is the one place that reads what the
/// shim said, and the one fact the window's strip is drawn from.
///
/// Every call is a probe. A check at launch would say "fine" for the rest of
/// the day after an Xcode update while the app was open; `GitRepository.run`
/// notes every result it returns instead, so the strip goes up on the first
/// refusal and comes down on the first success.
public final class GitAvailability: @unchecked Sendable {
	/// Why the shim would not run git. The raw value is what `--git-unavailable`
	/// names on the command line.
	public enum Cause: String, Equatable, Sendable, CaseIterable {
		case licenceNotAccepted = "licence"
		case developerToolsMissing = "tools"

		/// The one line the strip reads.
		public var sentence: String {
			switch self {
			case .licenceNotAccepted: "git cannot run: Xcode's licence has not been accepted."
			case .developerToolsMissing: "git cannot run: no developer tools are installed."
			}
		}

		/// The command a person types once to fix it, offered beside the sentence.
		public var command: String {
			switch self {
			case .licenceNotAccepted: "sudo xcodebuild -license accept"
			case .developerToolsMissing: "xcode-select --install"
			}
		}

		/// What the shim says, as it says it. Two strings, held here and
		/// nowhere else, with the tests that pin them.
		fileprivate var markers: [String] {
			switch self {
			case .licenceNotAccepted: ["You have not agreed to the Xcode license"]
			case .developerToolsMissing: ["invalid active developer path", "No developer tools were found"]
			}
		}
	}

	public static let shared = GitAvailability()

	private let lock = NSLock()
	private var storedCause: Cause?
	private var observers: [(Cause?) -> Void] = []

	/// A cause a driven run insists on, so the strip can be shown and read on
	/// a machine whose git is fine. Wins over anything git says.
	public var forcedCause: Cause? {
		get { lock.withLock { stored_forced } }
		set { lock.withLock { stored_forced = newValue } }
	}
	private var stored_forced: Cause?

	public init() {}

	/// Why git cannot run, or nil while it can.
	public var cause: Cause? {
		lock.withLock { stored_forced ?? storedCause }
	}

	public var isRunning: Bool { cause == nil }

	/// The shim's refusal in a result, or nil for anything git itself said —
	/// a `fatal:` at exit 128 included, which is git running and disagreeing.
	public static func classify(_ result: GitRepository.ProcessResult) -> Cause? {
		for cause in Cause.allCases where cause.markers.contains(where: { result.stderr.contains($0) }) {
			return cause
		}
		return nil
	}

	/// Told of every result git gave; tells the observers only when the
	/// answer changes, on the main queue, since what they do is draw.
	public func note(_ result: GitRepository.ProcessResult) {
		let cause = Self.classify(result)
		let changed: Bool = lock.withLock {
			guard storedCause != cause else { return false }
			storedCause = cause
			return true
		}
		guard changed else { return }
		let now = self.cause
		let observers = lock.withLock { self.observers }
		DispatchQueue.main.async { for observer in observers { observer(now) } }
	}

	/// Called when the answer changes, with the cause or nil for running again.
	public func observe(_ handler: @escaping (Cause?) -> Void) {
		lock.withLock { observers.append(handler) }
	}

	/// One `git --version`, for when the app comes back to the front while the
	/// strip is up: the person fixing this is in a terminal, and switching back
	/// is the moment they want the answer. The result notes itself.
	@discardableResult
	public func recheck() async -> Bool {
		_ = await GitRepository.run(["--version"], in: URL(fileURLWithPath: "/"))
		return isRunning
	}
}
