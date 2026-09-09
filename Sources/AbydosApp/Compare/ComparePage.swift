import AppKit
import AbydosKit

/// A compare page: a shelf of sources across the top, two of them side by
/// side below — as two files or as two folders — the file's history down the
/// edge when there is one, and a footer with what the page can do.
///
/// An editor tab, like the diff tab and the log page, so it splits, tears off
/// and is remembered. What it compares is `CompareShelf`'s to say; this view
/// shows whatever the shelf's two sides are and rebuilds when they change.
final class ComparePage: NSView, ScalingPage {
	private(set) var shelf: CompareShelf
	/// The tab's name and the line under it moved.
	var onTitleChanged: ((String, String) -> Void)?
	/// A hash on the rail was clicked: the commit, the repository it is in,
	/// and the path the file has there.
	var onOpenCommit: ((GitCommit, URL, String) -> Void)?
	/// Which repository owns a file on disk, and what it is called there —
	/// asked of the window, which knows the estate.
	var repositoryPlace: ((URL) -> (root: URL, path: String)?)?
	/// A remembered page whose side is gone offers to close.
	var onClose: (() -> Void)?

	private let shelfView = CompareShelfView()
	private let footer = CompareFooterView()
	private let rail = CompareHistoryRail()
	private var fileView: FileCompareView?
	private var fileScroll: NSScrollView?
	private var folderView: FolderCompareView?
	private(set) var comparison: FolderComparison?
	private var notice: ScaledLabel?
	private var closeButton: DrawnButton?
	private var railIsShown = false
	/// The folder shelf to go back to when a row was opened as a file diff.
	private var folderShelf: CompareShelf?
	private var loadGeneration = 0
	private(set) var isWorking = false
	private var historyRoot: URL?
	private var historyPath: String?

