import AppKit
import AbydosKit

/// A changed picture, looked at in one of three ways.
///
/// A picture is binary to git and diffed as the sentence "No textual changes."
/// This takes the two sides as git holds them and draws them: side by side at
/// one scale, over each other under a divider that is dragged, or the new one
/// with the regions that differ outlined and the rest dimmed. The choice
/// control above picks, and the pick is remembered.
///
/// A view beside `DiffView` rather than a mode of it: that view is virtualised
/// lines with one colour each and is at its length ceiling, and a picture with
/// a divider in it is a different view wearing its clothes. The hosts swap the
/// two in the scroll view they already have, by whether `FilePreview` says the
/// file is a picture.
final class PictureDiffView: NSView {
	/// One side of the change: what it is, and the picture if it could be read.
	struct Side {
		/// `HEAD`, `staged`, `working copy`, a short hash.
		let label: String
		let image: NSImage?
		let bitmap: PictureDiff.Bitmap?
		/// Why there is no picture, when there is none: the bytes would not
		/// decode, the blob could not be read.
		let reason: String?

		static func read(_ data: Data?, label: String, missing reason: String) -> Side {
			guard let data else { return Side(label: label, image: nil, bitmap: nil, reason: reason) }
			guard let bitmap = PictureDiff.Bitmap(data: data), let image = NSImage(data: data) else {
				return Side(label: label, image: nil, bitmap: nil, reason: "cannot be read")
			}
			return Side(label: label, image: image, bitmap: bitmap, reason: nil)
		}
	}

	enum Mode: Int, CaseIterable {
		case sideBySide, slider, changes

		var words: String {
			switch self {
			case .sideBySide: return "Side by side"
			case .slider: return "Slider"
			case .changes: return "Changes"
			}
		}
	}

	private(set) var old: Side?
	private(set) var new: Side?
	private(set) var outcome: PictureDiff.Outcome?
	private(set) var mode: Mode = .sideBySide

	private var choice: DrawnChoice!
	private let caption = ScaledLabel("", size: 10, colour: { Theme.current.gitIgnored })
	private let canvas = PictureCanvas()
	private var canvasHeight: NSLayoutConstraint!

	/// Where the slider's divider is, as a fraction of the picture's width,
	/// so a resize of the pane keeps it over the same pixels.
	private var divider: CGFloat = 0.5

	private var headerHeight: CGFloat { Theme.current.scaled(34) }
	/// The pictures fit the width they are given and this height at most: the
	/// diff area is a scroll view whose height is the page's business, and a
	/// picture taller than a screen is scrolled by it.
	private var canvasCeiling: CGFloat { Theme.current.scaled(520) }

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor

		choice = DrawnChoice(
			segments: Mode.allCases.map { .words($0.words) },
			selectedIndex: Settings.shared.pictureDiffMode
		) { [weak self] index in
			self?.choose(Mode(rawValue: index) ?? .sideBySide, remembering: true)
		}
		mode = Mode(rawValue: Settings.shared.pictureDiffMode) ?? .sideBySide
		choice.translatesAutoresizingMaskIntoConstraints = false
		caption.translatesAutoresizingMaskIntoConstraints = false
		canvas.translatesAutoresizingMaskIntoConstraints = false
		canvas.owner = self
		addSubview(choice)
		addSubview(caption)
		addSubview(canvas)

