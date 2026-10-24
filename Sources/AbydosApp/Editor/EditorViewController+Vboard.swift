import AbydosKit
import AppKit

/// `.vboard` files, opened as boards on the vboard server named in the
/// settings. See `VboardPaneView`.
extension EditorViewController {
	/// Paths to open as text once, because somebody pressed *Open as Text* on
	/// the board tab showing them. One-shot: the next time the file is opened,
	/// it is a board again.
	private static var textInsteadOfBoard: Set<String> = []

	/// A board tab for a `.vboard`, or nil for anything else.
	///
	/// Always a board tab for a `.vboard`, server or not: with no server named
	/// the pane says so and offers the text, which is how a `.vboard` opened
	/// before. A provisional tab and a restored one wait to be asked before
	/// anything is sent anywhere.
	func makeBoardTab(for fileURL: URL, preview: Bool) -> Tab? {
		guard fileURL.pathExtension.lowercased() == "vboard" else { return nil }
		if Self.textInsteadOfBoard.remove(FilePath.canonical(fileURL)) != nil { return nil }
		let pane = VboardPaneView(url: fileURL, start: !preview && !isRestoringSession)
		let tab = Tab(url: fileURL, document: nil, codeView: nil, contentView: pane, isPreview: preview)
		tab.board = pane
		tab.previewMode = .preview
		pane.onDirtyChanged = { [weak self, weak tab] in
			// An edit on the board is a commitment to the tab, as typing is.
			if tab?.board?.isDirty == true { tab?.isPreview = false }
			self?.refreshTabBar()
		}
		pane.onStatusChanged = { [weak self, weak tab] in
			guard let self, let tab, self.activeTab === tab else { return }
			self.onStatusChanged?(self)
		}
		pane.onOpenAsText = { [weak self, weak tab] in
			guard let self, let tab, let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
			Self.textInsteadOfBoard.insert(FilePath.canonical(fileURL))
			self.removeTab(at: index)
			self.open(fileURL: fileURL, focusEditor: true)
		}
		return tab
	}

	/// A board that lives on the server, in a page tab named by it: choosing the
	/// same board again brings that tab back rather than making another.
	///
	/// Looked for before the pane is made, because the pane goes to the server
	/// the moment it exists.
	func openServerBoard(_ board: VboardBoardSummary, server: URL) {
		let identifier = "vboard/\(server.host ?? "server")/\(board.id)"
		let page = URL(fileURLWithPath: "/ideai/page/" + identifier)
		if let index = tabs.firstIndex(where: { $0.pageTitle != nil && $0.url == page }) {
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return
		}
		let pane = VboardPaneView(board: board, page: page)
		openPage(pane, title: board.name, identifier: identifier, symbol: "rectangle.on.rectangle")
		guard let tab = tabs.first(where: { $0.contentView === pane }) else { return }
		tab.board = pane
		pane.onStatusChanged = { [weak self, weak tab] in
			guard let self, let tab, self.activeTab === tab else { return }
			self.onStatusChanged?(self)
		}
	}

	/// The board tab in front, for a driven run's report.
	var activeBoard: VboardPaneView? { activeTab?.board }
}
