import AppKit
import AbydosKit
import Metal
import simd

/// One cell as the shaders want it. Must match `CellInstance` in the shader.
struct CellInstance {
	var origin: SIMD2<Float>
	var size: SIMD2<Float>
	var glyphOrigin: SIMD2<Float>
	var glyphSize: SIMD2<Float>
	var uvOrigin: SIMD2<Float>
	var uvSize: SIMD2<Float>
	var foreground: SIMD4<Float>
	var background: SIMD4<Float>
	var isColour: Float
}

/// One picture as its shader wants it. Must match `ImageInstance` in the shader.
private struct ImageInstance {
	var origin: SIMD2<Float>
	var size: SIMD2<Float>
	var uvOrigin: SIMD2<Float>
	var uvSize: SIMD2<Float>
}

private struct Uniforms {
	var viewport: SIMD2<Float>
	/// How much of the bell is left to show, 1 down to 0.
	var bell: Float = 0
	/// Seconds since it rang, which keeps the wobble moving as it fades.
	var bellTime: Float = 0
	/// Where the visible window is in the document the cells were built in.
	var scroll: SIMD2<Float> = .zero
	/// Which pass over the cells: 0 paints backgrounds, 1 paints glyphs. See
	/// the fragment shader for why there are two.
	var pass: Float = 0
}

/// Draws the terminal grid on the GPU.
///
/// Every cell of the screen becomes one instance of a quad, and the whole
/// screen is one draw call. What made the CoreGraphics path slow was not the
/// work but the count of it — ten thousand rectangle fills and ten thousand
/// glyph draws for a screen where every cell has its own colour. The GPU does
/// not care how many cells differ.
@MainActor
final class TerminalMetalRenderer {
	let device: MTLDevice
	private let queue: MTLCommandQueue
	private let pipeline: MTLRenderPipelineState
	/// The kitty graphics protocol's pictures, which are not glyphs and do not
	/// go through the atlas.
	private let imagePipeline: MTLRenderPipelineState
	private(set) var atlas: GlyphAtlas

	private var instances: [CellInstance] = []
	private var instanceBuffer: MTLBuffer?

	/// What each row came to last time it was built, keyed by line number.
	///
	/// This is the whole of item 0488. A frame used to turn every cell on screen
	/// into instances whether it had changed or not — 10,904 of them on this
	/// machine, every frame, for ever — and the engine has been able to say
	/// which rows moved the entire time. A row nobody has touched is copied out
	/// of here instead, which is a memcpy where it was a palette lookup, an
	/// atlas lookup and a ligature scan per cell.
	///
	/// Keyed by *line number* rather than by the absolute row it currently sits
	/// at, because absolute rows shift when history is dropped and a key that
	/// moves under what it names is not a key. See `TerminalDirtyRows`.
	private var rowCache: [Int: [CellInstance]] = [:]

	/// The line whose top edge is at `inset.y` in the coordinates cached rows
	/// are built in.
	///
	/// Cells go into the buffer measured from here and the scroll offset in the
	/// uniforms takes them the rest of the way, so a row keeps its instances
	/// while the picture scrolls under it. Moved only when the distance from it
	/// grows far enough to be worth worrying about in a `Float` — which costs
	/// one frame built in full, once every 32,768 lines that leave history.
	private var documentBase = 0
	private static let longestRunFromBase = 1 << 15

	/// Whether rows are kept between frames at all. `ABYDOS_METAL_ROW_CACHE=0`
	/// says no, and every row of every frame is built as it was before 0488.
	///
	/// Here because of the morning item 0487 spent: it read two numbers from two
	/// binaries whose benchmark body had changed in between, and neither figure
	/// was a measurement of the same thing as the other. One binary that can be
	/// asked for either behaviour cannot make that mistake — the before and the
	/// after come out of the same build, the same window, the same load and the
	/// same minute, and the only difference between them is the thing being
	/// measured.
	private static let keepsRows = ProcessInfo.processInfo.environment["ABYDOS_METAL_ROW_CACHE"] != "0"

	/// What the cached rows were built against. Anything here changing means
	/// every one of them is about something that is no longer true.
	private struct RowContext: Equatable {
		var cellSize: CGSize
		var inset: CGPoint
		var background: SIMD4<Float>
		var foreground: SIMD4<Float>
		var baselineFromTop: CGFloat
		var scale: CGFloat
		var hoveredLink: UInt16
		var ligatures: Bool
		var faces: ObjectIdentifier
		var atlas: ObjectIdentifier
		var atlasGeneration: Int
		var documentBase: Int
		var cutouts: [Cutout]
	}

	private var rowContext: RowContext?
	/// The cursor in the frame before this one, and which line it was on, so the
	/// row it has left is built again along with the one it has arrived on.
	///
	/// The line number rather than the absolute row it came in as: a frame later,
	/// the absolute row may be a different line.
	private var lastCursor: Cursor?
	private var lastCursorLine: Int?

