import AppKit
import CoreText
import Metal

/// Where one glyph sits in the atlas, and where it sits relative to its cell.
struct AtlasEntry {
	/// Position in the atlas, normalised.
	let uvOrigin: SIMD2<Float>
	let uvSize: SIMD2<Float>
	/// Offset from the cell's top-left to the glyph's, in points.
	let offset: CGPoint
	/// Size of the glyph in points.
	let size: CGSize
	/// Whether it came from a colour font, and so carries its own colours
	/// rather than coverage for the cell's foreground to show through.
	let isColour: Bool
}

/// Glyphs rasterised once and kept on the GPU.
///
/// A terminal shows a few hundred distinct characters however long it runs, so
/// every glyph it will ever need is drawn once and then only ever stamped. That
/// is the whole reason the GPU can draw a screen of ten thousand individually
/// coloured cells in one call.
final class GlyphAtlas {
	/// One texture and where the next glyph goes in it.
	///
	/// Shelf packing: glyphs go along a row until it is full, then a new row
	/// starts below the tallest so far. Terminal glyphs are all much the same
	/// height, so the waste is small and the arithmetic is trivial.
	private final class Sheet {
		let texture: MTLTexture
		let bytesPerPixel: Int
		var nextX = 1
		var nextY = 1
		var shelfHeight = 0

		init?(device: MTLDevice, format: MTLPixelFormat, bytesPerPixel: Int, side: Int) {
			let descriptor = MTLTextureDescriptor.texture2DDescriptor(
				pixelFormat: format, width: side, height: side, mipmapped: false
			)
			descriptor.usage = .shaderRead
			descriptor.storageMode = .managed
			guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
			self.texture = texture
			self.bytesPerPixel = bytesPerPixel

			// Cleared once: an unwritten region would otherwise stamp whatever
			// the allocation happened to contain.
			let blank = [UInt8](repeating: 0, count: side * side * bytesPerPixel)
			texture.replace(
				region: MTLRegionMake2D(0, 0, side, side),
				mipmapLevel: 0,
				withBytes: blank,
				bytesPerRow: side * bytesPerPixel
			)
		}

		func reset() {
			nextX = 1
			nextY = 1
			shelfHeight = 0
		}

		func allocate(width: Int, height: Int) -> (x: Int, y: Int)? {
			guard width < texture.width, height < texture.height else { return nil }

			if nextX + width >= texture.width {
				nextX = 1
				nextY += shelfHeight + 1
				shelfHeight = 0
			}
			// Full. A terminal will not get here in practice — a few hundred
			// glyphs across four faces is a fraction of this — so it starts
			// again rather than growing.
			if nextY + height >= texture.height { reset() }

			let slot = (x: nextX, y: nextY)
			nextX += width + 1
			shelfHeight = max(shelfHeight, height)
			return slot
		}
	}

	private let device: MTLDevice
	/// Coverage, for the ordinary glyph whose colour is the cell's.
	private let coverage: Sheet
	/// Colour, for glyphs that carry their own — emoji, mostly.
	private let colour: Sheet
	private let scale: CGFloat

	var coverageTexture: MTLTexture { coverage.texture }
	var colourTexture: MTLTexture { colour.texture }

	private var entries: [Key: AtlasEntry?] = [:]

	/// The cell the separators are drawn to fill.
	///
	/// They are geometry rather than glyphs, so their size is the cell's, not
	/// the font's — and a cell of a different size means drawing them again.
	private var cellSize: CGSize = .zero

	private struct Key: Hashable {
		let scalar: UInt32
		let face: UInt8
	}

	init?(device: MTLDevice, scale: CGFloat, side: Int = 2048) {
		// The colour sheet is smaller: a terminal shows a handful of emoji, and
		// each costs four bytes a pixel rather than one.
		guard let coverage = Sheet(device: device, format: .r8Unorm, bytesPerPixel: 1, side: side),
		      let colour = Sheet(device: device, format: .bgra8Unorm, bytesPerPixel: 4, side: side / 2)
		else { return nil }

		self.device = device
		self.coverage = coverage
		self.colour = colour
		self.scale = scale
	}

	func removeAll() {
		entries.removeAll(keepingCapacity: true)
		coverage.reset()
		colour.reset()
	}

	/// The atlas entry for a code point, rasterising it the first time.
	///
	/// Returns nil for anything with nothing to draw — a space, or a character
	/// no font on the machine has a glyph for.
	/// Tells the atlas how big a cell is, since the separators are drawn to fill
	/// one exactly.
	func setCellSize(_ size: CGSize) {
		guard size != cellSize else { return }
		cellSize = size
		removeAll()
	}

	func entry(for scalar: UInt32, font: NSFont, faceIndex: UInt8) -> AtlasEntry? {
		let key = Key(scalar: scalar, face: faceIndex)
		if let known = entries[key] { return known }

		let made = PowerlineGlyph.isSeparator(scalar)
			? rasteriseSeparator(scalar: scalar)
			: rasterise(scalar: scalar, font: font)
		entries[key] = made
		return made
	}

