import AppKit
import AbydosKit

/// The views the debug pane's two lists are drawn with: the outline that holds
/// the variables, and the cells for a stack frame and a scope heading.
final class PlaceholderNode {}

/// The variables tree, which takes the keyboard when it is clicked.
///
/// **Reported from use: clicking a row did not give the tree the keyboard**, so
/// the arrows that an outline view answers by itself — ↑↓ to walk, → to open a
/// row, ← to close it — went to whatever had the keyboard instead, and reading
/// a frame stayed a job for the mouse. A click is the ordinary way somebody
/// says which of a window's panes they mean, and this is the pane that has to
/// hear it: the panel hands the keyboard to a terminal when it activates one,
/// and nothing was ever handing it here.
///
/// The tree already knew what to do with the keys. It only never got them.
final class VariablesOutlineView: NSOutlineView {
	override var acceptsFirstResponder: Bool { true }

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		super.mouseDown(with: event)
	}

	/// What this view says about taking the keyboard, for a driver to print.
	var focusReportForTesting: String {
		"accepts=\(acceptsFirstResponder) refuses=\(refusesFirstResponder)"
			+ " has it=\(window?.firstResponder === self)"
	}
}

// MARK: - Cells

final class StackFrameCell: NSView {
	// Named `stackFrame`, since `frame` is NSView's own.
	private let stackFrame: StackFrame
	private let projectRoot: URL

	init(stackFrame: StackFrame, projectRoot: URL) {
		self.stackFrame = stackFrame
		self.projectRoot = projectRoot
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let inset = Theme.current.scaled(10)

		let name = NSAttributedString(string: stackFrame.name, attributes: [
			.font: Theme.current.uiFont(11.5, weight: .medium),
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : Theme.current.sidebarHeaderText,
		])
		name.draw(in: NSRect(
			x: inset, y: Theme.current.scaled(4),
			width: max(0, bounds.width - inset * 2), height: Theme.current.scaled(14)
		))

		guard let file = stackFrame.file else { return }
		// Paths are shown relative to the project; absolute ones are unreadable
		// in a narrow pane and mostly identical prefix.
		//
		// Canonical on both sides: the frame's path comes from the debug
		// adapter, which answers with the real one, and the project root is
		// whatever the project was opened by. Under `/tmp` or `/var` — symlinks,
		// both — the two shared no prefix, every frame fell to its last
		// component, and two `main.go`s in different packages were drawn as the
		// same line. Same asymmetry as 0430.
		let path = FilePath.canonical(file)
		let base = FilePath.canonical(projectRoot)
		var display = path
		if path.hasPrefix(base + "/") {
			display = String(path.dropFirst(base.count + 1))
		} else {
			display = (path as NSString).lastPathComponent
		}

		let location = NSAttributedString(string: "\(display):\(stackFrame.line)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.uiFont(10).pointSize),
			.foregroundColor: isSelected ? NSColor.hex(0xC8CBD0) : Theme.current.gitIgnored,
		])
		location.draw(in: NSRect(
			x: inset, y: Theme.current.scaled(18),
			width: max(0, bounds.width - inset * 2), height: Theme.current.scaled(13)
		))
	}
}

final class ScopeCell: NSView {
	private let name: String

	init(name: String) {
		self.name = name
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let label = NSAttributedString(string: name.uppercased(), attributes: [
			.font: Theme.current.uiFont(10, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		label.draw(at: NSPoint(x: 0, y: bounds.midY - label.size().height / 2))
	}
}
