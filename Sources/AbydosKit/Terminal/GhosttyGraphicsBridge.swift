import CoreGraphics
import Foundation
import ImageIO
import GhosttyVt

/// Kitty graphics from libghostty-vt's store into ours (item 0485).
///
/// **This file is the answer to the question 0474 left open**, and the answer is
/// that the tmux image path works without anything new being exported from
/// libghostty-vt.
///
/// 0474 concluded that because the `U=1` unicode-placeholder half of the kitty
/// protocol is not exported — no `0x10EEEE`, no diacritic table, no placeholder
/// iterator, and `placement_rect`/`placement_viewport_pos` documented as refusing
/// virtual placements — `KittyGraphics` (1,066 lines) and `UnicodePlaceholder`
/// (226) came straight back. That conclusion assumed we needed libghostty-vt to
/// *draw*. We do not. What a placeholder layer needs is three things about each
/// cell and two about each image, and every one of them is exported:
///
/// | What our decoder needs | Where it comes from |
/// |---|---|
/// | the cell is U+10EEEE | `ghostty_cell_get(GHOSTTY_CELL_DATA_CODEPOINT)` |
/// | its row/column diacritics | `ghostty_grid_ref_graphemes` |
/// | the image id in its colour | `ghostty_grid_ref_style().fg_color`, raw |
/// | the picture in cells | `PLACEMENT_DATA_COLUMNS` / `_ROWS` on the virtual placement |
/// | the pixels | `ghostty_kitty_graphics_image` → `WIDTH`/`HEIGHT`/`FORMAT`/`DATA_PTR` |
///
/// The two calls that refuse virtual placements are the two we do not need:
/// they answer "where on the screen is this picture", and for a placeholder
/// picture the *cells* answer that, which is the whole point of the indirection.
/// `ghostty_kitty_graphics_image` takes a bare image id and does not care
/// whether the placement referring to it is virtual.
///
/// So the shape is **their state machine, their placement store, our placeholder
/// layer on top**, and what comes back from 0474's 1,292 lines is this file plus
/// `UnicodePlaceholder` (226) — the decoder and the fragment arithmetic — and
/// not `KittyGraphics`' parser, chunk reassembly, base64, inflate, PNG decode,
/// id assignment or eviction, all of which libghostty-vt does.
struct GhosttyGraphicsBridge {
	/// What one sync produced, in the shapes `TerminalImageStore` holds.
	struct Snapshot {
		var images: [UInt32: TerminalImage] = [:]
		/// Real (`t=f`) placements, at absolute rows.
		var placements: [TerminalImagePlacement] = []
		/// Virtual (`U=1`) placements, waiting for placeholder cells to say where
		/// they go.
		var virtual: [TerminalImageStore.VirtualKey: TerminalImageStore.VirtualPlacement] = [:]
		/// libghostty-vt's own storage generation, so an unchanged store can be
		/// skipped entirely.
		var generation: UInt64 = 0
	}

	/// Everything in the terminal's kitty storage, converted.
	///
	/// `scrollbackCount` turns libghostty-vt's viewport-relative placement rows
	/// into the absolute rows `TerminalImagePlacement` is documented to hold. That
	/// is only right while the viewport is pinned to the active area, which it
	/// always is here: this engine never scrolls libghostty-vt's viewport, because
	/// scrolling back is our own view walking a snapshot.
	static func snapshot(of terminal: GhosttyTerminal, scrollbackCount: Int) -> Snapshot? {
		var handle: GhosttyKittyGraphics?
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS, &handle)
			== GHOSTTY_SUCCESS, let handle
		else { return nil }

		var result = Snapshot()
		var generation: UInt64 = 0
		ghostty_kitty_graphics_get(handle, GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION, &generation)
		result.generation = generation
		// Zero means the storage has never been mutated, so there is nothing to
		// enumerate. This is the common case — most panes never show a picture —
		// and it is why the sync costs a single FFI call in ordinary use.
		guard generation != 0 else { return result }

		var created: GhosttyKittyGraphicsPlacementIterator?
		guard ghostty_kitty_graphics_placement_iterator_new(nil, &created) == GHOSTTY_SUCCESS,
		      let iterator = created
		else { return result }
		defer { ghostty_kitty_graphics_placement_iterator_free(iterator) }
		// The iterator is created empty and *populated* from the storage, which is
		// why this is a `get` on the storage rather than a call on the iterator.
		guard ghostty_kitty_graphics_get(
			handle, GHOSTTY_KITTY_GRAPHICS_DATA_PLACEMENT_ITERATOR, &created) == GHOSTTY_SUCCESS
		else { return result }