	/// Cells built this frame, and rows. Both are for `ABYDOS_METAL_PROBE`,
	/// which is how item 0488 was found and how it is shown to have worked.
	private(set) var cellsBuilt = 0
	private(set) var rowsBuilt = 0

	/// Where the window is in the document, for the uniforms.
	private var scroll = SIMD2<Float>(0, 0)

	/// Throws away every row kept from the last frame.
	///
	/// For the changes that alter the picture without altering the grid — a
	/// theme, a font, the keyboard arriving. `repaint()` means "all of this may
	/// differ", and this is what that means for a renderer that keeps things.
	func invalidateRows() {
		rowCache.removeAll(keepingCapacity: true)
		rowContext = nil
	}

	/// One texture per picture the terminal is holding, built the first time it
	/// is drawn and kept until the program deletes it.
	private var imageTextures: [UInt32: MTLTexture] = [:]
	/// What the store's generation was when the textures were last checked.
	private var lastGraphicsGeneration = -1
	/// This frame's pictures, split by whether they go under the text or over it.
	private var imagesBelow: [(payload: ImageInstance, texture: MTLTexture)] = []
	private var imagesAbove: [(payload: ImageInstance, texture: MTLTexture)] = []

	/// Cells a picture is showing through from behind.
	///
	/// Every cell paints its own background here, unlike the CoreGraphics path,
	/// which skips the fill when the colour is the default one. That is normally
	/// the cheaper choice — one uniform quad rather than a test per cell — but it
	/// would paint flat over a picture placed below the text and leave nothing of
	/// it to see. These are the cells that must leave their background alone.
	private struct Cutout: Equatable {
		var rows: ClosedRange<Int>
		var columns: Range<Int>
	}

	private var cutouts: [Cutout] = []

	/// Points to pixels.
	var scale: CGFloat {
		didSet {
			guard scale != oldValue, let fresh = GlyphAtlas(device: device, scale: scale) else { return }
			atlas = fresh
		}
	}

	init?(scale: CGFloat) {
		guard let device = MTLCreateSystemDefaultDevice(),
		      let queue = device.makeCommandQueue(),
		      let atlas = GlyphAtlas(device: device, scale: scale)
		else { return nil }

		let library: MTLLibrary
		do {
			library = try device.makeLibrary(source: TerminalShaders.source, options: nil)
		} catch {
			FileHandle.standardError.write(Data("terminal shaders failed: \(error)\n".utf8))
			return nil
		}

		let descriptor = MTLRenderPipelineDescriptor()
		descriptor.vertexFunction = library.makeFunction(name: "cellVertex")
		descriptor.fragmentFunction = library.makeFunction(name: "cellFragment")
		descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		// Straight alpha, so a glyph reaching outside its cell blends with what
		// its neighbour already put there rather than punching a hole in it.
		descriptor.colorAttachments[0].isBlendingEnabled = true
		descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
		descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
		descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
		descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

		guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

		// The same target and the same blending, except that a picture's colours
		// already have their alpha multiplied in — which is the one form both
		// drawing paths can share — so the source is taken whole rather than
		// scaled by its alpha a second time.
		let imageDescriptor = MTLRenderPipelineDescriptor()
		imageDescriptor.vertexFunction = library.makeFunction(name: "imageVertex")
		imageDescriptor.fragmentFunction = library.makeFunction(name: "imageFragment")
		imageDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		imageDescriptor.colorAttachments[0].isBlendingEnabled = true
		imageDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
		imageDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
		imageDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
		imageDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

		guard let imagePipeline = try? device.makeRenderPipelineState(descriptor: imageDescriptor) else {
			return nil
		}

		self.device = device
		self.queue = queue
		self.pipeline = pipeline
		self.imagePipeline = imagePipeline
		self.atlas = atlas
		self.scale = scale
	}

	private var shapedRuns = ShapedRuns()

	func clearGlyphs() {
		atlas.removeAll()
		shapedRuns.removeAll()
	}

	/// Whether a cell's character can be handed to the font at all.
	///
	/// A powerline separator, a box drawing and a block element are drawn here
	/// as geometry rather than taken from the font, and a placeholder is a
	/// piece of a picture rather than a character. None of them belongs in a
	/// shaped span.
	private func canShape(_ cell: TerminalCell) -> Bool {
		cell.scalar != 0 && cell.scalar != UnicodePlaceholder.scalar
			&& !PowerlineGlyph.isSeparator(cell.scalar) && !BoxDrawing.draws(cell.scalar)
			&& !GlyphAtlas.tiles(cell.scalar) && UnicodeScalar(cell.scalar) != nil
	}

