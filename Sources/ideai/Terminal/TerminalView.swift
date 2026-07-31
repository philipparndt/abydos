import AppKit
import IdeaiKit

/// Renders a `TerminalEmulator`'s grid and forwards input to its process.
///
/// Same virtualisation principle as the code view: only the rows in the
/// viewport are drawn, and cells are batched into runs of identical attributes
/// so a full-colour screen costs a handful of draw calls rather than one per
/// character.
final class TerminalView: NSView, NSTextInputClient {
	private let emulator: TerminalEmulator
	private let pty: PseudoTerminal

	/// Fired when the process exits, so the panel can label the tab.
	var onProcessExit: ((Int32) -> Void)?
	var onTitleChange: ((String) -> Void)?

	private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	private var cellWidth: CGFloat = 7
	private var cellHeight: CGFloat = 16
	private var baselineOffset: CGFloat = 4

	/// Follows output unless the user scrolls up to read history.
	private var isPinnedToBottom = true

	private var cursorVisible = true
	private var cursorTimer: Timer?

	private static let horizontalInset: CGFloat = 8
	private static let verticalInset: CGFloat = 4

	/// Coalesces repaints to one per runloop turn.
	///
	/// A full-screen program repaints by emitting many small writes; redrawing on
	/// each one both wastes work and visibly tears, because the screen is
	/// composited mid-update. Batching to a single pass per turn is what removes
	/// the flicker.
	private var redrawScheduled = false

	// MARK: - Init

	init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		emulator = TerminalEmulator(rows: 24, columns: 80)
		pty = PseudoTerminal()
		super.init(frame: .zero)

		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()

		emulator.onUpdate = { [weak self] in
			self?.scheduleRedraw()
		}
		// Replies such as the cursor-position report must go back to the process,
		// otherwise shells that ask for it hang.
		emulator.onResponse = { [weak self] response in
			self?.pty.write(response)
		}
		emulator.onBell = { NSSound.beep() }

		pty.onOutput = { [weak self] data in
			self?.emulator.write(data)
			if let title = self?.emulator.title { self?.onTitleChange?(title) }
		}
		pty.onExit = { [weak self] code in
			self?.emulator.write("\r\n[process exited with status \(code)]\r\n")
			self?.onProcessExit?(code)
		}

