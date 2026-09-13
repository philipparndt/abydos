import AbydosKit
import AppKit

/// The wave and the spectrogram of a sound, drawn across a tab, with the
/// playhead over both.
///
/// **The drawing is the timeline.** A click or a drag anywhere on it moves the
/// playhead there, so there is one timeline on screen rather than a waveform
/// with a scrubber under it — two timelines that can disagree by a pixel.
///
/// **It shows a window of the file**, from the whole of it down to 20 ms. Pinch,
/// or ⌥ and a vertical scroll, zooms around the pointer; a scroll without ⌥ pans.
/// The overview is stretched to the window at once, so a zoom never shows a
/// blank, and a reading of just the window at the width's detail replaces it
/// when one arrives — see `AudioFileView.readDetail`.
final class AudioCanvas: NSView {
	enum Mode: Int, CaseIterable {
		case wave, spectrum, both

		var name: String {
			switch self {
			case .wave: return "wave"
			case .spectrum: return "spectrum"
			case .both: return "both"
			}
		}
	}

	/// The whole file, read once.
	var overview: AudioOverview? {
		didSet {
			overviewImage = overview.flatMap(Self.makeSpectrumImage(of:))
			detail = nil
			clampWindow()
			refresh()
		}
	}

	/// The window on screen, read again at its own detail. Used only while it
	/// covers the window; a pan past it falls back to the overview.
	var detail: AudioOverview? {
		didSet {
			detailImage = detail.flatMap(Self.makeSpectrumImage(of:))
			refresh()
		}
	}

	var mode: Mode = .both {
		didSet { refresh() }
	}

	/// Where the playhead is, in seconds.
	var playhead: Double = 0 {
		didSet { placePlayhead() }
	}

	/// The window: where it starts and how long it is, in seconds. A span of
	/// the whole duration is the file at fit.
	private(set) var windowStart: Double = 0
	private(set) var windowSpan: Double = 0

	/// A click or a drag, in seconds.
	var onSeek: ((Double) -> Void)?
	/// The window moved; the owner reads its detail once it settles.
	var onWindowChanged: (() -> Void)?

	private let playheadLine = NSView()
	private var folded: [(minimums: [Float], maximums: [Float])] = []
	private var foldedKey: String?
	private var overviewImage: CGImage?
	private var detailImage: CGImage?

	private static let spectrumRows = 256
	private static let lowestFrequency = 20.0
	private static let decibelRange: Float = 80
	/// The closest a window may come.
	static let shortestSpan = 0.02

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		playheadLine.wantsLayer = true
		addSubview(playheadLine)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	func applyTheme() { refresh() }

	private func refresh() {
		foldedKey = nil
		needsDisplay = true
		placePlayhead()
	}

	override func layout() {
		super.layout()
		placePlayhead()
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		foldedKey = nil
	}

	// MARK: - The window

	var duration: Double { overview?.duration ?? 0 }
	var isZoomed: Bool { duration > 0 && windowSpan < duration - 1e-6 }

	/// Shows `start` to `start + span`, kept inside the file.
	func setWindow(start: Double, span: Double) {
		windowSpan = span
		windowStart = start
		clampWindow()
		refresh()
		onWindowChanged?()
	}

	func fit() {
		setWindow(start: 0, span: duration)
	}

	private func clampWindow() {
		guard duration > 0 else { windowStart = 0; windowSpan = 0; return }
		if windowSpan <= 0 { windowSpan = duration }
		windowSpan = min(duration, max(min(Self.shortestSpan, duration), windowSpan))
		windowStart = min(max(0, windowStart), duration - windowSpan)
	}

	private func seconds(atX x: CGFloat) -> Double {
		guard bounds.width > 0 else { return 0 }
		return windowStart + Double(x / bounds.width) * windowSpan
	}

	private func x(atSeconds seconds: Double) -> CGFloat {
		guard windowSpan > 0 else { return 0 }
		return CGFloat((seconds - windowStart) / windowSpan) * bounds.width
	}

	/// Zooms by `factor` (above 1 zooms in) keeping the moment under `x` still.
	func zoom(by factor: Double, aroundX x: CGFloat) {
		guard duration > 0, factor > 0 else { return }
		let anchor = seconds(atX: x)
		let span = min(duration, max(Self.shortestSpan, windowSpan / factor))
		let fraction = bounds.width > 0 ? Double(x / bounds.width) : 0.5
		setWindow(start: anchor - fraction * span, span: span)
	}

