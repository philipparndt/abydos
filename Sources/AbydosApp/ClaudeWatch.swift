import AppKit
import AbydosKit

/// Claude sessions announcing themselves, from the hook to the corner of the
/// window.
///
/// The hook is a separate process that lives for a few milliseconds, so what
/// arrives here is a distributed notification. What is done with it is the
/// point: not a flash on tmux's status line that is gone before anyone looks
/// up, but a toast in the window — which stays for a few seconds, says which
/// session it is about, and takes one click to get there.
@MainActor
final class ClaudeWatch {
	/// Where to put a message about a given tmux session.
	var windows: () -> [MainWindowController] = { [] }

	private var observer: (any NSObjectProtocol)?

	/// Whether news from elsewhere on the machine belongs in this run.
	///
	/// **Not while a picture is being taken** (0451). `Scripts/screenshots.sh`
	/// pins the window size, the panel height and a fresh copy of the project,
	/// because anything remembered per machine is a picture that looks
	/// different for everybody who takes it — and a Claude session in somebody
	/// else's terminal is exactly that. Three shots for 0425 came out with
	/// `● zsh · a subagent finished` stacked over the diagram, and were taken
	/// again until the corner happened to be empty.
	///
	/// **What is dropped is news from outside the run, not toasts.** That is
	/// the whole of the difference, and it is why neither of the two answers
	/// the item started with was taken. "No toasts on a capture run" and "leave
	/// the toast layer out of the capture" both break the same thing:
	/// `--toast --screenshot` is the only way to look at a toast, and it is how
	/// the toasts being unscaled at 2x was found (see `ToastView.closeRect`).
	/// Both would have broken it *silently* — a corner photographed empty looks
	/// exactly like a corner with nothing to say. Leaving the layer out is the
	/// more expensive of the two as well, since it puts knowledge of one
	/// particular view into the capture every part of the app shares. Here,
	/// everything the run itself causes still speaks: `--toast` still fills the
	/// corner to be photographed, `--toasts` still reports it, and a shot that
	/// provokes a real error still shows what the app really says about it.
	///
	/// **Declining costs nothing.** The hook posts a *distributed* notification
	/// and every listening process gets its own copy, so the app the person is
	/// working in still says it; and this run could not have acted on it in any
	/// case — it takes the accessory activation policy, never has the keyboard,
	/// and exits when the shutter closes, so "Click to open that tab" is an
	/// offer nobody could take.
	///
	/// **The capture rather than every headless run**, which was the open
	/// question. A run that is *not* taking a picture is precisely where this
	/// path would be checked — fire the hook, then read `--toasts` — and a rule
	/// about headless runs in general would leave no way to check it at all.
	/// Whether to listen at all on this run.
	///
	/// Asks about the driving rather than about the picture: a driven run has no
	/// business subscribing to somebody's agent activity, whether or not it ends
	/// in a screenshot.
	private static var listensOnThisRun: Bool { !LaunchOptions.parse().isDrivenRun }

	func start() {
		guard Self.listensOnThisRun else { return }
		guard observer == nil else { return }
		observer = DistributedNotificationCenter.default().addObserver(
			forName: Notification.Name(ClaudeHook.notificationName),
			object: nil,
			queue: .main
		) { [weak self] note in
			MainActor.assumeIsolated {
				self?.handle(note.userInfo as? [String: String] ?? [:])
			}
		}
	}

	func handle(_ payload: [String: String]) {
		guard let line = payload["announce"], !line.isEmpty else { return }

		let session = payload["tmuxSession"]
		let index = payload["window"].flatMap(Int.init)
		let controllers = windows()

		// The window whose tabs are that tmux session gets it: it is the one
		// that can do something about it. Failing that, whichever window is in
		// front, so news from a session nobody is mirroring is not simply lost.
		let target = session.flatMap { name in
			controllers.first { $0.mirroredTmuxSession == name }
		} ?? controllers.first { $0.window?.isKeyWindow == true } ?? controllers.first
		guard let target else { return }

		// Nothing to say about the pane somebody is already looking at: they
		// can see it happen.
		if isAlreadyInView(session: session, window: index, in: target) { return }

		let canReveal = index != nil && target.mirroredTmuxSession == session
		target.notify(
			line,
			detail: payload["message"],
			kind: payload["status"] == TmuxMirror.AIStatus.needsInput.rawValue
				? .warning
				: .information,
			actionTitle: canReveal ? "Click to open that tab" : nil,
			action: canReveal ? { [weak target] in
				target?.revealTmuxWindow(index ?? 0)
			} : nil
		)
	}

	/// Whether the session that spoke is the one on screen and in front.
	///
	/// Both halves matter: a tab that is active in a window sitting behind the
	/// browser is not being looked at, and a window in front showing another
	/// tab is not showing this one.
	private func isAlreadyInView(
		session: String?,
		window index: Int?,
		in controller: MainWindowController
	) -> Bool {
		guard NSApp.isActive, controller.window?.isKeyWindow == true else { return false }
		guard let session, controller.mirroredTmuxSession == session, let index else { return false }
		return controller.activeTmuxWindow == index
	}
}
