import AppKit
import AbydosKit

/// The window on screen, read again at the detail the width allows — for every
/// lane showing.
///
/// Reported 2026-09-16: "when zooming, the wave form looses all of its
/// details". Each lane is drawn from a reading of its whole file at 256 frames a
/// peak, which at 48 kHz is under two hundred peaks a second: a window of two
/// seconds across a thousand pixels has fewer peaks than pixels, and every one
/// is drawn as a block. The sound tab has read its window again at a peak per
/// pixel since it was written; the song pane never did.
///
/// This is that, for a pane of several files: once the window stops moving,
/// every lane's file is read over the window and half a window either side, at
/// the same frames per peak, and the canvas draws those readings while they
/// cover what is on screen. Its own object because the pane is at the size a
/// file here may be, and because it is state — a read going and a settle
/// waiting — not drawing.
@MainActor
final class SongDetail {
	private var reading: (flag: CancelFlag, task: Task<Void, Never>)?
	private var settle: DispatchWorkItem?

	/// How long the window has to stay still before it is read.
	static let settleDelay: TimeInterval = 0.15

	/// The files the canvas's lanes are drawn from, in lane order: the mix in
	/// the mix view, a stem per lane in the stems view.
	static func files(of rendered: [URL], stems: Bool) -> [URL] {
		guard let mix = rendered.first else { return [] }
		return stems ? Array(rendered.dropFirst()) : [mix]
	}

	func cancel() {
		settle?.cancel()
		settle = nil
		reading?.flag.set()
		reading = nil
	}

	/// The window moved, or the lanes changed: read the window again once it has
	/// stopped moving, or let the detail go when the whole song is in view.
	func windowChanged(on canvas: SongCanvas, files: [URL]) {
		settle?.cancel()
		guard canvas.isZoomed, !files.isEmpty, files.count == canvas.lanes.count else {
			cancel()
			canvas.setDetails([])
			return
		}
		if canvas.detailCovers { return }
		let work = DispatchWorkItem { [weak self, weak canvas] in
			guard let self, let canvas else { return }
			self.read(files, for: canvas)
		}
		settle = work
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
	}

	private func read(_ files: [URL], for canvas: SongCanvas) {
		guard let rate = canvas.lanes.lazy.compactMap({ $0.overview?.sampleRate }).first, rate > 0 else { return }
		let span = canvas.windowSpan
		let pixels = max(1, Int(canvas.bounds.width * (canvas.window?.backingScaleFactor ?? 2)))
		let from = max(0, Int((canvas.windowStart - span / 2) * rate))
		let to = Int((canvas.windowStart + span * 1.5) * rate)
		guard to > from else { return }
		// Twice the window on screen, so twice the pixels, never finer than a
		// frame a peak — and only where that is finer than the overview.
		let framesPerPeak = max(1, Int(Double(to - from) / Double(pixels * 2)))
		let overviewPeak = canvas.lanes.lazy.compactMap { $0.overview?.lanes.first?.framesPerPeak }.first ?? 256
		guard framesPerPeak < overviewPeak else {
			canvas.setDetails([])
			return
		}

		reading?.flag.set()
		let flag = CancelFlag()
		let columns = min(8192, pixels * 2)
		let task = Task { @MainActor [weak self, weak canvas] in
			let drawn = await withTaskGroup(of: (Int, SpectrumPicture?).self) { group in
				for (index, file) in files.enumerated() {
					group.addTask(priority: .userInitiated) {
						// The reading and its picture, both made here and not on
						// the main thread.
						(index, SpectrumPicture(of: try? AudioAnalysis.read(
							file, range: from..<to, framesPerPeak: framesPerPeak,
							maximumColumns: columns, minimumHop: 64
						) { flag.isSet }))
					}
				}
				var found = [SpectrumPicture?](repeating: nil, count: files.count)
				for await (index, picture) in group { found[index] = picture }
				return found
			}
			let readings = drawn.map { $0?.reading }
			guard let self, let canvas, !flag.isSet else { return }
			self.reading = nil
			// All of them or none: the lanes are folded together, at one
			// frames-per-peak, and a lane still drawn from its overview beside
			// one drawn from its detail would not line up.
			guard readings.allSatisfy({ $0 != nil }) else { return }
			canvas.setDetails(readings, images: drawn.map { $0?.image })
		}
		reading = (flag, task)
	}
}
