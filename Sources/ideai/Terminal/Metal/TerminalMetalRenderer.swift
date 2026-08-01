import AppKit
import IdeaiKit
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

private struct Uniforms {
	var viewport: SIMD2<Float>
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
	private(set) var atlas: GlyphAtlas

	private var instances: [CellInstance] = []
	private var instanceBuffer: MTLBuffer?

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

		self.device = device
		self.queue = queue
		self.pipeline = pipeline
		self.atlas = atlas
		self.scale = scale
	}

	func clearGlyphs() { atlas.removeAll() }

	// MARK: - Building

	/// Describes what a frame should contain, in the view's own coordinates.
	struct Frame {
		var cellSize: CGSize
		var inset: CGPoint
		/// Where the visible window starts within the document.
		var origin: CGPoint
		var background: SIMD4<Float>
		var foreground: SIMD4<Float>
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
	struct Cursor {
		var row: Int
		var column: Int
		var colour: SIMD4<Float>
	}

	func build(
		rows: [(index: Int, line: TerminalLine)],
		frame: Frame,
		faces: TerminalFaces,
		overlays: [Overlay] = [],
		cursor: Cursor? = nil
	) {
		instances.removeAll(keepingCapacity: true)
		atlas.setCellMetrics(size: frame.cellSize, baselineFromTop: faces.baselineFromTop)

		let pixel = Float(scale)
		func snap(_ value: Float) -> Float { (value * pixel).rounded() / pixel }

		// Every edge lands on a whole point, and each cell's far edge is the
		// next cell's near edge rather than its own width rounded separately.
		// Otherwise neighbouring backgrounds miss each other by a fraction of a
		// pixel and a dark seam runs between the segments of a prompt.
		func columnEdge(_ column: Int) -> Float {
			Float((frame.inset.x + CGFloat(column) * frame.cellSize.width - frame.origin.x).rounded())
		}
		func rowEdge(_ row: Int) -> Float {
			Float((frame.inset.y + CGFloat(row) * frame.cellSize.height - frame.origin.y).rounded())
		}

		for (index, line) in rows {
			let y = rowEdge(index)
			let rowHeight = rowEdge(index + 1) - y

			for (column, cell) in line.cells.enumerated() {
				if cell.isWideTrailer { continue }

				let resolved = cell.attributes.resolved
				var foreground = TerminalPalette.components(
					for: resolved.foreground,
					isForeground: true,
					bold: cell.attributes.bold,
					defaultForeground: frame.foreground,
					defaultBackground: frame.background
				)
				// Dimming is the alpha the CoreGraphics path uses, done here as
				// arithmetic rather than by asking for another colour.
				if cell.attributes.dim { foreground.w *= Float(TerminalPalette.dimAmount) }
				var background = TerminalPalette.components(
					for: resolved.background,
					isForeground: false,
					bold: false,
					defaultForeground: frame.foreground,
					defaultBackground: frame.background
				)

				// The cell under a block cursor is turned inside out: the block
				// is the cursor's colour and the character is cut out of it in
				// the colour behind. Laying a block over the character instead
				// leaves it the same colour as what is now behind it, which is
				// how it becomes unreadable exactly where you are looking.
				if let cursor, cursor.row == index, cursor.column == column {
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

				if !cell.attributes.hidden, cell.scalar != 0x20, cell.scalar != 0 {
					let faceIndex = TerminalFaces.index(
						bold: cell.attributes.bold, italic: cell.attributes.italic
					)
					let face = faces.face(bold: cell.attributes.bold, italic: cell.attributes.italic)
					if let entry = atlas.entry(for: cell.scalar, font: face, faceIndex: faceIndex) {
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

				instances.append(instance)
			}
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
	}

	var instanceCount: Int { instances.count }

	// MARK: - Drawing

	/// Renders the built instances into a target.
	///
	/// `viewport` is in points, the same units the instances were built in; the
	/// texture may be larger, and normalised coordinates do not care.
	func render(
		to target: MTLTexture,
		clear: SIMD4<Float>,
		viewport: SIMD2<Float>,
		drawable: CAMetalDrawable? = nil
	) {
		guard !instances.isEmpty else { return }
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

		var uniforms = Uniforms(viewport: viewport)
		encoder.setRenderPipelineState(pipeline)
		encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
		encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
		encoder.setFragmentTexture(atlas.coverageTexture, index: 0)
		encoder.setFragmentTexture(atlas.colourTexture, index: 1)
		encoder.drawPrimitives(
			type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count
		)
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