	init(shelf: CompareShelf) {
		self.shelf = shelf
		super.init(frame: .zero)
		wantsLayer = true
		clipsToBounds = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		addSubview(shelfView)
		addSubview(footer)
		addSubview(rail)
		rail.isHidden = true
		registerForDraggedTypes([.fileURL])

		shelfView.onPick = { [weak self] sideA, anchor in self?.offerSources(for: sideA, from: anchor) }
		shelfView.onSwap = { [weak self] in self?.swapSides() }
		shelfView.onBack = { [weak self] in self?.goBackToFolders() }
		footer.onNext = { [weak self] in self?.fileView?.nextChange() }
		footer.onPrevious = { [weak self] in self?.fileView?.previousChange() }
		footer.onShowEqual = { [weak self] shows in self?.folderView?.showsEqual = shows }
		footer.onFilter = { [weak self] text in self?.folderView?.filter = text }
		footer.onApply = { [weak self] in self?.askToApply() }
		rail.onChoose = { [weak self] commit, sideA in self?.choose(commit: commit, sideA: sideA) }
		rail.onOpenCommit = { [weak self] commit in
			guard let self, let root = self.historyRoot else { return }
			self.onOpenCommit?(commit, root, self.historyPath ?? "")
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// Framed by hand rather than by constraints, so a new size places the
	/// subviews itself — AppKit's own layout pass is not to be waited for.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		arrange()
		needsDisplay = true
	}

	override func layout() {
		super.layout()
		arrange()
	}

	private func arrange() {
		let theme = Theme.current
		let shelfHeight = theme.scaled(54)
		let footerHeight = theme.scaled(32)
		let railWidth = railIsShown ? min(theme.scaled(300), bounds.width * 0.3) : 0
		// The shelf spans the two halves and not the rail, so its swap sits
		// over the gutter between them; the rail takes the full height beside.
		shelfView.frame = NSRect(x: 0, y: 0, width: bounds.width - railWidth, height: shelfHeight)
		footer.frame = NSRect(x: 0, y: bounds.height - footerHeight, width: bounds.width - railWidth, height: footerHeight)
		let content = NSRect(
			x: 0, y: shelfHeight, width: bounds.width - railWidth,
			height: max(0, bounds.height - shelfHeight - footerHeight)
		)
		fileScroll?.frame = content
		folderView?.frame = content
		rail.frame = NSRect(x: bounds.width - railWidth, y: 0, width: railWidth, height: bounds.height)
		if let notice {
			notice.sizeToFit()
			notice.frame = NSRect(
				x: theme.scaled(20), y: content.minY + theme.scaled(20),
				width: max(0, content.width - theme.scaled(40)), height: notice.frame.height
			)
			closeButton?.frame = NSRect(x: theme.scaled(20), y: notice.frame.maxY + theme.scaled(10), width: theme.scaled(80), height: theme.scaled(24))
		}
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		fileView?.applySettings()
		folderView?.applySettings()
		rail.applySettings()
		footer.applyTheme()
		shelfView.applyTheme()
		arrange()
	}

	// MARK: - What is compared

	/// Builds the page for the shelf's two sides.
	///
	/// A folder view is kept, hidden, while one of its rows is open as a file
	/// diff: its expansion, its selection and its scroll position are what the
	/// reader comes back to, and rebuilding it lost all three.
	func compare(keepingFolders: Bool = false) {
		loadGeneration += 1
		if keepingFolders, let folderView {
			folderView.isHidden = true
		} else {
			comparison?.stop()
			comparison = nil
			folderView?.removeFromSuperview()
			folderView = nil
		}
		fileScroll?.removeFromSuperview()
		notice?.removeFromSuperview()
		closeButton?.removeFromSuperview()
		fileView = nil
		fileScroll = nil
		notice = nil
		closeButton = nil
		shelfView.show(shelf, canGoBack: folderShelf != nil)
		onTitleChanged?(shelf.title, "")

		// A remembered page whose side is gone — a temporary directory git
		// made for a dir-diff — says so rather than showing an empty diff.
		for (source, name) in [(shelf.left, "A"), (shelf.right, "B")] where !source.exists {
			showNotice("Side \(name) is no longer there: \(source.origin)", offersClose: true)
			footer.mode = .none
			showRail(false)
			return
		}

		if shelf.isFolderDiff {
			if let folderView, keepingFolders {
				folderView.isHidden = false
				footer.mode = .folder
				refreshFooter()
				showRail(false)
				onTitleChanged?(shelf.title, comparison?.counts.said ?? "")
				arrange()
			} else {
				loadFolders()
			}
		} else {
			loadFile()
		}
	}

	private func showNotice(_ text: String, offersClose: Bool) {
		let label = ScaledLabel(text, size: 12, colour: { Theme.current.sidebarText })
		label.lineBreakMode = .byWordWrapping
		label.maximumNumberOfLines = 3
		addSubview(label)
		notice = label
		if offersClose {
			let button = DrawnButton(title: "Close") { [weak self] in self?.onClose?() }
			addSubview(button)
			closeButton = button
		}
		arrange()
	}

	private func loadFile() {
		let view = FileCompareView()
		let scroll = NSScrollView()
		scroll.documentView = view
		scroll.hasVerticalScroller = true
		scroll.hasHorizontalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.editorBackground
		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
			view.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
		])
		view.onChangeMoved = { [weak self] _, _ in self?.footer.changeSaid = view.changeSaid }
		addSubview(scroll)
		fileView = view
		fileScroll = scroll
		footer.mode = .file
		footer.changeSaid = "Comparing…"
		arrange()