	/// Which cells of a line draw a shaped glyph instead of their own, and
	/// which draw nothing because a ligature covers them.
	///
	/// A present value of `.some(piece)` is a glyph to draw at that cell; a
	/// present `.some(nil)` is a cell a ligature has swallowed. A cell missing
	/// from the map is untouched and drawn the usual way, which is every cell
	/// when ligatures are off or nothing on the line can join.
	private func ligatures(
		in line: TerminalLine, faces: TerminalFaces
	) -> [Int: ShapedRuns.Piece?] {
		guard Settings.shared.fontLigatures else { return [:] }

		var map: [Int: ShapedRuns.Piece?] = [:]
		var start = 0
		let cells = line.cells
		while start < cells.count {
			var end = start + 1
			while end < cells.count, cells[end].attributes == cells[start].attributes { end += 1 }
			defer { start = end }
			guard Ligatures.mayLigate(cells[start..<end].lazy.map(\.scalar)) else { continue }

			let faceIndex = TerminalFaces.index(
				bold: cells[start].attributes.bold, italic: cells[start].attributes.italic
			)
			let face = faces.face(
				bold: cells[start].attributes.bold, italic: cells[start].attributes.italic
			)

			// A run is shaped in the stretches of it the font can be asked
			// about, not in one piece. One character it cannot be asked about
			// used to take the whole run's ligatures, and that is the bug: a
			// tmux pane border is drawn in the *default* colour while its pane
			// is not the active one, so it shares the attributes of the text
			// on either side of it and lands in the same run. Every line the
			// border crossed lost its ligatures, and making the other pane
			// active — which paints the border green — gave them back. The
			// same for a prompt's separators and for a picture.
			for span in Ligatures.spans(in: start..<end, canShape: { canShape(cells[$0]) }) {
				let spanStart = span.lowerBound
				let spanEnd = span.upperBound
				guard Ligatures.mayLigate(cells[span].lazy.map(\.scalar)) else { continue }

				// The span's characters, one per cell, and where each came from.
				var text = ""
				var cellOfOffset: [Int] = []
				for column in spanStart..<spanEnd {
					let cell = cells[column]
					if cell.isWideTrailer { continue }
					guard let scalar = UnicodeScalar(cell.scalar) else { continue }
					let piece = cell.combining ?? String(Character(scalar))
					text += piece
					// Relative to the span, so the cache can be keyed by the
					// text alone and still be right for the same span somewhere
					// else.
					cellOfOffset.append(
						contentsOf: Array(repeating: column - spanStart, count: piece.utf16.count)
					)
				}
				guard !text.isEmpty else { continue }

				guard let pieces = shapedRuns.pieces(
					for: text, cellOfOffset: cellOfOffset, font: face, faceIndex: faceIndex
				) else { continue }
				// One glyph per character, still: these fonts substitute shapes
				// rather than merging cells, which is what keeps the grid. So the
				// count is no guide to whether anything joined, and the shaped
				// glyphs are simply used — identical to the per-cell ones wherever
				// nothing did.
				for column in spanStart..<spanEnd { map[column] = .some(nil) }
				for piece in pieces { map[spanStart + piece.cellOffset] = piece }
			}
		}
		return map
	}


	// MARK: - Building

	/// Describes what a frame should contain, in the view's own coordinates.
	struct Frame {
		var cellSize: CGSize
		var inset: CGPoint
		/// Where the visible window starts within the document.
		var origin: CGPoint
		var background: SIMD4<Float>
		var foreground: SIMD4<Float>
		/// How many lines have fallen out of history, which is the difference
		/// between the absolute rows this frame names and the line numbers the
		/// kept rows are filed under.
		var discardedLineCount = 0
	}

	/// Turns rows of cells into instances.
	///
	/// `rows` are the lines to draw with the absolute index each one sits at, so
	/// a line keeps its place whatever is above it.
	/// A block of colour laid over the cells, for the cursor and the selection.
	struct Overlay {
		var row: Int
		var columns: Range<Int>
		var colour: SIMD4<Float>
	}

	/// Where the block cursor is, and what colour it is.
	///
	/// Equatable because a cursor is the one thing that changes a row without
	/// the engine having written to it: the cell under a block is turned inside
	/// out as it is built, so the row the cursor arrives on and the row it has
	/// left both have to be built again even though neither changed.
	struct Cursor: Equatable {
		var row: Int
		var column: Int
		var colour: SIMD4<Float>
		/// Block, underline or bar, as the program asked (DECSCUSR).
		var shape: TerminalEmulator.CursorShape = .block
		/// Filled where the keyboard is; an outline where it is not.
		var isFilled = true
		/// How thick that outline is, in points.
		var thickness: Float = 1.5
	}

	/// The hyperlink under the pointer, which is drawn underlined so it is
	/// visible that it can be clicked at all.
	var hoveredLink: UInt16 = 0

	/// A thin filled rectangle: an underline, or a line through.
	private func rule(x: Float, width: Float, y: Float, colour: SIMD4<Float>) -> CellInstance {
		CellInstance(
			origin: SIMD2(x, y),
			size: SIMD2(width, max(1, Float(1.0))),
			glyphOrigin: .zero,
			glyphSize: .zero,
			uvOrigin: .zero,
			uvSize: .zero,
			foreground: colour,
			background: colour,
			isColour: 0
		)
	}

