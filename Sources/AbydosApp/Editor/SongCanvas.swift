import AbydosKit
import AppKit

/// The stems of a song, one above the other, on one timeline.
///
/// `AudioCanvas` draws one sound; a song is several — the mix, and a stem per
/// layer — and what the pane needs from them is one window, one playhead and
/// one gesture over all of them, with each lane saying whose it is, whether it
/// is heard and whether the caret is in it. So this is a canvas of *lanes*:
/// each has a name, the tracks in it, its own wave and spectrum, an on/off
/// switch and a light. The wave and spectrum arithmetic is `AudioCanvas`'s own
/// statics, so the two draw the same file the same way.
///
/// **What it does not do that `AudioCanvas` does**: read the window again at
/// the width's detail when zoomed in. A song of a few minutes is a few
/// thousand peaks and columns per stem, which is a bar or two of detail at
/// most widths; closer than that the wave draws in steps. A re-read per stem
/// is a change of its own if it is wanted.
final class SongCanvas: NSView {
	struct Lane {
		var name: String
		/// The tracks rendered into it, for the header.
		var tracks: [String]
		var overview: AudioOverview?
		/// Heard, or muted from the pane.
		var isEnabled = true
		/// The caret is in a block that makes this stem.
		var isLit = false
	}

	private(set) var lanes: [Lane] = []
	private var spectrumImages: [CGImage?] = []
	private var folded: [[(minimums: [Float], maximums: [Float])]] = []
	private var foldedKey: String?

	var mode: AudioCanvas.Mode = .both {
		didSet { refresh() }
	}

	/// Whether each lane has a header naming it. The mix alone has none.
	var showsHeaders = true {
		didSet { refresh() }
	}

	/// The timeline's length: the longest stem's, which is the playback's.
	var duration: Double = 0 {
		didSet { clampWindow(); refresh() }
	}

	/// The bar grid: how long a bar is, and the beats in one.
	var barSeconds: Double = 0 {
		didSet { needsDisplay = true }
	}
	/// The stretch the loop plays, in seconds, drawn across every lane.
	var loopRange: ClosedRange<Double>? {
		didSet { if loopRange != oldValue { needsDisplay = true } }
	}

	var sections: [SongRender.Manifest.Section] = [] {
		didSet { needsDisplay = true }
	}

	var playhead: Double = 0 {
		didSet { placePlayhead() }
	}

	private(set) var windowStart: Double = 0
	private(set) var windowSpan: Double = 0

	var onSeek: ((Double) -> Void)?
	var onWindowChanged: (() -> Void)?
	/// The switch on a lane's header was clicked.
	var onToggleLane: ((Int) -> Void)?
	/// A lane's name was clicked: the source should show the block that makes it.
	var onRevealLane: ((Int) -> Void)?

	private let playheadLine = NSView()
	/// The press that is down began on a lane's header, so dragging it moves
	/// nothing. See `mouseDragged`.
	private var pressedHeader = false
	static let shortestSpan = AudioCanvas.shortestSpan

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

	// MARK: - The lanes

	/// New stems: their spectrum images are drawn once, here, and not again
	/// for a switch or a light.
	func setLanes(_ new: [Lane]) {
		lanes = new
		spectrumImages = new.map { $0.overview.flatMap(AudioCanvas.makeSpectrumImage(of:)) }
		refresh()
	}

	func setEnabled(_ enabled: Bool, at index: Int) {
		guard lanes.indices.contains(index) else { return }
		lanes[index].isEnabled = enabled
		needsDisplay = true
	}

	/// Lights the lanes whose names are in `names` and nothing else.
	func setLit(_ names: Set<String>) {
		var changed = false
		for index in lanes.indices {
			let lit = names.contains(lanes[index].name)
			if lanes[index].isLit != lit {
				lanes[index].isLit = lit
				changed = true
			}
		}
		if changed { needsDisplay = true }
	}

	var litLanes: [String] { lanes.filter(\.isLit).map(\.name) }

	// MARK: - The window

	var isZoomed: Bool { duration > 0 && windowSpan < duration - 1e-6 }

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

	func zoom(by factor: Double, aroundX x: CGFloat) {
		guard duration > 0, factor > 0 else { return }
		let anchor = seconds(atX: x)
		let span = min(duration, max(Self.shortestSpan, windowSpan / factor))
		let fraction = bounds.width > 0 ? Double(x / bounds.width) : 0.5
		setWindow(start: anchor - fraction * span, span: span)
	}