		while ghostty_kitty_graphics_placement_next(iterator) {
			var imageID: UInt32 = 0
			var placementID: UInt32 = 0
			var isVirtual = false
			var columns: UInt32 = 0
			var rows: UInt32 = 0
			var z: Int32 = 0
			var offsetX: UInt32 = 0
			var offsetY: UInt32 = 0
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IMAGE_ID, &imageID)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_PLACEMENT_ID, &placementID)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL, &isVirtual)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_COLUMNS, &columns)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_ROWS, &rows)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Z, &z)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_X_OFFSET, &offsetX)
			ghostty_kitty_graphics_placement_get(
				iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Y_OFFSET, &offsetY)

			guard let image = ghostty_kitty_graphics_image(handle, imageID) else { continue }
			if result.images[imageID] == nil, let converted = pixels(of: image, id: imageID) {
				result.images[imageID] = converted
			}

			// The source rectangle, resolved: a zero width or height means the
			// whole image, and the library clamps to the image's real bounds. This
			// one works for virtual placements too — it asks nothing about where
			// the placement is.
			var sourceX: UInt32 = 0, sourceY: UInt32 = 0
			var sourceWidth: UInt32 = 0, sourceHeight: UInt32 = 0
			guard ghostty_kitty_graphics_placement_source_rect(
				iterator, image, &sourceX, &sourceY, &sourceWidth, &sourceHeight) == GHOSTTY_SUCCESS
			else { continue }
			let source = TerminalImagePlacement.Rectangle(
				x: Int(sourceX), y: Int(sourceY),
				width: Int(sourceWidth), height: Int(sourceHeight))

			if isVirtual {
				// A virtual placement has a size in cells and no position. Its
				// columns and rows come straight off the transmit command — `c=46,
				// r=26` in 0468's capture — and the raw getters answer for a
				// virtual placement even though `placement_grid_size` refuses one.
				guard columns > 0, rows > 0 else { continue }
				let key = TerminalImageStore.VirtualKey(
					imageID: imageID, placementID: placementID)
				result.virtual[key] = TerminalImageStore.VirtualPlacement(
					columns: Int(columns), rows: Int(rows), source: source, z: z)
				continue
			}

			// A real placement knows where it is, and the library does the
			// pixels-to-cells arithmetic that 0468 was about.
			var gridColumns: UInt32 = 0, gridRows: UInt32 = 0
			guard ghostty_kitty_graphics_placement_grid_size(
				iterator, image, terminal, &gridColumns, &gridRows) == GHOSTTY_SUCCESS
			else { continue }
			var viewportColumn: Int32 = 0, viewportRow: Int32 = 0
			guard ghostty_kitty_graphics_placement_viewport_pos(
				iterator, image, terminal, &viewportColumn, &viewportRow) == GHOSTTY_SUCCESS
			else { continue }

			result.placements.append(TerminalImagePlacement(
				imageID: imageID,
				placementID: placementID,
				row: scrollbackCount + Int(viewportRow),
				column: Int(viewportColumn),
				columns: Int(gridColumns),
				rows: Int(gridRows),
				source: source,
				offsetX: Int(offsetX),
				offsetY: Int(offsetY),
				z: z))
		}
		return result
	}

	/// One stored image, in the premultiplied RGBA `TerminalImage` promises.
	///
	/// libghostty-vt always hands back decoded, uncompressed pixels — PNG is
	/// decoded and zlib inflated before storage — but in the format the program
	/// sent, which may be RGB, grey or grey-plus-alpha. Both of our drawing paths
	/// want premultiplied RGBA and nothing else, so the widening happens here.
	private static func pixels(
		of image: GhosttyKittyGraphicsImage, id: UInt32
	) -> TerminalImage? {
		var width: UInt32 = 0, height: UInt32 = 0
		var number: UInt32 = 0
		var format = GHOSTTY_KITTY_IMAGE_FORMAT_RGBA
		var data: UnsafePointer<UInt8>?
		var length = 0
		ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_WIDTH, &width)
		ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_HEIGHT, &height)
		ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_NUMBER, &number)
		ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_FORMAT, &format)
		ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_DATA_LEN, &length)
		// A payload still arriving reports its expected length but no pointer, and
		// the header says so. Nothing is drawn until it is all there, which is a
		// refusal rather than a half picture.
		guard ghostty_kitty_graphics_image_get(
			image, GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR, &data) == GHOSTTY_SUCCESS,
			let data, width > 0, height > 0, length > 0
		else { return nil }

		let pixelCount = Int(width) * Int(height)
		let source = UnsafeBufferPointer(start: data, count: length)
		var rgba = [UInt8](repeating: 255, count: pixelCount * 4)

		switch format {
		case GHOSTTY_KITTY_IMAGE_FORMAT_RGBA:
			guard length >= pixelCount * 4 else { return nil }
			for pixel in 0..<pixelCount {
				let alpha = UInt32(source[pixel * 4 + 3])
				for channel in 0..<3 {
					rgba[pixel * 4 + channel] =
						UInt8((UInt32(source[pixel * 4 + channel]) * alpha + 127) / 255)
				}
				rgba[pixel * 4 + 3] = source[pixel * 4 + 3]
			}
		case GHOSTTY_KITTY_IMAGE_FORMAT_RGB:
			guard length >= pixelCount * 3 else { return nil }
			for pixel in 0..<pixelCount {
				rgba[pixel * 4] = source[pixel * 3]
				rgba[pixel * 4 + 1] = source[pixel * 3 + 1]
				rgba[pixel * 4 + 2] = source[pixel * 3 + 2]
			}
		case GHOSTTY_KITTY_IMAGE_FORMAT_GRAY:
			guard length >= pixelCount else { return nil }
			for pixel in 0..<pixelCount {
				let grey = source[pixel]
				rgba[pixel * 4] = grey
				rgba[pixel * 4 + 1] = grey
				rgba[pixel * 4 + 2] = grey
			}
		case GHOSTTY_KITTY_IMAGE_FORMAT_GRAY_ALPHA:
			guard length >= pixelCount * 2 else { return nil }
			for pixel in 0..<pixelCount {
				let alpha = UInt32(source[pixel * 2 + 1])
				let grey = UInt8((UInt32(source[pixel * 2]) * alpha + 127) / 255)
				rgba[pixel * 4] = grey
				rgba[pixel * 4 + 1] = grey
				rgba[pixel * 4 + 2] = grey
				rgba[pixel * 4 + 3] = source[pixel * 2 + 1]
			}
		default:
			// The header says PNG is never reported, because it is decoded to RGBA
			// before storage. A format we do not know is a picture we do not draw.
			return nil
		}

		return TerminalImage(
			id: id, number: number,
			width: Int(width), height: Int(height), pixels: rgba)
	}
}

