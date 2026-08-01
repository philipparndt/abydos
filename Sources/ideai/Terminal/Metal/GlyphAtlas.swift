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
}

/// Glyphs rasterised once and kept on the GPU.
///
/// A terminal shows a few hundred distinct characters however long it runs, so
/// every glyph it will ever need is drawn once and then only ever stamped. That
/// is the whole reason the GPU can draw a screen of ten thousand individually
/// coloured cells in one call.
final class GlyphAtlas {
	private let device: MTLDevice
	private(set) var texture: MTLTexture

	/// Coverage only — the colour comes from the cell, not the glyph.
	private let format: MTLPixelFormat = .r8Unorm
	private let scale: CGFloat

	private var entries: [Key: AtlasEntry?] = [:]

	/// Shelf packing: glyphs go along a row until it is full, then a new row
	/// starts below the tallest so far. Terminal glyphs are all much the same
	/// height, so the waste is small and the arithmetic is trivial.
	private var nextX = 1
	private var nextY = 1
	private var shelfHeight = 0

	private struct Key: Hashable {
		let scalar: UInt32
		let face: UInt8
	}

	init?(device: MTLDevice, scale: CGFloat, side: Int = 2048) {
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: format,
			width: side,
			height: side,
			mipmapped: false
		)
		descriptor.usage = .shaderRead
		descriptor.storageMode = .managed
		guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

		self.device = device
		self.texture = texture
		self.scale = scale

		// Cleared once: an unwritten region would otherwise stamp whatever the
		// allocation happened to contain.
		let blank = [UInt8](repeating: 0, count: side * side)
		texture.replace(
			region: MTLRegionMake2D(0, 0, side, side),
			mipmapLevel: 0,
			withBytes: blank,
			bytesPerRow: side
		)
	}

	func removeAll() {
		entries.removeAll(keepingCapacity: true)
		nextX = 1
		nextY = 1
		shelfHeight = 0
	}

	/// The atlas entry for a code point, rasterising it the first time.
	///
	/// Returns nil for anything with nothing to draw — a space, or a character
	/// no font on the machine has a glyph for.
	func entry(for scalar: UInt32, font: NSFont, faceIndex: UInt8) -> AtlasEntry? {
		let key = Key(scalar: scalar, face: faceIndex)
		if let known = entries[key] { return known }

		let made = rasterise(scalar: scalar, font: font)
		entries[key] = made
		return made
	}

	private func rasterise(scalar: UInt32, font: NSFont) -> AtlasEntry? {
		guard let unicode = UnicodeScalar(scalar) else { return nil }
		var utf16 = Array(String(unicode).utf16)
		var glyphs = [CGGlyph](repeating: 0, count: utf16.count)

		var ctFont = font as CTFont
		if !CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count) || glyphs[0] == 0 {
			// Nothing in the terminal's own face — emoji, CJK and the powerline
			// range all live elsewhere, and CoreText knows where.
			ctFont = CTFontCreateForString(
				ctFont, String(unicode) as CFString, CFRange(location: 0, length: utf16.count)
			)
			guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count), glyphs[0] != 0 else {
				return nil
			}
		}

		var glyph = glyphs[0]
		var bounds = CGRect.zero
		CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &bounds, 1)
		guard bounds.width > 0, bounds.height > 0 else { return nil }

		// A pixel of margin so neighbouring glyphs cannot bleed into each other.
		let margin: CGFloat = 1
		let pixelWidth = Int(ceil(bounds.width * scale) + margin * 2)
		let pixelHeight = Int(ceil(bounds.height * scale) + margin * 2)
		guard let slot = allocate(width: pixelWidth, height: pixelHeight) else { return nil }

		guard let context = CGContext(
			data: nil,
			width: pixelWidth,
			height: pixelHeight,
			bitsPerComponent: 8,
			bytesPerRow: pixelWidth,
			space: CGColorSpaceCreateDeviceGray(),
			bitmapInfo: CGImageAlphaInfo.none.rawValue
		) else { return nil }

		context.setFillColor(gray: 0, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
		context.setFillColor(gray: 1, alpha: 1)
		context.setAllowsAntialiasing(true)
		context.setShouldAntialias(true)
		context.setShouldSubpixelPositionFonts(false)
		context.scaleBy(x: scale, y: scale)

		// Placed so the glyph's own bounding box lands inside the bitmap, with
		// the margin around it. CoreGraphics has y running up here.
		var position = CGPoint(
			x: -bounds.minX + margin / scale,
			y: -bounds.minY + margin / scale
		)
		CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)

		guard let pixels = context.data else { return nil }
		texture.replace(
			region: MTLRegionMake2D(slot.x, slot.y, pixelWidth, pixelHeight),
			mipmapLevel: 0,
			withBytes: pixels,
			bytesPerRow: pixelWidth
		)

		let side = Float(texture.width)
		return AtlasEntry(
			uvOrigin: SIMD2(Float(slot.x) / side, Float(slot.y) / side),
			uvSize: SIMD2(Float(pixelWidth) / side, Float(pixelHeight) / side),
			// The glyph's top in the view's coordinates, where y runs down: the
			// bounding box is measured up from the baseline.
			offset: CGPoint(
				x: bounds.minX - margin / scale,
				y: -bounds.maxY - margin / scale
			),
			size: CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
		)
	}

	private func allocate(width: Int, height: Int) -> (x: Int, y: Int)? {
		guard width < texture.width, height < texture.height else { return nil }

		if nextX + width >= texture.width {
			nextX = 1
			nextY += shelfHeight + 1
			shelfHeight = 0
		}
		// Full. A terminal will not get here in practice — a few hundred glyphs
		// across four faces is a fraction of this — so it starts again rather
		// than growing, and the glyphs still on screen are drawn again.
		if nextY + height >= texture.height {
			removeAll()
		}

		let slot = (x: nextX, y: nextY)
		nextX += width + 1
		shelfHeight = max(shelfHeight, height)
		return slot
	}
}