	/// Keeps the playhead on screen, a page at a time.
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
		let delta = abs(dx) > abs(dy) ? dx : dy
		guard isZoomed, delta != 0, bounds.width > 0 else { return }
		let pixels = fine ? delta : delta * 10
		setWindow(start: windowStart - Double(pixels / bounds.width) * windowSpan, span: windowSpan)
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(superview)
		let point = convert(event.locationInWindow, from: nil)
		pressedHeader = false
		// A header first: its switch, then its name. Anywhere else is the
		// timeline.
		if showsHeaders {
			for index in lanes.indices {
				let header = headerRect(ofLane: index)
				guard header.contains(point) else { continue }
				pressedHeader = true
				if switchRect(in: header).contains(point) {
					onToggleLane?(index)
				} else {
					onRevealLane?(index)
				}
				return
			}
		}
		seek(to: event)
	}

	override func mouseDragged(with event: NSEvent) {
		// **A press on a header is not a scrub.** Reported 2026-09-14: muting a
		// stem moved the playhead "from time to time". The click went to the
		// switch; a hand that moved a pixel while the button was down then sent
		// a drag, and every drag here seeked — to wherever along the song the
		// pointer was, which on a header near the left edge is the first bars.
		guard !pressedHeader else { return }
		seek(to: event)
	}

	/// A press on a lane's switch that moves a pixel before it lets go — the
	/// hand that muted a stem and moved the playhead — sent as real events.
	func wobbleSwitchForTesting(lane index: Int) {
		guard lanes.indices.contains(index), let window else { return }
		let box = switchRect(in: headerRect(ofLane: index))
		let at = convert(NSPoint(x: box.midX, y: box.midY), to: nil)
		for (type, dx) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseDragged, 1.0), (.leftMouseDragged, 2.0), (.leftMouseUp, 2.0)] {
			guard let event = NSEvent.mouseEvent(
				with: type, location: NSPoint(x: at.x + dx, y: at.y), modifierFlags: [], timestamp: 0,
				windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
			) else { continue }
			switch type {
			case .leftMouseDown: mouseDown(with: event)
			case .leftMouseDragged: mouseDragged(with: event)
			default: mouseUp(with: event)
			}
		}
	}

	private func seek(to event: NSEvent) {
		guard duration > 0, bounds.width > 0 else { return }
		let x = min(max(0, convert(event.locationInWindow, from: nil).x), bounds.width)
		let target = min(duration, max(0, seconds(atX: x)))
		playhead = target
		onSeek?(target)
	}

	override func resetCursorRects() {
		guard !lanes.isEmpty else { return }
		addCursorRect(bounds, cursor: .iBeam)
		if showsHeaders {
			for index in lanes.indices { addCursorRect(headerRect(ofLane: index), cursor: .pointingHand) }
		}
	}

	// MARK: - Where things go

	private var positionBarHeight: CGFloat { isZoomed ? max(3, Theme.current.scaled(4)) : 0 }
	private var sectionBandHeight: CGFloat { sections.isEmpty ? 0 : Theme.current.scaled(16) }
	private var headerHeight: CGFloat { showsHeaders ? Theme.current.scaled(20) : 0 }

	/// Everything but the position bar and the section band.
	private var lanesArea: NSRect {
		NSRect(
			x: 0, y: sectionBandHeight, width: bounds.width,
			height: max(0, bounds.height - positionBarHeight - sectionBandHeight)
		)
	}

	private func laneRect(_ index: Int) -> NSRect {
		let area = lanesArea
		guard !lanes.isEmpty else { return area }
		let height = area.height / CGFloat(lanes.count)
		return NSRect(x: 0, y: area.minY + height * CGFloat(index), width: area.width, height: height)
	}

	private func headerRect(ofLane index: Int) -> NSRect {
		let lane = laneRect(index)
		return NSRect(x: 0, y: lane.minY, width: lane.width, height: headerHeight)
	}

	private func switchRect(in header: NSRect) -> NSRect {
		let side = header.height
		return NSRect(x: header.minX + Theme.current.scaled(4), y: header.minY, width: side, height: side)
	}

	/// The drawing under a lane's header, split by the mode.
	private func waveRect(ofLane index: Int) -> NSRect? {
		let lane = laneRect(index)
		let body = NSRect(x: 0, y: lane.minY + headerHeight, width: lane.width, height: max(0, lane.height - headerHeight))
		switch mode {
		case .wave: return body
		case .spectrum: return nil
		case .both: return NSRect(x: 0, y: body.minY, width: body.width, height: (body.height / 2).rounded())
		}
	}

	private func spectrumRect(ofLane index: Int) -> NSRect? {
		let lane = laneRect(index)
		let body = NSRect(x: 0, y: lane.minY + headerHeight, width: lane.width, height: max(0, lane.height - headerHeight))
		switch mode {
		case .wave: return nil
		case .spectrum: return body
		case .both:
			let top = body.minY + (body.height / 2).rounded() + 1
			return NSRect(x: 0, y: top, width: body.width, height: body.maxY - top)
		}
	}

	private func placePlayhead() {
		let width = max(1, Theme.current.scaled(1.5))
		let x = (self.x(atSeconds: playhead) - width / 2).rounded()
		let area = lanesArea
		playheadLine.frame = NSRect(x: x, y: area.minY, width: width, height: area.height)
		playheadLine.layer?.backgroundColor = Theme.current.caret.cgColor
		playheadLine.isHidden = lanes.isEmpty || duration <= 0 || x < -width || x > bounds.width
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		bounds.fill()
		guard !lanes.isEmpty, duration > 0 else { return }

		drawSections()
		for index in lanes.indices {
			let lane = lanes[index]
			let rect = laneRect(index)
			if lane.isLit {
				Theme.current.selectionActive.withAlphaComponent(0.14).setFill()
				rect.fill()
			}
			if let waveRect = waveRect(ofLane: index) { drawWave(ofLane: index, in: waveRect) }
			if let spectrumRect = spectrumRect(ofLane: index) { drawSpectrum(ofLane: index, in: spectrumRect) }
			if mode == .both, let waveRect = waveRect(ofLane: index) {
				Theme.current.separator.setFill()
				NSRect(x: 0, y: waveRect.maxY, width: bounds.width, height: 1).fill()
			}
			if showsHeaders { drawHeader(ofLane: index) }
			if index > 0 {
				Theme.current.separator.setFill()
				NSRect(x: 0, y: rect.minY, width: bounds.width, height: 1).fill()
			}
		}
		drawBars()
		// Over the lanes: what the loop leaves out is dimmed, and a band under
		// the waves would have been painted over by them.
		drawLoop()
		if isZoomed { drawPositionBar() }
	}

	private func drawHeader(ofLane index: Int) {
		let lane = lanes[index]
		let header = headerRect(ofLane: index)
		let theme = Theme.current
		let ink = lane.isEnabled ? theme.editorText : theme.gitIgnored

		// The switch: a speaker, struck through when the stem is off.
		let symbol = lane.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
		if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: lane.isEnabled ? "On" : "Off") {
			let side = header.height * 0.6
			let box = switchRect(in: header)
			let configuration = NSImage.SymbolConfiguration(pointSize: side, weight: .regular)
				.applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
			let tinted = image.withSymbolConfiguration(configuration) ?? image
			let size = tinted.size
			let at = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
			tinted.draw(in: at, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
		}

		let name = NSAttributedString(string: lane.name, attributes: [
			.font: theme.uiFont(11, weight: lane.isLit ? .bold : .medium),
			.foregroundColor: lane.isLit ? theme.caret : ink,
		])
		var x = switchRect(in: header).maxX + theme.scaled(6)
		name.draw(at: NSPoint(x: x, y: header.midY - name.size().height / 2))
		x += name.size().width + theme.scaled(8)

		// The tracks in the layer, when they are not simply the layer.
		let others = lane.tracks.filter { $0 != lane.name }
		if !others.isEmpty {
			let list = NSAttributedString(string: others.joined(separator: " · "), attributes: [
				.font: theme.uiFont(10),
				.foregroundColor: theme.gitIgnored,
			])
			list.draw(at: NSPoint(x: x, y: header.midY - list.size().height / 2))
		}
	}

	private func drawWave(ofLane index: Int, in rect: NSRect) {
		let lane = lanes[index]
		guard let source = lane.overview, let firstLane = source.lanes.first, firstLane.count > 0 else { return }
		let scale = window?.backingScaleFactor ?? 2
		let columns = max(1, Int(rect.width * scale))
		let rate = source.sampleRate
		let perPeak = Double(firstLane.framesPerPeak)
		let first = (windowStart * rate - Double(source.startFrame)) / perPeak
		let last = ((windowStart + windowSpan) * rate - Double(source.startFrame)) / perPeak
		let key = "\(columns):\(first):\(last):\(lanes.count):\(mode)"
		if foldedKey != key {
			folded = lanes.map { lane in
				lane.overview?.lanes.map { AudioCanvas.fold($0, from: first, to: last, into: columns) } ?? []
			}
			foldedKey = key
		}
		guard folded.indices.contains(index) else { return }
		let channels = folded[index]
		guard !channels.isEmpty else { return }

		let theme = Theme.current
		let laneHeight = rect.height / CGFloat(channels.count)
		let ink = lane.isEnabled
			? (lane.isLit ? theme.caret : theme.gitModified)
			: theme.gitIgnored.withAlphaComponent(0.5)
		for (channel, peaks) in channels.enumerated() {
			let middle = rect.minY + laneHeight * (CGFloat(channel) + 0.5)
			let reach = laneHeight / 2 - theme.scaled(3)
			guard reach > 0 else { continue }

			theme.separator.withAlphaComponent(0.6).setFill()
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

	private func drawSpectrum(ofLane index: Int, in rect: NSRect) {
		guard spectrumImages.indices.contains(index), let image = spectrumImages[index],
		      let source = lanes[index].overview, source.sampleRate > 0,
		      let context = NSGraphicsContext.current?.cgContext else { return }

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
		if !lanes[index].isEnabled { context.setAlpha(0.35) }
		context.translateBy(x: 0, y: rect.maxY)
		context.scaleBy(x: 1, y: -1)
		context.draw(image, in: NSRect(x: left, y: 0, width: width, height: rect.height))
		context.restoreGState()
	}

	/// Bar lines over every lane, numbered where there is room.
	private func drawBars() {
		guard barSeconds > 0, windowSpan > 0 else { return }
		let barWidth = CGFloat(barSeconds / windowSpan) * bounds.width
		guard barWidth >= 6 else { return }
		let area = lanesArea
		let theme = Theme.current
		// A number every bar when bars are wide, every 4, 8, 16… otherwise.
		var every = 1
		while barWidth * CGFloat(every) < theme.scaled(44) { every *= 2 }
		let firstBar = Int((windowStart / barSeconds).rounded(.down))
		let lastBar = Int(((windowStart + windowSpan) / barSeconds).rounded(.up))
		let attributes: [NSAttributedString.Key: Any] = [
			.font: theme.uiFont(9),
			.foregroundColor: theme.gitIgnored,
		]
		for bar in max(0, firstBar)...max(0, lastBar) {
			let x = self.x(atSeconds: Double(bar) * barSeconds).rounded()
			guard x >= 0, x <= bounds.width else { continue }
			let strong = bar % every == 0
			theme.separator.withAlphaComponent(strong ? 0.7 : 0.3).setFill()
			NSRect(x: x, y: area.minY, width: 1, height: area.height).fill()
			if strong {
				NSAttributedString(string: "\(bar + 1)", attributes: attributes)
					.draw(at: NSPoint(x: x + 3, y: area.maxY - theme.scaled(13)))
			}
		}
	}

	/// The named sections along the top edge.
	private func drawSections() {
		guard !sections.isEmpty else { return }
		let theme = Theme.current
		let band = NSRect(x: 0, y: 0, width: bounds.width, height: sectionBandHeight)
		theme.separator.withAlphaComponent(0.25).setFill()
		band.fill()
		for section in sections {
			let left = max(0, x(atSeconds: section.start))
			let right = min(bounds.width, x(atSeconds: section.end))
			guard right > left else { continue }
			theme.gitModified.withAlphaComponent(0.18).setFill()
			NSRect(x: left, y: 0, width: right - left, height: band.height).fill()
			let label = NSAttributedString(string: section.name, attributes: [
				.font: theme.uiFont(9.5, weight: .medium),
				.foregroundColor: theme.editorText,
			])
			if label.size().width < right - left - 6 {
				label.draw(at: NSPoint(x: left + 4, y: band.midY - label.size().height / 2))
			}
		}
	}

	/// What the loop plays: everything outside it dimmed, its edges drawn.
	private func drawLoop() {
		guard let loopRange, duration > 0 else { return }
		let left = x(atSeconds: loopRange.lowerBound)
		let right = x(atSeconds: loopRange.upperBound)
		guard right > left else { return }
		let top = sectionBandHeight
		let height = max(0, bounds.height - top)
		Theme.current.editorBackground.withAlphaComponent(0.62).setFill()
		NSRect(x: 0, y: top, width: max(0, left), height: height).fill(using: .sourceOver)
		NSRect(x: right, y: top, width: max(0, bounds.width - right), height: height).fill(using: .sourceOver)
		Theme.current.gitModified.withAlphaComponent(0.9).setFill()
		let edge = max(1, Theme.current.scaled(1.5))
		NSRect(x: left, y: 0, width: edge, height: bounds.height).fill()
		NSRect(x: right - edge, y: 0, width: edge, height: bounds.height).fill()
	}

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
}