	/// Keeps the playhead on screen, a page at a time: while playing, and when a
	/// key jumps it out of the window.
	func follow(_ seconds: Double) {
		guard isZoomed, seconds < windowStart || seconds > windowStart + windowSpan else { return }
		setWindow(start: seconds - windowSpan * 0.05, span: windowSpan)
	}

	// MARK: - Gestures

	override func magnify(with event: NSEvent) {
		zoom(by: 1 + Double(event.magnification), aroundX: convert(event.locationInWindow, from: nil).x)
	}

	override func scrollWheel(with event: NSEvent) {
		guard duration > 0 else { return super.scrollWheel(with: event) }
		let x = convert(event.locationInWindow, from: nil).x
		let dx = event.scrollingDeltaX
		let dy = event.scrollingDeltaY
		let fine = event.hasPreciseScrollingDeltas
		if event.modifierFlags.contains(.option) {
			let step = fine ? dy / 200 : dy / 10
			zoom(by: exp(Double(step)), aroundX: x)
			return
		}
		// Horizontal when there is some, vertical otherwise: a mouse wheel has
		// only the one, and a timeline has only the one direction to go.
		let delta = abs(dx) > abs(dy) ? dx : dy
		guard isZoomed, delta != 0, bounds.width > 0 else { return }
		let pixels = fine ? delta : delta * 10
		setWindow(start: windowStart - Double(pixels / bounds.width) * windowSpan, span: windowSpan)
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(superview)
		seek(to: event)
	}

	override func mouseDragged(with event: NSEvent) {
		seek(to: event)
	}

	private func seek(to event: NSEvent) {
		guard duration > 0, bounds.width > 0 else { return }
		let x = min(max(0, convert(event.locationInWindow, from: nil).x), bounds.width)
		let target = min(duration, max(0, seconds(atX: x)))
		playhead = target
		onSeek?(target)
	}

	override func resetCursorRects() {
		if overview != nil { addCursorRect(bounds, cursor: .iBeam) }
	}

	// MARK: - Where things go

	private var positionBarHeight: CGFloat { isZoomed ? max(3, Theme.current.scaled(4)) : 0 }

