import AppKit
import AbydosKit

/// What runs when you press play, and how it went.
///
/// Xcode's arrangement rather than IDEA's: one strip in the titlebar carrying
/// the scheme, the two buttons, and a line of status. It costs no vertical
/// space at all, which for something looked at constantly and pressed
/// occasionally is the right trade.
final class RunControl: NSView, TitlebarMenuAnchor {
	var onRun: (() -> Void)?
	var onDebug: (() -> Void)?
	var onStop: (() -> Void)?
	/// The ways of starting that are wanted now and then rather than
	/// constantly: profiling, and running with coverage. They live behind the
	/// debug button's chevron so the strip stays two buttons wide.
	var onProfile: (() -> Void)?
	var onCoverage: (() -> Void)?
	/// The other ways of starting a debug session, which used to be on the
	/// rail's ladybird — a button whose job is to show a pane, asking what to
	/// run. They belong here, beside the Debug this menu already offers.
	var onDebugExecutable: (() -> Void)?
	var onAttachToProcess: (() -> Void)?
	var onDebugGoPackage: (() -> Void)?
	/// Whether debugging a Go package is worth offering. It is not, in a project
	/// with no Go module: the rail used to start one outright and produced an
	/// error about a missing `go.mod`, which is an answer to a question nobody
	/// asked.
	var isGoProject: (() -> Bool)?
	/// Asked to show the list of configurations, at a point in this view.
	/// Asked for the configuration list, with the rect the popover should point
	/// at — the scheme well, not the whole control.
	var onChooseConfiguration: ((NSRect) -> Void)?

	/// Whether the configuration popover is open, so the well it came out of
	/// stays lit while it is. The pills have had this since they were pills; the
	/// run control needed it the moment its list stopped being an `NSMenu`,
	/// which closes on its own.
	var isMenuOpen = false {
		didSet {
			guard isMenuOpen != oldValue else { return }
			needsDisplay = true
		}
	}

	private(set) var configurationName: String?
	private var status: String = ""
	private var isBusy = false
	/// Set when the last run failed, so the line reads as bad news.
	private var failed = false
	/// A stop already asked for: pressing it again does nothing but confuse.
	private var isStopping = false
	/// The button being pressed, drawn lit for a moment.
	private var pressedRect: NSRect?

	/// Rects of the things that can be pressed, worked out while drawing.
	private var runRect: NSRect = .zero
	private var debugRect: NSRect = .zero
	/// The chevron on the debug button, which opens the other ways to start.
	private var debugMenuRect: NSRect = .zero
	private var schemeRect: NSRect = .zero
	private var toolTips: [NSView.ToolTipTag: String] = [:]
	/// Told when a run starts or ends, so the titlebar can take the colour.
	/// Told when the run state changes, so the line under the titlebar can show
	/// it. A failure is part of it: it is not a kind of busyness, but it is
	/// something the window should go on saying after the run has ended.
	var onRunStateChanged: ((TitlebarSeam.State) -> Void)?

	private var runState: TitlebarSeam.State {
		if isBusy { return isPreparing ? .preparing : .running }
		return failed ? .failed : .idle
	}

	/// Whether the busy state is a launch being arranged rather than a program
	/// running. It decides whether the seam moves; see `TitlebarSeam.State`.
	private var isPreparing = false

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// The same air on both sides of what is drawn.
	private static var margin: CGFloat { Theme.current.scaled(8) }

	override var intrinsicContentSize: NSSize {
		// Sized to its contents rather than to a fixed width: with nothing to
		// say about the last run, a fixed width leaves all the spare room on
		// the right and the strip sits off-centre in its own frame.
		NSSize(width: contentWidth, height: Theme.current.scaled(30))
	}

	/// Room kept for the message, whether or not there is one.
	///
	/// Reserved rather than added: the alternative is a strip that grows when
	/// a run finishes, which moves the button somebody was about to press. It
	/// also keeps this to one thing in the titlebar rather than two — the
	/// toolbar draws a background behind every item it is given, and two of
	/// them for one control looked like two controls.
	private static var statusWidth: CGFloat { Theme.current.scaled(230) }

	/// Everything drawn, plus a margin at each end.
	private var contentWidth: CGFloat {
		let button = Theme.current.scaled(26)
		return Self.margin
			+ button + Theme.current.scaled(4) + button + Self.chevronWidth
			+ Theme.current.scaled(10) + Theme.current.scaled(190)
			+ Theme.current.scaled(10) + Self.statusWidth
			+ Self.margin
	}