		canvasHeight = canvas.heightAnchor.constraint(equalToConstant: 0)
		let inset = Theme.current.scaled(10)
		NSLayoutConstraint.activate([
			choice.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			choice.centerYAnchor.constraint(equalTo: topAnchor, constant: headerHeight / 2),
			caption.leadingAnchor.constraint(equalTo: choice.trailingAnchor, constant: Theme.current.scaled(12)),
			caption.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
			caption.centerYAnchor.constraint(equalTo: choice.centerYAnchor),
			canvas.topAnchor.constraint(equalTo: topAnchor, constant: headerHeight),
			canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
			canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
			canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
			canvasHeight,
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - What is shown

	/// The two sides, either of which may be missing, and the comparison the
	/// host already ran off the main thread.
	func show(old: Side?, new: Side?, outcome: PictureDiff.Outcome?) {
		self.old = old
		self.new = new
		self.outcome = outcome
		divider = 0.5
		choose(mode, remembering: false)
	}

	/// Whether a mode can be drawn for what is shown, and why not when not.
	private func availability(of mode: Mode) -> String? {
		let both = old?.image != nil && new?.image != nil
		switch mode {
		case .sideBySide: return nil
		case .slider: return both ? nil : "one side only"
		case .changes:
			guard both else { return "one side only" }
			if case let .declined(reason)? = outcome { return reason }
			return outcome == nil ? "not compared" : nil
		}
	}

	private func choose(_ wanted: Mode, remembering: Bool) {
		// A mode that cannot be drawn for these pictures falls back to the one
		// that always can, and the caption says why.
		let unavailable = availability(of: wanted)
		mode = unavailable == nil ? wanted : .sideBySide
		choice.selectedIndex = mode.rawValue
		if remembering, unavailable == nil { Settings.shared.pictureDiffMode = wanted.rawValue }
		caption.stringValue = captionText(unavailable: wanted != mode ? unavailable : nil)
		canvas.needsDisplay = true
		invalidateIntrinsicContentSize()
		needsLayout = true
	}

	private func captionText(unavailable: String?) -> String {
		var pieces: [String] = []
		if let old { pieces.append("\(old.label) \(old.bitmap?.sizeDescription ?? old.reason ?? "no picture")") }
		if let new { pieces.append("\(new.label) \(new.bitmap?.sizeDescription ?? new.reason ?? "no picture")") }
		if mode == .changes, case let .regions(regions)? = outcome {
			pieces.append(regions.count == 1 ? "1 region" : "\(regions.count) regions")
		}
		if let unavailable { pieces.append("\(unavailable) — showing side by side") }
		return pieces.joined(separator: "  ·  ")
	}

	// MARK: - Geometry

	/// The pictures' pixel sizes, side by side or one over the other.
	private var pictureSizes: (old: NSSize?, new: NSSize?) {
		(old?.image?.size, new?.image?.size)
	}

	/// The scale that fits what the mode draws into the width and the ceiling,
	/// never above 1: a picture is not blown up past its own size.
	private func fittingScale(width: CGFloat) -> CGFloat {
		let sizes = pictureSizes
		let gap = Theme.current.scaled(12)
		let inset = Theme.current.scaled(10)
		var wanted = NSSize.zero
		switch mode {
		case .sideBySide:
			let widths = [sizes.old?.width, sizes.new?.width].compactMap { $0 }
			let heights = [sizes.old?.height, sizes.new?.height].compactMap { $0 }
			wanted = NSSize(
				width: widths.reduce(0, +) + (widths.count > 1 ? gap : 0),
				height: heights.max() ?? 0
			)
		case .slider, .changes:
			wanted = sizes.new ?? sizes.old ?? .zero
		}
		guard wanted.width > 0, wanted.height > 0 else { return 1 }
		let room = NSSize(width: max(1, width - inset * 2), height: canvasCeiling - Theme.current.scaled(24))
		return min(1, room.width / wanted.width, room.height / wanted.height)
	}

	override func layout() {
		super.layout()
		let scale = fittingScale(width: bounds.width)
		let sizes = pictureSizes
		let tallest = max(sizes.old?.height ?? 0, sizes.new?.height ?? 0) * scale
		canvasHeight.constant = tallest > 0 ? tallest + Theme.current.scaled(24) : Theme.current.scaled(60)
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize {
		NSSize(width: NSView.noIntrinsicMetric, height: headerHeight + canvasHeight.constant)
	}

	/// Where each picture is drawn, in the canvas's coordinates, for the mode.
	fileprivate func placements(in bounds: NSRect) -> (old: NSRect?, new: NSRect?, scale: CGFloat) {
		let scale = fittingScale(width: bounds.width)
		let sizes = pictureSizes
		let gap = Theme.current.scaled(12)
		let top = Theme.current.scaled(4)
		func box(_ size: NSSize?, x: CGFloat) -> NSRect? {
			guard let size else { return nil }
			return NSRect(x: x, y: top, width: size.width * scale, height: size.height * scale)
		}
		switch mode {
		case .sideBySide:
			let oldWidth = (sizes.old?.width ?? 0) * scale
			let newWidth = (sizes.new?.width ?? 0) * scale
			let total = oldWidth + newWidth + (oldWidth > 0 && newWidth > 0 ? gap : 0)
			let left = max(Theme.current.scaled(10), (bounds.width - total) / 2)
			let oldBox = box(sizes.old, x: left)
			let newBox = box(sizes.new, x: left + oldWidth + (oldWidth > 0 ? gap : 0))
			return (oldBox, newBox, scale)
		case .slider, .changes:
			let size = sizes.new ?? sizes.old
			let width = (size?.width ?? 0) * scale
			let left = max(Theme.current.scaled(10), (bounds.width - width) / 2)
			let one = box(size, x: left)
			return (one, one, scale)
		}
	}

	fileprivate var dividerFraction: CGFloat {
		get { divider }
		set { divider = min(1, max(0, newValue)); canvas.needsDisplay = true }
	}

	// MARK: - For the harness

	/// One line: the mode, the two sides, the regions.
	var reportForTesting: String {
		var said = ["picture mode=\(mode.words.lowercased())"]
		said.append("old=\(old?.bitmap?.sizeDescription ?? old?.reason ?? "none")")
		said.append("new=\(new?.bitmap?.sizeDescription ?? new?.reason ?? "none")")
		switch outcome {
		case let .regions(regions)?: said.append("regions=\(regions.count)")
		case let .declined(reason)?: said.append("declined=\(reason)")
		case nil: said.append("regions=uncompared")
		}
		said.append("divider=\(String(format: "%.2f", divider))")
		return said.joined(separator: " ")
	}

	func chooseForTesting(_ index: Int) { choose(Mode(rawValue: index) ?? .sideBySide, remembering: true) }
}

/// The pictures themselves, drawn for the mode the view is in.
private final class PictureCanvas: NSView {
	weak var owner: PictureDiffView?
	private var dragging = false

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		guard let owner else { return }
		let placed = owner.placements(in: bounds)
		switch owner.mode {
		case .sideBySide:
			drawSide(owner.old, in: placed.old)
			drawSide(owner.new, in: placed.new)
		case .slider:
			guard let box = placed.new, let newImage = owner.new?.image, let oldImage = owner.old?.image else { return }
			checkerboard(in: box)
			draw(newImage, in: box)
			// The old picture to the left of the divider, clipped there, over
			// the new one: dragging right reveals more of what was.
			let split = box.minX + box.width * owner.dividerFraction
			NSGraphicsContext.saveGraphicsState()
			NSBezierPath(rect: NSRect(x: box.minX, y: box.minY, width: split - box.minX, height: box.height)).addClip()
			draw(oldImage, in: box)
			NSGraphicsContext.restoreGraphicsState()
			drawDivider(at: split, in: box)
		case .changes:
			guard let box = placed.new, let newImage = owner.new?.image, let bitmap = owner.new?.bitmap else { return }
			checkerboard(in: box)
			draw(newImage, in: box, fraction: 0.35)
			guard case let .regions(regions)? = owner.outcome else { return }
			let scale = placed.scale
			for region in regions {
				// The region at full strength, cut from the picture, then its
				// outline in the modified colour the changes tree uses.
				let rect = NSRect(
					x: box.minX + CGFloat(region.x) * scale,
					y: box.minY + CGFloat(region.y) * scale,
					width: CGFloat(region.width) * scale,
					height: CGFloat(region.height) * scale
				)
				// `from` is in the image's own (unflipped) coordinates.
				let from = NSRect(
					x: CGFloat(region.x),
					y: CGFloat(bitmap.height - region.y - region.height),
					width: CGFloat(region.width),
					height: CGFloat(region.height)
				)
				newImage.draw(in: rect, from: from, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
				let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
				outline.lineWidth = Theme.current.scaled(1.5)
				Theme.current.gitModified.setStroke()
				outline.stroke()
			}
		}
	}

	private func drawSide(_ side: PictureDiffView.Side?, in box: NSRect?) {
		guard let side else { return }
		guard let box else {
			return
		}
		if let image = side.image {
			checkerboard(in: box)
			draw(image, in: box)
		} else {
			// A missing side keeps its place and says what it is.
			Theme.current.separator.setStroke()
			let frame = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
			frame.lineWidth = 1
			frame.stroke()
			let words = NSAttributedString(
				string: side.reason ?? "no picture",
				attributes: [.font: Theme.current.uiFont(11), .foregroundColor: Theme.current.gitIgnored]
			)
			let size = words.size()
			words.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
		}
		let label = NSAttributedString(
			string: side.label,
			attributes: [.font: Theme.current.uiFont(10), .foregroundColor: Theme.current.gitIgnored]
		)
		label.draw(at: NSPoint(x: box.minX, y: box.maxY + Theme.current.scaled(4)))
	}

	private func draw(_ image: NSImage, in box: NSRect, fraction: CGFloat = 1) {
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current?.imageInterpolation = .high
		image.draw(in: box, from: .zero, operation: .sourceOver, fraction: fraction, respectFlipped: true, hints: nil)
		NSGraphicsContext.restoreGraphicsState()
	}

	private func drawDivider(at x: CGFloat, in box: NSRect) {
		let line = NSBezierPath()
		line.move(to: NSPoint(x: x, y: box.minY))
		line.line(to: NSPoint(x: x, y: box.maxY))
		line.lineWidth = Theme.current.scaled(2)
		Theme.current.gitModified.setStroke()
		line.stroke()
		// A handle in the middle, so the divider reads as a thing to drag.
		let knob = Theme.current.scaled(14)
		let handle = NSBezierPath(ovalIn: NSRect(x: x - knob / 2, y: box.midY - knob / 2, width: knob, height: knob))
		Theme.current.gitModified.setFill()
		handle.fill()
	}

	/// The same checkerboard the editor's picture view draws, because a
	/// transparent edit is a real edit and has to be seen as one.
	private func checkerboard(in box: NSRect) {
		let square: CGFloat = 8
		let dark = Theme.current.editorBackground.blended(withFraction: 0.06, of: .white) ?? Theme.current.editorBackground
		let light = Theme.current.editorBackground.blended(withFraction: 0.12, of: .white) ?? Theme.current.editorBackground
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: box).addClip()
		dark.setFill()
		box.fill()
		light.setFill()
		var row = 0
		var y = box.minY
		while y < box.maxY {
			var x = box.minX + (row.isMultiple(of: 2) ? 0 : square)
			while x < box.maxX {
				NSRect(x: x, y: y, width: square, height: square).fill()
				x += square * 2
			}
			y += square
			row += 1
		}
		NSGraphicsContext.restoreGraphicsState()
	}

	// MARK: - The divider

	override func mouseDown(with event: NSEvent) {
		guard let owner, owner.mode == .slider else { return super.mouseDown(with: event) }
		dragging = true
		move(to: convert(event.locationInWindow, from: nil))
	}

	override func mouseDragged(with event: NSEvent) {
		guard dragging else { return super.mouseDragged(with: event) }
		move(to: convert(event.locationInWindow, from: nil))
	}

	override func mouseUp(with event: NSEvent) {
		dragging = false
	}

	private func move(to point: NSPoint) {
		guard let owner, let box = owner.placements(in: bounds).new, box.width > 0 else { return }
		owner.dividerFraction = (point.x - box.minX) / box.width
	}
}
