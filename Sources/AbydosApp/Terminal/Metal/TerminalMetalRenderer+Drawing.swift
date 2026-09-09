import AppKit
import AbydosKit

/// The pictures on the grid, and the draw call that puts a frame on screen.
extension TerminalMetalRenderer {
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
	func isCutOut(row: Int, column: Int) -> Bool {
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