	/// Turns the rows of a frame into instances, building only the ones that
	/// changed and copying the rest out of the frame before.
	///
	/// `changed` is the rows the engine reported, as line numbers — see
	/// `TerminalDirtyRows` for why they are line numbers and not the absolute
	/// rows `rows` carries. Nil means the engine reported nothing, which is a
	/// frame drawn for some other reason: the cursor moving, the bell, a scroll.
	func build(
		rows: [(index: Int, line: TerminalLine)],
		changed: ClosedRange<Int>? = nil,
		frame: Frame,
		faces: TerminalFaces,
		overlays: [Overlay] = [],
		cursor: Cursor? = nil
	) {
		instances.removeAll(keepingCapacity: true)
		cellsBuilt = 0
		rowsBuilt = 0
		// First, because emptying the atlas moves every glyph in it and the
		// rows kept from the last frame are full of coordinates into it.
		atlas.setCellMetrics(size: frame.cellSize, baselineFromTop: faces.baselineFromTop)

		// Asked to keep nothing, which is the renderer as it was before 0488 and
		// is how the two are measured against each other.
		if !Self.keepsRows { rowCache.removeAll(keepingCapacity: true) }

		// Far enough from where the kept rows are measured from that a `Float`
		// is worth thinking about: measure from here instead. One frame built in
		// full, once every 32,768 lines that leave history.
		let fromBase = frame.discardedLineCount - documentBase
		if fromBase < 0 || fromBase > Self.longestRunFromBase {
			documentBase = frame.discardedLineCount
			rowCache.removeAll(keepingCapacity: true)
		}

		// Everything a kept row assumed and cannot check for itself.
		let context = RowContext(
			cellSize: frame.cellSize,
			inset: frame.inset,
			background: frame.background,
			foreground: frame.foreground,
			baselineFromTop: faces.baselineFromTop,
			scale: scale,
			hoveredLink: hoveredLink,
			ligatures: Settings.shared.fontLigatures,
			faces: ObjectIdentifier(faces.regular),
			atlas: ObjectIdentifier(atlas),
			atlasGeneration: atlas.generation,
			documentBase: documentBase,
			cutouts: cutouts
		)
		if rowContext != context {
			rowCache.removeAll(keepingCapacity: true)
			rowContext = context
		}

		let pixel = Float(scale)
		func snap(_ value: Float) -> Float { (value * pixel).rounded() / pixel }

		// Every edge lands on a whole point, and each cell's far edge is the
		// next cell's near edge rather than its own width rounded separately.
		// Otherwise neighbouring backgrounds miss each other by a fraction of a
		// pixel and a dark seam runs between the segments of a prompt.
		//
		// In the document rather than in the window: the scroll offset is
		// subtracted in the shader, so where a row sits does not depend on where
		// the window is looking. That is what lets a row keep the instances it
		// was built with while output scrolls the picture under it. It comes out
		// at the same whole point either way, because the inset and the cell are
		// both whole numbers of points and only the offset is not.
		func columnEdge(_ column: Int) -> Float {
			Float((frame.inset.x + CGFloat(column) * frame.cellSize.width).rounded())
		}
		func rowEdge(_ row: Int) -> Float {
			let line = row + frame.discardedLineCount - documentBase
			return Float((frame.inset.y + CGFloat(line) * frame.cellSize.height).rounded())
		}

		scroll = SIMD2(
			Float(frame.origin.x.rounded()),
			Float((frame.origin.y
				+ CGFloat(frame.discardedLineCount - documentBase) * frame.cellSize.height).rounded())
		)

		/// One row's worth of instances, in document coordinates.
		func buildRow(index: Int, line: TerminalLine) -> [CellInstance] {
			var built: [CellInstance] = []
			built.reserveCapacity(line.cells.count)
			let y = rowEdge(index)
			let rowHeight = rowEdge(index + 1) - y
			// Just below the baseline, where an underline belongs.
			let underlineOffset = min(rowHeight - 1, Float(faces.baselineFromTop) + 2)

			// What the shaper made of this row's runs, if ligatures are wanted
			// and any run could have one. Empty otherwise, and the per-cell path
			// below is unchanged — which is also where anything this cannot
			// handle ends up, since every step of it can decline.
			let ligated = ligatures(in: line, faces: faces)

			for (column, cell) in line.cells.enumerated() {
				if cell.isWideTrailer { continue }

				let resolved = cell.attributes.resolved
				// `isForeground` follows the swap: for an inverse cell `resolved`
				// has moved the background into the foreground slot, so a
				// `.default` there means the default background. Resolving it as
				// a foreground is what made an inverse cell with no colours set
				// draw exactly like a plain one.
				var foreground = TerminalPalette.components(
					for: resolved.foreground,
					isForeground: !cell.attributes.inverse,
					bold: cell.attributes.bold,
					defaultForeground: frame.foreground,
					defaultBackground: frame.background
				)
				// Dimming is the alpha the CoreGraphics path uses, done here as
				// arithmetic rather than by asking for another colour.
				if cell.attributes.dim { foreground.w *= Float(TerminalPalette.dimAmount) }
				var background = TerminalPalette.components(
					for: resolved.background,
					isForeground: cell.attributes.inverse,
					bold: false,
					defaultForeground: frame.foreground,
					defaultBackground: frame.background
				)
				// A cell that asked for no particular colour, over a picture, is
				// asking for the picture. One that named a colour meant it, and
				// paints over the picture as it would over anything else.
				// An inverse cell named a colour by asking for the other one, so
				// it paints over a picture like any other coloured cell.
				if resolved.background == .default, !cell.attributes.inverse,
				   isCutOut(row: index, column: column) {
					background.w = 0
				}

				// The cell under a block cursor is turned inside out: the block
				// is the cursor's colour and the character is cut out of it in
				// the colour behind. Laying a block over the character instead
				// leaves it the same colour as what is now behind it, which is
				// how it becomes unreadable exactly where you are looking.
				// Only a block turns the cell inside out; an underline or a bar
				// is drawn over it afterwards and leaves the character alone.
				if let cursor, cursor.isFilled, cursor.shape == .block,
				   cursor.row == index, cursor.column == column {
					background = cursor.colour
					foreground = frame.background
				}

				let x = columnEdge(column)
				let isWide = column + 1 < line.cells.count && line.cells[column + 1].isWideTrailer
				let width = columnEdge(column + (isWide ? 2 : 1)) - x

				var instance = CellInstance(
					origin: SIMD2(x, y),
					size: SIMD2(width, rowHeight),
					glyphOrigin: .zero,
					glyphSize: .zero,
					uvOrigin: .zero,
					uvSize: .zero,
					foreground: cell.attributes.hidden ? background : foreground,
					background: background,
					isColour: 0
				)

				// A placeholder is a piece of a picture, not a character: drawn
				// as one it is a private-use codepoint no font has, and the
				// picture arrives under a grid of missing-glyph boxes.
				if !cell.attributes.hidden, cell.scalar != 0x20, cell.scalar != 0,
				   cell.scalar != UnicodePlaceholder.scalar {
					let faceIndex = TerminalFaces.index(
						bold: cell.attributes.bold, italic: cell.attributes.italic
					)
					let face = faces.face(bold: cell.attributes.bold, italic: cell.attributes.italic)
					// A cell the shaper covered draws what the shaper chose, and
					// nothing at all when that choice has no ink.
					//
					// The second half is the whole of a bug worth remembering.
					// These fonts do not merge cells: a ligature is one glyph
					// carrying the ink for the group, sitting on the *last*
					// cell with a bearing that reaches back over the others —
					// `...` is 16pt of ink hanging off a cell 8.4pt wide — and
					// every cell before it gets a carrier glyph that is
					// deliberately empty. The atlas has nothing to rasterise for
					// an empty glyph and answers nil, which used to fall through
					// to "then draw the character itself". So the first cell
					// drew a plain `.` and the last drew the ligature over it:
					// two dots for `..`, three for `...`, and the first of `!!`
					// painted twice. Only here, because the editor hands the
					// whole line to CoreText, which draws an empty glyph as
					// nothing without being told.
					//
					// Nil either way is a cell with nothing to draw — and it
					// falls through rather than skipping the cell, because the
					// cell still has a background. Skipping it left a black
					// column down every `///` in a diff: three cells, two of
					// them carriers, and the green they were sitting on never
					// painted.
					let entry: AtlasEntry?
					if let covered = ligated[column] {
						entry = covered.flatMap {
							atlas.entry(forGlyph: $0.glyph, in: $0.font, faceIndex: faceIndex)
						}
					} else {
						entry = atlas.entry(for: cell.scalar, font: face, faceIndex: faceIndex)
					}
					if let entry {
						// A glyph hangs off the baseline, which sits a fixed
						// distance down the cell; a separator is the cell.
						// A separator or a tiling character is the cell; anything
						// else hangs off the baseline.
						let fillsCell = PowerlineGlyph.isSeparator(cell.scalar)
							|| BoxDrawing.draws(cell.scalar)
							|| GlyphAtlas.tiles(cell.scalar)
						let anchor = fillsCell ? y : y + Float(faces.baselineFromTop)
						// Snapped to whole pixels. The glyph was rasterised at
						// one position inside its bitmap, so landing it on a
						// fraction of a pixel resamples it — by a different
						// fraction for each cell, since a bearing is fractional
						// and a cell edge is not. Letters then sit unevenly
						// however exactly the cells themselves line up.
						instance.glyphOrigin = SIMD2(
							snap(x + Float(entry.offset.x)),
							snap(anchor + Float(entry.offset.y))
						)
						instance.glyphSize = SIMD2(Float(entry.size.width), Float(entry.size.height))
						instance.uvOrigin = entry.uvOrigin
						instance.uvSize = entry.uvSize
						instance.isColour = entry.isColour ? 1 : 0
					}
				}

				built.append(instance)
				// Counted here rather than from the row's width, so that it is
				// the same count as the instances it used to be: a cell a wide
				// glyph has swallowed produces neither.
				cellsBuilt += 1

				// Lines through and under the text, which the GPU path never
				// drew at all: a man page's underlined headings and a diff's
				// struck-out text came out plain.
				let isLinked = cursor == nil && cell.attributes.link != 0 && cell.attributes.link == hoveredLink
				if cell.attributes.underline || isLinked {
					built.append(rule(x: x, width: width, y: y + underlineOffset, colour: foreground))
				}
				if cell.attributes.strikethrough {
					built.append(rule(x: x, width: width, y: y + rowHeight * 0.45, colour: foreground))
				}
			}
			rowsBuilt += 1
			return built
		}

		// The cursor is drawn into the cell it is on, so the row it has arrived
		// on and the row it has left are both out of date however little the
		// engine says changed. Everything else that moves without a row being
		// written to — the selection, the hovered link, the bell — is either
		// laid over the cells afterwards or is a uniform, except the link, which
		// is in the context above and takes the lot.
		let cursorLine = cursor.map { $0.row + frame.discardedLineCount }
		if cursor != lastCursor {
			for line in [cursorLine, lastCursorLine] {
				guard let line else { continue }
				rowCache[line] = nil
			}
			lastCursor = cursor
			lastCursorLine = cursorLine
		}

		for (index, line) in rows {
			let number = index + frame.discardedLineCount
			if let kept = rowCache[number], !(changed?.contains(number) ?? false) {
				instances.append(contentsOf: kept)
				continue
			}
			let built = buildRow(index: index, line: line)
			rowCache[number] = built
			instances.append(contentsOf: built)
		}

		// Rows nobody can see are dropped, every frame and not only when there
		// are too many of them, and that is a correctness rule rather than a
		// bound on memory. A row off screen goes on changing — output arrives at
		// the bottom while somebody reads history further up — and the range
		// that said so is taken by a frame which had no reason to build it. So
		// what a kept row is allowed to mean is exactly this: it was on screen
		// when the last frame was built, and every range since has been asked.
		// Anything else has to be built again when it comes back into view.
		if let first = rows.first?.index, let last = rows.last?.index {
			let shown = (first + frame.discardedLineCount)...(last + frame.discardedLineCount)
			if rowCache.count != rows.count {
				rowCache = rowCache.filter { shown.contains($0.key) }
			}
		} else {
			rowCache.removeAll(keepingCapacity: true)
		}

		// After the cells, so they land on top of them: the selection tints what
		// is underneath rather than replacing it, and the cursor is a block the
		// character shows through.
		for overlay in overlays {
			let y = rowEdge(overlay.row)
			let x = columnEdge(overlay.columns.lowerBound)
			instances.append(CellInstance(
				origin: SIMD2(x, y),
				size: SIMD2(
					columnEdge(overlay.columns.upperBound) - x,
					rowEdge(overlay.row + 1) - y
				),
				glyphOrigin: .zero,
				glyphSize: .zero,
				uvOrigin: .zero,
				uvSize: .zero,
				foreground: overlay.colour,
				background: overlay.colour,
				isColour: 0
			))
		}

		// A cursor that is not a block: a line under the cell, or a bar at its
		// leading edge — which is what vim asks for in insert mode, and saying
		// "block" there is a lie about what typing will do.
		if let cursor, cursor.isFilled, cursor.shape != .block {
			let y = rowEdge(cursor.row)
			let height = rowEdge(cursor.row + 1) - y
			let x = columnEdge(cursor.column)
			let width = columnEdge(cursor.column + 1) - x
			let thickness = snap(cursor.thickness)

			instances.append(rule(
				x: x,
				width: cursor.shape == .bar ? thickness : width,
				y: cursor.shape == .bar ? y : y + height - thickness,
				colour: cursor.colour
			))
			if cursor.shape == .bar {
				// A bar is as tall as the cell, which `rule` is not.
				instances[instances.count - 1].size = SIMD2(thickness, height)
			}
		}

		// An outlined cursor is four thin blocks rather than a filled one: the
		// character underneath is left exactly as it was written, which is what
		// says the keyboard is elsewhere rather than that the text changed.
		if let cursor, !cursor.isFilled {
			let y = rowEdge(cursor.row)
			let height = rowEdge(cursor.row + 1) - y
			let x = columnEdge(cursor.column)
			let width = columnEdge(cursor.column + 1) - x
			let edge = snap(cursor.thickness)

			for side in [
				(x: x, y: y, width: width, height: edge),
				(x: x, y: y + height - edge, width: width, height: edge),
				(x: x, y: y, width: edge, height: height),
				(x: x + width - edge, y: y, width: edge, height: height),
			] {
				instances.append(CellInstance(
					origin: SIMD2(side.x, side.y),
					size: SIMD2(side.width, side.height),
					glyphOrigin: .zero,
					glyphSize: .zero,
					uvOrigin: .zero,
					uvSize: .zero,
					foreground: cursor.colour,
					background: cursor.colour,
					isColour: 0
				))
			}
		}
	}

