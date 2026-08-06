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

	func start() {
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