		let generation = loadGeneration
		let left = shelf.left, right = shelf.right
		isWorking = true
		Task { @MainActor [weak self] in
			async let leftText = left.readText()
			async let rightText = right.readText()
			let (l, r) = await (leftText, rightText)
			guard let self, generation == self.loadGeneration else { return }
			if l == nil || r == nil {
				let missing = l == nil ? "A" : "B"
				self.showNotice("Side \(missing) has no such file: \((l == nil ? left : right).origin)", offersClose: false)
			}
			let leftLines = l ?? "", rightLines = r ?? ""
			// The language from the name, for the colours; a file too long
			// to colour cheaply is drawn plain, as `DiffPreparation` bounds it.
			let language = LanguageRegistry.shared.languageId(for: URL(fileURLWithPath: "/" + left.name))
				?? LanguageRegistry.shared.languageId(for: URL(fileURLWithPath: "/" + right.name))
			let result = await Task.detached(priority: .userInitiated) {
				let diff = TextDiff(leftLines, rightLines)
				var leftTokens: [Int: [HighlightToken]] = [:]
				var rightTokens: [Int: [HighlightToken]] = [:]
				if let language, diff.leftLines.count + diff.rightLines.count <= 10_000 {
					leftTokens = DiffHighlighter.highlightLines(leftLines, languageId: language)
					rightTokens = DiffHighlighter.highlightLines(rightLines, languageId: language)
				}
				return (diff, leftTokens, rightTokens)
			}.value
			guard generation == self.loadGeneration else { return }
			view.setDiff(result.0, leftTokens: result.1, rightTokens: result.2)
			self.footer.changeSaid = view.changeSaid
			self.isWorking = false
			self.onTitleChanged?(self.shelf.title, result.0.counts.said)
			await self.loadHistory()
		}
	}

	private func loadFolders() {
		let comparison = FolderComparison(left: shelf.left, right: shelf.right)
		self.comparison = comparison
		let view = FolderCompareView(comparison: comparison)
		view.onOpenRow = { [weak self] node in self?.openRow(node) }
		view.onMarksChanged = { [weak self] in self?.refreshFooter() }
		comparison.onChange = { [weak self] in
			view.reload()
			self?.refreshFooter()
			self?.onTitleChanged?(self?.shelf.title ?? "", comparison.counts.said)
		}
		addSubview(view)
		folderView = view
		footer.mode = .folder
		footer.showsEqual = view.showsEqual
		showRail(false)
		arrange()
		isWorking = true
		comparison.start()
		comparison.watch()
		Task { @MainActor [weak self] in
			await comparison.settled()
			self?.isWorking = false
		}
	}

	private func refreshFooter() {
		guard let comparison else { return }
		let count = comparison.operations.count
		footer.itemsSaid = count == 0 ? "" : "\(count) item\(count == 1 ? "" : "s") to copy"
		footer.canApply = count > 0
	}

	/// A file row of the folder diff, opened as a file diff in the same tab,
	/// with the folders to come back to.
	private func openRow(_ node: FolderComparison.Node) {
		guard !node.isDirectory else { return }
		let left = shelf.left.descending(to: node.relativePath, isDirectory: false)
		let right = shelf.right.descending(to: node.relativePath, isDirectory: false)
		folderShelf = folderShelf ?? shelf
		shelf = CompareShelf(a: left, b: right)
		compare(keepingFolders: true)
	}

	private func goBackToFolders() {
		guard let folders = folderShelf else { return }
		folderShelf = nil
		shelf = folders
		compare(keepingFolders: true)
	}

	private func choose(_ index: Int, sideA: Bool) {
		if let refusal = shelf.choose(index, sideA: sideA) {
			Toast.post("Not comparable", detail: refusal, kind: .information)
			return
		}
		folderShelf = nil
		compare()
	}

	private func swapSides() {
		shelf.swap()
		// Two folders swap in place, keeping the trees as they are; two files
		// are re-diffed, which is cheap and keeps nothing worth keeping.
		if let comparison, let folderView, folderShelf == nil {
			comparison.swapSides()
			folderView.reload()
			shelfView.show(shelf, canGoBack: false)
			onTitleChanged?(shelf.title, comparison.counts.said)
			refreshFooter()
			return
		}
		folderShelf = nil
		compare()
	}

	/// The sources a side can be, as a menu under its card: every source on
	/// the shelf, the one it is now ticked. Picking the other side's source
	/// is the swap, by the shelf's own rule.
	private func offerSources(for sideA: Bool, from anchor: NSView) {
		let menu = NSMenu()
		let current = sideA ? shelf.a : shelf.b
		for (index, source) in shelf.sources.enumerated() {
			let item = NSMenuItem(title: "\(source.name)  —  \(source.origin)", action: #selector(pickSource(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = [index, sideA ? 1 : 0]
			item.state = index == current ? .on : .off
			item.isEnabled = shelf.refusal(making: index, sideA: sideA) == nil || index == current
			menu.addItem(item)
		}
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
	}

	@objc private func pickSource(_ item: NSMenuItem) {
		guard let pair = item.representedObject as? [Int], pair.count == 2 else { return }
		choose(pair[0], sideA: pair[1] == 1)
	}

	private func choose(commit: GitCommit, sideA: Bool) {
		guard let root = historyRoot, let path = historyPath else { return }
		let source = CompareSource.blob(repository: root, commit: commit.hash, path: path)
		if let refusal = shelf.take(source, sideA: sideA) {
			Toast.post("Not comparable", detail: refusal, kind: .information)
			return
		}
		compare()
	}

	// MARK: - The history rail

	/// The history of whichever side is in a repository: a blob's own, or a
	/// disk file's through the estate.
	private func loadHistory() async {
		var place: (root: URL, path: String)?
		for source in [shelf.left, shelf.right] {
			switch source {
			case .blob(let repository, _, let path): place = (repository, path)
			case .file(let url): place = repositoryPlace?(url)
			case .folder, .tree: break
			}
			if place != nil { break }
		}
		guard let place else {
			showRail(false)
			return
		}
		let generation = loadGeneration
		let commits = await GitHistory.log(in: place.root, path: place.path, limit: 200)
		guard generation == loadGeneration else { return }
		historyRoot = place.root
		historyPath = place.path
		guard !commits.isEmpty else {
			showRail(false)
			return
		}
		rail.show(commits: commits, chosenA: chosenHash(shelf.left, in: commits), chosenB: chosenHash(shelf.right, in: commits))
		showRail(true)
	}

	private func chosenHash(_ source: CompareSource, in commits: [GitCommit]) -> String? {
		guard case .blob(_, let commit, _) = source else { return nil }
		return commits.first { $0.hash == commit || $0.hash.hasPrefix(commit) }?.hash
	}

	private func showRail(_ shows: Bool) {
		railIsShown = shows
		rail.isHidden = !shows
		arrange()
	}

	// MARK: - Applying

	private func askToApply() {
		guard let comparison, let window else { return }
		let operations = comparison.operations
		guard !operations.isEmpty else { return }
		let alert = NSAlert()
		alert.messageText = "Apply \(operations.count) change\(operations.count == 1 ? "" : "s")?"
		alert.informativeText = operations.map(\.said).joined(separator: "\n")
			+ "\n\nWhat is overwritten or removed goes to the Trash first."
		alert.addButton(withTitle: "Apply")
		alert.addButton(withTitle: "Cancel")
		alert.beginSheetModal(for: window) { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			Task { @MainActor in
				let results = await comparison.apply()
				let failed = results.filter { $0.error != nil }
				if let first = failed.first {
					Toast.post("\(failed.count) of \(results.count) did not apply", detail: "\(first.operation.said): \(first.error ?? "")")
				}
				self?.refreshFooter()
			}
		}
	}

	// MARK: - Drops

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		EditorDrop.urls(from: sender.draggingPasteboard).isEmpty ? [] : .copy
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let dropped = EditorDrop.urls(from: sender.draggingPasteboard)
		guard !dropped.isEmpty else { return false }
		for url in dropped { shelf.add(Self.source(for: url)) }
		shelfView.show(shelf, canGoBack: folderShelf != nil)
		return true
	}

	static func source(for url: URL) -> CompareSource {
		(DroppedFiles.directoryCheck(url) ?? false) ? .folder(url) : .file(url)
	}

	// MARK: - For a driven run

	var reportForTesting: String {
		var lines = ["title: \(shelf.title)", "shelf: " + shelf.sources.enumerated().map { index, source in
			let chips = (index == shelf.a ? "A" : "") + (index == shelf.b ? "B" : "")
			return "[\(chips)] \(source.origin)"
		}.joined(separator: " | ")]
		if let fileView { lines.append(fileView.reportForTesting) }
		if let comparison { lines.append(comparison.counts.said) }
		if let folderView { lines.append(folderView.reportForTesting) }
		if railIsShown { lines.append("history:\n" + rail.reportForTesting) }
		if let notice { lines.append("notice: " + notice.stringValue) }
		return lines.joined(separator: "\n")
	}

	/// The gestures the page has, as steps: `next`, `previous`, `open:<path>`,
	/// `mark:<path>:<copy to A|copy to B|delete>`, `clear:<path>`, `select:<path>`, `equal`,
	/// `filter:<text>`, `back`, `chip:<index>:<A|B>`, `history:<row>:<A|B>`,
	/// `wrap`, `apply`, `settle`, `wait:<seconds>`, `report`. A driven `apply` marks and does
	/// nothing: what a driven run is forbidden to touch includes the folders
	/// it was pointed at.
	func stepsForTesting(_ steps: String) async -> String {
		var report: [String] = []
		for step in steps.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
			let parts = step.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
			switch parts[0] {
			case "settle":
				while isWorking { try? await Task.sleep(nanoseconds: 50_000_000) }
				if let comparison { await comparison.settled() }
				try? await Task.sleep(nanoseconds: 100_000_000)
				report.append("settled")
			case "next": fileView?.nextChange(); report.append(fileView?.changeSaid ?? "no file diff")
			case "previous": fileView?.previousChange(); report.append(fileView?.changeSaid ?? "no file diff")
			case "open": report.append(folderView?.openForTesting(parts.dropFirst().joined(separator: ":")) ?? "no folder diff")
			case "mark":
				guard parts.count >= 3 else { report.append("mark: path and mark"); continue }
				let mark: FolderComparison.Mark? = ["copy to A": .copyToLeft, "copy to B": .copyToRight, "delete": .delete][parts[2]]
				report.append(folderView?.markForTesting(parts[1], mark) ?? "no folder diff")
			case "clear": report.append(folderView?.markForTesting(parts.dropFirst().joined(separator: ":"), nil) ?? "no folder diff")
			case "select": report.append(folderView?.selectForTesting(parts.dropFirst().joined(separator: ":")) ?? "no folder diff")
			case "equal":
				folderView?.showsEqual.toggle()
				footer.showsEqual = folderView?.showsEqual ?? false
				report.append("equal \(folderView?.showsEqual == true ? "shown" : "hidden")")
			case "filter":
				let text = parts.dropFirst().joined(separator: ":")
				folderView?.filter = text
				footer.filterText = text
				report.append("filter \(text)")
			case "back": goBackToFolders(); report.append("back")
			case "chip":
				guard parts.count >= 3, let index = Int(parts[1]) else { report.append("chip: index and side"); continue }
				choose(index, sideA: parts[2] == "A")
				report.append("chip \(parts[2]) on \(index)")
			case "swap":
				swapSides()
				report.append("swapped")
			case "history":
				guard parts.count >= 3, let row = Int(parts[1]) else { report.append("history: row and side"); continue }
				report.append(rail.chooseForTesting(row: row, sideA: parts[2] == "A"))
			case "wrap":
				Settings.shared.wordWrap.toggle()
				report.append("wrap \(Settings.shared.wordWrap ? "on" : "off")")
			case "apply":
				report.append("apply refused: a driven run marks and does not apply (\(comparison?.operations.count ?? 0) marked)")
			case "report": report.append(reportForTesting)
			default: report.append("unknown step \(step)")
			}
		}
		return report.joined(separator: "\n")
	}
}

