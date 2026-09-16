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

	func keep(_ readings: [AudioOverview?]) {
		// A reading of the mix that was growing belongs to the render that was
		// growing, and this is another one.
		growing?.flag.set()
		growing = nil
		lastGrowingRead = nil
		self.readings = readings
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
		guard growing == nil else { return }
		if let last = lastGrowingRead {
			guard Date().timeIntervalSince(last.at) >= Self.restBetweenReads,
			      seconds >= last.seconds * Self.growth || seconds >= last.seconds + Self.growthSeconds
			else { return }
		}
		lastGrowingRead = (Date(), seconds)
		let flag = CancelFlag()
		let task = Task { @MainActor [weak self] in
			let read = await Task.detached(priority: .utility) { () -> AudioOverview? in
				try? AudioAnalysis.read(mix) { flag.isSet }
			}.value
			guard let self, !flag.isSet else { return }
			self.growing = nil
			guard let read, !self.readings.isEmpty else { return }
			self.readings[0] = read
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
			for (index, file) in files.enumerated() where readings[index] == nil {
				let read = await Task.detached(priority: .userInitiated) { () -> AudioOverview? in
					try? AudioAnalysis.read(file) { flag.isSet }
				}.value
				guard let self, !flag.isSet else { return }
				readings[index] = read
				if let read {
					SongRenderCache.shared.read(read, at: index, of: directory, for: song)
					if index > 0, manifest.layers.indices.contains(index - 1) {
						SongRenderCache.shared.remember(read, ofStem: manifest.layers[index - 1].key, of: song)
					}
				}
				self.readings = readings
				self.onRead()
			}
		}
		reading = (flag, task)
	}
}
