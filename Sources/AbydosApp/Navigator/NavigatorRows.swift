import AppKit
import AbydosKit

// MARK: - Rows

/// What the tree's undo manager holds instead of the navigator.
///
/// A registered undo keeps its target alive, and the target has to outlive the
/// registration for the handler to have anything to run on — so it cannot be
/// weak. Making it this rather than the controller keeps the strong reference
/// off the view controller, and the one weak hop is all the handler needs.
final class FileUndoTarget {
	weak var navigator: ProjectNavigatorViewController?
}

/// A text field cell whose text sits in the middle of its box.
///
/// `NSTextFieldCell` draws its text at the top of whatever height it is given
/// and offers no way to say otherwise, which is why every list that edits a
/// name in place ends up with one of these. The three overrides are the three
/// rects it uses: one to draw through, and two for the field editor, which is a
/// separate view laid into the cell and would otherwise stay at the top while
/// the drawn text moved.
final class CentredFieldCell: NSTextFieldCell {
	private func centred(_ rect: NSRect) -> NSRect {
		let height = cellSize(forBounds: rect).height
		guard rect.height > height else { return rect }
		var centred = rect
		centred.origin.y += ((rect.height - height) / 2).rounded()
		centred.size.height = height
		return centred
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: centred(rect))
	}

	override func edit(
		withFrame rect: NSRect, in controlView: NSView,
		editor: NSText, delegate: Any?, event: NSEvent?
	) {
		super.edit(
			withFrame: centred(rect), in: controlView,
			editor: editor, delegate: delegate, event: event
		)
	}

	override func select(
		withFrame rect: NSRect, in controlView: NSView,
		editor: NSText, delegate: Any?, start: Int, length: Int
	) {
		super.select(
			withFrame: centred(rect), in: controlView,
			editor: editor, delegate: delegate, start: start, length: length
		)
	}
}

final class NavigatorCellView: NSTableCellView {
	var node: FileNode?
	/// What to draw, which is the node's own name until a chain of directories
	/// is folded into this row and it becomes all of their names.
	private var title = ""
	private var isRoot = false
	private var subtitle: String?
	private var isExpanded = false
	/// Set instead of `node` for one of the Dependencies section's own rows.
	/// A package is not a file and has no `FileNode` behind it — the files
	/// start one level below it.
	private var dependency: DependencyNode?
	/// And for one of the Claude Sessions root's own rows, for the same reason:
	/// a session is not a file, and its files start one level below it.
	private var session: SessionNode?

	func configure(dependency: DependencyNode) {
		self.dependency = dependency
		self.subtitle = dependency.subtitle
		needsDisplay = true
	}

	func configure(session: SessionNode) {
		self.session = session
		self.subtitle = session.subtitle
		needsDisplay = true
	}

	func configure(
		node: FileNode,
		title: String,
		isRoot: Bool,
		subtitle: String?,
		isExpanded: Bool,
		isSubproject: Bool = false,
		isRenaming: Bool = false
	) {
		self.node = node
		self.title = title
		self.isRoot = isRoot
		self.subtitle = subtitle
		self.isExpanded = isExpanded
		self.isSubproject = isSubproject
		self.isRenaming = isRenaming
		needsDisplay = true
	}

	/// Whether the field is standing on this row.
	///
	/// The name is then not drawn at all. Drawing it under the field and
	/// covering it up looks the same only while the field is as wide as the
	/// name it replaced — and it is not, since it stops at the edge of the
	/// pane, so the tail of the old name showed past the field's right border
	/// with the new one already typed in front of it.
	var isRenaming = false {
		didSet { if isRenaming != oldValue { needsDisplay = true } }
	}

	/// The folder the run button, git and the language server are pointed at.
	private var isSubproject = false

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// On a selected row the VCS colour would fight the pill behind it, so the
		// label goes to whichever plain ink the palette reads with — the
		// treatment IDEA uses. Near-white was written for the dark theme's blue
		// and disappeared entirely on the light theme's pale one, which the
		// presentation mode ships by default.
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let selectedInk: NSColor = Theme.current.isLight
			? Theme.current.sidebarHeaderText
			: .hex(0xE8EAED)

		/// The selected ink, still saying whether git cares about the file.
		///
		/// **Selecting a row used to take its status away.** Every row went to
		/// `selectedInk`, so an ignored file — the one state a reader is most
		/// likely to be checking, because it decides whether the file is part of
		/// the project at all — looked exactly like a tracked one for as long as
		/// it was selected. Clicking a row to find out about it removed the
		/// answer.
		///
		/// Dimmed rather than recoloured. The selection has to stay legible
		/// against its blue, so `gitIgnored`'s own grey is not what to use here;
		/// what carries over is the *quietness*, which is what the colour was
		/// saying. The other states keep the plain ink: modified and added are
		/// already marked in the trailing column, and this row is not where
		/// those are read.
		func ink(saying status: GitFileStatus) -> NSColor {
			switch status {
			case .ignored, .deleted: return selectedInk.withAlphaComponent(0.55)
			default:                 return selectedInk
			}
		}

		let icon: NSImage?
		let text: String
		let nameColor: NSColor
		let nameFont: NSFont

