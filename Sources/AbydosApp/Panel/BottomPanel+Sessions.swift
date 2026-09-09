import AppKit
import AbydosKit

/// The sessions this panel holds, and the debug console among them.
extension BottomPanel {
	// MARK: - Sessions

	func showDebugConsoleForTesting() {
		showDebug()?.showConsole()
	}

	/// Brings the debug pane forward, opening an empty one if there is none.
	///
	/// **It used to answer nil**, because a pane was built only by a session
	/// starting — so the rail's ladybird with nothing running had nothing to
	/// open, and asked how to start a session instead. A pane with no session
	/// shows the breakpoints the project has, which outlive every session and
	/// until now could only be read one gutter at a time.
	@discardableResult
	func showDebug() -> DebugPane? {
		for (index, session) in sessions.enumerated() {
			if case let .debug(pane) = session.kind {
				activate(sessions[index], focus: true)
				return pane
			}
		}
		guard let root = workingDirectory else { return nil }
		return installDebugPane(session: nil, root: root, focus: true)
	}

	/// Draws the debug toolbar to a PNG, if there is one.
	@discardableResult
	func writeDebugToolbarImageForTesting(to path: String) -> Bool {
		for session in sessions {
			if case let .debug(pane) = session.kind {
				return pane.writeToolbarImageForTesting(to: path)
			}
		}
		return false
	}

	/// Exercises watches, goroutines, conditions and copying, and says what
	/// each produced.
	func exerciseDebugExtrasForTesting() {
		guard let session = activeDebugSession else {
			print("EXTRAS: no session")
			return
		}

		session.addWatch("number")
		session.addWatch("numbers")
		session.addWatch("answer * 2")
		session.addWatch("nonesuch")

		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 900_000_000)
			for watch in session.watches {
				print("WATCH: \(watch.expression) = \(watch.value ?? "nil") failed=\(watch.failed)")
			}
			print("THREADS: \(session.threads.count) goroutines, showing \(session.selectedThreadID ?? -1)")
			for thread in session.threads.prefix(4) {
				print("THREAD: \(thread.id) \(thread.name)")
			}

			// Another goroutine's stack, without moving the execution marker.
			if let other = session.threads.first(where: { $0.id != session.selectedThreadID }) {
				await session.selectThread(id: other.id)
				print("THREADS: switched to \(other.id), stack has \(session.stackFrames.count) frames")
			}

			for pane in self.debugPanesForTesting {
				print("COPY: \(pane.copyFirstVariableForTesting())")
			}
		}
	}

	var debugPanesForTesting: [DebugPane] {
		sessions.compactMap { if case let .debug(pane) = $0.kind { return pane } else { return nil } }
	}

	var debugToolTipsForTesting: [String] {
		for session in sessions {
			if case let .debug(pane) = session.kind { return pane.toolbarToolTipsForTesting }
		}
		return []
	}

	/// Whether the keyboard is in this panel.
	///
	/// Asked by ⌘T, which means "another terminal tab" while typing in one and
	/// nothing at all anywhere else — the same key doing two jobs depending on
	/// where you are is exactly what makes it feel native.
	var hasKeyboardFocus: Bool {
		guard !isHidden, let responder = window?.firstResponder as? NSView else { return false }
		return responder === self || responder.isDescendant(of: self)
	}

	/// How many sessions are open, for checking a new tab arrived.
	var sessionCountForTesting: Int { sessions.count }

	/// Both columns, with the one in front marked, so where a new terminal
	/// landed can be checked rather than photographed.
	///
	/// The two look the same from a count and from one column's strip — which
	/// is exactly how ⌘D came to open a tab where a pane beside it was asked
	/// for, and pass a check that only ever read one column.
	var columnsForTesting: String {
		let columns = Set(sessions.map(\.column)).sorted()
		return columns.map { column in
			let tabs = sessions.filter { $0.column == column }
				.map { $0 === activeSession ? "[\($0.title)]" : $0.title }
				.joined(separator: " ")
			return "col\(column): \(tabs)"
		}.joined(separator: "   ||   ")
	}

	/// Asks the terminal in front what a key with Option held would send.
	func optionKeyForTesting(bare: String, composed: String) -> String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count,
		      let terminal = sessions[index].terminal
		else { return "no terminal" }
		return terminal.terminalView.optionKeyForTesting(bare: bare, composed: composed)
	}

	/// Feeds the terminal in front a burst of frames.
	func burstForTesting(frames: Int) -> Int {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count,
		      let terminal = sessions[index].terminal
		else { return -1 }
		terminal.terminalView.burstForTesting(frames: frames)
		return frames
	}

	/// Presses keys by key code in the terminal in front.
	func deadKeyForTesting(presses: [(code: UInt16, shift: Bool)]) -> String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count,
		      let terminal = sessions[index].terminal
		else { return "no terminal" }
		return terminal.terminalView.deadKeyForTesting(presses: presses)
	}



	/// Whether the strip is a view of tmux rather than a list of terminals.
	///
	/// Only with a session to mirror and a terminal attached to it: the mode is
	/// about one shell seen two ways, and without the shell there is nothing to
	/// see.
	var mirrorsTmux: Bool {
		Settings.shared.strictTmux && Settings.shared.startsTmux && tmuxSession != nil
	}

}
