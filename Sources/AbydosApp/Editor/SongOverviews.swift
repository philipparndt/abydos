import AppKit
import AbydosKit

/// The drawings of a render: the mix's and one per stem, read behind the pane.
///
/// Reading a four-minute WAV takes a moment and there are eleven of them, so
/// they arrive one at a time and the lanes are redrawn as each lands. A render
/// that is replaced cancels the reading of the one before it, and what has been
/// read is kept in `SongRenderCache` — by stem key, so a layer an edit did not
/// touch is not read again.
///
/// Its own object because it is the pane's other half-second of state: what has
/// been read, and the task and flag that are reading the rest.
@MainActor
final class SongOverviews {
	/// The mix first, then a stem per layer; nil where nothing has been read.
	private(set) var readings: [AudioOverview?] = []
	private var reading: (flag: CancelFlag, task: Task<Void, Never>)?
	/// The reading of a mix that is still being written, and when it started.
	private var growing: (flag: CancelFlag, task: Task<Void, Never>)?
	private var lastGrowingRead: (at: Date, seconds: Double)?

	/// Told as each drawing lands.
	var onRead: () -> Void = {}

	/// Which lane each reading is of — "mix", then the layers' names — so a new
	/// render's lanes can go on showing the last render's drawing of them.
	private var names: [String] = []
	/// The last drawing of every lane, by name. It outlives a render with no
	/// such lane: a stream is the mix alone, and the stems are back after it.
	private var last: [String: AudioOverview] = [:]

	/// The last drawing of a lane, whichever render it was of.
	func lastDrawing(ofLane name: String) -> AudioOverview? { last[name] }

	/// The spectrum of each reading, made where the reading was read — off the
	/// main thread, once — and kept beside it: see `SpectrumPicture`.
	private(set) var images: [CGImage?] = []
	private var lastImages: [String: CGImage] = [:]
	private var drawing: Task<Void, Never>?

	func image(at index: Int) -> CGImage? { images.indices.contains(index) ? images[index] : nil }
	func lastImage(ofLane name: String) -> CGImage? { lastImages[name] }

	/// Pictures for the readings that came without one — out of the cache, where
	/// a reading is kept and its picture is not — made behind the pane.
	private func drawMissing() {
		let missing = readings.indices.filter { readings[$0] != nil && image(at: $0) == nil }
		guard !missing.isEmpty else { return }
		let wanted = missing.map { ($0, readings[$0]!) }
		drawing?.cancel()
		drawing = Task { @MainActor [weak self] in
			for (index, reading) in wanted {
				let picture = await Task.detached(priority: .utility) { SpectrumPicture(of: reading) }.value
				guard let self, !Task.isCancelled else { return }
				// Still the reading it was made of: a newer render may have
				// replaced it while this was being drawn.
				guard self.readings.indices.contains(index), self.readings[index]?.frameCount == reading.frameCount,
				      self.images.indices.contains(index), self.images[index] == nil else { continue }
				self.images[index] = picture?.image
				self.remember()
				self.onRead()
			}
		}
	}
	/// The readings that are of the render before this one: drawn until the
	/// new one has been read, and then replaced.
	private var stale: Set<Int> = []
	/// A new render's readings: what is already known of it, and for every
	/// lane nothing is known of yet, **the last render's drawing of that lane**,
	/// kept until its own has been read.
	///
	/// Reported 2026-09-17: "while playing also the wave and spectrum renders
	/// often disapears and appears again. This also always happens once the
	/// complete song is rendered (switch from stream to render)". Every render
	/// taking over — the stream, then the finished render behind it — emptied
	/// the lanes and drew nothing until its files had been read again, which
	/// under a playing song being saved is two blanks a save. A drawing a save
	/// old is a far smaller lie than no drawing.
	func keep(_ fresh: [AudioOverview?], names new: [String]) {
		// A reading of the mix that was growing belongs to the render that was
		// growing, and this is another one.
		growing?.flag.set()
		growing = nil
		lastGrowingRead = nil
		var kept = fresh
		var old: Set<Int> = []
		for index in kept.indices where kept[index] == nil && new.indices.contains(index) {
			// A mix read while it was still being written counts too: most of a
			// wave, drawn where it belongs, until the whole of it has been read.
			guard let drawing = last[new[index]] else { continue }
			kept[index] = drawing
			old.insert(index)
		}
		// A carried reading brings its picture; a fresh one out of the cache has
		// none yet, and gets one behind the pane.
		images = kept.indices.map { index in
			old.contains(index) && new.indices.contains(index) ? lastImages[new[index]] : nil
		}
		readings = kept
		names = new
		stale = old
		remember()
		drawMissing()
	}