	private var statusText: NSAttributedString {
		// One line, ending in an ellipsis when there is more of it. A message
		// long enough to wrap would otherwise grow down the window, and this is
		// a strip in a titlebar; the whole message is in the tooltip, the toast
		// and the launch log.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		return NSAttributedString(string: status, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: failed ? NSColor.hex(0xE05252) : Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
	}

	/// Where the message is, and the cross that forgets it.
	private var statusRect: NSRect {
		NSRect(
			x: schemeRect.maxX + Theme.current.scaled(10),
			y: 0,
			width: Self.statusWidth,
			height: bounds.height
		)
	}

	private var clearRect: NSRect {
		let size = Theme.current.scaled(14)
		return NSRect(
			x: statusRect.maxX - size,
			y: bounds.midY - size / 2,
			width: size,
			height: size
		)
	}

	/// What the strip is showing, for tests.
	var selectedNameForTesting: String? { configurationName }

	func setConfiguration(_ name: String?) {
		guard name != configurationName else { return }
		configurationName = name
		needsDisplay = true
		rebuildToolTips()
	}

	/// What to say about the last or current run.
	func setStatus(
		_ text: String, busy: Bool = false, failed: Bool = false, preparing: Bool = false
	) {
		// One line, whatever it was given: this is a strip in a titlebar, and a
		// message with newlines in it turns into a paragraph across the window.
		let text = text.replacingOccurrences(of: "\n", with: " ")
			.trimmingCharacters(in: .whitespaces)
		guard text != status || busy != isBusy || failed != self.failed
			|| preparing != isPreparing
		else { return }
		let wasBusy = isBusy
		let wasState = runState
		status = text
		if !busy { isStopping = false }
		rebuildToolTips()
		isBusy = busy
		// Only meaningful while busy: a failure or an idle strip has nothing to
		// be preparing, and leaving it set would move the seam over a finished run.
		isPreparing = busy && preparing
		self.failed = failed
		needsDisplay = true
		// The run button is a stop button while busy, and says so.
		if wasBusy != busy {
			rebuildToolTips()
		}
		if wasState != runState {
			onRunStateChanged?(runState)
		}
	}

	/// Re-measures at the theme's scale.
	func applyThemeChange() {
		invalidateIntrinsicContentSize()
		layoutParts()
		rebuildToolTips()
		needsDisplay = true
	}

	// MARK: - Layout

	private func layoutParts() {
		let height = bounds.height
		let button = Theme.current.scaled(26)
		let y = (height - button) / 2

		runRect = NSRect(x: Self.margin, y: y, width: button, height: button)
		debugRect = NSRect(x: runRect.maxX + Theme.current.scaled(4), y: y, width: button, height: button)
		// Narrow, and part of the same shape: a chevron beside the ladybird
		// reads as "and the other ways", not as a third button.
		debugMenuRect = NSRect(
			x: debugRect.maxX, y: y, width: Self.chevronWidth, height: button
		)

		let schemeStart = debugMenuRect.maxX + Theme.current.scaled(10)
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
		toolTips[addToolTip(debugMenuRect, owner: self, userData: nil)] = "Profile, coverage…"
		toolTips[addToolTip(schemeRect, owner: self, userData: nil)] = "Choose what to run"
		if !status.isEmpty {
			toolTips[addToolTip(statusRect, owner: self, userData: nil)] = status
		}
	}

	override func layout() {
		super.layout()
		rebuildToolTips()
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		layoutParts()

		if !status.isEmpty, clearRect.insetBy(dx: -4, dy: -4).contains(point) {
			setStatus("")
		} else if runRect.contains(point) {
			// Said before anything is done. Starting a program means building
			// it, and stopping one in a cluster means asking a pod on the other
			// side of a network — both take long enough that a button which
			// says nothing looks like a button that missed the click.
			if isBusy {
				guard !isStopping else { return }
				isStopping = true
				// The titlebar's colour answers the click straight away, while
				// the button goes on saying "stop" until the program has
				// actually stopped. Starting means building, and stopping in a
				// cluster means asking a pod on the other side of a network:
				// both are long enough that silence reads as a missed click.
				onRunStateChanged?(.idle)
				setStatus("Stopping\u{2026}", busy: true)
				onStop?()
			} else {
				press(runRect)
				onRunStateChanged?(.running)
				setStatus("Starting\u{2026}", busy: true)
				onRun?()
			}
		} else if debugMenuRect.contains(point) {
			showStartMenu()
		} else if debugRect.contains(point) {
			press(debugRect)
			onRunStateChanged?(.running)
			setStatus("Starting\u{2026}", busy: true)
			onDebug?()
		} else if schemeRect.contains(point) {
			onChooseConfiguration?(schemeRect)
		}
	}

