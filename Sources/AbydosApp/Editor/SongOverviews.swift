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

	/// Told as each drawing lands.
	var onRead: () -> Void = {}

	func keep(_ readings: [AudioOverview?]) {
		self.readings = readings
	}

	func cancel() {
		reading?.flag.set()
		reading = nil
	}

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
