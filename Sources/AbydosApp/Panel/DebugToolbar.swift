import AppKit
import AbydosKit

// `VariableCell` moved to `VariableCell.swift` when the popup over a value
// beside the code came to need the same row; see the note there.


final class DebugToolbar: NSView {
	var onContinue: (() -> Void)?
	var onPause: (() -> Void)?
	var onStepOver: (() -> Void)?
	var onStepInto: (() -> Void)?
	var onStepOut: (() -> Void)?
	var onStop: (() -> Void)?
	/// Start it again, once it is over — with or without the debugger.
	var onRunAgain: (() -> Void)?
	var onDebugAgain: (() -> Void)?

	/// What a button is, which decides its glyph, its name and what it does.
	private enum Kind {
		case play, pause, stepOver, stepInto, stepOut, stop
		/// Only once it is over, where Continue was: continuing a program that
		/// has ended means nothing, and starting it again is the one thing
		/// somebody standing here wants.
		case runAgain, debugAgain

		var tooltip: String {
			switch self {
			case .play: return "Continue (F9)"
			case .pause: return "Pause"
			case .stepOver: return "Step Over (F8)"
			case .stepInto: return "Step Into (F7)"
			case .stepOut: return "Step Out (\u{21E7}F8)"
			case .stop: return "Stop (\u{2318}F2)"
			case .runAgain: return "Run Again"
			case .debugAgain: return "Debug Again"
			}
		}
	}

	private struct Button {
		let rect: NSRect
		let kind: Kind
		let isEnabled: Bool
	}

	private var state: DebugSession.State = .idle
	private var exitCode: Int?
	private var buttons: [Button] = []
	private var labelOrigin: CGFloat = 0
	/// Tooltip text by the tag AppKit handed back for it.
	private var toolTipsByTag: [NSView.ToolTipTag: String] = [:]

	override var isFlipped: Bool { true }

	func update(state: DebugSession.State, exitCode: Int? = nil) {
		guard state != self.state || exitCode != self.exitCode else { return }
		self.state = state
		self.exitCode = exitCode
		rebuild()
	}

	override func layout() {
		super.layout()
		rebuild()
	}

	// MARK: - Layout

	/// Works out where the buttons are, and registers their tooltips.
	///
	/// Deliberately not done while drawing: registering a tooltip mutates
	/// tracking state, which is not something to do from inside `draw`.
	private func rebuild() {
		let isStopped: Bool
		if case .stopped = state { isStopped = true } else { isStopped = false }
		let isRunning = state == .running
		let canStop = state != .idle && state != .terminated

		let size = Theme.current.scaled(22)
		let gap = Theme.current.scaled(2)
		let y = bounds.midY - size / 2
		var x = Theme.current.scaled(10)

		func place(_ kind: Kind, enabled: Bool, extraGap: CGFloat = 0) -> Button {
			x += extraGap
			let button = Button(
				rect: NSRect(x: x, y: y, width: size, height: size), kind: kind, isEnabled: enabled
			)
			x += size + gap
			return button
		}

		// Over and done with: the stepping buttons have nothing to step, and
		// the slot they were in is where starting it again belongs.
		if !canStop {
			buttons = [
				place(.runAgain, enabled: true),
				place(.debugAgain, enabled: true),
			]
		} else {
			// Continue and pause occupy the same slot, as in every debugger.
			buttons = [
				isRunning ? place(.pause, enabled: true) : place(.play, enabled: isStopped),
				place(.stepOver, enabled: isStopped),
				place(.stepInto, enabled: isStopped),
				place(.stepOut, enabled: isStopped),
				place(.stop, enabled: canStop, extraGap: Theme.current.scaled(8)),
			]
		}
		labelOrigin = x + Theme.current.scaled(10)

		removeAllToolTips()
		toolTipsByTag = [:]
		for button in buttons {
			// Owned by the view, with the text kept here. Passing a bridged
			// string as the owner instead crashes on hover: AppKit does not
			// retain it, so by the time somebody points at the button the
			// string it reads back has been freed.
			let tag = addToolTip(button.rect, owner: self, userData: nil)
			toolTipsByTag[tag] = button.kind.tooltip
		}
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let button = buttons.first(where: { $0.isEnabled && $0.rect.contains(point) })
		else { return }

		switch button.kind {
		case .play: onContinue?()
		case .pause: onPause?()
		case .stepOver: onStepOver?()
		case .stepInto: onStepInto?()
		case .stepOut: onStepOut?()
		case .stop: onStop?()
		case .runAgain: onRunAgain?()
		case .debugAgain: onDebugAgain?()
		}
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		if buttons.isEmpty { rebuild() }

		for button in buttons {
			let colour = button.isEnabled
				? Theme.current.sidebarHeaderText
				: Theme.current.gitIgnored.withAlphaComponent(0.4)
			draw(kind: button.kind, in: button.rect, colour: colour)
		}

		let failed = state == .terminated && (exitCode ?? 0) != 0
		let label = NSAttributedString(string: statusText, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: failed ? NSColor.hex(0xE05252) : Theme.current.sidebarText,
		])
		label.draw(at: NSPoint(x: labelOrigin, y: bounds.midY - label.size().height / 2))