	var instanceCount: Int { instances.count }

	// MARK: - Pictures

	/// Works out where this frame's pictures go, and makes textures for any that
	/// have not been drawn before.
	///
	/// Separate from `build` because a picture is not a cell: it has its own
	/// pipeline, its own texture, and there are a handful of them rather than
	/// thousands.
	/// Must run before `build` for the frame: what it works out about pictures
	/// behind the text is what tells the cells to leave those backgrounds alone.
	func buildImages(placements: [TerminalImagePlacement], store: TerminalImageStore, frame: Frame) {
		imagesBelow.removeAll(keepingCapacity: true)
		imagesAbove.removeAll(keepingCapacity: true)
		cutouts.removeAll(keepingCapacity: true)

		// A picture the program has deleted must not keep its texture alive; the
		// store counts every change, so one comparison says whether to look.
		if store.generation != lastGraphicsGeneration {
			lastGraphicsGeneration = store.generation
			let live = store.images
			imageTextures = imageTextures.filter { live[$0.key] != nil }
		}

		guard !placements.isEmpty else { return }

		for placement in placements.sorted(by: { $0.z < $1.z }) {
			guard let image = store.images[placement.imageID],
			      let texture = texture(for: image)
			else { continue }

			// Points, as everything else built here is: the offsets the protocol
			// carries are in the picture's own pixels.
			let offsetX = Float(placement.offsetX) / Float(scale)
			let offsetY = Float(placement.offsetY) / Float(scale)
			let x = Float(frame.inset.x) + Float(placement.column) * Float(frame.cellSize.width) + offsetX
			let y = Float(frame.inset.y) + Float(placement.row) * Float(frame.cellSize.height) + offsetY

			// Cropping is done by naming the part of the texture to sample rather
			// than by cutting the picture up, so an image shown in pieces — as a
			// program redrawing one corner does — still uploads once.
			let width = Float(image.width)
			let height = Float(image.height)
			let payload = ImageInstance(
				origin: SIMD2(x - Float(frame.origin.x), y - Float(frame.origin.y)),
				size: SIMD2(
					Float(placement.columns) * Float(frame.cellSize.width),
					Float(placement.rows) * Float(frame.cellSize.height)
				),
				uvOrigin: SIMD2(Float(placement.source.x) / width, Float(placement.source.y) / height),
				uvSize: SIMD2(Float(placement.source.width) / width, Float(placement.source.height) / height)
			)

			if placement.z < 0 {
				imagesBelow.append((payload, texture))
				cutouts.append(Cutout(
					rows: placement.rowRange,
					columns: placement.column..<(placement.column + placement.columns)
				))
			} else {
				imagesAbove.append((payload, texture))
			}
		}
	}

