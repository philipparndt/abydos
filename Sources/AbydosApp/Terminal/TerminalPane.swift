import AppKit
import AbydosKit

/// Scrolling container that keeps the terminal sized to its viewport.
final class TerminalPane: NSView {
	let terminalView: TerminalView
	private let scrollView = NSScrollView()

	/// A pane that shows output and runs nothing.
	convenience init(readOnly: Void) {
		self.init(terminalView: TerminalView.forOutput())
	}

	convenience init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		self.init(terminalView: TerminalView(workingDirectory: workingDirectory, command: command))
	}

	private init(terminalView: TerminalView) {
		self.terminalView = terminalView
		super.init(frame: .zero)

		scrollView.documentView = terminalView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = TerminalPalette.background
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

	/// The view inside, for the panel to pass a resize down to.
	var terminalViewForTesting: TerminalView { terminalView }

	/// Shows text in the pane as though something in it had printed it.
	///
	/// A lone newline is turned into a return and a newline, because this is a
	/// terminal and not a text view: `\n` moves down a line and leaves the cursor
	/// in the column it was in, so output written the way a file is written comes
	/// out as a staircase. What already has its return keeps it — a `docker pull`
	/// redrawing one line with a bare `\r` is left exactly as it came.
	func write(_ text: String) {
		terminalView.append(
			text
				.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\n", with: "\r\n")
		)
	}

	/// Starts a shell in a pane that has only been showing output.
	func startProcess(
		_ command: (executable: String, arguments: [String]), workingDirectory: URL? = nil
	) {
		terminalView.startProcess(command, workingDirectory: workingDirectory)
	}

	/// Whether this pane is still only showing output.
	var showsOutputOnly: Bool { terminalView.showsOutputOnly }

	/// Where the shell in this terminal currently is.
	var currentDirectoryForTesting: URL? { terminalView.currentDirectory() }
	/// Where the shell is *while it is waiting* — nil while it is running
	/// something. This is what following uses; the one above is what a driven
	/// run asks when it wants the answer whatever the terminal is doing.
	var settledDirectoryForTesting: URL? { terminalView.settledDirectory() }
	var ttyName: String? { terminalView.ttyName }
	var geometryForTesting: String { terminalView.geometryForTesting }
	var gridSizeForTesting: (rows: Int, columns: Int) { terminalView.gridSizeForTesting }

	func rightPressForTesting(row: Int, column: Int) {
		terminalView.rightPressForTesting(row: row, column: column)
	}

	func rightDragForTesting(row: Int, column: Int) {
		terminalView.rightDragForTesting(row: row, column: column)
	}

	func rightReleaseForTesting(row: Int, column: Int) {
		terminalView.rightReleaseForTesting(row: row, column: column)
	}

	func moveMouseForTesting(row: Int, column: Int) {
		terminalView.moveMouseForTesting(row: row, column: column)
	}

	/// Output arrived, which is the moment to check whether the shell has moved.
	var onOutput: (() -> Void)? {
		get { terminalView.onOutput }
		set { terminalView.onOutput = newValue }
	}

	func focus() {
		window?.makeFirstResponder(terminalView)
	}
}

/// The four faces a terminal cell can ask for, and what each one advances by.
///
/// Derived once per font change. Asking NSFontManager to convert a font is
/// slow enough to matter when it happens for every run of every frame, and the
/// advance was being measured through a string-keyed cache that allocated its
/// key on each lookup.
struct TerminalFaces {
	let regular: NSFont
	let bold: NSFont
	let italic: NSFont
	let boldItalic: NSFont
	/// Advance of the regular face, which is what the cell grid is built on.
	let advance: CGFloat
	/// Distance from the top of a cell down to the baseline.
	let baselineFromTop: CGFloat

	private let advances: (CGFloat, CGFloat, CGFloat, CGFloat)

	init(base: NSFont) {
		let manager = NSFontManager.shared
		regular = base
		bold = manager.convert(base, toHaveTrait: .boldFontMask)
		italic = manager.convert(base, toHaveTrait: .italicFontMask)
		boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)

		func width(_ font: NSFont) -> CGFloat {
			("0" as NSString).size(withAttributes: [.font: font]).width
		}
		advances = (width(regular), width(bold), width(italic), width(boldItalic))
		advance = advances.0
		baselineFromTop = (base.ascender + base.leading).rounded()
	}

	/// Which of the four faces a pair of flags asks for.
	static func index(bold isBold: Bool, italic isItalic: Bool) -> UInt8 {
		(isBold ? 1 : 0) | (isItalic ? 2 : 0)
	}

	func face(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
		switch (isBold, isItalic) {
		case (false, false): return regular
		case (true, false):  return bold
		case (false, true):  return italic
		case (true, true):   return boldItalic
		}
	}

	func advance(bold isBold: Bool, italic isItalic: Bool) -> CGFloat {
		switch (isBold, isItalic) {
		case (false, false): return advances.0
		case (true, false):  return advances.1
		case (false, true):  return advances.2
		case (true, true):   return advances.3
		}
	}
}


/// A glyph for one code point, together with the font that actually has it.
///
/// Looked up once and kept. Turning a character into a glyph means asking
/// CoreText, and asking it for a font that can draw one means asking the whole
/// fallback cascade — neither is something to do sixty times a second for every