		guard let location, !location.isEmpty else { return }
		drawTag(location, after: labelOrigin + label.size().width)
	}

	/// The tag: a rounded chip in the colour the rest of this app uses for
	/// something running elsewhere.
	private func drawTag(_ text: String, after x: CGFloat) {
		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.sidebarBackground,
		]
		let label = NSAttributedString(string: text, attributes: attributes)
		let size = label.size()
		let padding = Theme.current.scaled(6)
		let gap = Theme.current.scaled(10)

		let chip = NSRect(
			x: x + gap,
			y: bounds.midY - (size.height + Theme.current.scaled(3)) / 2,
			width: size.width + padding * 2,
			height: size.height + Theme.current.scaled(3)
		)
		// Not drawn at all rather than clipped: a pod name cut in half is worse
		// than no tag, and the toolbar is narrow when the panel is.
		guard chip.maxX < bounds.width - Theme.current.scaled(120) else { return }

		let path = NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2)
		Theme.current.gitModified.setFill()
		path.fill()
		label.draw(at: NSPoint(x: chip.minX + padding, y: chip.midY - size.height / 2))
	}

	/// The three stepping glyphs are drawn rather than borrowed.
	///
	/// No SF Symbol says "step over": the nearest are corner arrows that read
	/// as "into" or "out" just as readily, which is no use on a row of three
	/// buttons differing only in that. Drawn, they say what every debugger has
	/// said for twenty years — an arc hopping over the call, an arrow down
	/// into it, an arrow back up out of it, with the call itself as a dot.
	private func draw(kind: Kind, in rect: NSRect, colour: NSColor) {
		let glyph = Theme.current.scaled(14)
		let box = NSRect(
			x: rect.midX - glyph / 2, y: rect.midY - glyph / 2, width: glyph, height: glyph
		)

		switch kind {
		case .play, .pause, .stop, .runAgain, .debugAgain:
			let symbol: String
			switch kind {
			case .pause: symbol = "pause.fill"
			case .stop: symbol = "stop.fill"
			case .debugAgain: symbol = "ladybug.fill"
			default: symbol = "play.fill"
			}
			Theme.symbol(symbol, size: 11 * Theme.current.scale, color: colour)?.drawFitted(in: box)

		case .stepOver:
			// Curves rather than arc angles: this view is flipped, and angles
			// measured the usual way come out mirrored in it.
			colour.setStroke()
			let arc = NSBezierPath()
			arc.lineWidth = Theme.current.scaled(1.5)
			let left = NSPoint(x: box.minX + box.width * 0.04, y: box.maxY - box.height * 0.34)
			let right = NSPoint(x: box.maxX - box.width * 0.16, y: box.maxY - box.height * 0.38)
			arc.move(to: left)
			arc.curve(
				to: right,
				controlPoint1: NSPoint(x: box.minX + box.width * 0.08, y: box.minY),
				controlPoint2: NSPoint(x: box.maxX - box.width * 0.12, y: box.minY)
			)
			arc.stroke()
			arrowhead(
				at: NSPoint(x: right.x + box.width * 0.06, y: right.y + box.height * 0.26),
				pointing: .down, size: box.width * 0.34, colour: colour
			)
			callDot(in: box, colour: colour)

		case .stepInto:
			colour.setStroke()
			let into = NSBezierPath()
			into.lineWidth = Theme.current.scaled(1.5)
			into.move(to: NSPoint(x: box.midX, y: box.minY))
			into.line(to: NSPoint(x: box.midX, y: box.midY + box.height * 0.02))
			into.stroke()
			arrowhead(
				at: NSPoint(x: box.midX, y: box.midY + box.height * 0.26),
				pointing: .down, size: box.width * 0.4, colour: colour
			)
			callDot(in: box, colour: colour)

		case .stepOut:
			colour.setStroke()
			let out = NSBezierPath()
			out.lineWidth = Theme.current.scaled(1.5)
			out.move(to: NSPoint(x: box.midX, y: box.midY + box.height * 0.18))
			out.line(to: NSPoint(x: box.midX, y: box.minY + box.height * 0.28))
			out.stroke()
			arrowhead(
				at: NSPoint(x: box.midX, y: box.minY),
				pointing: .up, size: box.width * 0.4, colour: colour
			)
			callDot(in: box, colour: colour)
		}
	}

	/// The call being stepped over, into or out of.
	private func callDot(in box: NSRect, colour: NSColor) {
		let size = box.width * 0.26
		colour.withAlphaComponent(0.8).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: box.midX - size / 2, y: box.maxY - size, width: size, height: size
		)).fill()
	}

	private enum Direction { case up, down }

	/// A filled triangle. The view is flipped, so a downward arrow's base sits
	/// at a smaller y than its tip.
	private func arrowhead(at tip: NSPoint, pointing: Direction, size: CGFloat, colour: NSColor) {
		let path = NSBezierPath()
		let half = size / 2
		let back = pointing == .down ? tip.y - size * 0.85 : tip.y + size * 0.85
		path.move(to: tip)
		path.line(to: NSPoint(x: tip.x - half, y: back))
		path.line(to: NSPoint(x: tip.x + half, y: back))
		path.close()
		colour.setFill()
		path.fill()
	}

	/// Asks for each tooltip the way AppKit does when somebody hovers.
	func toolTipsForTesting() -> [String] {
		toolTipsByTag.keys.sorted().map {
			view(self, stringForToolTip: $0, point: .zero, userData: nil)
		}
	}

	/// Draws the toolbar to a PNG, so the glyphs can be looked at.
	@discardableResult
	func writeImageForTesting(to path: String, state: DebugSession.State, exitCode: Int? = nil) -> Bool {
		// Wide enough for the tag to have somewhere to go: it is left out when
		// the toolbar is narrow, which is right in the panel and useless here.
		frame = NSRect(x: 0, y: 0, width: location == nil ? 360 : 620, height: 30)
		self.state = state
		self.exitCode = exitCode
		rebuild()
		guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return false }
		cacheDisplay(in: bounds, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
	}

	/// Where this is running, when it is not here. Drawn as a tag beside the
	/// state, because a session in a pod is otherwise indistinguishable from
	/// one on this machine — same toolbar, same stack, same variables.
	var location: String? { didSet { needsDisplay = true } }

	private var statusText: String {
		switch state {
		case .idle: return "Not running"
		case .starting: return "Starting\u{2026}"
		case .running: return "Running"
		case let .stopped(reason): return "Paused \u{2014} \(reason)"
		case .terminated:
			guard let exitCode else { return "Finished" }
			return exitCode == 0 ? "Finished — exit code 0" : "Failed — exit code \(exitCode)"
		}
	}
}

/// The toolbar on its own, for looking at.
///
/// A session in a pod cannot be conjured in a capture run — it needs a cluster
/// — so the one thing that differs is drawn directly: the state it would be in,
/// and the tag saying where.
enum DebugToolbarPreview {
	@discardableResult
	static func write(to path: String, location: String?) -> Bool {
		let toolbar = DebugToolbar()
		toolbar.location = location
		return toolbar.writeImageForTesting(
			to: path, state: .stopped(reason: "breakpoint"), exitCode: nil
		)
	}
}

extension DebugToolbar: NSViewToolTipOwner {
	func view(
		_ view: NSView,
		stringForToolTip tag: NSView.ToolTipTag,
		point: NSPoint,
		userData: UnsafeMutableRawPointer?
	) -> String {
		toolTipsByTag[tag] ?? ""
	}
}