		self.pendingLaunch = (workingDirectory, command)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		cursorTimer?.invalidate()
		pty.terminate()
	}

	private var pendingLaunch: (URL?, (executable: String, arguments: [String])?)?

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		guard window != nil, let launch = pendingLaunch else { return }
		pendingLaunch = nil

		launchWhenSized(launch)
	}

	/// Waits until the pane has a real size before starting the child.
	///
	/// Measuring too early yields a grid a few rows tall. A full-screen program
	/// like tmux lays its status bar out once, at whatever size it was told, and
	/// never learns better unless something resizes afterwards — which is why the
	/// status line ended up near the top until the pane was dragged.
	private func launchWhenSized(_ launch: (URL?, (executable: String, arguments: [String])?), attempt: Int = 0) {
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }

			let height = self.enclosingScrollView?.contentView.bounds.height ?? 0
			let width = self.enclosingScrollView?.contentView.bounds.width ?? 0
			let isSized = height >= self.cellHeight * 4 && width >= self.cellWidth * 20

			// Give layout a few turns, then start anyway rather than never.
			guard isSized || attempt >= 20 else {
				self.launchWhenSized(launch, attempt: attempt + 1)
				return
			}

			self.recomputeGridSize()
			if let command = launch.1 {
				self.pty.start(
					executable: command.executable,
					arguments: command.arguments,
					workingDirectory: launch.0,
					rows: self.emulator.screen.rows,
					columns: self.emulator.screen.columns
				)
			} else {
				self.pty.startLoginShell(
					workingDirectory: launch.0,
					rows: self.emulator.screen.rows,
					columns: self.emulator.screen.columns
				)
			}
			self.startCursorBlink()
		}
	}

	private func scheduleRedraw() {
		guard !redrawScheduled else { return }
		redrawScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.redrawScheduled = false

			// On the alternate screen the document never grows and there is no
			// history to follow, so resizing and autoscrolling there would fight
			// the program's own repainting.
			if !self.emulator.isAlternateScreen {
				self.updateFrameSize()
				if self.isPinnedToBottom { self.scrollToBottom() }
			}
			self.needsDisplay = true
		}
	}

	// MARK: - Metrics

	/// Logged once, so "which font is it actually using?" has a definite answer.
	private static var didLogFont = false

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		if !Self.didLogFont {
			Self.didLogFont = true
			FileHandle.standardError.write(Data("ideai terminal font: \(font.fontName)\n".utf8))
		}

		// Cell metrics are rounded to whole points.
		//
		// A fractional advance accumulates across a row, so run backgrounds land
		// on sub-pixel boundaries and leave hairline seams between them — visible
		// as a step where a powerline separator meets the next segment. Whole-point
		// cells make neighbouring fills abut exactly.
		let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
		cellWidth = max(1, advance.rounded())
		cellHeight = max(1, (font.ascender - font.descender + font.leading).rounded() + 2)
		baselineOffset = (-font.descender + font.leading).rounded()
	}

	func applyThemeChange() {
		updateMetrics()
		recomputeGridSize()
		needsDisplay = true
	}

	/// Derives rows and columns from the pane size and tells both the emulator
	/// and the process.
	private func recomputeGridSize() {
		guard let clip = enclosingScrollView?.contentView else { return }
		let usableWidth = clip.bounds.width - Self.horizontalInset * 2
		let usableHeight = clip.bounds.height - Self.verticalInset * 2

		let columns = max(20, Int(floor(usableWidth / max(1, cellWidth))))
		let rows = max(4, Int(floor(usableHeight / max(1, cellHeight))))

		guard rows != emulator.screen.rows || columns != emulator.screen.columns else { return }
		emulator.resize(rows: rows, columns: columns)
		pty.resize(rows: rows, columns: columns)
		updateFrameSize()
	}

	private func updateFrameSize() {
		let totalRows = emulator.isAlternateScreen
			? emulator.screen.rows
			: emulator.screen.totalLineCount
		let height = CGFloat(totalRows) * cellHeight + Self.verticalInset * 2
		let width = enclosingScrollView?.contentSize.width ?? bounds.width
		let newSize = NSSize(width: max(width, 10), height: max(height, 10))
		if abs(newSize.height - frame.height) > 0.5 || abs(newSize.width - frame.width) > 0.5 {
			setFrameSize(newSize)
		}
	}

	func scrollToBottom() {
		guard let scrollView = enclosingScrollView else { return }
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	/// Called by the container when the clip view's bounds change.
	func viewportChanged() {
		guard let scrollView = enclosingScrollView else {
			recomputeGridSize()
			return
		}

		// Decided before the grid changes, not after. A resize moves the bottom
		// of the document, so comparing the old offset against the new maximum
		// unpins a view that was following the output — leaving the prompt off
		// screen with stale lines showing in its place.
		let offset = scrollView.contentView.bounds.origin.y
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		isPinnedToBottom = offset >= maxY - cellHeight

		recomputeGridSize()

		if isPinnedToBottom { scrollToBottom() }
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let screen = emulator.screen
		let firstRow = max(0, Int(floor((dirtyRect.minY - Self.verticalInset) / cellHeight)))
		let lastRow = min(screen.totalLineCount, Int(ceil((dirtyRect.maxY - Self.verticalInset) / cellHeight)) + 1)
		guard lastRow > firstRow else { return }

		for index in firstRow..<lastRow {
			guard let line = screen.line(at: index) else { continue }
			draw(line: line, atRow: index)
		}

		drawCursor()
	}

	/// Draws one row, batching neighbouring cells that share attributes.
	private func draw(line: TerminalLine, atRow index: Int) {
		let y = (Self.verticalInset + CGFloat(index) * cellHeight).rounded()

		var column = 0
		while column < line.cells.count {
			let attributes = line.cells[column].attributes

			// Extend the run while attributes match.
			var end = column + 1
			while end < line.cells.count, line.cells[end].attributes == attributes {
				end += 1
			}

			var text = ""
			// Powerline separators are drawn as geometry, not glyphs, so a space
			// stands in for them here to keep the run's spacing intact.
			var powerline: [(column: Int, scalar: UInt32)] = []

			for cellIndex in column..<end {
				let cell = line.cells[cellIndex]
				// The trailing half of a wide glyph contributes no character; the
				// leading half already advanced two columns.
				if cell.isWideTrailer { continue }

				if let scalar = cell.character.unicodeScalars.first,
				   PowerlineGlyph.isSeparator(scalar.value) {
					powerline.append((cellIndex, scalar.value))
					text.append(" ")
					continue
				}
				text.append(cell.character)
			}

			let x = (Self.horizontalInset + CGFloat(column) * cellWidth).rounded()
			// Computed from the run's end rather than its length, so consecutive
			// runs share an edge exactly instead of each rounding independently.
			let endX = (Self.horizontalInset + CGFloat(end) * cellWidth).rounded()
			let width = endX - x
			let resolved = attributes.resolved

			let background = TerminalPalette.color(for: resolved.background, isForeground: false, bold: false)
			if resolved.background != .default {
				background.setFill()
				NSRect(x: x, y: y.rounded(), width: width, height: cellHeight).fill()
			}

			// Separators are filled shapes in the run's foreground colour, sized to
			// the cell exactly — which is what removes the seam and the height
			// mismatch a font glyph leaves behind.
			if !powerline.isEmpty {
				let colour = TerminalPalette.color(
					for: resolved.foreground,
					isForeground: true,
					bold: attributes.bold
				)
				for entry in powerline {
					let cellX = (Self.horizontalInset + CGFloat(entry.column) * cellWidth).rounded()
					let cellEnd = (Self.horizontalInset + CGFloat(entry.column + 1) * cellWidth).rounded()
					PowerlineGlyph.draw(
						scalar: entry.scalar,
						in: NSRect(x: cellX, y: y.rounded(), width: cellEnd - cellX, height: cellHeight),
						color: colour
					)
				}
			}

			guard !attributes.hidden, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
				column = end
				continue
			}

			var foreground = TerminalPalette.color(
				for: resolved.foreground,
				isForeground: true,
				bold: attributes.bold
			)
			if attributes.dim { foreground = foreground.withAlphaComponent(0.6) }

			var drawFont = font
			if attributes.bold {
				drawFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
			}
			if attributes.italic {
				drawFont = NSFontManager.shared.convert(drawFont, toHaveTrait: .italicFontMask)
			}

			var textAttributes: [NSAttributedString.Key: Any] = [
				.font: drawFont,
				.foregroundColor: foreground,
			]
			if attributes.underline {
				textAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
			}
			if attributes.strikethrough {
				textAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
			}

			NSAttributedString(string: text, attributes: textAttributes)
				.draw(at: NSPoint(x: x, y: y))

			column = end
		}
	}

	private func drawCursor() {
		guard emulator.isCursorVisible, cursorVisible, window?.firstResponder === self else { return }

		let row = emulator.screen.scrollback.count + emulator.cursorRow
		let x = Self.horizontalInset + CGFloat(emulator.cursorColumn) * cellWidth
		let y = Self.verticalInset + CGFloat(row) * cellHeight

		Theme.current.caret.withAlphaComponent(0.8).setFill()
		NSRect(x: x, y: y, width: cellWidth, height: cellHeight).fill()
	}

	private func startCursorBlink() {
		cursorTimer?.invalidate()
		cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
			guard let self else { return }
			self.cursorVisible.toggle()
			self.needsDisplay = true
		}
	}

	override func becomeFirstResponder() -> Bool {
		cursorVisible = true
		needsDisplay = true
		return true
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return true
	}

	// MARK: - Input

	override func keyDown(with event: NSEvent) {
		guard let bytes = encode(event: event) else { return }
		// Typing always jumps back to the prompt, as every terminal does.
		isPinnedToBottom = true
		pty.write(bytes)
		scrollToBottom()
	}

	/// Translates a key event into the bytes a terminal would send.
	private func encode(event: NSEvent) -> String? {
		let flags = event.modifierFlags

		switch event.keyCode {
		case 126: return emulator.encodeArrow(.up)
		case 125: return emulator.encodeArrow(.down)
		case 124: return emulator.encodeArrow(.right)
		case 123: return emulator.encodeArrow(.left)
		case 115: return "\u{1B}[H"   // Home
		case 119: return "\u{1B}[F"   // End
		case 116: return "\u{1B}[5~"  // Page Up
		case 121: return "\u{1B}[6~"  // Page Down
		case 117: return "\u{1B}[3~"  // Forward delete
		case 51:  return "\u{7F}"     // Backspace sends DEL, not BS
		case 36:  return "\r"
		case 48:  return "\t"
		case 53:  return "\u{1B}"
		default:  break
		}

		guard var characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }

		if flags.contains(.control) {
			// ⌃A…⌃Z and the handful of punctuation controls.
			guard let scalar = characters.lowercased().unicodeScalars.first else { return nil }
			switch scalar {
			case "a"..."z":
				return String(UnicodeScalar(scalar.value - 96)!)
			case "[": return "\u{1B}"
			case "\\": return "\u{1C}"
			case "]": return "\u{1D}"
			case " ", "2": return "\u{0}"
			default: return nil
			}
		}

		// Option is Meta: prefix with ESC, which is what shells expect for
		// word-wise editing (⌥B, ⌥F).
		if flags.contains(.option) {
			return "\u{1B}" + characters
		}

		// Otherwise send what was actually typed, so dead keys and IME work.
		if let typed = event.characters, !typed.isEmpty {
			characters = typed
		}
		return characters
	}

	// MARK: - Mouse

	/// Grid position under a pointer event, 1-based as the protocol expects.
	private func gridPosition(for event: NSEvent) -> (row: Int, column: Int) {
		let point = convert(event.locationInWindow, from: nil)
		let column = Int((point.x - Self.horizontalInset) / max(1, cellWidth)) + 1
		var row = Int((point.y - Self.verticalInset) / max(1, cellHeight))
		// The protocol addresses the visible grid, so scrollback is subtracted.
		row -= emulator.screen.scrollback.count
		return (max(1, row + 1), max(1, column))
	}

	private func modifiers(_ event: NSEvent) -> (Bool, Bool, Bool) {
		let flags = event.modifierFlags
		return (flags.contains(.shift), flags.contains(.option), flags.contains(.control))
	}

	/// Forwards a pointer event, returning true when the program consumed it.
	private func forwardMouse(
		_ event: NSEvent,
		button: TerminalEmulator.MouseButton,
		isRelease: Bool,
		isDrag: Bool = false
	) -> Bool {
		// Shift is the conventional override for "let the terminal handle it",
		// which is how selection stays possible while a program grabs the mouse.
		guard !event.modifierFlags.contains(.shift) else { return false }

		let position = gridPosition(for: event)
		let (shift, option, control) = modifiers(event)
		guard let sequence = emulator.encodeMouse(
			button: button,
			row: position.row,
			column: position.column,
			isRelease: isRelease,
			isDrag: isDrag,
			shift: shift,
			option: option,
			control: control
		) else { return false }

		pty.write(sequence)
		return true
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		_ = forwardMouse(event, button: .left, isRelease: false)
	}

	override func mouseUp(with event: NSEvent) {
		_ = forwardMouse(event, button: .left, isRelease: true)
	}

	override func mouseDragged(with event: NSEvent) {
		_ = forwardMouse(event, button: .left, isRelease: false, isDrag: true)
	}

	override func rightMouseDown(with event: NSEvent) {
		_ = forwardMouse(event, button: .right, isRelease: false)
	}

	override func rightMouseUp(with event: NSEvent) {
		_ = forwardMouse(event, button: .right, isRelease: true)
	}

	override func scrollWheel(with event: NSEvent) {
		// A program tracking the mouse gets wheel events as button 64/65.
		if emulator.mouseTracking != .off, !event.modifierFlags.contains(.shift) {
			let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))
			let button: TerminalEmulator.MouseButton = event.scrollingDeltaY > 0 ? .scrollUp : .scrollDown
            let position = gridPosition(for: event)
			for _ in 0..<steps {
				if let sequence = emulator.encodeMouse(
					button: button,
					row: position.row,
					column: position.column,
					isRelease: false
				) {
					pty.write(sequence)
				}
			}
			return
		}

		// On the alternate screen there is no scrollback to move through, so the
		// wheel drives the program's own cursor instead of doing nothing.
		if emulator.isAlternateScreen {
			let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))
			let key: TerminalEmulator.ArrowKey = event.scrollingDeltaY > 0 ? .up : .down
			pty.write(String(repeating: emulator.encodeArrow(key), count: steps))
			return
		}

		super.scrollWheel(with: event)
	}

	// MARK: - Actions

	@objc func copy(_ sender: Any?) {
		let text = emulator.screen.allText()
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc func paste(_ sender: Any?) {
		guard let text = NSPasteboard.general.string(forType: .string) else { return }
		isPinnedToBottom = true
		// Bracketed paste tells the program the text arrived at once, which stops
		// shells from executing every pasted line as it lands.
		if emulator.bracketedPaste {
			pty.write("\u{1B}[200~" + text + "\u{1B}[201~")
		} else {
			pty.write(text)
		}
		scrollToBottom()
	}

	func sendInterrupt() {
		pty.interrupt()
	}

	func terminateProcess() {
		pty.terminate()
	}

	var isProcessRunning: Bool { pty.isRunning }

	/// Writes text as though typed. Used to drive a session programmatically —
	/// the same entry point an agent prompt will take.
	func send(_ text: String) {
		isPinnedToBottom = true
		pty.write(text)
		scrollToBottom()
	}

	// MARK: - NSTextInputClient

	// Minimal conformance so IME candidates commit into the terminal.

	func insertText(_ string: Any, replacementRange: NSRange) {
		let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
		guard !text.isEmpty else { return }
		pty.write(text)
	}

	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
	func unmarkText() {}
	func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
	func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
	func hasMarkedText() -> Bool { false }
	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
	func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
	func characterIndex(for point: NSPoint) -> Int { 0 }

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		guard let window else { return .zero }
		let row = emulator.screen.scrollback.count + emulator.cursorRow
		let rect = NSRect(
			x: Self.horizontalInset + CGFloat(emulator.cursorColumn) * cellWidth,
			y: Self.verticalInset + CGFloat(row) * cellHeight,
			width: cellWidth,
			height: cellHeight
		)
		return window.convertToScreen(convert(rect, to: nil))
	}
}

/// Scrolling container that keeps the terminal sized to its viewport.
final class TerminalPane: NSView {
	let terminalView: TerminalView
	private let scrollView = NSScrollView()

	init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		terminalView = TerminalView(workingDirectory: workingDirectory, command: command)
		super.init(frame: .zero)

		scrollView.documentView = terminalView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		scrollView.contentView.postsBoundsChangedNotifications = true

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak self] _ in
			self?.terminalView.viewportChanged()
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		// The grid is measured in cells, so a resize changes rows and columns.
		terminalView.viewportChanged()
	}

	override func layout() {
		super.layout()
		// Catches the case where the pane gains its real size through layout
		// rather than an explicit frame change.
		terminalView.viewportChanged()
	}

	func focus() {
		window?.makeFirstResponder(terminalView)
	}
}