/// The top of a compare page: what is on the left over the left half, what
/// is on the right over the right half, and between them — over the gutter
/// — the one control that turns them round.
///
/// It was a row of cards each with an A chip and a B chip, and the chips
/// asked a question nobody wanted: two letters on every card, when the two
/// halves below already say which side is which. Now a side is a card, the
/// letter is a label on it, the other sources the page holds are a menu under
/// it, and the swap is where the eye already goes for "the other way round".
final class CompareShelfView: NSView {
	/// A card was pressed: which side, and the card, for the menu to hang on.
	var onPick: ((Bool, NSView) -> Void)?
	var onSwap: (() -> Void)?
	var onBack: (() -> Void)?
	private let left = CompareShelfCard()
	private let right = CompareShelfCard()
	private lazy var swap = DrawnButton(symbol: "arrow.left.arrow.right", description: "Swap A and B") { [weak self] in self?.onSwap?() }
	private lazy var back = DrawnButton(symbol: "chevron.left", description: "Back to the folders") { [weak self] in self?.onBack?() }
	private var canGoBack = false

	override var isFlipped: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		left.onPress = { [weak self] card in self?.onPick?(true, card) }
		right.onPress = { [weak self] card in self?.onPick?(false, card) }
		addSubview(left)
		addSubview(right)
		addSubview(swap)
		addSubview(back)
		swap.toolTip = "Swap A and B"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Framed by hand rather than by constraints, so a new size places the
	/// subviews itself — AppKit's own layout pass is not to be waited for.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		arrange()
	}

	override func layout() {
		super.layout()
		arrange()
	}

	func show(_ shelf: CompareShelf, canGoBack: Bool) {
		let choices = shelf.sources.count > 1
		left.show(shelf.left, letter: "A", hasChoices: choices)
		right.show(shelf.right, letter: "B", hasChoices: choices)
		self.canGoBack = canGoBack
		back.isHidden = !canGoBack
		arrange()
		needsDisplay = true
	}

	func applyTheme() {
		left.needsDisplay = true
		right.needsDisplay = true
		arrange()
	}

	private func arrange() {
		let theme = Theme.current
		let inset = theme.scaled(8)
		let top = theme.scaled(6)
		let height = bounds.height - theme.scaled(12)
		let middle = (bounds.width / 2).rounded()
		let swapWidth = theme.scaled(28)
		var leftStart = inset
		if canGoBack {
			back.frame = NSRect(x: inset, y: top, width: theme.scaled(24), height: height)
			leftStart += theme.scaled(30)
		}
		swap.frame = NSRect(x: middle - swapWidth / 2, y: top, width: swapWidth, height: height)
		let gap = theme.scaled(8)
		left.frame = NSRect(x: leftStart, y: top, width: max(0, middle - swapWidth / 2 - gap - leftStart), height: height)
		right.frame = NSRect(x: middle + swapWidth / 2 + gap, y: top, width: max(0, bounds.width - inset - (middle + swapWidth / 2 + gap)), height: height)
	}

	/// `bounds`, never `dirtyRect`: since macOS 14 a view does not clip to its
	/// bounds, and the rect handed in reaches across the whole page — a strip
	/// that filled it painted the editor's own colour over the trees below and
	/// the tab bar above, and looked like a page that drew nothing at all.
	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
	}
}

