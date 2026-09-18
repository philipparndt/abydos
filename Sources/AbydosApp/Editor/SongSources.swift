import AppKit
import AbydosKit

/// The files a song is made of, and the watch on them.
///
/// The song itself, and since includes (mat e72d7e5) every file its last render
/// read: a song of three files is changed by a save of any of them, and an
/// included kit can sit beside the song, below it or above it. FSEvents watches
/// directories, so this watches one per source's directory, none inside
/// another — and whether anything that matters actually changed is the
/// fingerprint's question, asked after the pane's debounce.
///
/// Its own object rather than four properties of the pane: it is a fact about
/// files, it is asked the same questions from four places, and `SongPreviewView`
/// is large enough that a reader looking for what plays should not have to walk
/// past FSEvents to find it.
@MainActor
final class SongSources {
	/// The files the last render read, the song first; empty before one.
	private(set) var files: [URL] = []
	private var watchers: [String: FileSystemWatcher] = [:]
	private let changed: () -> Void

	init(changed: @escaping () -> Void) {
		self.changed = changed
	}

	/// What is watched: the sources, or the song alone before a render.
	private func watched(_ song: URL) -> [URL] {
		files.isEmpty ? [song] : files
	}

	/// Watches a song and whatever it was last read from, in place of whatever
	/// was being watched.
	func begin(song: URL, files: [URL]) {
		self.files = files
		watch(song)
	}

	/// The files a manifest says the song was read from; true when they are not
	/// the ones being watched already.
	@discardableResult
	func adopt(_ sources: [String], of song: URL) -> Bool {
		let read = sources.map { URL(fileURLWithPath: $0) }
		guard read != files else { return false }
		files = read
		watch(song)
		return true
	}

	/// Whether any source was written after `date` — after a render started,
	/// and so possibly after that render read it.
	///
	/// **A render is of its files as they were when it started, not as they are
	/// when it lands.** Before a song's first render only the song is watched,
	/// since which files it includes is what the render finds out. A save of one
	/// of those files while that render runs changes nothing that is watched, so
	/// nothing renders again — and the render then landed, adopted the files it
	/// had read, and was credited with them *as they were by then*. Reported
	/// 2026-09-16 as "Mix view loses the drums for a mat .song render": the
	/// pane had rendered a `drums.song` from before a save at 20:26:49 in a run
	/// that started before it and ended at 20:27:18, and showed that for the
	/// rest of the session. Its drums layer was keyed `76eaae…`; the file on
	/// disk renders as `7d1626…`, which the pane never made.
	func changed(after date: Date, of song: URL) -> Bool {
		watched(song).contains { source in
			let values = try? source.resourceValues(forKeys: [.contentModificationDateKey])
			return (values?.contentModificationDate ?? .distantPast) > date
		}
	}

	/// Size and date of every source: an event says something in a directory
	/// happened, and most of what happens is not the song.
	func fingerprint(of song: URL) -> String {
		watched(song).map { source in
			let values = try? source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
			return "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
		}.joined(separator: ";")
	}

	private func watch(_ song: URL) {
		let directories = Set(watched(song).map { $0.deletingLastPathComponent().standardizedFileURL.path })
		// FSEvents watches a tree, so a directory inside another is watched already.
		let roots = directories.filter { directory in
			!directories.contains { $0 != directory && directory.hasPrefix($0 + "/") }
		}
		for gone in Set(watchers.keys).subtracting(roots) {
			watchers.removeValue(forKey: gone)
		}
		for root in roots where watchers[root] == nil {
			let watcher = FileSystemWatcher(root: URL(fileURLWithPath: root, isDirectory: true)) { [changed] _ in
				DispatchQueue.main.async { changed() }
			}
			watcher.start()
			watchers[root] = watcher
		}
	}
}
