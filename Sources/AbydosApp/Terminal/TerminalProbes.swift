import AppKit
import AbydosKit

/// waits for a frame.
enum InputProbe {
	static let enabled = ProcessInfo.processInfo.environment["ABYDOS_INPUT_PROBE"] != nil
	nonisolated(unsafe) private static var samples: [(echo: Double, parse: Double, draw: Double, total: Double)] = []

	static func record(echo: Double, parse: Double, draw: Double, total: Double) {
		samples.append((echo, parse, draw, total))
		let ms = { (value: Double) in String(format: "%6.2f", value * 1000) }
		FileHandle.standardError.write(Data(
			"INPUT echo=\(ms(echo)) parse=\(ms(parse)) draw=\(ms(draw)) total=\(ms(total))\n".utf8
		))
	}

	nonisolated(unsafe) private static var frames = 0
	nonisolated(unsafe) private static var framesWithoutCursor = 0

	/// Frames drawn without the cursor in them, which is what a flicker is: a
	/// picture taken while a program had hidden it to repaint.
	nonisolated(unsafe) private static var places: [(row: Int, column: Int)] = []

	static func frame(cursor: Bool, row: Int = 0, column: Int = 0) {
		frames += 1
		if !cursor { framesWithoutCursor += 1 }
		places.append((row, column))
	}

	/// Frames whose cursor was somewhere the frames on either side were not —
	/// a position the terminal passed through rather than settled in, which is
	/// the cursor appearing where it never really was.
	private static var transientPlaces: Int {
		guard places.count > 2 else { return 0 }
		var count = 0
		for index in 1..<(places.count - 1) where
			places[index] != places[index - 1] && places[index - 1] == places[index + 1] {
			count += 1
		}
		return count
	}

	static func report() {
		FileHandle.standardError.write(Data(
			"INPUTSUM frames=\(frames) withoutCursor=\(framesWithoutCursor) transient=\(transientPlaces) \n".utf8
		))
		guard !samples.isEmpty else { return }
		func line(_ name: String, _ values: [Double]) -> String {
			let sorted = values.sorted()
			let ms = { (value: Double) in String(format: "%6.2f", value * 1000) }
			let mean = values.reduce(0, +) / Double(values.count)
			return "INPUTSUM \(name) mean=\(ms(mean)) median=\(ms(sorted[sorted.count / 2])) "
				+ "min=\(ms(sorted[0])) max=\(ms(sorted[sorted.count - 1]))"
		}
		let text = [
			line("echo ", samples.map(\.echo)),
			line("parse", samples.map(\.parse)),
			line("draw ", samples.map(\.draw)),
			line("total", samples.map(\.total)),
			"INPUTSUM samples=\(samples.count)",
		].joined(separator: "\n") + "\n"
		FileHandle.standardError.write(Data(text.utf8))
	}
}

/// Temporary: splits a GPU frame into where its time actually goes.
enum MetalProbe {
	static let enabled = ProcessInfo.processInfo.environment["ABYDOS_METAL_PROBE"] != nil
	nonisolated(unsafe) static var buildSeconds = 0.0
	nonisolated(unsafe) static var drawableSeconds = 0.0
	nonisolated(unsafe) static var encodeSeconds = 0.0
	nonisolated(unsafe) static var parseSeconds = 0.0
	nonisolated(unsafe) static var renders = 0
	/// Cells a frame turned into instances, which is what item 0488 is about.
	///
	/// It used to be the instance count, and while every cell on screen was
	/// built every frame the two were the same number — 10,904 either way. They
	/// are not the same number any more, so both are printed: `cells/render` is
	/// the work done, `instances/render` is what the GPU was handed, and it is
	/// still the whole screen because the rows that were not built are still in
	/// the buffer from the frame that did build them.
	nonisolated(unsafe) static var cells = 0
	nonisolated(unsafe) static var rows = 0
	nonisolated(unsafe) static var instances = 0

	/// The inputs to the redraw policy, since the policy is now a claim about
	/// them (item 0491).
	///
	/// `stale` is the worst the picture got: how many milliseconds behind the pty
	/// the oldest unparsed delivery was when the drain reached it. `delivery` is
	/// the longest single `write` — the parse work that could not be broken up,
	/// and therefore the floor under how long a frame can be blocked.
	nonisolated(unsafe) static var worstStaleSeconds = 0.0
	nonisolated(unsafe) static var worstDeliverySeconds = 0.0
	nonisolated(unsafe) static var worstDeliveryBytes = 0
	nonisolated(unsafe) static var deliveries = 0

	static func note(staleBy: TimeInterval) {
		worstStaleSeconds = max(worstStaleSeconds, staleBy)
	}

	static func note(delivery seconds: TimeInterval, bytes: Int) {
		deliveries += 1
		if seconds > worstDeliverySeconds {
			worstDeliverySeconds = seconds
			worstDeliveryBytes = bytes
		}
	}

	static func start() {
		guard enabled else { return }
		Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
			let ms = { (value: Double) in String(format: "%.0f", value * 1000) }
			let per = { (total: Int) in renders > 0 ? total / renders : 0 }
			var line = "METALPROBE renders=\(renders) cells/render=\(per(cells)) "
			line += "rows/render=\(per(rows)) instances/render=\(per(instances)) "
			line += "parse=\(ms(parseSeconds))ms build=\(ms(buildSeconds))ms "
			line += "drawable=\(ms(drawableSeconds))ms encode=\(ms(encodeSeconds))ms "
			line += "stale=\(ms(worstStaleSeconds))ms deliveries=\(deliveries) "
			line += "worst=\(ms(worstDeliverySeconds))ms/\(worstDeliveryBytes / 1024)K\n"
			FileHandle.standardError.write(Data(line.utf8))
			buildSeconds = 0; drawableSeconds = 0; encodeSeconds = 0; parseSeconds = 0
			renders = 0; cells = 0; rows = 0; instances = 0
			worstStaleSeconds = 0; worstDeliverySeconds = 0; worstDeliveryBytes = 0
			deliveries = 0
		}
	}
}