/// One side of the shelf: its letter, what it is, where it is from, and a
/// chevron when there is something else it could be.
final class CompareShelfCard: NSView {
	var onPress: ((NSView) -> Void)?
	private var source: CompareSource?
	private var letter = "A"
	private var hasChoices = false

	override var isFlipped: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// A layer-backed view displayed at one size keeps that picture at the
	/// next unless it is told; a view drawn by hand is told here.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}

	func show(_ source: CompareSource, letter: String, hasChoices: Bool) {
		self.source = source
		self.letter = letter
		self.hasChoices = hasChoices
		toolTip = source.origin + (hasChoices ? "\n\nClick to make this side something else on the shelf." : "")
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let source else { return }
		let theme = Theme.current
		let path = NSBezierPath(roundedRect: bounds, xRadius: theme.scaled(6), yRadius: theme.scaled(6))
		theme.editorBackground.setFill()
		path.fill()
		theme.separator.setStroke()
		path.stroke()

		// The letter, lit, at the edge the side is on.
		let chip = NSSize(width: theme.scaled(18), height: theme.scaled(16))
		let inset = theme.scaled(8)
		let chipRect = NSRect(x: inset, y: (bounds.height - chip.height) / 2, width: chip.width, height: chip.height)
		let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: theme.scaled(4), yRadius: theme.scaled(4))
		theme.gitModified.setFill()
		chipPath.fill()
		let chipFont = Theme.font(size: theme.fontSize * 0.75, weight: .bold, monospaced: false)
		let chipAttributes: [NSAttributedString.Key: Any] = [.font: chipFont, .foregroundColor: NSColor.white]
		let chipSize = (letter as NSString).size(withAttributes: chipAttributes)
		(letter as NSString).draw(at: NSPoint(x: chipRect.midX - chipSize.width / 2, y: chipRect.midY - chipSize.height / 2), withAttributes: chipAttributes)

