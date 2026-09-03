import AppKit
import AbydosKit

/// The two documents a diff area can hold — the text diff and the picture
/// diff — and which is in the scroll view.
///
/// Three panes host a `DiffView` in a scroll view of their own and hand it
/// patch text. A changed picture wants the other view in the same place, and
/// the swap has to leave the panes' own arithmetic alone: they read
/// `diffView.enclosingScrollView` for their layout, which is nil the moment the
/// text view is not the document. So the scroll view is remembered here, once,
/// while the text view is still in it.
@MainActor
final class DiffDocuments {
	let scroll: NSScrollView
	let text: DiffView
	private(set) lazy var picture = PictureDiffView()

	init?(text: DiffView) {
		guard let scroll = text.enclosingScrollView else { return nil }
		self.scroll = scroll
		self.text = text
	}

	var showsPicture: Bool { scroll.documentView === picture }

	func showText() { show(text) }

	@discardableResult
	func showPicture() -> PictureDiffView {
		show(picture)
		return picture
	}

	/// The document view, pinned to the clip view's width and top the way the
	/// panes pin the text view, with the height from `intrinsicContentSize`.
	private func show(_ view: NSView) {
		guard scroll.documentView !== view else { return }
		view.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = view
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
			view.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
		])
	}

	/// Whichever is showing, for a driven run.
	var reportForTesting: String {
		showsPicture ? picture.reportForTesting : text.reportForTesting
	}
}

/// Reading the two sides of a changed picture from git, and comparing them,
/// off the main thread.
enum PictureDiffLoader {
	struct Loaded: Sendable {
		let old: PictureDiffView.Side?
		let new: PictureDiffView.Side?
		let outcome: PictureDiff.Outcome?
	}

	/// Whether a change is one the picture diff should take.
	static func isPicture(_ path: String, in root: URL) -> Bool {
		FilePreview.kind(for: root.appendingPathComponent(path)) == .image
	}

	/// A working-copy change. The old side of an unstaged change is the index,
	/// which is `HEAD` unless part of the file is staged, and is labelled by
	/// which it is; of a staged change, `HEAD`. The new side of an unstaged
	/// change is the working file; of a staged change, the index — the bytes
	/// that will be committed, which the working file may no longer be.
	static func load(_ change: GitChange, path: String, in root: URL) async -> Loaded {
		let added = change.kind == .added || change.kind == .untracked
		let deleted = change.kind == .deleted
		let head = added ? nil : await GitBlob.read("HEAD", path: path, in: root)
		let index = added && !change.isStaged ? nil : await GitBlob.read("", path: path, in: root)

		let oldData: Data?, oldLabel: String
		let newData: Data?, newLabel: String
		if change.isStaged {
			oldData = head; oldLabel = "HEAD"
			newData = deleted ? nil : index; newLabel = "staged"
		} else {
			oldData = index; oldLabel = (index != nil && index == head) ? "HEAD" : "index"
			newData = deleted ? nil : GitBlob.readWorkingFile(path, in: root); newLabel = "working copy"
		}
		return await sides(
			old: oldData, oldLabel: oldLabel, oldMissing: added ? "no picture" : "could not be read",
			new: newData, newLabel: newLabel, newMissing: deleted ? "no picture" : "could not be read"
		)
	}

	/// A commit's change: the parent against the commit, the rename followed.
	static func load(_ file: GitCommitFile, at hash: String, in root: URL) async -> Loaded {
		let short = String(hash.prefix(7))
		let oldData = file.kind == .added
			? nil
			: await GitBlob.read("\(hash)~", path: file.originalPath ?? file.path, in: root)
		let newData = file.kind == .deleted ? nil : await GitBlob.read(hash, path: file.path, in: root)
		return await sides(
			old: oldData, oldLabel: "\(short)~", oldMissing: file.kind == .added ? "no picture" : "could not be read",
			new: newData, newLabel: short, newMissing: file.kind == .deleted ? "no picture" : "could not be read"
		)
	}

	/// A pull request's change: the merge base against the head, when both are
	/// local. A side that is not says so rather than pretending.
	static func load(_ file: GitCommitFile, base: String?, head: String?, in root: URL) async -> Loaded {
		let oldData: Data? = file.kind == .added ? nil
			: await base.asyncFlatMap { await GitBlob.read($0, path: file.originalPath ?? file.path, in: root) }
		let newData: Data? = file.kind == .deleted ? nil
			: await head.asyncFlatMap { await GitBlob.read($0, path: file.path, in: root) }
		return await sides(
			old: oldData, oldLabel: "base", oldMissing: file.kind == .added ? "no picture" : "base not fetched",
			new: newData, newLabel: "head", newMissing: file.kind == .deleted ? "no picture" : "head not fetched"
		)
	}

	/// Decodes both and compares them off the main thread: a bitmap of a 4k
	/// screenshot is tens of megabytes and the comparison walks all of it.
	private static func sides(
		old: Data?, oldLabel: String, oldMissing: String,
		new: Data?, newLabel: String, newMissing: String
	) async -> Loaded {
		await Task.detached(priority: .userInitiated) {
			let oldSide = PictureDiffView.Side.read(old, label: oldLabel, missing: oldMissing)
			let newSide = PictureDiffView.Side.read(new, label: newLabel, missing: newMissing)
			var outcome: PictureDiff.Outcome?
			if let a = oldSide.bitmap, let b = newSide.bitmap {
				outcome = PictureDiff.compare(a, b)
			}
			return Loaded(old: oldSide, new: newSide, outcome: outcome)
		}.value
	}
}

private extension Optional {
	func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
		guard let wrapped = self else { return nil }
		return await transform(wrapped)
	}
}
