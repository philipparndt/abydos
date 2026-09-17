import AbydosKit
import AppKit

extension NSAttributedString.Key {
	/// Marks a run of inline code. The value is the `MarkdownPill` drawn behind it.
	static let abydosInlineCode = NSAttributedString.Key("abydosInlineCode")
}

/// What is drawn behind a run of inline code: a rounded panel with room
/// around the letters.
///
/// A `backgroundColor` attribute hugs the glyphs — a rectangle the exact
/// height of the line and no wider than the letters, which is what the preview
/// drew and what read as a smudge beside GitHub's pill. The room is made two
/// ways and neither adds a character: the layout manager paints past the glyphs
/// by `padX` and `padY`, and the renderer kerns the letter before the run and
/// the run's last letter by `padX`, so the neighbours step aside for the paint.
/// Copying the sentence out of the preview yields the sentence.
final class MarkdownPill {
	let colour: NSColor
	let radius: CGFloat
	let padX: CGFloat
	let padY: CGFloat

	init(colour: NSColor, radius: CGFloat, padX: CGFloat, padY: CGFloat) {
		self.colour = colour
		self.radius = radius
		self.padX = padX
		self.padY = padY
	}
}

/// The layout manager under a rendered markdown page: TextKit 1, because
/// `NSTextTable` and `NSTextBlock` are, and the one place a pill is painted.
final class MarkdownLayoutManager: NSLayoutManager {
	override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
		super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
		guard let storage = textStorage else { return }
		let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
		storage.enumerateAttribute(.abydosInlineCode, in: characters, options: []) { value, range, _ in
			guard let pill = value as? MarkdownPill else { return }
			drawPill(pill, behind: range, at: origin, in: storage)
		}
	}

	/// One pill per line the run touches: a run that wraps is two pills, each
	/// the height of its letters rather than of the line, so the room above and
	/// below is the pill's own and not the paragraph's leading.
	private func drawPill(_ pill: MarkdownPill, behind range: NSRange, at origin: NSPoint, in storage: NSTextStorage) {
		let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
		guard glyphs.length > 0,
		      let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil)
		else { return }
		let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
			?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
		let letters = font.ascender - font.descender

		var index = glyphs.location
		while index < NSMaxRange(glyphs) {
			var lineGlyphs = NSRange()
			let fragment = lineFragmentRect(forGlyphAt: index, effectiveRange: &lineGlyphs)
			let onThisLine = NSIntersectionRange(lineGlyphs, glyphs)
			guard onThisLine.length > 0 else { break }
			let bounds = boundingRect(forGlyphRange: onThisLine, in: container)
			let baseline = location(forGlyphAt: onThisLine.location).y
			// The kern the renderer put on the letter before the run is the room
			// on the left; the run's own last letter carries the room on the right
			// inside `bounds`, so the pill grows leftward only.
			let rect = NSRect(
				x: bounds.minX - pill.padX,
				y: fragment.minY + baseline - font.ascender - pill.padY,
				width: bounds.width + pill.padX,
				height: letters + 2 * pill.padY
			).offsetBy(dx: origin.x, dy: origin.y)
			pill.colour.setFill()
			NSBezierPath(roundedRect: rect, xRadius: pill.radius, yRadius: pill.radius).fill()
			index = NSMaxRange(lineGlyphs)
		}
	}
}

/// The panel a fenced code block sits on, with the corners the rest of the
/// window's controls have.
///
/// `NSTextBlock` paints its background square. Every paragraph of a fence
/// carries the same one of these, which is how the text system lays them out
/// as one block — one panel around all of them, drawn once — exactly as a
/// table cell with several paragraphs is drawn today.
final class MarkdownPanelBlock: NSTextBlock {
	private let colour: NSColor
	private let radius: CGFloat

	init(colour: NSColor, radius: CGFloat) {
		self.colour = colour
		self.radius = radius
		super.init()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func drawBackground(
		withFrame frameRect: NSRect, in controlView: NSView?, characterRange: NSRange, layoutManager: NSLayoutManager
	) {
		// The frame handed over is the block's whole rectangle, margins included
		// — `NSTextBlock` paints inside them and so does this, or the panel
		// stands on the space meant to keep the next paragraph off it.
		var rect = frameRect
		rect.origin.x += width(for: .margin, edge: .minX)
		rect.origin.y += width(for: .margin, edge: .minY)
		rect.size.width -= width(for: .margin, edge: .minX) + width(for: .margin, edge: .maxX)
		rect.size.height -= width(for: .margin, edge: .minY) + width(for: .margin, edge: .maxY)
		colour.setFill()
		NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
	}
}

/// Builds the text views a rendered markdown page is shown in.
enum MarkdownPage {
	/// A text view on `MarkdownLayoutManager`, with the sizing `NSTextView()`
	/// would have given it: as wide as its scroll view and as tall as its text.
	///
	/// Built by hand because a layout manager cannot be swapped into a view
	/// after the fact — the convenience initialiser has already made one — and
	/// because a view made this way is TextKit 1 from the start rather than a
	/// TextKit 2 view that falls back the first time it meets a table.
	@MainActor
	static func textView<View: NSTextView>(_ make: (NSTextContainer) -> View) -> View {
		let storage = NSTextStorage()
		let layout = MarkdownLayoutManager()
		storage.addLayoutManager(layout)
		// Ten million points tall, which is the height `NSTextView()` gives its own
		// container: a text block laid out against the largest double came out one
		// letter wide, the arithmetic having gone through infinity on the way.
		let container = NSTextContainer(size: NSSize(width: 0, height: 10_000_000))
		container.widthTracksTextView = true
		layout.addTextContainer(container)
		let view = make(container)
		view.minSize = NSSize.zero
		view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		view.isVerticallyResizable = true
		view.isHorizontallyResizable = false
		view.autoresizingMask = [NSView.AutoresizingMask.width]
		return view
	}
}
