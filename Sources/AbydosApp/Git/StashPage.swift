import AppKit
import AbydosKit

/// One stash, as a page: what is in it, and what to do with it.
///
/// **A stash is a commit nobody can read.** The refs tree opens one to a list of
/// file names and stops there — no diff, no counts, nothing that says whether
/// the thing is worth keeping. So the way to find out what a week-old stash held
/// was to apply it over a clean working copy and look, which is the one move
/// somebody with work in progress cannot make. Reported as: *it shall be
/// possible to look into a stash, like we are able to review changes before a
/// commit*.
///
/// It is the commit page's shape, read-only: the files on the left, the diff of
/// the selected one beside them, and the verbs along the bottom. Read-only
/// because a stash has already happened — there is nothing here to stage, and
/// offering to would be the same lie the log page's diff used to tell.
///
/// `ChangedFileList` is the list, which is its third page and the reason it is
/// its own class: a commit's files, a pull request's files and a stash's files
/// are all `[GitCommitFile]` drawn the same way, and a third implementation
/// would be a third opinion about what a rename looks like.
final class StashPage: NSView {
	/// The stash's own verbs, done by whoever knows how — the pane, which
	/// already asks the questions each of them needs asking.
	var onApply: ((GitStash.Entry) -> Void)?
	var onBranch: ((GitStash.Entry) -> Void)?
	var onDrop: ((GitStash.Entry) -> Void)?

	private let root: URL
	private(set) var entry: GitStash.Entry

	private let title = NSTextField(labelWithString: "")
	private let subtitle = NSTextField(labelWithString: "")
	private var fileList: ChangedFileList!
	private var diffView: DiffView!
	private var split: NSSplitView!

	private let applyButton = NSButton(title: "Apply…", target: nil, action: nil)
	private let branchButton = NSButton(title: "Branch from It…", target: nil, action: nil)
	private let dropButton = NSButton(title: "Drop…", target: nil, action: nil)

	private var files: [GitCommitFile] = []
	/// The path whose diff is on screen, so a refresh can put it back.
	private var showing: String?
	/// Whether the stash this page is about has been dropped.
	private var isGone = false

	/// Which stash this page is on, for a session to write down.
	///
	/// The commit, because that is the stash: `stash@{0}` names a different one
	/// after a single `git stash push`, and a page reopened by index would come
	/// back on somebody else's work.
	func stashToRemember() -> [String: String] { ["commit": entry.commit] }

	init(root: URL, entry: GitStash.Entry) {
		self.root = root
		self.entry = entry
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		refresh()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Points the page at another stash, so pressing `Review` on a second one
	/// does not leave two pages behind — the same rule `openPage` keeps by
	/// identifier.
	func show(_ other: GitStash.Entry) {
		guard other != entry else { return }
		entry = other
		showing = nil
		refresh()
	}

	private func build() {
		title.font = Theme.current.uiFont(15, weight: .semibold)
		title.textColor = Theme.current.sidebarHeaderText
		title.lineBreakMode = .byTruncatingTail
		subtitle.font = Theme.current.uiFont(11)
		subtitle.textColor = Theme.current.sidebarText
		subtitle.lineBreakMode = .byTruncatingTail

		fileList = ChangedFileList(
			rowHeight: Theme.current.scaled(22), arrangedByFolder: true
		)
		fileList.onSelect = { [weak self] file in self?.showDiff(of: file) }

		diffView = DiffView()
		// **A stash has already happened.** Nothing here is stageable and
		// nothing here is discardable — the file on disk is not what this diff
		// is about — so the menu that offers those verbs is not offered. Same
		// reason the log page's diff is read-only.
		diffView.isReadOnly = true

		let diffScroll = NSScrollView()
		diffScroll.documentView = diffView
		diffScroll.hasVerticalScroller = true
		diffScroll.drawsBackground = true
		diffScroll.backgroundColor = Theme.current.editorBackground
		diffView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			diffView.leadingAnchor.constraint(equalTo: diffScroll.contentView.leadingAnchor),
			diffView.trailingAnchor.constraint(equalTo: diffScroll.contentView.trailingAnchor),
			diffView.topAnchor.constraint(equalTo: diffScroll.contentView.topAnchor),
		])

		split = NSSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(fileList)
		split.addArrangedSubview(diffScroll)

		for made in [applyButton, branchButton, dropButton] {
			made.bezelStyle = .rounded
			made.controlSize = .regular
			made.target = self
		}
		applyButton.action = #selector(apply)
		branchButton.action = #selector(branch)
		dropButton.action = #selector(drop)
		dropButton.hasDestructiveAction = true
		// **The verbs are on the page, not back in the tree.** Reviewing a
		// stash and then having to find its row again to act on what you read
		// is the same fault as a commit page that opens a tab: it answers a
		// gesture made to stay in one place by sending somebody somewhere else.
		let verbs = NSStackView(views: [NSView(), branchButton, dropButton, applyButton])
		verbs.orientation = .horizontal
		verbs.spacing = Theme.current.scaled(8)
		verbs.alignment = .centerY

		let heading = NSStackView(views: [title, subtitle])
		heading.orientation = .vertical
		heading.alignment = .leading
		heading.spacing = Theme.current.scaled(2)

