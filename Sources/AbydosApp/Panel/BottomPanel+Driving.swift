import AppKit
import AbydosKit

/// The verbs that drive the bottom panel from the command line.
///
/// They sat on `MainWindowController` because that is where the launch flag
/// arrives. Each of them reaches only into the panel, and each had to be handed
/// the panel to do it — which is how a driving surface comes to be the reason a
/// window controller cannot make anything private.
///
/// The ones still on the window are the ones that also have to *show* the panel
/// first: `setPanelVisible` is the window's, being about the split it lives in,
/// and those verbs follow it rather than reaching back for it.
extension BottomPanel {
	/// What the panel's tab strip is showing and what it is holding back.
	var panelOverflowReportForTesting: String { overflowReportForTesting }

	/// Chooses one of the tabs the strip had no room for, as its menu entry
	/// would — so that the run moving to bring it into view can be looked at.
	func selectHiddenPanelTabForTesting(_ position: Int) -> String {
		selectHiddenTabForTesting(position)
	}

	func addTerminalTabForTesting() {
		addTabForTesting()
	}

	func clickPanelTabAndReportForTesting(_ index: Int) -> String {
		let said = clickPanelTabForTesting(index)
		// Where the keyboard landed, which is the whole of what reaching for a
		// pane means: a tree nobody can walk is a tree nobody selected.
		return said + " | " + variablesKeyboardReportForTesting()
	}

	/// Brings a tmux window forward, as clicking its tab would.
	/// Presses ⌃C in the debugger's console, for `--debug-interrupt`.
	func pressDebugInterruptForTesting() -> String {
		activeDebugPane?.pressInterruptForTesting() ?? "no debug session"
	}

	/// Puts the pointer on the ✕ of every tab of every strip in the window and
	/// says what each strip made of it, then photographs the window with the
	/// first ✕ of each hovered and again with the pointer off them all.
	///
	/// The strips are found by walking the window rather than asked of the editor
	/// and the panel in turn. What is being checked is that the two agree, and one
	/// walk both puts them in the same picture and picks up a third strip if
	/// somebody adds one — which is how this went wrong in the first place: the
	/// editor's strip grew a hover and the panel's was somewhere else.
	func tabCloseHoverForTesting(to path: String) {
		guard let window else { return }
		seedUnclosableTabForTesting()
		window.contentView?.layoutSubtreeIfNeeded()
		let strips = Self.tabStrips(under: window.contentView)

		print("HOVER: \(strips.count) strips")
		// Every tab, not only the first: the one that must *not* light up is a
		// tmux window, and tmux's windows are never at the front of a strip.
		for strip in strips {
			for index in 0..<max(strip.tabCountForTesting, 1) {
				print("  on  \(strip.hoverCloseForTesting(index))")
			}
			strip.hoverCloseForTesting(0)
		}
		WindowCapture.write(window: window, to: path)

		for strip in strips { print("  off \(strip.hoverCloseForTesting(nil))") }
		WindowCapture.write(
			window: window, to: (path as NSString).deletingPathExtension + "-left.png"
		)
		fflush(stdout)
	}

	/// The geometry every board card is drawn with, for `--card-report`.
	func cardGeometryForTesting() -> String {
		existingBacklogPane?.cardGeometryReportForTesting ?? "no pane"
	}

	/// What the + and its chevron answer to, for the harness.
	var terminalAddControlsForTesting: String { addControlsForTesting }

	/// Types into the terminal at a human rate and reports what each keystroke
	/// cost, so "it feels slower" can be answered with numbers.
	func measureTypingForTesting(presses: Int, interval: TimeInterval) {
		guard let terminal = showTerminal()?.terminalView else { return }
		window?.makeFirstResponder(terminal)
		let letters = Array("abcdefghijklmnopqrstuvwxyz")
		for press in 0..<presses {
			DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(press)) {
				self.window?.makeFirstResponder(terminal)
				terminal.typeForTesting(String(letters[press % letters.count]))
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(presses) + 0.5) {
			InputProbe.report()
		}
	}

