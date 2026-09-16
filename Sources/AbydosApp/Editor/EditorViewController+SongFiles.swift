import AppKit
import AbydosKit

/// Showing a song's other files in the song's own tab.
///
/// A song is written across files — a kit of instruments, a set of patterns,
/// the song that includes them — and the song is what plays. Opening one of
/// those files as a tab of its own meant a second song pane, which had to work
/// out for itself which song the file belonged to and start again; reported
/// 2026-09-16: "jumping to other files and keep the stream does not really
/// work … It stops very often and also it cannot know to which song it
/// belongs."
///
/// A file cannot know. The song knows — it is the one that includes them, and
/// the server says which files it is made of. So the song's tab shows them: the
/// text in front changes, the pane below does not, and nothing is asked about
/// which song anything belongs to.
extension EditorViewController {
	/// Shows another of this tab's song's files in it.
	///
	/// The file in front is put aside whole — its caret, folds, scroll and undo
	/// are its code view's, which is kept — and the one asked for is put back if
	/// it has been shown before, or built if it has not. The pane is untouched:
	/// the song did not change, so nothing re-renders and nothing stops.
	@discardableResult
	func showInTab(file: URL, in tab: Tab) -> Bool {
		guard FilePath.canonical(file) != FilePath.canonical(tab.url) else { return true }
		guard FileManager.default.fileExists(atPath: file.path) else { return false }

		// Going from one of a song's files to another is navigation, and ⌘[
		// comes back from it — which is what the row above the text is for.
		let departure = currentPlace
		defer {
			DispatchQueue.main.async { [weak self] in
				guard let self, let arrival = self.currentPlace else { return }
				self.reportNavigation(from: departure, to: arrival)
			}
		}

		let leaving = FilePath.canonical(tab.url)
		let leavingView = tab.sourceView
		tab.halves[leaving] = tab.half
		tab.shows(file)

		if let kept = tab.halves[FilePath.canonical(file)] {
			tab.half = kept
		} else {
			guard let document = try? TextDocument(url: file) else {
				// Unreadable: the tab stays where it was.
				tab.shows(URL(fileURLWithPath: leaving))
				if let back = tab.halves[leaving] { tab.half = back }
				return false
			}
			let (codeView, scrollView) = makeCodeSource()
			tab.half = Tab.Half(
				document: document, codeView: codeView, sourceView: scrollView, serverRoot: nil
			)
			// Everything a file's code view does, wired to this tab: the same
			// call the tab's own file went through when it opened.
			wire(codeView, of: file, document: document, in: tab)
			codeView.setWordWrap(Settings.shared.wordWrap)
			codeView.showsTimeCodes = Settings.shared.songTimeCodes
			codeView.showsTimelineBars = Settings.shared.songTimelineBars
		}

		put(tab.sourceView, inPlaceOf: leavingView, in: tab)
		applyDebugState(to: tab)
		applyConditionalBreakpoints(to: tab)
		refreshChangedLines(for: tab)
		restoreFind(for: tab)
		tab.codeView?.reportCaretPosition()
		statusLanguage = tab.document?.displayLanguageName
		if let pane: SongPreviewView = Self.pane(in: tab.contentView) {
			pane.shows(file: file)
			// Each file has a code view of its own, and the pane is the same
			// pane: the caret's lane, the timeline bars and the loop are tied
			// to whichever of them is in front.
			bindSong(pane, to: tab)
		}
		refreshFilesBar(in: tab)
		refreshTabBar()
		onStatusChanged?(self)
		onActiveFileChanged?(tab.url)
		return true
	}