		var textEnd = bounds.width - inset
		if hasChoices {
			let chevron = "⌄" as NSString
			let chevronAttributes: [NSAttributedString.Key: Any] = [
				.font: Theme.font(size: theme.fontSize, weight: .regular, monospaced: false),
				.foregroundColor: theme.gitIgnored,
			]
			let size = chevron.size(withAttributes: chevronAttributes)
			chevron.draw(at: NSPoint(x: bounds.width - inset - size.width, y: (bounds.height - size.height) / 2 - theme.scaled(2)), withAttributes: chevronAttributes)
			textEnd -= size.width + theme.scaled(6)
		}

		let name = Theme.font(size: theme.fontSize * 0.9, weight: .semibold, monospaced: false)
		let small = Theme.font(size: theme.fontSize * 0.75, weight: .regular, monospaced: false)
		let textX = chipRect.maxX + theme.scaled(8)
		let textWidth = max(0, textEnd - textX)
		(source.name as NSString).draw(
			with: NSRect(x: textX, y: theme.scaled(6), width: textWidth, height: name.pointSize * 1.4),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
			attributes: [.font: name, .foregroundColor: theme.sidebarText]
		)
		(source.origin as NSString).draw(
			with: NSRect(x: textX, y: theme.scaled(6) + name.pointSize * 1.45, width: textWidth, height: small.pointSize * 1.4),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
			attributes: [.font: small, .foregroundColor: theme.gitIgnored]
		)
	}

	override func mouseDown(with event: NSEvent) {
		guard hasChoices else { return super.mouseDown(with: event) }
		onPress?(self)
	}
}

