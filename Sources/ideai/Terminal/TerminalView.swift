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

	// MARK: - Init

	init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		emulator = TerminalEmulator(rows: 24, columns: 80)
		pty = PseudoTerminal()
		super.init(frame: .zero)

		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()

		emulator.onUpdate = { [weak self] in
			guard let self else { return }
			self.needsDisplay = true
			self.updateFrameSize()
			if self.isPinnedToBottom { self.scrollToBottom() }
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

		// Launch only once the view has a size, so the child's initial window
		// dimensions are right and its first prompt is not mis-wrapped.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
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

	// MARK: - Metrics

	private func updateMetrics() {
		font = .monospacedSystemFont(ofSize: Theme.current.fontSize, weight: .regular)
		cellWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
		cellHeight = ceil(font.ascender - font.descender + font.leading) + 2
		baselineOffset = ceil(-font.descender + font.leading)
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
		let totalRows = emulator.screen.totalLineCount
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
		recomputeGridSize()

		guard let scrollView = enclosingScrollView else { return }
		let offset = scrollView.contentView.bounds.origin.y
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		// Re-pin once the user scrolls back to the bottom.
		isPinnedToBottom = offset >= maxY - cellHeight
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
		let y = Self.verticalInset + CGFloat(index) * cellHeight

		var column = 0
		while column < line.cells.count {
			let attributes = line.cells[column].attributes

			// Extend the run while attributes match.
			var end = column + 1
			while end < line.cells.count, line.cells[end].attributes == attributes {
				end += 1
			}

			var text = ""
			for cellIndex in column..<end {
				let cell = line.cells[cellIndex]
				// The trailing half of a wide glyph contributes no character; the
				// leading half already advanced two columns.
				if cell.isWideTrailer { continue }
				text.append(cell.character)
			}

			let x = Self.horizontalInset + CGFloat(column) * cellWidth
			let width = CGFloat(end - column) * cellWidth
			let resolved = attributes.resolved

			let background = TerminalPalette.color(for: resolved.background, isForeground: false, bold: false)
			if resolved.background != .default {
				background.setFill()
				NSRect(x: x, y: y, width: width, height: cellHeight).fill()
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

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
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

	func focus() {
		window?.makeFirstResponder(terminalView)
	}
}
