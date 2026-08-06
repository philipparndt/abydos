import AppKit
import AbydosKit

/// The profiled program's heap, as a line rather than a snapshot.
///
/// A profile answers "where did the memory go"; this answers the question
/// somebody actually starts with — "is it growing?" — which no single profile
/// can, because the shape of a leak is only visible over time. It sits above
/// the flame graph, a strip high enough to read a slope off and no higher.
final class HeapStripView: NSView {
	private var series = GoMemoryWatch.Series()

	override var isFlipped: Bool { true }

	/// The height a slope is legible at without taking room from the graph.
	static let preferredHeight: CGFloat = 54

	init() {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		toolTip = "Heap of the profiled program, since the profiler connected"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func add(_ sample: GoMemoryWatch.Sample) {
		series.append(sample)
		needsDisplay = true
	}

	func clear() {
		series.clear()
		needsDisplay = true
	}

	var isEmpty: Bool { series.isEmpty }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		// A hairline under the strip, so it reads as its own band rather than
		// as the top of the flame graph.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

		guard let latest = series.latest else {
			draw(text: "Waiting for /debug/vars…", at: NSPoint(x: 10, y: 8), colour: Theme.current.gitIgnored)
			return
		}

		drawLabels(latest)
		drawLine()
	}

	/// The figures, on one line above the chart.
	private func drawLabels(_ latest: GoMemoryWatch.Sample) {
		func bytes(_ value: Int) -> String { GoMemoryWatch.format(bytes: value) }

		let growth = series.growth
		let sign = growth < 0 ? "−" : "+"
		var parts = [
			"Heap \(bytes(latest.heapInuse))",
			"peak \(bytes(series.peak))",
			"\(sign)\(bytes(abs(growth))) over \(Self.duration(series.span))",
		]
		// Every byte ever allocated: the only figure here that is really
		// counted from the program's own start rather than from when this was
		// pointed at it.
		if latest.totalAlloc > 0 {
			parts.append("\(bytes(latest.totalAlloc)) allocated since start")
		}
		parts.append("GC \(latest.collections)")

		draw(
			text: parts.joined(separator: "   ·   "),
			at: NSPoint(x: 10, y: 5),
			colour: series.isGrowing ? .hex(0xD6A05E) : Theme.current.sidebarText
		)
	}

	/// The heap over time, filled under the line.
	private func drawLine() {
		let top = Theme.current.scaled(22.0)
		let plot = NSRect(
			x: 10, y: top,
			width: max(1, bounds.width - 20), height: max(1, bounds.height - top - 6)
		)
		guard series.samples.count > 1 else { return }

		// Against the peak, not against zero: a heap that sits at 400 MB and
		// wobbles by 10 would otherwise be a flat line with nothing to read.
		let values = series.samples.map(\.heapInuse)
		let high = Double(values.max() ?? 1)
		let low = Double(values.min() ?? 0)
		let range = max(high - low, high * 0.05, 1)
		let base = max(0, high - range * 1.15)

		func point(_ index: Int) -> NSPoint {
			let x = plot.minX + plot.width * Double(index) / Double(values.count - 1)
			let share = (Double(values[index]) - base) / max(high - base, 1)
			return NSPoint(x: x, y: plot.maxY - plot.height * min(1, max(0, share)))
		}

		let line = NSBezierPath()
		line.move(to: point(0))
		for index in 1..<values.count { line.line(to: point(index)) }

		let fill = line.copy() as! NSBezierPath
		fill.line(to: NSPoint(x: plot.maxX, y: plot.maxY))
		fill.line(to: NSPoint(x: plot.minX, y: plot.maxY))
		fill.close()

		let colour: NSColor = series.isGrowing ? .hex(0xD6A05E) : .hex(0x6A9955)
		colour.withAlphaComponent(0.18).setFill()
		fill.fill()
		colour.setStroke()
		line.lineWidth = 1.5
		line.lineJoinStyle = .round
		line.stroke()
	}

	private func draw(text: String, at origin: NSPoint, colour: NSColor) {
		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: colour,
		]
		(text as NSString).draw(at: origin, withAttributes: attributes)
	}

	/// "3m", "45s" — how long the line covers, in the shortest true form.
	static func duration(_ seconds: TimeInterval) -> String {
		let whole = Int(seconds.rounded())
		if whole < 90 { return "\(whole)s" }
		if whole < 3600 { return "\(whole / 60)m" }
		return String(format: "%.1fh", seconds / 3600)
	}
}
