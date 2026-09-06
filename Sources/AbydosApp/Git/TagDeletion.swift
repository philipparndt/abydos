import AppKit
import AbydosKit

/// Deleting tags: what is being removed, whether the remote goes with it, and
/// what happened to each half.
///
/// **A sibling of `BranchDeletion` rather than a mode inside it.** A branch
/// delete is a question about worktrees and about commits nothing else has; a
/// tag delete is a question about a remote a workflow reads. One type answering
/// both would answer neither in its own words, and `BranchDeletion` is 886
/// lines of the first question.
///
/// What it does take from there is the lifetime, which was learnt the hard way
/// — see `untilTheSheetIsAnswered` below.
@MainActor
final class TagDeletion {
	private let root: URL
	private let remote: String?
	private weak var window: NSWindow?

	/// **Holds itself while its sheet is up.**
	///
	/// `ask` returns the moment the sheet is on screen and the press that
	/// started it has nowhere to put this object, so without this the handler's
	/// `self` is nil by the time somebody presses Delete and the press does
	/// nothing at all — no error, because nothing ran to fail. The account is
	/// in `BranchDeletion`, which is where it was paid for.
	private var untilTheSheetIsAnswered: TagDeletion?

	/// Which tags the delete is working on, as it works — the same reason
	/// `BranchDeletion` has one: a push per tag is not instant, and a list that
	/// looks unchanged looks like a press that never landed.
	var onDeleting: ((Set<String>) -> Void)?
	var onFinished: (() -> Void)?

	init(root: URL, remote: String?, window: NSWindow?) {
		self.root = root
		self.remote = remote
		self.window = window
	}

	/// Asks about the tags, having first found out where each one points.
	///
	/// Asked before the question is put, because a tag's name is not enough to
	/// check a selection by: `v1` and `v1.4.2` can be the same commit or a year
	/// apart, and the sheet is where somebody notices they picked the wrong one.
	func ask(about tags: [GitBranch]) {
		guard !tags.isEmpty else { return }
		Task { @MainActor in
			var described: [(name: String, at: String)] = []
			for tag in tags {
				described.append((tag.name, await GitTags.describe(tag.name, in: self.root) ?? "—"))
			}
			self.askAboutDeleting(described)
		}
	}

