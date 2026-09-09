import AppKit
import AbydosKit

/// Opening a compare page, from wherever two things to compare come from: two
/// rows of the tree, a file dropped on an open file, an open panel, a
/// remembered session, the command line.
///
/// Its own file for the reason `MainWindowController+Blame` is one: the window
/// controller is where the tree, the editor and the git pages meet, and a page
/// that needs all three has to be opened from here, but the opening is one
/// subject and this is it.
extension MainWindowController {
	/// Opens a compare page over two sources, or brings back the one already
	/// open over them.
	@discardableResult
	func openComparePage(left: CompareSource, right: CompareSource, asked: Bool = true) -> ComparePage? {
		guard left.canBeComparedWith(right) else {
			Toast.post(
				"Not comparable",
				detail: "A file is compared with a file and a folder with a folder.",
				kind: .information
			)
			return nil
		}
		guard let group = editor.activeGroup else { return nil }
		let identifier = ComparePageIdentity.identifier(left: left, right: right)
		if let existing = group.page(identifier: identifier) as? ComparePage {
			group.openPage(existing, title: existing.shelf.title, identifier: identifier, symbol: Self.compareSymbol)
			return existing
		}

		let page = ComparePage(shelf: CompareShelf(a: left, b: right))
		page.repositoryPlace = { [weak self] url in
			self?.sidebar.repositoryPlace(of: url).map { ($0.root, $0.path) }
		}
		page.onOpenCommit = { [weak self] commit, repository, path in
			// The log of the repository the commit is in, at that commit, scoped
			// to the file — the gesture blame's own reveal makes.
			let page = self?.sidebar.showLogPage(scopedTo: commit.hash, in: repository)
			if !path.isEmpty { page?.setScope(path: path) }
		}
		page.onTitleChanged = { [weak group, weak page] title, subtitle in
			guard let group, let page else { return }
			group.retitlePage(page, title: title, subtitle: subtitle)
		}
		page.onClose = { [weak group] in
			_ = group?.closeTab(showing: URL(fileURLWithPath: "/ideai/page/" + identifier))
		}
		leaveTerminalFullScreen()
		group.openPage(page, title: page.shelf.title, identifier: identifier, symbol: Self.compareSymbol)
		if asked { giveTheEditorTheWindow() }
		page.compare()
		return page
	}

	static let compareSymbol = "arrow.left.arrow.right"

	/// *Compare Selected* over two rows of the tree: the first selected is A.
	func compareSelected(_ urls: [URL]) {
		guard urls.count == 2 else { return }
		openComparePage(left: ComparePage.source(for: urls[0]), right: ComparePage.source(for: urls[1]))
	}

	/// *Compare ▸ With…* on a row: asks for the other side with an open panel
	/// that offers only the row's own kind.
	func compareWith(_ url: URL) {
		let isFolder = DroppedFiles.directoryCheck(url) ?? false
		let panel = NSOpenPanel()
		panel.canChooseFiles = !isFolder
		panel.canChooseDirectories = isFolder
		panel.allowsMultipleSelection = false
		panel.message = "Compare \(url.lastPathComponent) with…"
		panel.prompt = "Compare"
		guard let window else { return }
		panel.beginSheetModal(for: window) { [weak self] response in
			guard response == .OK, let other = panel.url else { return }
			self?.openComparePage(left: ComparePage.source(for: url), right: ComparePage.source(for: other))
		}
	}

	/// A file dropped over the text of an open file: a comparison of the two,
	/// with the open file as A. Anything else is not this window's to take.
	func compareDropped(_ dropped: [URL], onto active: URL) -> Bool {
		guard dropped.count == 1, let other = dropped.first,
		      DroppedFiles.directoryCheck(other) == false, DroppedFiles.directoryCheck(active) == false
		else { return false }
		return openComparePage(left: .file(active), right: .file(other)) != nil
	}

	/// The page in front, if it is a compare page.
	var activeComparePage: ComparePage? {
		editor.activeGroup?.activePageView as? ComparePage
	}

	// MARK: - For a driven run

	/// `--compare <a> <b>`: opens the page and says what it opened.
	func openCompareForTesting(_ a: String, _ b: String) -> String {
		let left = ComparePage.source(for: URL(fileURLWithPath: a).standardizedFileURL)
		let right = ComparePage.source(for: URL(fileURLWithPath: b).standardizedFileURL)
		guard let page = openComparePage(left: left, right: right) else { return "refused: \(a) against \(b)" }
		return "opened \(page.shelf.title)"
	}

	/// `--compare-steps <steps>`, over the page in front.
	func compareStepsForTesting(_ steps: String) async -> String {
		guard let page = activeComparePage else { return "no compare page in front" }
		return await page.stepsForTesting(steps)
	}
}
