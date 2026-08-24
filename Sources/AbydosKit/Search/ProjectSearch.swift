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

/// How a search ended.
///
/// One value rather than a pair of positional arguments, because item 519 had to
/// add a third thing to it and `(true, 1462)` at a call site had already stopped
/// saying which was which. `capped` is the one that was missing and the one that
/// matters: the walk has stopped at a bound and there is more out there, and the
/// pane above has to be able to *say* so. Before it existed, `completed` was true
/// whether the tree had been walked or the 500-file limit had been hit, and the
/// status line printed a bare count either way — a truncated list that looked
/// complete, which is the failure this program refuses everywhere else.
public struct SearchOutcome: Equatable, Sendable {
	/// False when a newer search superseded this one, in which case nothing else
	/// here is worth reading.
	public let completed: Bool
	/// How many files were opened and looked at.
	public let scanned: Int
	/// True when the walk stopped at `maximumResults` or `maximumMatches`, so
	/// what was reported is a prefix of what is there.
	public let capped: Bool

	public init(completed: Bool, scanned: Int, capped: Bool) {
		self.completed = completed
		self.scanned = scanned
		self.capped = capped
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
	/// Cap on *matches* reported, across every file.
	///
	/// The bound that was missing, and the one the row list is actually linear
	/// in. `maximumResults` counts files and `TextSearch.matchLimit` counts one
	/// file's hits, so between them they permitted 500 × 5 000 = 2.5 million
	/// rows; a one-character query over this repository measured 440 854, and
	/// building rows for them left the main thread dead for seven seconds at a
	/// stretch. Item 519.
	///
	/// It stops the *walk*, not just the display: past this point the remaining
	/// files are not read, not decoded and not searched, which is the difference
	/// between a bound and a truncation.
	public var maximumMatches = 20_000

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
		onFinished: @escaping (SearchOutcome) -> Void
	) {
		lock.lock()
		generation += 1
		let currentGeneration = generation
		lock.unlock()

		guard !query.isEmpty, TextSearch.isValid(query: query, options: options) else {
			DispatchQueue.main.async {
				onFinished(SearchOutcome(completed: true, scanned: 0, capped: false))
			}
			return
		}

		queue.async { [weak self] in
			guard let self else { return }
			let files = self.collectFiles()

			var batch: [FileSearchResult] = []
			var reported = 0
			var matched = 0
			var scanned = 0
			var capped = false

			for url in files {
				// Abandon promptly when a newer search has started.
				guard self.isCurrent(currentGeneration) else {
					DispatchQueue.main.async {
						onFinished(SearchOutcome(completed: false, scanned: scanned, capped: false))
					}
					return
				}
				scanned += 1

				guard let result = self.search(file: url, query: query, options: options) else { continue }
				batch.append(result)
				reported += 1
				matched += result.matches.count

				// Flush periodically so results appear while the walk continues.
				if batch.count >= 20 {
					let flush = batch
					batch = []
					DispatchQueue.main.async {
						guard self.isCurrent(currentGeneration) else { return }
						onResults(flush)
					}
				}
				// Both bounds end the walk rather than the reporting, and both are
				// taken after the file that crossed them: a file arrives whole or
				// not at all, because a heading that reads `12` over eight rows is
				// a worse answer than a list that stops one file early.
				if reported >= self.maximumResults || matched >= self.maximumMatches {
					capped = true
					break
				}
			}

			let remaining = batch
			let outcome = SearchOutcome(completed: true, scanned: scanned, capped: capped)
			DispatchQueue.main.async {
				guard self.isCurrent(currentGeneration) else {
					onFinished(SearchOutcome(completed: false, scanned: scanned, capped: false))
					return
				}
				if !remaining.isEmpty { onResults(remaining) }
				onFinished(outcome)
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
	///
	/// The walk moved to `ProjectFiles` when a second caller wanted it — the
	/// command palette, which lists files by name. Its rules are the ones both
	/// want, and a directory name added to the excluded directories setting has
	/// to be skipped by both; two copies of that would drift the first time
	/// somebody edited one.
	func collectFiles() -> [URL] {
		ProjectFiles.walk(in: root, maximumFileSize: maximumFileSize)
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