// MARK: - The PNG decoder libghostty-vt has to be given

/// `icat` sends `f=100`, which is PNG, and libghostty-vt has no PNG decoder of
/// its own: `GHOSTTY_SYS_OPT_DECODE_PNG` is how the embedder supplies one, and
/// without it every PNG transmit is rejected. This is the same ImageIO path
/// `KittyGraphics.decodePNG` uses, so both engines decode a picture identically.
///
/// Process-global and installed once. The decoded buffer has to be allocated
/// with the allocator handed to the callback, because the library takes
/// ownership and frees it with that same allocator.
enum GhosttyPngDecoder {
	private static let installed: Bool = {
		let decode: GhosttySysDecodePngFn = { _, allocator, data, length, out in
			guard let allocator, let data, let out, length > 0 else { return false }
			let png = Data(bytes: data, count: length)
			guard let source = CGImageSourceCreateWithData(png as CFData, nil),
			      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
			else { return false }

			let width = decoded.width
			let height = decoded.height
			// The same ceiling `KittyGraphics.decodePNG` uses: a header claiming a
			// picture nobody could draw is a refusal rather than an allocation.
			guard width > 0, height > 0, width * height <= 64_000_000 else { return false }

			let byteCount = width * height * 4
			guard let buffer = ghostty_alloc(allocator, byteCount) else { return false }
			guard let context = CGContext(
				data: buffer,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: width * 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			) else {
				ghostty_free(allocator, buffer, byteCount)
				return false
			}
			context.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))

			// **Undone again**, on purpose. CoreGraphics will only draw into a
			// premultiplied bitmap, but the kitty protocol's RGBA is straight
			// alpha and that is what libghostty-vt stores and what everything
			// reading `GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR` will assume — including
			// `GhosttyGraphicsBridge.pixels`, which premultiplies on the way out.
			// Premultiplying twice draws every partly transparent picture too
			// dark, and a picture that is subtly wrong is the failure this item
			// is most concerned with.
			for pixel in 0..<(width * height) {
				let alpha = UInt32(buffer[pixel * 4 + 3])
				guard alpha > 0, alpha < 255 else { continue }
				for channel in 0..<3 {
					buffer[pixel * 4 + channel] =
						UInt8(min(255, (UInt32(buffer[pixel * 4 + channel]) * 255 + alpha / 2) / alpha))
				}
			}

			out.pointee.width = UInt32(width)
			out.pointee.height = UInt32(height)
			out.pointee.data = buffer
			out.pointee.data_len = byteCount
			return true
		}
		return ghostty_sys_set(
			GHOSTTY_SYS_OPT_DECODE_PNG,
			unsafeBitCast(decode, to: UnsafeRawPointer.self)) == GHOSTTY_SUCCESS
	}()

	/// Installs the decoder if it is not installed, and says whether it is.
	@discardableResult static func install() -> Bool { installed }
}