	private var drawingBounds: NSRect {
		NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - positionBarHeight)
	}

	private var waveRect: NSRect? {
		let area = drawingBounds
		switch mode {
		case .wave: return area
		case .spectrum: return nil
		case .both: return NSRect(x: 0, y: 0, width: area.width, height: (area.height / 2).rounded())
		}
	}

	private var spectrumRect: NSRect? {
		let area = drawingBounds
		switch mode {
		case .wave: return nil
		case .spectrum: return area
		case .both:
			let top = (area.height / 2).rounded() + 1
			return NSRect(x: 0, y: top, width: area.width, height: area.height - top)
		}
	}

	private func placePlayhead() {
		let width = max(1, Theme.current.scaled(1.5))
		let x = (self.x(atSeconds: playhead) - width / 2).rounded()
		playheadLine.frame = NSRect(x: x, y: 0, width: width, height: drawingBounds.height)
		playheadLine.layer?.backgroundColor = Theme.current.caret.cgColor
		playheadLine.isHidden = overview == nil || x < -width || x > bounds.width
	}

	/// The reading to draw from: the detail while it covers the window.
	private var source: AudioOverview? {
		guard let overview else { return nil }
		guard let detail, overview.sampleRate > 0 else { return overview }
		let rate = overview.sampleRate
		let from = Double(detail.startFrame) / rate
		let to = Double(detail.startFrame + detail.frameCount) / rate
		return from <= windowStart + 1e-6 && to >= windowStart + windowSpan - 1e-6 ? detail : overview
	}

	/// The detail's frames per peak while it is what is drawn, for a report.
	var detailInUse: Int? {
		guard let detail, let source, source.startFrame == detail.startFrame,
		      source.frameCount == detail.frameCount else { return nil }
		return detail.lanes.first?.framesPerPeak
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		bounds.fill()
		guard let source, duration > 0 else { return }
		if let rect = waveRect { drawWave(source, in: rect) }
		if let rect = spectrumRect { drawSpectrum(source, in: rect) }
		if mode == .both {
			Theme.current.separator.setFill()
			NSRect(x: 0, y: (drawingBounds.height / 2).rounded(), width: bounds.width, height: 1).fill()
		}
		if isZoomed { drawPositionBar() }
	}

	private func drawWave(_ source: AudioOverview, in rect: NSRect) {
		guard let firstLane = source.lanes.first, firstLane.count > 0 else { return }
		let scale = window?.backingScaleFactor ?? 2
		let columns = max(1, Int(rect.width * scale))
		let rate = source.sampleRate
		let perPeak = Double(firstLane.framesPerPeak)
		// The peaks the window covers, as indices into this reading.
		let first = (windowStart * rate - Double(source.startFrame)) / perPeak
		let last = ((windowStart + windowSpan) * rate - Double(source.startFrame)) / perPeak
		let key = "\(columns):\(first):\(last):\(source.startFrame):\(firstLane.framesPerPeak)"
		if foldedKey != key {
			folded = source.lanes.map { lane in
				Self.fold(lane, from: first, to: last, into: columns)
			}
			foldedKey = key
		}

		let laneHeight = rect.height / CGFloat(folded.count)
		let ink = Theme.current.gitModified
		for (lane, peaks) in folded.enumerated() {
			let middle = rect.minY + laneHeight * (CGFloat(lane) + 0.5)
			let reach = laneHeight / 2 - Theme.current.scaled(4)

			Theme.current.separator.withAlphaComponent(0.6).setFill()
			NSRect(x: rect.minX, y: middle.rounded(), width: rect.width, height: 1).fill()

			let path = NSBezierPath()
			for column in 0..<peaks.maximums.count where peaks.maximums[column] >= peaks.minimums[column] {
				let x = rect.minX + CGFloat(column) / scale
				let top = middle - CGFloat(min(1, peaks.maximums[column])) * reach
				let bottom = middle - CGFloat(max(-1, peaks.minimums[column])) * reach
				path.move(to: NSPoint(x: x, y: top))
				path.line(to: NSPoint(x: x, y: max(bottom, top + 1 / scale)))
			}
			path.lineWidth = 1 / scale
			ink.setStroke()
			path.stroke()
		}
	}

	/// The peaks between two fractional indices folded into `columns`; a column
	/// with no peak in it takes the nearest one, so a close zoom draws steps
	/// rather than gaps.
	static func fold(
		_ lane: AudioPeaks, from first: Double, to last: Double, into columns: Int
	) -> (minimums: [Float], maximums: [Float]) {
		var lows = [Float](repeating: 1, count: columns)
		var highs = [Float](repeating: -1, count: columns)
		let span = max(1e-9, last - first)
		for column in 0..<columns {
			let a = first + span * Double(column) / Double(columns)
			let b = first + span * Double(column + 1) / Double(columns)
			var start = Int(a.rounded(.down))
			var end = max(start + 1, Int(b.rounded(.up)))
			start = max(0, start)
			end = min(lane.count, end)
			guard start < end else { continue }
			var low = Float.greatestFiniteMagnitude
			var high = -Float.greatestFiniteMagnitude
			for index in start..<end {
				low = min(low, lane.minimums[index])
				high = max(high, lane.maximums[index])
			}
			lows[column] = low
			highs[column] = high
		}
		return (lows, highs)
	}

	private func drawSpectrum(_ source: AudioOverview, in rect: NSRect) {
		let image = source.startFrame == overview?.startFrame && source.frameCount == overview?.frameCount
			? overviewImage : detailImage
		guard let image, let context = NSGraphicsContext.current?.cgContext, source.sampleRate > 0 else { return }

		// Where this reading's columns lie on the timeline, drawn through the
		// window: the image is as wide as its reading, and the window crops it.
		let spectrogram = source.spectrogram
		let rate = source.sampleRate
		let readingStart = Double(source.startFrame) / rate
		let columnSeconds = Double(spectrogram.hop) / rate
		let imageStart = readingStart + Double(spectrogram.windowSize) / 2 / rate
		let imageSeconds = Double(max(1, spectrogram.columns)) * columnSeconds
		let left = x(atSeconds: imageStart) + rect.minX
		let width = CGFloat(imageSeconds / windowSpan) * rect.width

		context.saveGState()
		context.clip(to: rect)
		context.interpolationQuality = .medium
		context.translateBy(x: 0, y: rect.maxY)
		context.scaleBy(x: 1, y: -1)
		context.draw(image, in: NSRect(x: left, y: 0, width: width, height: rect.height))
		context.restoreGState()

		let nyquist = rate / 2
		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(9.5),
			.foregroundColor: NSColor.white.withAlphaComponent(0.75),
		]
		for (hertz, label) in [(100.0, "100 Hz"), (1000.0, "1 kHz"), (10_000.0, "10 kHz")] where hertz < nyquist {
			let position = log(hertz / Self.lowestFrequency) / log(nyquist / Self.lowestFrequency)
			let y = rect.maxY - CGFloat(position) * rect.height
			let text = NSAttributedString(string: label, attributes: attributes)
			text.draw(at: NSPoint(x: rect.minX + Theme.current.scaled(6), y: y - text.size().height / 2))
			NSColor.white.withAlphaComponent(0.18).setFill()
			NSRect(x: rect.minX, y: y.rounded(), width: rect.width, height: 1).fill()
		}
	}

	/// Which part of the file is on screen, along the bottom edge.
	private func drawPositionBar() {
		let height = positionBarHeight
		let track = NSRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
		Theme.current.separator.withAlphaComponent(0.5).setFill()
		track.fill()
		let from = CGFloat(windowStart / duration) * bounds.width
		let width = max(Theme.current.scaled(6), CGFloat(windowSpan / duration) * bounds.width)
		Theme.current.gitModified.withAlphaComponent(0.8).setFill()
		NSBezierPath(
			roundedRect: NSRect(x: from, y: track.minY, width: width, height: height),
			xRadius: height / 2, yRadius: height / 2
		).fill()
	}

	/// A reading's spectrogram as an image: one pixel column per spectrogram
	/// column, rows on a logarithmic axis from 20 Hz to the Nyquist frequency,
	/// loudness as a dark-to-bright colour scale.
	static func makeSpectrumImage(of reading: AudioOverview) -> CGImage? {
		let spectrogram = reading.spectrogram
		let width = spectrogram.columns
		let height = spectrumRows
		guard width > 0, spectrogram.bins > 1 else { return nil }

		let nyquist = spectrogram.sampleRate / 2
		let binWidth = spectrogram.sampleRate / Double(spectrogram.windowSize)
		let rowBins: [Int] = (0..<height).map { row in
			let position = Double(height - 1 - row) / Double(height - 1)
			let hertz = lowestFrequency * pow(nyquist / lowestFrequency, position)
			return min(spectrogram.bins - 1, max(1, Int((hertz / binWidth).rounded())))
		}
		let floor = spectrogram.loudest - decibelRange
		let palette = colourScale

		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		for column in 0..<width {
			for row in 0..<height {
				let value = spectrogram.value(column: column, bin: rowBins[row])
				let t = max(0, min(1, (value - floor) / decibelRange))
				let colour = palette[Int(t * Float(palette.count - 1))]
				let index = (row * width + column) * 4
				pixels[index] = colour.0
				pixels[index + 1] = colour.1
				pixels[index + 2] = colour.2
				pixels[index + 3] = 255
			}
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
		return CGImage(
			width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
			bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
		)
	}

	/// Near-black through violet and orange to pale yellow: quiet recedes, loud
	/// stands out, on either theme. Fixed rather than taken from the palette,
	/// because it is a scale to read values off, not a surface.
	private static let colourScale: [(UInt8, UInt8, UInt8)] = {
		let stops: [(Float, Float, Float, Float)] = [
			(0.00, 0.02, 0.02, 0.06),
			(0.30, 0.25, 0.07, 0.42),
			(0.60, 0.80, 0.26, 0.30),
			(0.85, 0.99, 0.60, 0.25),
			(1.00, 0.99, 0.95, 0.60),
		]
		return (0..<256).map { step in
			let t = Float(step) / 255
			let upper = stops.firstIndex { $0.0 >= t } ?? stops.count - 1
			let lower = max(0, upper - 1)
			let (a, b) = (stops[lower], stops[upper])
			let span = max(0.0001, b.0 - a.0)
			let k = max(0, min(1, (t - a.0) / span))
			func mix(_ x: Float, _ y: Float) -> UInt8 { UInt8(max(0, min(255, (x + (y - x) * k) * 255))) }
			return (mix(a.1, b.1), mix(a.2, b.2), mix(a.3, b.3))
		}
	}()
}