	/// Right-clicks the tmux status line and then moves the pointer up through
	/// the menu it opens, which is the gesture that was dead.
	func tmuxMenuForTesting(hovers: Int) {
		let grid = terminalGridForTesting
		guard grid.rows > 4 else { return }
		// The window tab, not the session name: `[menu]  [0:zsh]` — the tab is
		// what has a menu bound to it. Held down, because a tmux menu is a
		// press-drag-release affair.
		terminalMenuDragForTesting(
			from: (row: grid.rows, column: 12),
			over: (0..<max(1, hovers)).map { (row: grid.rows - 2 - $0, column: 14) }
		)
	}

	/// The panel's own layout, beside the terminal's grid.
	///
	/// Where the tab strip sits inside the panel is not visible in any of the
	/// numbers above, and it is what a band above the tabs is made of.
	func panelGeometryForTesting() -> String {
		stripGeometryForTesting()
	}

	/// Where the terminal in front says it is — the answer the window follows.
	func terminalDirectoryForTesting() -> URL? {
		activeTerminalDirectoryForTesting()
	}

	func echoDebugOutputForTesting() {
		debugOutput = { text in
			FileHandle.standardError.write(Data("[debug] \(text)".utf8))
		}
	}

	var terminalSessionCountForTesting: Int { sessionCountForTesting }

	/// Turns the engine setting on and opens a terminal, so a pane older than
	/// the change sits beside one younger — for `--engine-switch`.
	func switchEngineForTesting() {
		Settings.shared.terminalGhosttyEngine = true
		print("ENGINE: setting on, opening a pane")
		newTerminal()
		fflush(stdout)
	}

	/// Which panes say they were drawn by the other engine, for `--engines`.
	func reportEnginesForTesting() {
		print("ENGINES:\n\(engineMarksForTesting())")
		fflush(stdout)
	}

	/// Walks the panel's variables tree with the keyboard, and reads it twice.
	///
	/// **The second read is the point.** → on a row the adapter has not been
	/// asked about returns before its children exist; the tree is rebuilt when
	/// the answer arrives, and that rebuild is what used to leave nothing
	/// selected. A report printed on the same turn as the key press cannot see
	/// it, which is how the bug came back after being called fixed.
	func walkThePaneForTesting() {
		print("VALUE panel: \(variablesKeyboardReportForTesting())")
		print("VALUE panel clicked: \(clickVariablesForTesting())")
		print("VALUE panel down: \(walkVariablesForTesting(["down"]))")
		// Past the leaf and onto a row with something under it: → on a leaf
		// asks the adapter for nothing, so it cannot rebuild anything and the
		// bug cannot show. `openable=` in the report says which kind of row
		// this landed on.
		print("VALUE panel on a container: \(walkVariablesForTesting(["down"]))")
		print("VALUE panel right: \(walkVariablesForTesting(["right"]))")
		fflush(stdout)
		walkVariablesThenSettleForTesting([]) { [weak self] after in
			print("VALUE panel right, once its children arrived: \(after)")
			print("VALUE panel after: \(self?.variablesKeyboardReportForTesting() ?? "gone")")
			print("VALUE panel selection: \(self?.variablesSelectionColourForTesting() ?? "gone")")
			fflush(stdout)
		}
	}

	/// Every tab strip under a view, wherever it has been nested.
	///
	/// It was a private helper on the window controller and only this verb ever
	/// called it, so it came here rather than staying behind as the last reason
	/// to look there.
	private static func tabStrips(under view: NSView?) -> [any TabCloseHovering] {
		guard let view else { return [] }
		let here = view as? (any TabCloseHovering)
		return (here.map { [$0] } ?? []) + view.subviews.flatMap { tabStrips(under: $0) }
	}
}