	/// Lights a button for a moment, so a press is visible even when what it
	/// starts takes a while to say anything.
	private func press(_ rect: NSRect) {
		pressedRect = rect
		needsDisplay = true
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
			self?.pressedRect = nil
			self?.needsDisplay = true
		}
	}

	private static var chevronWidth: CGFloat { Theme.current.scaled(14) }

	/// The ways of starting that are not one of the two buttons.
	private func showStartMenu() {
		let menu = NSMenu()
		menu.addItem(withTitle: "Debug", action: #selector(debugFromMenu), keyEquivalent: "")
		// Go first where the project is Go, since that is then the likely one.
		if isGoProject?() == true {
			menu.addItem(
				withTitle: "Debug Go Package", action: #selector(debugGoFromMenu), keyEquivalent: ""
			)
		}
		menu.addItem(
			withTitle: "Debug Executable\u{2026}", action: #selector(debugExecutableFromMenu),
			keyEquivalent: ""
		)
		menu.addItem(
			withTitle: "Attach to Process\u{2026}", action: #selector(attachFromMenu), keyEquivalent: ""
		)
		menu.addItem(.separator())
		menu.addItem(withTitle: "Profile", action: #selector(profileFromMenu), keyEquivalent: "")
		menu.addItem(
			withTitle: "Run with Coverage", action: #selector(coverageFromMenu), keyEquivalent: ""
		)
		for item in menu.items { item.target = self }

		menu.popUp(
			positioning: nil,
			at: NSPoint(x: debugRect.minX, y: debugRect.maxY + Theme.current.scaled(4)),
			in: self
		)
	}

	@objc private func debugFromMenu() { onDebug?() }
	@objc private func debugGoFromMenu() { onDebugGoPackage?() }
	@objc private func debugExecutableFromMenu() { onDebugExecutable?() }
	@objc private func attachFromMenu() { onAttachToProcess?() }
	@objc private func profileFromMenu() { onProfile?() }
	@objc private func coverageFromMenu() { onCoverage?() }

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		layoutParts()

		// Nothing is drawn for "running": the titlebar behind the whole strip
		// takes the colour instead, which is one flat area rather than a shape
		// sitting on top of another shape.

		// Stop replaces run while something is running, as it does everywhere:
		// the two are the same question asked at different moments.
		if let pressedRect {
			let path = NSBezierPath(
				roundedRect: pressedRect.insetBy(dx: Theme.current.scaled(1), dy: Theme.current.scaled(1)),
				xRadius: Theme.current.scaled(6),
				yRadius: Theme.current.scaled(6)
			)
			NSColor.white.withAlphaComponent(0.14).setFill()
			path.fill()
		}

		drawButton(
			in: runRect,
			symbol: isBusy ? "stop.fill" : "play.fill",
			tint: isBusy
				? .hex(isStopping ? 0x9A6060 : 0xE05252)
				: Theme.current.gitAdded
		)
		drawButton(in: debugRect, symbol: "ladybug.fill", tint: Theme.current.gitModified)
		if let chevron = Theme.symbol(
			"chevron.down", size: 7 * Theme.current.scale, color: Theme.current.gitIgnored
		) {
			let size = Theme.current.scaled(8)
			chevron.drawFitted(in: NSRect(
				x: debugMenuRect.midX - size / 2 - Theme.current.scaled(1),
				y: debugMenuRect.midY - size / 2,
				width: size,
				height: size
			))
		}

		// The scheme, in a well of its own so it reads as something to press.
		let well = NSBezierPath(roundedRect: schemeRect, xRadius: 5, yRadius: 5)
		NSColor.white.withAlphaComponent(isMenuOpen ? 0.14 : 0.06).setFill()
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

		drawStatus()

		if let chevron = Theme.symbol("chevron.down", size: 8 * Theme.current.scale, color: Theme.current.gitIgnored) {
			let size = Theme.current.scaled(9)
			chevron.drawFitted(in: NSRect(
				x: schemeRect.maxX - size - Theme.current.scaled(7),
				y: schemeRect.midY - size / 2,
				width: size,
				height: size
			))
		}

	}

	/// The message, and a way to be rid of it.
	private func drawStatus() {
		guard !status.isEmpty else { return }
		let text = statusText
		let size = text.size()
		let area = statusRect

		text.draw(in: NSRect(
			x: area.minX,
			y: area.midY - size.height / 2,
			width: max(0, area.width - Theme.current.scaled(18)),
			height: size.height
		))

		Theme.symbol(
			"xmark", size: 8 * Theme.current.scale, color: Theme.current.gitIgnored.withAlphaComponent(0.8)
		)?.drawFitted(in: clearRect.insetBy(dx: Theme.current.scaled(3), dy: Theme.current.scaled(3)))
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
