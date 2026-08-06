import AppKit

/// Read-only hex dump.
///
/// Uses the same virtualisation principle as the code view: the file is memory
/// mapped and only the rows in the viewport are formatted and drawn, so a 114 MB
/// STL opens instantly and scrolls at full speed. Nothing is ever converted to a
/// string up front.
final class HexView: NSView {
	private let data: Data
	private static let bytesPerRow = 16

	private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	private var rowHeight: CGFloat = 17
	private var charWidth: CGFloat = 7

	/// Column origins, computed once from the font metrics.
	private var offsetColumnX: CGFloat = 12
	private var hexColumnX: CGFloat = 0
	private var asciiColumnX: CGFloat = 0

	init(data: Data) {
		self.data = data
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		computeMetrics()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private var rowCount: Int {
		max(1, (data.count + Self.bytesPerRow - 1) / Self.bytesPerRow)
	}

	private func computeMetrics() {
		charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
		rowHeight = ceil(font.ascender - font.descender + font.leading) + 4

		// offset(8) + gap + hex(16 * 3 + extra gap at the midpoint) + gap + ascii
		hexColumnX = offsetColumnX + charWidth * 10
		asciiColumnX = hexColumnX + charWidth * (CGFloat(Self.bytesPerRow) * 3 + 2)
	}

	var intrinsicSize: NSSize {
		NSSize(
			width: asciiColumnX + charWidth * CGFloat(Self.bytesPerRow) + 24,
			height: CGFloat(rowCount) * rowHeight + 8
		)
	}

	func sizeToFit() {
		setFrameSize(intrinsicSize)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let firstRow = max(0, Int(floor(dirtyRect.minY / rowHeight)) - 1)
		let lastRow = min(rowCount, Int(ceil(dirtyRect.maxY / rowHeight)) + 1)
		guard lastRow > firstRow else { return }

		let offsetAttributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: Theme.current.gutterText,
		]
		let hexAttributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: Theme.current.editorText,
		]
		let zeroAttributes: [NSAttributedString.Key: Any] = [
			.font: font,
			// Dimming zero bytes makes structure in binary data far easier to see.
			.foregroundColor: Theme.current.gutterText,
		]
		let asciiAttributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: Theme.current.gitAdded,
		]

		for row in firstRow..<lastRow {
			let y = CGFloat(row) * rowHeight
			let start = row * Self.bytesPerRow
			guard start < data.count else { break }
			let end = min(data.count, start + Self.bytesPerRow)

			// Alternating band every 8 rows, as a reading aid.
			if (row / 8) % 2 == 1 {
				Theme.current.currentLineBackground.withAlphaComponent(0.4).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: rowHeight).fill()
			}

			NSAttributedString(string: String(format: "%08X", start), attributes: offsetAttributes)
				.draw(at: NSPoint(x: offsetColumnX, y: y + 2))

			var hexX = hexColumnX
			var asciiX = asciiColumnX
			for index in start..<end {
				let byte = data[data.startIndex + index]
				let attributes = byte == 0 ? zeroAttributes : hexAttributes
				NSAttributedString(string: String(format: "%02X", byte), attributes: attributes)
					.draw(at: NSPoint(x: hexX, y: y + 2))
				hexX += charWidth * 3
				// Extra gap splitting the row into two groups of eight.
				if (index - start) == Self.bytesPerRow / 2 - 1 { hexX += charWidth * 2 }

				// Printable ASCII only; everything else becomes a dot.
				let scalar = (byte >= 0x20 && byte < 0x7F) ? Character(UnicodeScalar(byte)) : "."
				NSAttributedString(string: String(scalar), attributes: asciiAttributes)
					.draw(at: NSPoint(x: asciiX, y: y + 2))
				asciiX += charWidth
			}
		}
	}
}

/// Scrolling container for a hex dump.
final class HexViewerController {
	let scrollView: NSScrollView
	private let hexView: HexView

	init(data: Data) {
		hexView = HexView(data: data)
		hexView.sizeToFit()

		scrollView = NSScrollView()
		scrollView.documentView = hexView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
	}
}
