import AppKit
import IdeaiKit

/// What runs when you press play, and how it went.
///
/// Xcode's arrangement rather than IDEA's: one strip in the titlebar carrying
/// the scheme, the two buttons, and a line of status. It costs no vertical
/// space at all, which for something looked at constantly and pressed
/// occasionally is the right trade.
final class RunControl: NSView {
	var onRun: (() -> Void)?
	var onDebug: (() -> Void)?
	var onStop: (() -> Void)?
	/// Asked to show the list of configurations, at a point in this view.
	var onChooseConfiguration: ((NSPoint) -> Void)?

	private(set) var configurationName: String?
	private var status: String = ""
	private var isBusy = false
	/// Set when the last run failed, so the line reads as bad news.
	private var failed = false

	/// Rects of the things that can be pressed, worked out while drawing.
	private var runRect: NSRect = .zero
	private var debugRect: NSRect = .zero
	private var schemeRect: NSRect = .zero
	private var toolTips: [NSView.ToolTipTag: String] = [:]
	/// Told when a run starts or ends, so the titlebar can take the colour.
	var onBusyChanged: ((Bool) -> Void)?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var intrinsicContentSize: NSSize {
		NSSize(width: 420, height: Theme.current.scaled(30))
	}

	func setConfiguration(_ name: String?) {
		guard name != configurationName else { return }
		configurationName = name
		needsDisplay = true
		rebuildToolTips()
	}

	/// What to say about the last or current run.
	func setStatus(_ text: String, busy: Bool = false, failed: Bool = false) {
		guard text != status || busy != isBusy || failed != self.failed else { return }
		let wasBusy = isBusy
		status = text
		isBusy = busy
		self.failed = failed
		needsDisplay = true
		// The run button is a stop button while busy, and says so.
		if wasBusy != busy {
			rebuildToolTips()
			onBusyChanged?(busy)
		}
	}

	// MARK: - Layout

	private func layoutParts() {
		let height = bounds.height
		let button = Theme.current.scaled(26)
		let y = (height - button) / 2

		runRect = NSRect(x: Theme.current.scaled(2), y: y, width: button, height: button)
		debugRect = NSRect(x: runRect.maxX + Theme.current.scaled(4), y: y, width: button, height: button)

		let schemeStart = debugRect.maxX + Theme.current.scaled(10)
		schemeRect = NSRect(
			x: schemeStart,
			y: (height - Theme.current.scaled(20)) / 2,
			width: Theme.current.scaled(190),
			height: Theme.current.scaled(20)
		)
	}

	private func rebuildToolTips() {
		removeAllToolTips()
		toolTips = [:]
		layoutParts()
		toolTips[addToolTip(runRect, owner: self, userData: nil)] = isBusy ? "Stop" : "Run (⌃R)"
		toolTips[addToolTip(debugRect, owner: self, userData: nil)] = "Debug (⌃D)"
		toolTips[addToolTip(schemeRect, owner: self, userData: nil)] = "Choose what to run"
	}

	override func layout() {
		super.layout()
		rebuildToolTips()
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		layoutParts()

		if runRect.contains(point) {
			isBusy ? onStop?() : onRun?()
		} else if debugRect.contains(point) {
			onDebug?()
		} else if schemeRect.contains(point) {
			onChooseConfiguration?(NSPoint(x: schemeRect.minX, y: schemeRect.maxY))
		}
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		layoutParts()

		// Nothing is drawn for "running": the titlebar behind the whole strip
		// takes the colour instead, which is one flat area rather than a shape
		// sitting on top of another shape.

		// Stop replaces run while something is running, as it does everywhere:
		// the two are the same question asked at different moments.
		drawButton(
			in: runRect,
			symbol: isBusy ? "stop.fill" : "play.fill",
			tint: isBusy ? .hex(0xE05252) : Theme.current.gitAdded
		)
		drawButton(in: debugRect, symbol: "ladybug.fill", tint: Theme.current.gitModified)

		// The scheme, in a well of its own so it reads as something to press.
		let well = NSBezierPath(roundedRect: schemeRect, xRadius: 5, yRadius: 5)
		NSColor.white.withAlphaComponent(0.06).setFill()
		well.fill()

		let name = configurationName ?? "No configuration"
		let label = NSAttributedString(string: name, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: configurationName == nil
				? Theme.current.gitIgnored
				: Theme.current.sidebarText,
		])
		label.draw(in: NSRect(
			x: schemeRect.minX + Theme.current.scaled(8),
			y: schemeRect.midY - label.size().height / 2,
			width: schemeRect.width - Theme.current.scaled(24),
			height: label.size().height
		))

		if let chevron = Theme.symbol("chevron.down", size: 8 * Theme.current.scale, color: Theme.current.gitIgnored) {
			let size = Theme.current.scaled(9)
			chevron.drawFitted(in: NSRect(
				x: schemeRect.maxX - size - Theme.current.scaled(7),
				y: schemeRect.midY - size / 2,
				width: size,
				height: size
			))
		}

		guard !status.isEmpty else { return }
		let statusText = NSAttributedString(string: status, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: failed ? NSColor.hex(0xE05252) : Theme.current.gitIgnored,
		])
		let x = schemeRect.maxX + Theme.current.scaled(12)
		statusText.draw(in: NSRect(
			x: x,
			y: bounds.midY - statusText.size().height / 2,
			width: max(0, bounds.width - x),
			height: statusText.size().height
		))
	}

	private func drawButton(in rect: NSRect, symbol: String, tint: NSColor) {
		let size = Theme.current.scaled(15)
		Theme.symbol(symbol, size: 14 * Theme.current.scale, color: tint)?.drawFitted(in: NSRect(
			x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size
		))
	}
}

extension RunControl: NSViewToolTipOwner {
	func view(
		_ view: NSView,
		stringForToolTip tag: NSView.ToolTipTag,
		point: NSPoint,
		userData: UnsafeMutableRawPointer?
	) -> String {
		toolTips[tag] ?? ""
	}
}
