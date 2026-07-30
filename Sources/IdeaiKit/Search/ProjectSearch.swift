import Foundation

/// Matches within one file.
public struct FileSearchResult: Equatable, Sendable {
	public let url: URL
	/// Path relative to the search root, for display.
	public let relativePath: String
	public var matches: [SearchMatch]

	public init(url: URL, relativePath: String, matches: [SearchMatch]) {
		self.url = url
		self.relativePath = relativePath
		self.matches = matches
	}
}

/// Searches every file in a project.
///
/// Results are streamed rather than returned in one batch, so the first hits
/// appear immediately instead of after the whole tree has been walked. Each
/// search is cancellable, because the user typing another character should
/// abandon the previous one rather than queue behind it.
public final class ProjectSearch {
	private let root: URL
	private let queue = DispatchQueue(label: "ideai.search", qos: .userInitiated, attributes: .concurrent)
	private var generation = 0
	private let lock = NSLock()

	/// Files larger than this are skipped: they are almost always data or build
	/// output, and reading them would dominate the search.
	public var maximumFileSize = 4 * 1024 * 1024
	/// Cap on files reported, so a huge tree cannot flood the UI.
	public var maximumResults = 500

	public init(root: URL) {
		self.root = root
	}

	/// Starts a search, cancelling any previous one.
	///
	/// `onResults` is called on the main queue with batches as they are found,
	/// and `onFinished` once, with whether the run completed or was superseded.
	public func search(
		query: String,
		options: SearchOptions,
		onResults: @escaping ([FileSearchResult]) -> Void,
		onFinished: @escaping (_ completed: Bool, _ fileCount: Int) -> Void
	) {
		lock.lock()
		generation += 1
		let currentGeneration = generation
		lock.unlock()

		guard !query.isEmpty, TextSearch.isValid(query: query, options: options) else {
			DispatchQueue.main.async { onFinished(true, 0) }
			return
		}

		queue.async { [weak self] in
			guard let self else { return }
			let files = self.collectFiles()

			var batch: [FileSearchResult] = []
			var reported = 0
			var scanned = 0

			for url in files {
				// Abandon promptly when a newer search has started.
				guard self.isCurrent(currentGeneration) else {
					DispatchQueue.main.async { onFinished(false, scanned) }
					return
				}
				scanned += 1

				guard let result = self.search(file: url, query: query, options: options) else { continue }
				batch.append(result)
				reported += 1

				// Flush periodically so results appear while the walk continues.
				if batch.count >= 20 {
					let flush = batch
					batch = []
					DispatchQueue.main.async {
						guard self.isCurrent(currentGeneration) else { return }
						onResults(flush)
					}
				}
				if reported >= self.maximumResults { break }
			}

			let remaining = batch
			DispatchQueue.main.async {
				guard self.isCurrent(currentGeneration) else {
					onFinished(false, scanned)
					return
				}
				if !remaining.isEmpty { onResults(remaining) }
				onFinished(true, scanned)
			}
		}
	}

	public func cancel() {
		lock.lock()
		generation += 1
		lock.unlock()
	}

	private func isCurrent(_ value: Int) -> Bool {
		lock.lock(); defer { lock.unlock() }
		return generation == value
	}

	// MARK: - Walking

	/// Files worth searching, skipping excluded directories and binaries.
	func collectFiles() -> [URL] {
		let excluded = Set(Settings.shared.excludedDirectories)
		var results: [URL] = []

		let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles, .skipsPackageDescendants]
		) else { return [] }

		for case let url as URL in enumerator {
			let name = url.lastPathComponent
			guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

			if values.isDirectory == true {
				// Pruning at the directory level avoids walking node_modules at all,
				// which is the difference between a fast search and an unusable one.
				if excluded.contains(name) || name == ".git" {
					enumerator.skipDescendants()
				}
				continue
			}

			if let size = values.fileSize, size > maximumFileSize { continue }
			if values.isSymbolicLink == true { continue }
			results.append(url)
		}
		return results
	}

	private func search(file url: URL, query: String, options: SearchOptions) -> FileSearchResult? {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
		// A NUL byte in the first few KB means binary — the same test git uses.
		if data.prefix(8_000).contains(0) { return nil }
		guard let text = String(data: data, encoding: .utf8) else { return nil }

		let matches = TextSearch.matches(in: text, query: query, options: options)
		guard !matches.isEmpty else { return nil }

		let base = root.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path

		return FileSearchResult(url: url, relativePath: relative, matches: matches)
	}
}