		for view in [heading, split, verbs] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}
		let inset = Theme.current.scaled(14)
		NSLayoutConstraint.activate([
			heading.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			split.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: inset * 0.7),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),

			verbs.topAnchor.constraint(equalTo: split.bottomAnchor, constant: inset * 0.6),
			verbs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			verbs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			verbs.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset * 0.7),
		])

		// A third of the width to the list, which is what the log page gives it
		// and what a list of paths wants: long enough for the tail of a name,
		// short enough that the diff is the thing being read.
		DispatchQueue.main.async { [weak self] in
			guard let self, self.bounds.width > 0 else { return }
			self.split.setPosition(self.bounds.width / 3, ofDividerAt: 0)
		}
	}

	// MARK: - Reading it

	/// Re-reads the stash and puts the diff back where it was.
	///
	/// Cheap enough to do on demand and not on a timer: a stash is a commit and
	/// commits do not change. What changes is whether it is still there — a
	/// stash dropped from this page, or from the tree beside it, leaves a page
	/// describing something that no longer exists, and `stash@{1}` now means
	/// somebody else's stash rather than nothing at all.
	func refresh() {
		let entry = self.entry
		title.stringValue = entry.message
		subtitle.stringValue = [
			entry.reference,
			entry.branch.isEmpty ? nil : "on \(entry.branch)",
			entry.age,
		].compactMap { $0 }.joined(separator: " · ")

		Task { @MainActor [weak self] in
			guard let self else { return }
			// **Asked by reference and by commit.** A drop renumbers everything
			// under it, so `stash@{1}` after one has gone is a different stash
			// — and the commit is what says whether *this* one is still there.
			let still = await GitStash.list(in: self.root)
			guard self.entry == entry else { return }
			guard still.contains(where: { $0.commit == entry.commit }) else {
				self.subtitle.stringValue = "Dropped — it is not in the stash list any more"
				self.subtitle.textColor = Theme.current.gitConflict
				for made in [self.applyButton, self.branchButton, self.dropButton] {
					made.isEnabled = false
				}
				self.isGone = true
				return
			}
			self.subtitle.textColor = Theme.current.sidebarText
			for made in [self.applyButton, self.branchButton, self.dropButton] {
				made.isEnabled = true
			}
			self.isGone = false

			let held = await GitStash.files(entry, in: self.root)
			guard self.entry == entry else { return }
			self.files = held
			self.fileList.setFiles(held)
			// **Counts asked once, for the list to draw.** Same as a commit's
			// files: `--numstat` over the stash against the commit it was made
			// on, in one process rather than one per row. An untracked file has
			// no line count there — it is in the third parent — so its row says
			// what it says for any file git could not measure.
			let counts = await GitLineCounts.commit(entry.commit, in: self.root)
			guard self.entry == entry else { return }
			self.fileList.setLineCounts(counts)

			guard let first = held.first else {
				self.diffView.setDiff("", staged: false, url: nil)
				return
			}
			let wanted = self.showing.flatMap { path in held.first { $0.path == path } } ?? first
			self.fileList.select(path: wanted.path)
			self.showDiff(of: wanted)
		}
	}

	private func showDiff(of file: GitCommitFile) {
		showing = file.path
		let entry = self.entry
		Task { @MainActor [weak self] in
			guard let self else { return }
			let text = await GitStash.diff(entry, path: file.path, in: self.root)
			guard self.entry == entry, self.showing == file.path else { return }
			let prepared = await DiffView.prepareOffMain(
				text, url: self.root.appendingPathComponent(file.path)
			)
			guard self.entry == entry, self.showing == file.path else { return }
			self.diffView.setDiff(prepared, staged: false)
		}
	}

	// MARK: - Its verbs

	@objc private func apply() { onApply?(entry) }
	@objc private func branch() { onBranch?(entry) }
	@objc private func drop() { onDrop?(entry) }

	// MARK: - Driven runs

	/// What the page is showing: the stash, its files, and the diff on screen.
	func reportForTesting() -> String {
		let listed = files.map(\.path).joined(separator: ", ")
		return "STASH-PAGE “\(title.stringValue)” [\(subtitle.stringValue)]"
			+ (isGone ? " gone" : "")
			+ " files=\(files.isEmpty ? "none" : listed)"
			+ " showing=\(showing ?? "none")"
			+ " diff=\(diffView.reportForTesting)"
			+ " verbs=\(diffView.verbsForTesting())"
	}

	/// Chooses a file the way a click on its row does.
	func selectForTesting(_ path: String) -> String {
		guard let file = files.first(where: { $0.path == path || $0.name == path }) else {
			return "no file called \(path)"
		}
		fileList.select(path: file.path)
		showDiff(of: file)
		return "showing \(file.path)"
	}

	/// Presses one of the verbs along the bottom.
	func pressForTesting(_ name: String) -> String {
		switch name {
		case "apply":  apply();  return "apply \(entry.reference)"
		case "branch": branch(); return "branch \(entry.reference)"
		case "drop":   drop();   return "drop \(entry.reference)"
		default:       return "no button called \(name)"
		}
	}
}