	private func remember() {
		for (index, reading) in readings.enumerated() where names.indices.contains(index) {
			guard let reading else { continue }
			last[names[index]] = reading
			if let image = image(at: index) { lastImages[names[index]] = image } else { lastImages[names[index]] = nil }
		}
	}

	/// Another song: nothing drawn of the last one is a drawing of this one.
	func forget() {
		cancel()
		drawing?.cancel()
		readings = []
		images = []
		names = []
		stale = []
		last = [:]
		lastImages = [:]
	}

	func cancel() {
		reading?.flag.set()
		reading = nil
		growing?.flag.set()
		growing = nil
		lastGrowingRead = nil
	}

	/// Draws a mix that is still being written, as far as it has been written.
	///
	/// Asked for 2026-09-16, of a streamed render's empty lane: "Drawing it
	/// progressively -> Yes do this". The whole file is read again rather than
	/// the new part appended, because the reading's peaks and its spectrogram
	/// are laid out for the file's length, not bolted end to end — and a read
	/// of a few megabytes costs a fraction of what rendering them did.
	///
	/// Held back so the reading never becomes the work: one at a time, no more
	/// often than `restBetweenReads`, and only when a `growth` of the song has
	/// arrived since the last one. Nothing read here is kept in the cache —
	/// it is a piece of a file, and the whole of it is moments away.
	func readGrowing(mix: URL, seconds: Double) {
		guard growing == nil, !stale.contains(0) else { return }
		if let last = lastGrowingRead {
			guard Date().timeIntervalSince(last.at) >= Self.restBetweenReads,
			      seconds >= last.seconds * Self.growth || seconds >= last.seconds + Self.growthSeconds
			else { return }
		}
		lastGrowingRead = (Date(), seconds)
		let flag = CancelFlag()
		let task = Task { @MainActor [weak self] in
			let picture = await Task.detached(priority: .utility) {
				SpectrumPicture(of: try? AudioAnalysis.read(mix) { flag.isSet })
			}.value
			guard let self, !flag.isSet else { return }
			self.growing = nil
			guard let picture, !self.readings.isEmpty else { return }
			self.readings[0] = picture.reading
			if !self.images.isEmpty { self.images[0] = picture.image }
			self.remember()
			self.onRead()
		}
		growing = (flag, task)
	}

	/// How long the mix is left alone between readings while it is written,
	/// and how much longer it has to have become to be worth reading again.
	private static let restBetweenReads: TimeInterval = 1.0
	private static let growth = 1.35
	private static let growthSeconds = 20.0

	/// Reads whatever is not read yet, in order, for the song at `song`.
	func read(files: [URL], manifest: SongRender.Manifest, directory: URL, song: URL) {
		cancel()
		let flag = CancelFlag()
		var readings = self.readings
		let task = Task { @MainActor [weak self] in
			for (index, file) in files.enumerated() where readings[index] == nil || self?.stale.contains(index) == true {
				let picture = await Task.detached(priority: .userInitiated) {
					SpectrumPicture(of: try? AudioAnalysis.read(file) { flag.isSet })
				}.value
				let read = picture?.reading
				guard let self, !flag.isSet else { return }
				// A reading that failed leaves the old drawing where it is.
				if read != nil || !self.stale.contains(index) {
					readings[index] = read
					if self.images.indices.contains(index) { self.images[index] = picture?.image }
				}
				self.stale.remove(index)
				if let read {
					SongRenderCache.shared.read(read, at: index, of: directory, for: song)
					if index > 0, manifest.layers.indices.contains(index - 1) {
						SongRenderCache.shared.remember(read, ofStem: manifest.layers[index - 1].key, of: song)
					}
				}
				self.readings = readings
				self.remember()
				self.onRead()
			}
		}
		reading = (flag, task)
	}
}
