import Foundation

/// Watches a directory tree via FSEvents and reports changed directories.
///
/// FSEvents is the right tool here rather than polling: the kernel already
/// knows what changed, so an idle project costs nothing and a `git checkout`
/// touching a thousand files arrives as one coalesced batch.
public final class FileSystemWatcher {
	private var stream: FSEventStreamRef?
	private let root: URL
	private let queue = DispatchQueue(label: "ideai.fswatch")
	private let onChange: ([URL]) -> Void

	/// Events are coalesced over this window so a burst of writes produces one
	/// refresh instead of hundreds.
	private let latency: CFTimeInterval = 0.25

	public init(root: URL, onChange: @escaping ([URL]) -> Void) {
		self.root = root.standardizedFileURL
		self.onChange = onChange
	}

	deinit {
		stop()
	}

	public func start() {
		guard stream == nil else { return }

		// The callback is C, so the instance is passed through as a raw pointer.
		// Unretained is safe because `stop()` runs before deinit completes.
		var context = FSEventStreamContext(
			version: 0,
			info: Unmanaged.passUnretained(self).toOpaque(),
			retain: nil,
			release: nil,
			copyDescription: nil
		)

		let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
			guard let info else { return }
			let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
			guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
			watcher.handle(paths: Array(paths.prefix(count)))
		}

		let flags = UInt32(
			kFSEventStreamCreateFlagUseCFTypes |
			kFSEventStreamCreateFlagFileEvents |
			kFSEventStreamCreateFlagNoDefer
		)

		guard let created = FSEventStreamCreate(
			kCFAllocatorDefault,
			callback,
			&context,
			[root.path] as CFArray,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			latency,
			flags
		) else { return }

		FSEventStreamSetDispatchQueue(created, queue)
		FSEventStreamStart(created)
		stream = created
	}

	public func stop() {
		guard let stream else { return }
		FSEventStreamStop(stream)
		FSEventStreamInvalidate(stream)
		FSEventStreamRelease(stream)
		self.stream = nil
	}

	private func handle(paths: [String]) {
		// Report parent directories: what the tree needs to know is which
		// directory listings became stale, not which individual files moved.
		var directories = Set<URL>()
		for path in paths {
			let url = URL(fileURLWithPath: path)
			if path.contains("/.git/") || url.lastPathComponent == ".DS_Store" { continue }
			directories.insert(url.deletingLastPathComponent().standardizedFileURL)
		}
		guard !directories.isEmpty else { return }

		let changed = Array(directories)
		DispatchQueue.main.async { [onChange] in
			onChange(changed)
		}
	}
}
