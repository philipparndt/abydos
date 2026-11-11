import AppKit
import AbydosKit

/// Where every window's tmux client is, read twice a second while there is a
/// window and tmux is switched on.
///
/// A panel mirroring tmux polls its own client and learns from that when `C-b s`
/// or `C-b w` took it to a session another window is on. A panel whose tabs are
/// this app's own polled nothing, so the second window could sit on the first
/// window's session — which is the report this exists for, 2026-10-22, the two
/// windows switching each other's tmux windows — and nothing here would know.
///
/// One `list-clients` answers for every window at once. It runs with one window
/// open too: a terminal in another program — another copy of Abydos, iTerm — can
/// be on the session a window arrives at, which is the same collision.
///
/// It also keeps, for every client on the server, the last few windows it had in
/// front. A `C-b w` from one of ours into a session an outside client is on
/// moves that client too, before anything here hears of it; this history is how
/// it is put back. See `BottomPanel.moveToGroupedSession`.
@MainActor
final class TmuxClientWatch {
	private var timer: Timer?
	private var reading = false
	private let panels: () -> [BottomPanel]
	private var settingsObserver: NSObjectProtocol?

	/// What each client on the server had in front, by its terminal, newest
	/// last: only changes, and only a few.
	private(set) static var history: [String: [(session: String, windowID: String, at: Date)]] = [:]

	init(panels: @escaping () -> [BottomPanel]) {
		self.panels = panels
		// Turning tmux on with windows already open starts it, not only a
		// window opening or closing.
		settingsObserver = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.update() }
		}
	}

	/// Starts or stops with the number of windows, and the setting.
	func update() {
		let wanted = !panels().isEmpty && Settings.shared.startsTmux
		if wanted, timer == nil {
			let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated { self?.read() }
			}
			RunLoop.main.add(timer, forMode: .common)
			self.timer = timer
		} else if !wanted {
			timer?.invalidate()
			timer = nil
		}
	}

	private func read() {
		guard !reading, panels().contains(where: { $0.tmuxClientTTY != nil }) else { return }
		reading = true
		Task { @MainActor in
			defer { self.reading = false }
			let clients = await TmuxMirror.clients()
			Self.remember(clients)
			// The panels that mirror tmux ask for themselves.
			let unmirrored = self.panels().filter { $0.mirroredTmuxSession == nil && $0.tmuxClientTTY != nil }
			for panel in unmirrored {
				guard let tty = panel.tmuxClientTTY else { continue }
				// Its client has left — detached, or the terminal has: what the
				// panel knew about it is about nothing now.
				guard let client = clients.first(where: { $0.tty == tty }) else {
					panel.forgetTmuxClient()
					continue
				}
				let shared = clients.contains { $0.session == client.session && $0.tty != tty }
				await panel.clientWasRead(session: client.session, windowID: client.windowID, sharedWithAnotherClient: shared)
			}
		}
	}

	private static func remember(_ clients: [TmuxMirror.Client]) {
		let now = Date()
		for client in clients where !client.windowID.isEmpty {
			var seen = history[client.tty] ?? []
			guard seen.last?.windowID != client.windowID || seen.last?.session != client.session else { continue }
			seen.append((client.session, client.windowID, now))
			history[client.tty] = Array(seen.suffix(6))
		}
		let live = Set(clients.map(\.tty))
		history = history.filter { live.contains($0.key) }
	}

	/// The window a client had in front before `detected` could have been the
	/// moment something moved it: the newest older than a second before, the
	/// watch reading twice a second.
	static func windowBefore(_ detected: Date, forClient tty: String) -> (session: String, windowID: String)? {
		history[tty]?.last(where: { $0.at <= detected.addingTimeInterval(-1) }).map { ($0.session, $0.windowID) }
	}
}