	/// Whether a cell has a picture behind it that its background would hide.
	private func isCutOut(row: Int, column: Int) -> Bool {
		// Empty for all but the rare screen that has an image behind its text, so
		// this costs a count check per cell and nothing else.
		guard !cutouts.isEmpty else { return false }
		return cutouts.contains { $0.rows.contains(row) && $0.columns.contains(column) }
	}

	private func texture(for image: TerminalImage) -> MTLTexture? {
		if let existing = imageTextures[image.id] { return existing }

		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: .rgba8Unorm, width: image.width, height: image.height, mipmapped: false
		)
		descriptor.usage = .shaderRead
		guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
		image.pixels.withUnsafeBytes { bytes in
			texture.replace(
				region: MTLRegionMake2D(0, 0, image.width, image.height),
				mipmapLevel: 0,
				withBytes: bytes.baseAddress!,
				bytesPerRow: image.width * 4
			)
		}
		imageTextures[image.id] = texture
		return texture
	}

	private func encodeImages(
		_ pictures: [(payload: ImageInstance, texture: MTLTexture)],
		into encoder: MTLRenderCommandEncoder,
		uniforms: inout Uniforms
	) {
		guard !pictures.isEmpty else { return }
		encoder.setRenderPipelineState(imagePipeline)
		encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
		for picture in pictures {
			var payload = picture.payload
			encoder.setVertexBytes(&payload, length: MemoryLayout<ImageInstance>.stride, index: 0)
			encoder.setFragmentTexture(picture.texture, index: 0)
			encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
		}
	}

	// MARK: - Drawing

	/// Renders the built instances into a target.
	///
	/// `viewport` is in points, the same units the instances were built in; the
	/// texture may be larger, and normalised coordinates do not care.
	/// How the bell is showing right now: strength, and how long it has been.
	var bell: (strength: Float, elapsed: Float) = (0, 0)

	func render(
		to target: MTLTexture,
		clear: SIMD4<Float>,
		viewport: SIMD2<Float>,
		drawable: CAMetalDrawable? = nil
	) {
		guard !instances.isEmpty || !imagesBelow.isEmpty || !imagesAbove.isEmpty else { return }
		upload()

		let pass = MTLRenderPassDescriptor()
		pass.colorAttachments[0].texture = target
		pass.colorAttachments[0].loadAction = .clear
		pass.colorAttachments[0].storeAction = .store
		pass.colorAttachments[0].clearColor = MTLClearColor(
			red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: Double(clear.w)
		)

		guard let commands = queue.makeCommandBuffer(),
		      let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
		else { return }

		var uniforms = Uniforms(
			viewport: viewport, bell: bell.strength, bellTime: bell.elapsed, scroll: scroll
		)

		// A picture with a negative z goes behind the text, one without goes in
		// front, and the cells are drawn between them. Three passes in the one
		// encoder, since only the pipeline and its bindings change.
		encodeImages(imagesBelow, into: encoder, uniforms: &uniforms)

		if !instances.isEmpty {
			encoder.setRenderPipelineState(pipeline)
			encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
			encoder.setFragmentTexture(atlas.coverageTexture, index: 0)
			encoder.setFragmentTexture(atlas.colourTexture, index: 1)
			// The same instances twice: every background, then every glyph.
			// One pass drew the cells in order, so the next cell's background
			// landed on the part of a glyph that reached past its own cell —
			// a symbol from a fallback font nearly two cells wide lost its
			// right half, every time. Two draws of one buffer cost less than
			// the single fill they replace did on the CoreGraphics path.
			for pass: Float in [0, 1] {
				uniforms.pass = pass
				encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
				encoder.drawPrimitives(
					type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count
				)
			}
		}

		encodeImages(imagesAbove, into: encoder, uniforms: &uniforms)
		encoder.endEncoding()
		commands.commit()

		guard let drawable else {
			// No drawable means someone is about to read the pixels back.
			commands.waitUntilCompleted()
			return
		}

		// The layer presents with the transaction, so the frame has to be handed
		// over here rather than by the command buffer: waited until the GPU has
		// the work, then presented, so the new contents and the new size become
		// visible together.
		commands.waitUntilScheduled()
		drawable.present()
	}

	/// Renders one frame into a texture and writes it out as a PNG.
	///
	/// Metal draws into its own layer, which the window-capture path cannot see,
	/// so without this there would be no way to check what the renderer produces
	/// except by looking at the screen.
	func writePNG(to path: String, points: SIMD2<Float>, clear: SIMD4<Float>) -> Bool {
		let width = Int(points.x * Float(scale))
		let height = Int(points.y * Float(scale))
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
		)
		descriptor.usage = [.renderTarget, .shaderRead]
		descriptor.storageMode = .managed
		guard let target = device.makeTexture(descriptor: descriptor) else { return false }

		render(to: target, clear: clear, viewport: points)

		// Managed textures live on both sides; the CPU copy has to be brought
		// up to date before it can be read.
		guard let commands = queue.makeCommandBuffer(),
		      let blit = commands.makeBlitCommandEncoder()
		else { return false }
		blit.synchronize(resource: target)
		blit.endEncoding()
		commands.commit()
		commands.waitUntilCompleted()

		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		target.getBytes(
			&pixels, bytesPerRow: width * 4,
			from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
		)
		// BGRA as Metal wrote it, RGBA as an image wants it.
		for index in stride(from: 0, to: pixels.count, by: 4) {
			pixels.swapAt(index, index + 2)
		}

		guard let provider = CGDataProvider(data: Data(pixels) as CFData),
		      let image = CGImage(
				width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
				bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
				provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
			)
		else { return false }

		let rep = NSBitmapImageRep(cgImage: image)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
	}

	private func upload() {
		let needed = MemoryLayout<CellInstance>.stride * instances.count
		if instanceBuffer == nil || instanceBuffer!.length < needed {
			// Grown with room to spare, so a screen getting slightly bigger does
			// not mean a new buffer every frame.
			instanceBuffer = device.makeBuffer(length: needed * 2, options: .storageModeShared)
		}
		guard let buffer = instanceBuffer else { return }
		instances.withUnsafeBytes { bytes in
			buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: needed)
		}
	}
}

extension NSColor {
	/// Straight sRGB components, which is what the shaders work in.
	var components: SIMD4<Float> {
		let srgb = usingColorSpace(.sRGB) ?? self
		return SIMD4(
			Float(srgb.redComponent), Float(srgb.greenComponent),
			Float(srgb.blueComponent), Float(srgb.alphaComponent)
		)
	}
}
