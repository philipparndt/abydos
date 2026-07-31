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

		let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
			guard let info else { return }
			let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
			guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
			let flags = (0..<count).map { eventFlags[$0] }
			watcher.handle(paths: Array(paths.prefix(count)), flags: flags)
		}

		let flags = UInt32(
			kFSEventStreamCreateFlagUseCFTypes |
			kFSEventStreamCreateFlagFileEvents |
			// Without this, moving or renaming the project directory itself goes
			// unreported and the tree keeps showing a path that no longer exists.
			kFSEventStreamCreateFlagWatchRoot |
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

	private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
		// Report parent directories: what the tree needs to know is which
		// directory listings became stale, not which individual files moved.
		var directories = Set<URL>()
		for (index, path) in paths.enumerated() {
			let url = URL(fileURLWithPath: path)
			if path.contains("/.git/") || url.lastPathComponent == ".DS_Store" { continue }
			let flag = index < flags.count ? flags[index] : 0

			// A burst too large to describe file by file — a checkout, a build,
			// an install — arrives as "this directory changed somehow, look
			// again". Reporting the parent would miss everything underneath.
			if flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
				directories.insert(url.standardizedFileURL)
				continue
			}

			// The project directory itself moved; the whole tree is suspect.
			if flag & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
				directories.insert(root)
				continue
			}

			directories.insert(url.deletingLastPathComponent().standardizedFileURL)
		}
		guard !directories.isEmpty else { return }

		let changed = Array(directories)
		DispatchQueue.main.async { [onChange] in
			onChange(changed)
		}
	}
}