		if let session {
			text = session.title
			switch session.row {
			case .section:
				icon = FileIcon.sessionSection()
				// The other roots are written this way: this is a root of the
				// tree, not a folder inside anything.
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13, weight: .bold)
			case let .session(_, asked):
				icon = FileIcon.session()
				// A session the transcript said nothing about is named by its
				// id, which is not a name — so it is drawn in the grey a note
				// uses rather than as a title somebody wrote.
				nameColor = isSelected
					? selectedInk
					: (asked == nil ? Theme.current.gitIgnored : Theme.current.sidebarHeaderText)
				nameFont = Theme.current.uiFont(13)
			}
		} else if let dependency {
			text = dependency.title
			switch dependency.row {
			case .section:
				icon = FileIcon.dependencySection()
				// Written the way the project root above it is: this is the other
				// root of the tree, not a folder inside anything.
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13, weight: .bold)
			case .group:
				icon = FileIcon.subprojectFolder()
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13, weight: .bold)
			case let .package(package):
				icon = FileIcon.dependencyPackage(fetched: package.localPath != nil)
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13)
			case .toolchain:
				icon = FileIcon.dependencyToolchain()
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13)
			case .note:
				icon = FileIcon.dependencyNote()
				// The grey the subtitle uses, because a note *is* a subtitle
				// wearing the name's place: nothing is wrong with the project.
				nameColor = isSelected ? selectedInk : Theme.current.gitIgnored
				nameFont = Theme.current.uiFont(13)
			}
		} else {
			guard let node else { return }
			text = title
			// The folder being worked on is tinted rather than decorated: a mark
			// beside the name reads as a status — modified, added — and this is
			// not a status. It is which folder everything is pointed at.
			icon = isSubproject
				? FileIcon.subprojectFolder()
				: FileIcon.image(for: node, isExpanded: isExpanded)
			// The subproject is written the way the project above it is — bold
			// and bright — because that is what it is here: the project
			// everything is pointed at. The blue folder says which of the two.
			nameColor = isSelected
				? (isRoot || isSubproject
					? selectedInk
					: ink(saying: node.gitStatus))
				: (isRoot || isSubproject
					? Theme.current.sidebarHeaderText
					: Theme.current.color(for: node.gitStatus))
			nameFont = isRoot || isSubproject
				? Theme.current.uiFont(13, weight: .bold)
				: Theme.current.uiFont(13)
		}

		var x = Theme.current.scaled(2)
		let iconSize = Theme.current.scaled(16)
		if let icon {
			icon.drawFitted(
				in: NSRect(x: x, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)
			)
		}
		x += iconSize + Theme.current.scaled(6)

		// The icon stays while the name is being edited — it says what kind of
		// thing this is, and the field does not cover it — but the name itself
		// belongs to the field now.
		if isRenaming { return }

		// Truncated rather than run past the edge: a long name would otherwise
		// draw straight over the row's rounded selection and out of the pane.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let name = NSAttributedString(string: text, attributes: [
			.font: nameFont,
			.foregroundColor: nameColor,
			.paragraphStyle: paragraph,
		])
		let nameSize = name.size()
		let trailing = Theme.current.scaled(8)
		// The change mark's room, taken before anything is measured against it.
		// Colouring the name was the only signal, and a shade of text is only
		// legible against the shades beside it.
		let mark = markColour(for: node)
		let markRoom = mark == nil ? 0 : Theme.current.scaled(12)
		// Against the same edge the mark is drawn at, or a narrow pane runs the
		// name under the dot.
		let available = max(0, markEdge - x - trailing - markRoom)
		let nameWidth = min(ceil(nameSize.width), available)
		name.draw(in: NSRect(
			x: x,
			y: bounds.midY - nameSize.height / 2,
			width: nameWidth,
			height: nameSize.height
		))
		x += nameWidth + trailing

		if let subtitle {
			let attributed = NSAttributedString(string: subtitle, attributes: [
				.font: Theme.current.uiFont(11),
				.foregroundColor: Theme.current.gitIgnored,
				.paragraphStyle: paragraph,
			])
			let size = attributed.size()
			attributed.draw(in: NSRect(
				x: x,
				y: bounds.midY - size.height / 2,
				width: max(0, markEdge - x - trailing - markRoom),
				height: size.height
			))
		}

		if let mark {
			let side = Theme.current.scaled(6)
			mark.setFill()
			NSBezierPath(ovalIn: NSRect(
				x: markEdge - trailing - side,
				y: (bounds.midY - side / 2).rounded(),
				width: side, height: side
			)).fill()
		}
	}

	/// The right-hand edge the mark is drawn against — **not `bounds.maxX`**,
	/// which is off screen. The column is sized to its widest row and the root
	/// carries the project's whole path, so a cell is routinely wider than the
	/// pane. Found by capturing the sidebar and finding no dots in it.
	private var markEdge: CGFloat {
		guard let clip = enclosingScrollView?.contentView else { return bounds.maxX }
		let visible = convert(clip.bounds, from: clip)
		return min(bounds.maxX, visible.maxX)
	}

	/// The colour a row's change mark is drawn in, or nothing to say.
	///
	/// **`ignored` says nothing on purpose**: in a project with a build
	/// directory those rows outnumber everything else, and a mark on nearly
	/// every row is furniture. `unmodified` is that argument from the other end.
	private func markColour(for node: FileNode?) -> NSColor? {
		guard let node, !isRoot, !isSubproject else { return nil }
		switch node.gitStatus {
		case .unmodified, .ignored: return nil
		default: return Theme.current.color(for: node.gitStatus)
		}
	}

}