	/// Draws a powerline separator as the shape it is, filling the cell.
	///
	/// The same geometry the CoreGraphics path draws, for the same reason: a
	/// font glyph is sized to the font's metrics and never quite fills the cell,
	/// which leaves a seam where one prompt segment meets the next. Rasterised
	/// once at cell size and then stamped like any other glyph.
	private func rasteriseSeparator(scalar: UInt32) -> AtlasEntry? {
		guard cellSize.width > 0, cellSize.height > 0 else { return nil }

		let pixelWidth = Int((cellSize.width * scale).rounded())
		let pixelHeight = Int((cellSize.height * scale).rounded())
		guard pixelWidth > 0, pixelHeight > 0,
		      let slot = coverage.allocate(width: pixelWidth, height: pixelHeight),
		      let context = CGContext(
				data: nil,
				width: pixelWidth,
				height: pixelHeight,
				bitsPerComponent: 8,
				bytesPerRow: pixelWidth,
				space: CGColorSpaceCreateDeviceGray(),
				bitmapInfo: CGImageAlphaInfo.none.rawValue
			)
		else { return nil }

		context.setFillColor(gray: 0, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
		context.scaleBy(x: scale, y: scale)

		// White, because what is stored is coverage: the cell's own foreground
		// is what actually shows through it.
		let graphics = NSGraphicsContext(cgContext: context, flipped: false)
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = graphics
		PowerlineGlyph.draw(
			scalar: scalar,
			in: NSRect(origin: .zero, size: cellSize),
			color: .white
		)
		NSGraphicsContext.restoreGraphicsState()

		guard let pixels = context.data else { return nil }
		coverage.texture.replace(
			region: MTLRegionMake2D(slot.x, slot.y, pixelWidth, pixelHeight),
			mipmapLevel: 0,
			withBytes: pixels,
			bytesPerRow: pixelWidth
		)

		let side = Float(coverage.texture.width)
		return AtlasEntry(
			uvOrigin: SIMD2(Float(slot.x) / side, Float(slot.y) / side),
			uvSize: SIMD2(Float(pixelWidth) / side, Float(pixelHeight) / side),
			// It fills the cell, so it starts where the cell does.
			offset: .zero,
			size: cellSize,
			isColour: false
		)
	}

	private func rasterise(scalar: UInt32, font: NSFont) -> AtlasEntry? {
		guard let unicode = UnicodeScalar(scalar) else { return nil }
		var utf16 = Array(String(unicode).utf16)
		var glyphs = [CGGlyph](repeating: 0, count: utf16.count)

		var ctFont = font as CTFont
		if !CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count) || glyphs[0] == 0 {
			// Nothing in the terminal's own face — emoji, CJK and the powerline
			// range all live elsewhere, and CoreText knows where.
			guard let fallback = GlyphFallback.font(for: unicode, from: ctFont) else { return nil }
			ctFont = fallback
			guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count), glyphs[0] != 0 else {
				return nil
			}
		}

		var glyph = glyphs[0]
		var bounds = CGRect.zero
		CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &bounds, 1)
		guard bounds.width > 0, bounds.height > 0 else { return nil }

		// An emoji font draws its own colours; everything else draws coverage
		// for the cell's foreground to show through.
		let isColour = CTFontGetSymbolicTraits(ctFont).contains(.traitColorGlyphs)

		// A pixel of margin so neighbouring glyphs cannot bleed into each other.
		let margin: CGFloat = 1
		let pixelWidth = Int(ceil(bounds.width * scale) + margin * 2)
		let pixelHeight = Int(ceil(bounds.height * scale) + margin * 2)
		let sheet = isColour ? colour : coverage
		guard let slot = sheet.allocate(width: pixelWidth, height: pixelHeight) else { return nil }

		let bytesPerRow = pixelWidth * sheet.bytesPerPixel
		guard let context = CGContext(
			data: nil,
			width: pixelWidth,
			height: pixelHeight,
			bitsPerComponent: 8,
			bytesPerRow: bytesPerRow,
			space: isColour ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
			bitmapInfo: isColour
				? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
				: CGImageAlphaInfo.none.rawValue
		) else { return nil }

		if isColour {
			// Transparent, so what the cell already painted shows around the
			// emoji rather than a black box.
			context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
		} else {
			context.setFillColor(gray: 0, alpha: 1)
			context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
			context.setFillColor(gray: 1, alpha: 1)
		}
		context.setAllowsAntialiasing(true)
		context.setShouldAntialias(true)
		context.setShouldSubpixelPositionFonts(false)
		context.scaleBy(x: scale, y: scale)

		// Placed so the glyph's own bounding box lands inside the bitmap, with
		// the margin around it. CoreGraphics has y running up here.
		//
		// Rounded to a whole pixel first. A bearing is fractional and differs
		// per character, so drawing at it rasterises every glyph at a different
		// fraction of a pixel — and no amount of care about where the bitmap
		// then goes can undo that. Letters come out looking as though they sit
		// on slightly different lines, which is what "m and a look offset"
		// means. Rounding here puts every glyph on the same phase.
		var position = CGPoint(
			x: ((-bounds.minX * scale).rounded() + margin) / scale,
			y: ((-bounds.minY * scale).rounded() + margin) / scale
		)
		CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)

		guard let pixels = context.data else { return nil }
		sheet.texture.replace(
			region: MTLRegionMake2D(slot.x, slot.y, pixelWidth, pixelHeight),
			mipmapLevel: 0,
			withBytes: pixels,
			bytesPerRow: bytesPerRow
		)

		let side = Float(sheet.texture.width)
		return AtlasEntry(
			uvOrigin: SIMD2(Float(slot.x) / side, Float(slot.y) / side),
			uvSize: SIMD2(Float(pixelWidth) / side, Float(pixelHeight) / side),
			// Where the bitmap's top-left sits relative to the pen, in the
			// view's coordinates where y runs down. Derived from where the
			// glyph was actually drawn rather than from its bounds, so the
			// rounding above is accounted for rather than fought.
			offset: CGPoint(
				x: -position.x,
				y: position.y - CGFloat(pixelHeight) / scale
			),
			size: CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale),
			isColour: isColour
		)
	}

}
