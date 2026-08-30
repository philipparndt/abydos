import AppKit
import AbydosKit

/// One file a stopped operation is waiting on, drawn as a row of the strip.
///
/// **A row, not a line of text, because there is something to do to it.** The
/// strip used to say `3 files conflicted` and offer a `Files` button that
/// opened all of them at once; which file, and what to do about any one of
/// them, were questions it had no way of asking. A row is clicked to open the
/// file and right-clicked for the two verbs that clear it without opening
/// anything.
///
/// It keeps its place when it is resolved rather than disappearing. A list that
/// empties from the middle is one somebody has to re-find their place in after
/// every file, and the count under the headline — `2 of 3 resolved` — needs the
/// rows it is counting to still be there.
final class ConflictFileRow: NSView {
	let waiting: GitConflicts.Waiting

	var onOpen: (() -> Void)?
	/// Built on demand rather than held: the branch names in it come from a
	/// read that can land after the row is built.
	var buildMenu: (() -> NSMenu?)?

	private let mark = NSTextField(labelWithString: "")
	private let name = NSTextField(labelWithString: "")
	private let note = NSTextField(labelWithString: "")
	private var hovering = false
	private var tracking: NSTrackingArea?

	init(waiting: GitConflicts.Waiting) {
		self.waiting = waiting
		super.init(frame: .zero)
		wantsLayer = true

		let theme = Theme.current
		mark.stringValue = waiting.isResolved ? "✓" : "◆"
		mark.font = theme.uiFont(waiting.isResolved ? 10 : 8.5, weight: .bold)
		mark.textColor = waiting.isResolved ? theme.gitAdded : theme.gitConflict
		mark.alignment = .center

		// **The folder greyed and the file plain.** The names in one repository
		// are long and share their first thirty characters — three rows reading
		// `Sources/AbydosApp/…` truncated at the same point are three rows
		// nobody can tell apart. Trimming from the head keeps the end, which is
		// the half that differs.
		let attributed = NSMutableAttributedString()
		let struck = waiting.isResolved ? NSUnderlineStyle.single.rawValue : 0
		if !waiting.directory.isEmpty {
			attributed.append(NSAttributedString(
				string: waiting.directory + "/",
				attributes: [
					.foregroundColor: theme.sidebarText.withAlphaComponent(
						waiting.isResolved ? 0.35 : 0.5
					),
					.font: theme.uiFont(10.5),
					// The whole path, not the last component of it. Striking
					// only the name reads as a folder that is still waiting on
					// a file that is not.
					.strikethroughStyle: struck,
				]
			))
		}
		attributed.append(NSAttributedString(
			string: waiting.name,
			attributes: [
				.foregroundColor: waiting.isResolved
					? theme.sidebarText.withAlphaComponent(0.55)
					: theme.sidebarText,
				.font: theme.uiFont(10.5),
				.strikethroughStyle: struck,
			]
		))
		name.attributedStringValue = attributed
		name.lineBreakMode = .byTruncatingHead
		name.cell?.usesSingleLineMode = true
		name.toolTip = waiting.path

		// **Nothing when there is nothing to say.** A count of markers is only
		// interesting once it is zero and the file is still unresolved — that
		// is somebody who has edited it by hand and not told git, and it is
		// the one state with no other signal on screen.
		if waiting.isResolved {
			note.stringValue = ""
		} else if waiting.markers == 0 {
			note.stringValue = "edited"
			note.textColor = theme.gitModified
			note.toolTip = "No markers left in it. Mark Resolved to stage it as it stands."
		} else {
			note.stringValue = "\(waiting.markers)"
			note.textColor = theme.sidebarText.withAlphaComponent(0.45)
			note.toolTip = "\(waiting.markers) conflict"
				+ (waiting.markers == 1 ? "" : "s") + " still marked in the file"
		}
		note.font = theme.uiFont(9.5, weight: .medium)

		let stack = NSStackView(views: [mark, name, note])
		stack.orientation = .horizontal
		stack.spacing = theme.scaled(6)
		stack.alignment = .centerY
		stack.setHuggingPriority(.defaultLow, for: .horizontal)
		name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		name.setContentHuggingPriority(.defaultLow, for: .horizontal)
		note.setContentCompressionResistancePriority(.required, for: .horizontal)
		mark.setContentCompressionResistancePriority(.required, for: .horizontal)

		addSubview(stack)
		stack.translatesAutoresizingMaskIntoConstraints = false
		let pad = theme.scaled(3)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.scaled(2)),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -theme.scaled(2)),
			stack.topAnchor.constraint(equalTo: topAnchor, constant: pad),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
			mark.widthAnchor.constraint(equalToConstant: theme.scaled(11)),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Pointer

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let tracking { removeTrackingArea(tracking) }
		let made = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		)
		addTrackingArea(made)
		tracking = made
	}

	override func mouseEntered(with event: NSEvent) { hovering = true; paint() }
	override func mouseExited(with event: NSEvent) { hovering = false; paint() }

	private func paint() {
		layer?.cornerRadius = Theme.current.scaled(4)
		layer?.backgroundColor = hovering
			? Theme.current.sidebarText.withAlphaComponent(0.09).cgColor
			: NSColor.clear.cgColor
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .pointingHand)
	}

	/// A click opens the file. Which is what somebody came to the row for:
	/// resolving a conflict is reading the two halves and writing a third, and
	/// nothing in a sidebar can do that part.
	override func mouseDown(with event: NSEvent) {
		guard event.clickCount >= 1 else { return }
		onOpen?()
	}

	override func menu(for event: NSEvent) -> NSMenu? { buildMenu?() }
}
