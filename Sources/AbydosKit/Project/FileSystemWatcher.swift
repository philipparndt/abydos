import Foundation

/// One batch of filesystem activity, as FSEvents described it.
///
/// Two lists rather than one, because the two questions are different. The tree
/// wants to know *which listings went stale*, which is the parent of everything
/// that moved. Anything deciding whether the change is worth reacting to wants
/// to know *what was written*, and a parent directory cannot answer that: while
/// a language server imports a Tycho reactor it writes `.classpath` into a
/// bundle and a Java source file lives under the same bundle, so at directory
/// granularity "somebody wrote metadata" and "somebody wrote code" are the same
/// event. 0446 is what it costs to answer the second question with the first.
public struct FileSystemChange {
	/// Directories whose listing may no longer be right.
	public var directories: [URL]

	/// The paths FSEvents actually named, when it named them.
	public var paths: [URL]

	/// Whether `paths` is the whole batch.
	///
	/// False when the kernel gave up on describing a burst file by file and
	/// said "scan this subtree instead" — a checkout, a build, an install.
	/// Anything filtering on `paths` has to treat that as "could be anything".
	public var namesEveryPath: Bool

	public init(directories: [URL], paths: [URL], namesEveryPath: Bool) {
		self.directories = directories
		self.paths = paths
		self.namesEveryPath = namesEveryPath
	}
}

/// Watches a directory tree via FSEvents and reports what changed.
///
/// FSEvents is the right tool here rather than polling: the kernel already
/// knows what changed, so an idle project costs nothing and a `git checkout`
/// touching a thousand files arrives as one coalesced batch.
public final class FileSystemWatcher {
	private var stream: FSEventStreamRef?
	private let root: URL
	private let queue = DispatchQueue(label: "abydos.fswatch")
	private let onChange: (FileSystemChange) -> Void

	/// Events are coalesced over this window so a burst of writes produces one
	/// refresh instead of hundreds.
	private let latency: CFTimeInterval = 0.25

	/// Whether `.git` is reported like anything else.
	///
	/// Off for the tree, which would otherwise redraw itself every time git
	/// touched an index; on for the watcher that exists precisely to notice
	/// that somebody committed from a terminal.
	private let includesGitDirectory: Bool

	public init(
		root: URL,
		includesGitDirectory: Bool = false,
		onChange: @escaping (FileSystemChange) -> Void
	) {
		self.root = root.standardizedFileURL
		self.includesGitDirectory = includesGitDirectory
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
		guard let change = Self.change(
			from: paths,
			flags: flags,
			root: root,
			includesGitDirectory: includesGitDirectory
		) else { return }
		DispatchQueue.main.async { [onChange] in
			onChange(change)
		}
	}

	/// What one FSEvents callback means, as a value.
	///
	/// Separated from delivering it so there is something to test: the callback
	/// is C, the delivery is on the main queue, and a test that waited for both
	/// would be a test about scheduling. What is worth checking is the reading
	/// of the flags.
	static func change(
		from paths: [String],
		flags: [FSEventStreamEventFlags],
		root: URL,
		includesGitDirectory: Bool
	) -> FileSystemChange? {
		// Report parent directories: what the tree needs to know is which
		// directory listings became stale, not which individual files moved.
		// The paths themselves are kept beside them, for the things that care
		// what was written rather than where.
		var directories = Set<URL>()
		var named = Set<URL>()
		var namesEveryPath = true
		for (index, path) in paths.enumerated() {
			let url = URL(fileURLWithPath: path)
			if !includesGitDirectory, path.contains("/.git/") { continue }
			if url.lastPathComponent == ".DS_Store" { continue }
			let flag = index < flags.count ? flags[index] : 0

			// A burst too large to describe file by file — a checkout, a build,
			// an install — arrives as "this directory changed somehow, look
			// again". Reporting the parent would miss everything underneath,
			// and nothing downstream may assume the named paths are the whole
			// of what happened.
			if flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
				directories.insert(url.standardizedFileURL)
				namesEveryPath = false
				continue
			}

			// The project directory itself moved; the whole tree is suspect.
			if flag & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
				directories.insert(root)
				namesEveryPath = false
				continue
			}

			directories.insert(url.deletingLastPathComponent().standardizedFileURL)
			named.insert(url.standardizedFileURL)
		}
		guard !directories.isEmpty else { return nil }

		return FileSystemChange(
			directories: Array(directories),
			paths: Array(named),
			namesEveryPath: namesEveryPath
		)
	}
}