/// The strip under a compare page: for a file diff, where the reader is and
/// the two arrows; for a folder diff, the filter, the equal-rows switch, the
/// count of marks and *Apply…*.
final class CompareFooterView: NSView {
	enum Mode { case none, file, folder }

	var onNext: (() -> Void)?
	var onPrevious: (() -> Void)?
	var onShowEqual: ((Bool) -> Void)?
	var onFilter: ((String) -> Void)?
	var onApply: (() -> Void)?

	var mode: Mode = .none {
		didSet { arrangeForMode() }
	}

	var changeSaid = "" {
		didSet { changeLabel.stringValue = changeSaid }
	}

	var itemsSaid = "" {
		didSet { itemsLabel.stringValue = itemsSaid }
	}

	var canApply = false {
		didSet { apply.isEnabled = canApply }
	}

	var showsEqual = false {
		didSet { equal.state = showsEqual ? .on : .off }
	}

	var filterText: String {
		get { filter.stringValue }
		set { filter.stringValue = newValue }
	}

	private let changeLabel = ScaledLabel("", size: 11, colour: { Theme.current.sidebarText })
	private lazy var previous = DrawnButton(symbol: "chevron.up", description: "Previous change") { [weak self] in self?.onPrevious?() }
	private lazy var next = DrawnButton(symbol: "chevron.down", description: "Next change") { [weak self] in self?.onNext?() }
	private let filter = ScaledSearchField(placeholder: "Filter by name")
	private lazy var equal = DrawnCheckbox(title: "Show equal") { [weak self] in self?.equalToggled() }
	private let itemsLabel = ScaledLabel("", size: 11, colour: { Theme.current.gitIgnored })
	private lazy var apply = DrawnButton(title: "Apply…") { [weak self] in self?.onApply?() }

