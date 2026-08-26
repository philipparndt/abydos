import AppKit
import AbydosKit

/// Copying a place in the code so somebody else can go to it, and going to one
/// that was copied.
///
/// A permalink names a commit, a file and a line; following one has to find
/// that commit in this checkout, which is why this knows about a project at all.
@MainActor
final class CodeLinks {
	let editor: EditorAreaController
	let toasts: ToastPresenter

	var currentProject: () -> Project? = { nil }
	var onNotify: (String, String?, Toast.Kind) -> Void = { _, _, _ in }

	/// The window's toast, with the labels its callers already use.
	func notify(_ title: String, detail: String? = nil, kind: Toast.Kind = .error) {
		onNotify(title, detail, kind)
	}


	init(editor: EditorAreaController, toasts: ToastPresenter) {
		self.editor = editor
		self.toasts = toasts
	}

	/// Copies where somebody is, in the form they asked for.
	///
	/// **Two forms because there are two audiences, and they want different
	/// strings.** An assistant or a terminal wants `path:line`, which needs
	/// nothing but the project root and is openable by `abydos`. A person, and a
	/// bookmark for Monday, wants a permalink pinned to a commit, because a link
	/// into a branch is wrong the next time somebody edits above the line.
	/// Edit ▸ Copy Reference, which is ⌘⇧C.
	@objc func copyReference(_ sender: Any?) { copyLinkFromTheCaret(.reference) }

	/// Edit ▸ Copy Permalink.
	@objc func copyPermalink(_ sender: Any?) { copyLinkFromTheCaret(.permalink) }

	/// The same gesture the context menu makes, from the caret rather than from
	/// where somebody right-clicked. Silent with no file open: a menu item that
	/// does nothing is better than one that says so.
	func copyLinkFromTheCaret(_ form: CodeView.LinkForm) {
		guard let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let url = group.activeTabURL,
		      let span = codeView.lineSpanForReference()
		else { return }
		copyLink(to: url, form: form, line: span.line, endLine: span.endLine)
	}

	func copyLink(to url: URL, form: CodeView.LinkForm, line: Int, endLine: Int?) {
		let place = CodePlace(url: url, in: currentProject()?.root, line: line, endLine: endLine)

		switch form {
		case .reference:
			copyToPasteboard(place.text)
			notify(
				place.lineCount > 1 ? "Copied \(place.lineCount) lines" : "Copied the reference",
				detail: place.text, kind: .information
			)

		case .permalink:
			Task { @MainActor [weak self] in
				guard let self else { return }
				let found = await GitRepository.discover(from: url.deletingLastPathComponent())
				// Read once and kept, rather than reached for three times.
				guard let root = found?.root else {
					notify(
						"No repository to link to",
						detail: "A permalink names a commit, and this file is not in a checkout.",
						kind: .information
					)
					return
				}
				// **Two roots, and they can differ.** The forge serves paths
				// relative to the repository; a reference is relative to the
				// project, which in a monorepo is a directory inside it. Each is
				// right for its own audience.
				let inRepository = CodePlace(url: url, in: root, line: line, endLine: endLine)
				guard let link = await CodeLink.permalink(
					for: inRepository,
					repositoryPath: inRepository.path,
					repository: root
				) else {
					notify(
						"Nothing to link to",
						detail: "This checkout has no remote this app recognises, "
							+ "so there is no address to build.",
						kind: .information
					)
					return
				}
				self.copyToPasteboard(link.url.absoluteString)
				// The caveat is the whole point of this path: the two ways a
				// permalink is a dead letter are both invisible to whoever
				// receives it.
				notify(
					link.caveat == nil ? "Copied the permalink" : "Copied, with something to know",
					detail: link.caveat ?? link.url.absoluteString,
					kind: link.caveat == nil ? .information : .warning
				)
			}
		}
	}

	/// Edit ▸ Go to Copied Place, which is ⌘⇧V.
	///
	/// **The way in, with no URL scheme to rely on.** A permalink is not
	/// clickable into this app — registering a scheme is its own item — so the
	/// pasteboard is the door: whatever is on it, a reference or one of this
	/// app's permalinks, is opened.
	@objc func goToCopiedPlace(_ sender: Any?) {
		let copied = NSPasteboard.general.string(forType: .string) ?? ""

		// A permalink first, because it is the specific shape: `path:line` would
		// otherwise match the tail of a URL that has a colon and a number in it.
		if let followed = CodeLink.follow(copied) {
			follow(followed)
			return
		}
		guard let place = CodePlace.parse(copied) else {
			notify(
				"Nothing to go to",
				detail: "What is copied is neither a reference like “path:12” nor a permalink.",
				kind: .information
			)
			return
		}
		// **A reference from anywhere else is opened at the number, with nothing
		// inferred.** This app has no idea what that file looked like when the
		// reference was made, and re-finding a line from a guess about its text
		// would be inventing.
		let url = place.url(in: currentProject()?.root)
		guard FileManager.default.fileExists(atPath: url.path) else {
			notify("No such file", detail: place.text, kind: .warning)
			return
		}
		editor.open(fileURL: url, atLine: place.line)
	}

