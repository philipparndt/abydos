import AppKit
import AbydosKit

/// A terminal tab that is open before there is a shell to put in it.
///
/// Opening a project's devcontainer can take minutes the first time: an image
/// is pulled or a Dockerfile is built, and then `onCreateCommand`,
/// `updateContentCommand` and `postCreateCommand` run. All of that used to
/// happen with nothing in the pane and the shell appearing when it was over,
/// which from the outside is indistinguishable from the app having hung.
///
/// So the tab opens at once and the work is written into it — and then the same
/// pane *becomes* the shell. One tab throughout, and the honest way round: the
/// pane is a terminal, so the progress goes into the terminal the shell will
/// use, the scrollback keeps what happened, and the prompt follows it. A
/// separate log view swapped for a terminal would have thrown that away at the
/// moment it became worth reading.
///
/// **A failure is not swept away.** Nothing is cleared, no shell is started
/// into a container that never came up, and the sentence saying which command
/// failed is the last thing in the pane.
///
/// **The tab can be closed part-way**, which is somebody changing their mind
/// about a five-minute pull. What is under way is not cancelled — the container
/// belongs to the project rather than to this tab, and the language servers
/// commonly wait on the very same start — so instead the reporting moves: steps
/// and the outcome become toasts, the way they were before there was a pane,
/// and the commands' own output goes on going to
/// `~/Library/Logs/Abydos/devcontainer.log`. Nothing is left running with
/// nowhere to say what happened to it.
@MainActor
final class PreparingTerminal {
	/// The pane, while it is still open. Weak, so a window closed under this
	/// takes the pane with it and leaves nothing to write into.
	private weak var pane: TerminalPane?
	/// Set when the tab is closed, which a weak reference alone cannot say
	/// soon enough: a closed pane is alive until the last thing lets go of it.
	private var wasClosed = false
	/// What to say in a toast instead, once there is no pane. The project's name
	/// is the only context a toast has.
	private let subject: String

	init(pane: TerminalPane, subject: String) {
		self.pane = pane
		self.subject = subject
	}

	/// Whether there is still a pane to write into.
	var isOpen: Bool { !wasClosed && pane != nil }

	/// Told by the panel when the tab is closed.
	func paneWasClosed() { wasClosed = true }

	// MARK: - Saying what is happening

	/// A step: one sentence naming what is starting now.
	///
	/// Set apart from the output around it so the shape of the thing is
	/// readable — the steps are the outline and everything between two of them
	/// is one command talking.
	func step(_ text: String) {
		guard let pane, isOpen else {
			Toast.post(text, kind: .information)
			return
		}
		pane.write("\u{1B}[1;36m\(text)\u{1B}[0m\r\n")
	}

	/// What a command printed, exactly as it printed it.
	func output(_ text: String) {
		// Not a toast when the tab has gone: this is a `docker pull`'s layers and
		// ten minutes of `npm ci`, and the log is where that belongs. The
		// lifecycle commands write every line of theirs to devcontainer.log
		// whether or not anybody is watching.
		guard let pane, isOpen else { return }
		pane.write(text)
	}

	/// It worked: this pane is now that shell.
	func becomeShell(running command: (executable: String, arguments: [String])) {
		guard let pane, isOpen else {
			// Not a failure and worth saying: what was asked for is up, and the
			// next terminal in it opens at once.
			Toast.post(
				"\(subject)'s devcontainer is ready",
				detail: "The tab was closed while it was starting. Opening a terminal in it now "
					+ "is instant.",
				kind: .information
			)
			return
		}
		pane.write("\u{1B}[1;32mThe devcontainer is up. This tab is now a shell inside it.\u{1B}[0m\r\n")
		pane.startProcess(command)
		// Only when this tab is the one on screen. A pull can take minutes,
		// somebody who went to another tab meanwhile is typing in it, and taking
		// the keyboard off them for a prompt they are not looking at is worse
		// than making them click.
		if pane.window != nil { pane.focus() }
	}

	/// It did not work, and the pane keeps every word of why.
	func refuse(_ sentence: String) {
		guard let pane, isOpen else {
			Toast.post("\(subject)'s devcontainer was not started", detail: sentence, kind: .error)
			return
		}
		// Red, and last. Nothing is started and nothing is cleared: what the
		// build or the command said is above this line, which is the only place
		// the reason actually is.
		pane.write("\r\n\u{1B}[1;31m\(sentence)\u{1B}[0m\r\n")
	}

	/// The two sinks, wired to this pane, for whatever is being got ready.
	///
	/// Both hop to the main thread through the main *queue* rather than through
	/// a task: these arrive in an order that means something — a step, then what
	/// that step printed — and unstructured tasks hopping to the main actor are
	/// not promised to run in the order they were made.
	var progress: DevContainers.Progress {
		DevContainers.Progress(
			step: { [weak self] message in
				DispatchQueue.main.async { MainActor.assumeIsolated { self?.step(message) } }
			},
			output: { [weak self] text in
				DispatchQueue.main.async { MainActor.assumeIsolated { self?.output(text) } }
			}
		)
	}
}