	override var isFlipped: Bool { true }

	/// Framed by hand rather than by constraints, so a new size places the
	/// subviews itself — AppKit's own layout pass is not to be waited for.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		arrange()
		needsDisplay = true
	}

	override func layout() {
		super.layout()
		arrange()
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		for view in [changeLabel, previous, next, filter, equal, itemsLabel, apply] as [NSView] {
			view.isHidden = true
			addSubview(view)
		}
		filter.target = self
		filter.action = #selector(filterChanged)
		apply.isEnabled = false
		next.toolTip = "Next change  ⌘↓"
		previous.toolTip = "Previous change  ⌘↑"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	@objc private func filterChanged() { onFilter?(filter.stringValue) }

	/// The box flipped itself; the page is told which way.
	private func equalToggled() { onShowEqual?(equal.state == .on) }

	func applyTheme() { arrange(); needsDisplay = true }

	private func arrangeForMode() {
		changeLabel.isHidden = mode != .file
		previous.isHidden = mode != .file
		next.isHidden = mode != .file
		filter.isHidden = mode != .folder
		equal.isHidden = mode != .folder
		itemsLabel.isHidden = mode != .folder
		apply.isHidden = mode != .folder
		arrange()
	}

	private func arrange() {
		let theme = Theme.current
		let inset = theme.scaled(10)
		let height = bounds.height
		let buttonSize = theme.scaled(22)
		switch mode {
		case .file:
			changeLabel.sizeToFit()
			next.frame = NSRect(x: bounds.width - inset - buttonSize, y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)
			previous.frame = NSRect(x: next.frame.minX - buttonSize - theme.scaled(4), y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)
			changeLabel.frame = NSRect(x: previous.frame.minX - theme.scaled(8) - changeLabel.frame.width, y: (height - changeLabel.frame.height) / 2, width: changeLabel.frame.width, height: changeLabel.frame.height)
		case .folder:
			let fieldHeight = theme.scaled(22)
			filter.frame = NSRect(x: inset, y: (height - fieldHeight) / 2, width: min(theme.scaled(220), bounds.width * 0.3), height: fieldHeight)
			equal.sizeToFit()
			equal.frame = NSRect(x: filter.frame.maxX + theme.scaled(12), y: (height - equal.frame.height) / 2, width: equal.frame.width, height: equal.frame.height)
			apply.sizeToFit()
			let applyWidth = max(theme.scaled(70), apply.frame.width + theme.scaled(16))
			apply.frame = NSRect(x: bounds.width - inset - applyWidth, y: (height - buttonSize) / 2, width: applyWidth, height: buttonSize)
			itemsLabel.sizeToFit()
			itemsLabel.frame = NSRect(x: apply.frame.minX - theme.scaled(10) - itemsLabel.frame.width, y: (height - itemsLabel.frame.height) / 2, width: itemsLabel.frame.width, height: itemsLabel.frame.height)
		case .none:
			break
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		// `bounds`, not `dirtyRect` — see `CompareShelfView.draw`.
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
	}
}