	/// Opens one of this app's own permalinks, at the line the text is on now.
	func follow(_ followed: CodeLink.Followed) {
		Task { @MainActor [weak self] in
			guard let self, let project = currentProject() else { return }
			let root = await GitRepository.discover(from: project.root)?.root
			guard let root else {
				notify(
					"Not a checkout",
					detail: "This link names a commit, and this project is not in a repository.",
					kind: .information
				)
				return
			}
			let file = root.appendingPathComponent(followed.path)
			guard FileManager.default.fileExists(atPath: file.path) else {
				notify(
					"That file is not in this project",
					detail: followed.path + " — the link may be for another repository.",
					kind: .warning
				)
				return
			}
			let landing = await CodeLink.land(followed, in: root)
			self.editor.open(fileURL: file, atLine: landing.line)
			// Said only when there is something to say. A destination that
			// quietly differs from the one in the link is worse than a wrong
			// one, because nobody knows to check.
			if let said = landing.said(commit: followed.commit) {
				notify("Followed the link", detail: said, kind: .information)
			}
		}
	}

	func copyToPasteboard(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	/// Switches to a branch the way the titlebar does, and says what came of it
	/// — for `--checkout-branch`.
	///
	/// Through `BranchMenu.checkout`, which is the function the titlebar and the
	/// switcher share, so what is driven is what a click does.
	func checkoutBranchForTesting(_ branch: String, pressing: Bool) {
		guard let root = currentProject()?.root else {
			print("BRANCH: no project")
			fflush(stdout)
			return
		}
		let before = toasts.saidForTesting.count
		BranchMenu.checkout(branch, in: root)

		// git and the worktree list are two processes; give them a moment.
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			guard let self else { return }
			let said = self.toasts.saidForTesting.dropFirst(before)
			print("BRANCH \(branch): \(said.isEmpty ? "nothing said" : said.joined(separator: " / "))")
			Task { @MainActor in
				let on = await BranchMenu.currentBranchForTesting(in: root)
				print("BRANCH \(branch): on \(on ?? "none") in \(root.lastPathComponent)")
				fflush(stdout)
			}
			guard pressing else { return }

			let pressed = self.toasts.pressLastOfferForTesting()
			print("BRANCH pressed: \(pressed)")
			fflush(stdout)
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
				guard let self else { return }
				print("BRANCH after: project=\(currentProject()?.root.lastPathComponent ?? "none")"
					+ " said=\(self.toasts.saidForTesting.dropFirst(before).joined(separator: " / "))")
				fflush(stdout)
			}
		}
	}

	/// Copies a link the way the menu does, and says what came of it — for
	/// `--copy-link`.
	///
	/// **Through the same call the menu makes**, so what is watched is what the
	/// gesture does: the pasteboard afterwards is the deliverable, and the
	/// sentence beside it is the other half.
	func copyLinkForTesting(_ form: String, line: Int, endLine: Int?) {
		guard let group = editor.activeGroup, let url = group.activeTabURL else {
			print("LINK: nothing open")
			fflush(stdout)
			return
		}
		let said = toasts.saidForTesting.count
		copyLink(
			to: url,
			form: form == "permalink" ? .permalink : .reference,
			line: line, endLine: endLine
		)
		// The permalink asks git, so the answer is a moment away.
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			guard let self else { return }
			print("LINK copied: \(NSPasteboard.general.string(forType: .string) ?? "nothing")")
			print("LINK said: \(self.toasts.saidForTesting.dropFirst(said).joined(separator: " / "))")
			fflush(stdout)
		}
	}

	/// Puts a link on the pasteboard and follows it, saying where the caret
	/// ended up — for `--follow-link`.
	func followLinkForTesting(_ text: String) {
		copyToPasteboard(text)
		let said = toasts.saidForTesting.count
		goToCopiedPlace(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
			guard let self else { return }
			let where_ = self.editor.activeGroup?.activeCodeView?.caretPositionForRequest()
			print("LINK followed: \(self.editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing")"
				+ " line \(where_.map { $0.line + 1 } ?? -1)")
			print("LINK said: \(self.toasts.saidForTesting.dropFirst(said).joined(separator: " / "))")
			fflush(stdout)
		}
	}
}