	/// The new file's view where the old one was, inside whatever the tab is
	/// showing — beside the song's pane, over it, or on its own.
	///
	/// **Found from the view being replaced, not from the tab.** A song tab's
	/// content view is the crumb row and the split under it, so looking for the
	/// split at the top of the tab finds a stack view and swaps nothing:
	/// reported 2026-09-16, "the file change does not change the editors
	/// content". The one thing that is always true is where the outgoing view
	/// is, so the swap happens there.
	private func put(_ source: NSView?, inPlaceOf leaving: NSView?, in tab: Tab) {
		guard let source, source !== leaving else { return }
		let hadKeyboard = (view.window?.firstResponder as? NSView)
			.map { leaving.map($0.isDescendant(of:)) ?? false } ?? false
		defer {
			if hadKeyboard { view.window?.makeFirstResponder(tab.codeView ?? source) }
		}

		if let leaving, let parent = leaving.superview {
			source.translatesAutoresizingMaskIntoConstraints = true
			if let split = parent as? NSSplitView, let at = split.arrangedSubviews.firstIndex(of: leaving) {
				// The divider stays where the person left it: a swap is not a
				// reason for the pane to change size.
				let held = split.isVertical ? leaving.frame.width : leaving.frame.height
				split.insertArrangedSubview(source, at: at)
				split.removeArrangedSubview(leaving)
				leaving.removeFromSuperview()
				if held > 0, split.arrangedSubviews.count > 1 { split.setPosition(held, ofDividerAt: 0) }
			} else if let stack = parent as? NSStackView, let at = stack.arrangedSubviews.firstIndex(of: leaving) {
				stack.insertArrangedSubview(source, at: at)
				stack.removeArrangedSubview(leaving)
				leaving.removeFromSuperview()
			} else {
				source.frame = leaving.frame
				source.autoresizingMask = leaving.autoresizingMask
				parent.replaceSubview(leaving, with: source)
			}
			if tab.contentView === leaving {
				tab.contentView = source
				if activeTab === tab { reinstallContent(of: tab) }
			}
			return
		}

		// Nothing on screen to replace — the tab was never shown, or it is
		// showing the file on its own.
		if tab.contentView === leaving || leaving == nil {
			tab.contentView = source
			if activeTab === tab { reinstallContent(of: tab) }
		}
	}

	/// Puts the tab's content view back in the content area, for the swap that
	/// replaced it outright.
	private func reinstallContent(of tab: Tab) {
		contentArea.subviews.forEach { $0.removeFromSuperview() }
		let content = tab.contentView
		content.translatesAutoresizingMaskIntoConstraints = false
		contentArea.addSubview(content)
		NSLayoutConstraint.activate([
			content.topAnchor.constraint(equalTo: contentArea.topAnchor),
			content.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
			content.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			content.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
		])
	}

	/// What the row above the text says: the song, its files, and which of them
	/// is in front.
	func refreshFilesBar(in tab: Tab) {
		guard let bar: SongFilesBar = Self.pane(in: tab.contentView), let song = tab.song else { return }
		let files = filesOfTheSong(in: tab).map { URL(fileURLWithPath: $0) }
		bar.show(song: song, files: files, shown: tab.url)
	}

	/// The song tab this file belongs in, if one is open here.
	///
	/// The tab in front first — with two songs open, the one being worked on is
	/// the one that should follow a jump — and then any other. A file no open
	/// song is made of belongs nowhere and opens as itself.
	func tabShowing(fileOfSong file: URL) -> Tab? {
		guard FilePreview.kind(for: file) == .song else { return nil }
		if let active = activeTab, isOfTheSameSong(file, as: active) { return active }
		return tabs.first { isOfTheSameSong(file, as: $0) }
	}

	/// Whether this tab is a song's, and the file is one of that song's.
	func isOfTheSameSong(_ file: URL, as tab: Tab) -> Bool {
		guard tab.song != nil else { return false }
		return filesOfTheSong(in: tab).contains(FilePath.canonical(file))
	}

	/// Every file the song in this tab is made of, canonical: what the server
	/// said, and the song itself.
	func filesOfTheSong(in tab: Tab) -> Set<String> {
		guard let song = tab.song else { return [] }
		var files: Set<String> = [FilePath.canonical(song)]
		// The timeline of whichever of the song's files has been looked at
		// carries the whole list, so the answer does not depend on which one is
		// in front.
		for url in [song, tab.url] {
			guard let timeline = LanguageService.shared.timeline(for: url) else { continue }
			for uri in timeline.files {
				if let file = URL(string: uri), file.isFileURL { files.insert(FilePath.canonical(file)) }
			}
		}
		// And what the render was made of, which knows before the server does
		// when a file is included but never opened.
		for path in SongRenderCache.shared.manifest(for: song)?.sources ?? [] {
			files.insert(FilePath.canonical(URL(fileURLWithPath: path)))
		}
		return files
	}
}