	private func askAboutDeleting(_ tags: [(name: String, at: String)]) {
		guard let first = tags.first else { return }

		let alert = NSAlert()
		alert.messageText = tags.count == 1
			? "Delete the tag “\(first.name)”?"
			: "Delete \(tags.count) tags?"

		var said: [String] = []
		if tags.count == 1 {
			said.append("It points at \(first.at).")
		}
		// The one reassuring thing that is true, and its limit. A tag is a name
		// for a commit: while that commit is reachable the tag can be written
		// again, which is what makes the local half the cheap one.
		said.append(tags.count == 1
			? "The commit is not touched, so the tag can be written again while it is still there."
			: "The commits are not touched, so the tags can be written again while they are still there.")
		if remote != nil {
			said.append("Deleting on the remote is a separate choice below: that is the copy a "
				+ "workflow, a release page and everybody else's fetch read.")
		}
		alert.informativeText = said.joined(separator: "\n\n")

		// The list where there is more than one: a single tag is named in the
		// title and described in the sentence, so a one-row list would be the
		// same words a third time — `BranchDeletion`'s rule, and the same list.
		let listing = tags.count > 1
			? BranchDeleteList(rows: tags.map { .init(name: $0.name, detail: $0.at, kind: .safe) })
			: nil

		var alsoRemote: NSButton?
		if let remote {
			// Named after the remote rather than "the remote": a fork and an
			// upstream are both plausible, and a sheet that made somebody
			// remember which is a sheet that gets the wrong answer.
			let box = NSButton(
				checkboxWithTitle: "Also delete on \(remote)", target: nil, action: nil
			)
			// **An explicit frame**, for the reason `BranchDeletion` records:
			// `NSAlert` lays an accessory out from the frame it is given, and a
			// checkbox at zero by zero is a dialog with an invisible control.
			box.frame = NSRect(origin: .zero, size: box.fittingSize)
			box.state = .off
			box.toolTip = "It goes from \(remote) for everybody. "
				+ "Pushing the tag again puts it back, if the commit is still somewhere."
			alsoRemote = box
		}
		alert.accessoryView = Self.accessory(listing: listing, checkbox: alsoRemote)

		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Cancel")
		// Not destructive-red: a tag is a name for a commit, and the commit
		// stays. Red here is the boy who cried wolf for the deletes that do
		// lose something.

		untilTheSheetIsAnswered = self
		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard let self else { return }
			defer { self.untilTheSheetIsAnswered = nil }
			guard response == .alertFirstButtonReturn else { return }
			self.delete(tags.map(\.name), alsoOnRemote: alsoRemote?.state == .on)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	/// The two halves, local first, reported per tag.
	///
	/// **Local first because it is the half that works.** If the remote refuses
	/// — a protected tag, no permission, no network — the tag is at least gone
	/// from the tree somebody is looking at, and the report says which state
	/// they are in rather than leaving "could not delete" over a half-done pair.
	///
	/// One tag at a time, not one push for all of them: a refspec git refuses
	/// takes the whole push with it, and a run that deleted none of four
	/// because the second had already gone is worse than one that says so about
	/// the second. That is `BranchDeletion`'s finding, and it is git's
	/// behaviour rather than that pane's.
	private func delete(_ names: [String], alsoOnRemote: Bool) {
		Task { @MainActor in
			var working = Set(names)
			self.onDeleting?(working)
			defer {
				self.onDeleting?([])
				self.onFinished?()
			}

			var deleted: [String] = []
			var locallyOnly: [String] = []
			var failures: [String] = []

			for name in names {
				let local = await GitTags.delete(name, in: self.root)
				guard local.exitCode == 0 else {
					failures.append("\(name): \(Self.said(local))")
					working.remove(name)
					self.onDeleting?(working)
					continue
				}
				if alsoOnRemote, let remote = self.remote {
					let sent = await GitTags.deleteOnRemote(name, in: self.root, remote: remote)
					if sent.exitCode == 0 {
						deleted.append(name)
					} else {
						// The half-done pair, named as one: this is the state
						// somebody would otherwise go to a terminal to find out.
						locallyOnly.append("\(name): \(Self.said(sent))")
					}
				} else {
					deleted.append(name)
				}
				working.remove(name)
				self.onDeleting?(working)
			}

			self.report(deleted: deleted, locallyOnly: locallyOnly, failures: failures,
			            alsoOnRemote: alsoOnRemote)
		}
	}

	private func report(
		deleted: [String], locallyOnly: [String], failures: [String], alsoOnRemote: Bool
	) {
		let remoteName = remote ?? "the remote"
		if !failures.isEmpty {
			Toast.post(
				failures.count == 1 ? "Could not delete a tag" : "Could not delete \(failures.count) tags",
				detail: failures.joined(separator: "\n")
			)
		}
		if !locallyOnly.isEmpty {
			Toast.post(
				locallyOnly.count == 1
					? "Deleted here, still on \(remoteName)"
					: "\(locallyOnly.count) deleted here, still on \(remoteName)",
				detail: locallyOnly.joined(separator: "\n")
			)
		}
		guard !deleted.isEmpty else { return }
		let where_ = alsoOnRemote ? " and from \(remoteName)" : ""
		Toast.post(
			deleted.count == 1
				? "Deleted \(deleted[0])\(where_)"
				: "Deleted \(deleted.count) tags\(where_)",
			detail: alsoOnRemote
				? "Pushing them again puts them back, if the commits are still somewhere."
				: "The remote's copy, if there is one, is untouched.",
			kind: .information
		)
	}

	// MARK: - For the harness

	/// The sheet's words, and then the press — without the sheet.
	///
	/// **A modal sheet is where a driven run stops.** `NSAlert` wants a person,
	/// and a harness that reached in and pressed its button would be testing
	/// `NSAlert`. What is worth checking is on either side of it: the sentences
	/// the sheet would put in front of somebody, and what agreeing to it does —
	/// so this says the first and performs the second, through the same
	/// `delete` the button calls.
	func askForTesting(about tags: [GitBranch], alsoOnRemote: Bool) {
		guard !tags.isEmpty else {
			print("TAGDELETE: nothing selected")
			fflush(stdout)
			return
		}
		Task { @MainActor in
			var described: [(name: String, at: String)] = []
			for tag in tags {
				described.append((tag.name, await GitTags.describe(tag.name, in: self.root) ?? "—"))
			}
			let named = described.map { "\($0.name)@\($0.at)" }.joined(separator: " | ")
			print("TAGDELETE: asking about \(named)"
				+ " remote=\(self.remote ?? "none") alsoOnRemote=\(alsoOnRemote)")
			fflush(stdout)
			self.delete(described.map(\.name), alsoOnRemote: alsoOnRemote)
		}
	}

	/// What git said about it, whichever stream it said it on.
	private static func said(_ result: GitRepository.ProcessResult) -> String {
		let text = result.stderr.isEmpty ? result.stdout : result.stderr
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// The list and the checkbox stacked, `NSAlert` taking one accessory view.
	private static func accessory(listing: NSView?, checkbox: NSView?) -> NSView? {
		let parts = [listing, checkbox].compactMap { $0 }
		guard !parts.isEmpty else { return nil }
		guard parts.count > 1 else { return parts[0] }

		let gap: CGFloat = 10
		let width = parts.map(\.frame.width).max() ?? 0
		let height = parts.map(\.frame.height).reduce(0, +) + gap
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
		// Top down: an `NSView` here is not flipped, and the list belongs above
		// the question about the remote.
		var y = height
		for part in parts {
			y -= part.frame.height
			part.frame = NSRect(
				x: 0, y: y, width: max(part.frame.width, width), height: part.frame.height
			)
			container.addSubview(part)
			y -= gap
		}
		return container
	}
}
