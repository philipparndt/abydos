import AppKit
import AbydosKit

/// crooked.
final class CenteredTextField: NSTextField {
	override class var cellClass: AnyClass? {
		get { CenteredTextFieldCell.self }
		set { super.cellClass = newValue }
	}
}

final class CenteredTextFieldCell: NSTextFieldCell {
	private func centered(_ rect: NSRect) -> NSRect {
		let height = ceil(font?.boundingRectForFont.height ?? rect.height)
		guard height < rect.height else { return rect }
		return NSRect(
			x: rect.minX + 3, y: rect.minY + (rect.height - height) / 2,
			width: rect.width - 6, height: height
		)
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: centered(rect))
	}

	override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
		super.edit(withFrame: centered(rect), in: view, editor: editor, delegate: delegate, event: event)
	}

	override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
		super.select(withFrame: centered(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
	}
}


/// A terminal can be dragged out of the panel into a window, and the panel is
/// where it goes back to.
extension BottomPanel: TerminalDragSource {
	func detachTerminal(at index: Int) -> DetachedTerminal? {
		guard sessions.indices.contains(index) else { return nil }
		let session = sessions[index]
		guard case let .terminal(pane) = session.kind else { return nil }

		sessions.remove(at: index)
		for (column, showing) in activeByColumn where showing === session {
			activeByColumn[column] = nil
		}
		pane.removeFromSuperview()

		rebuildColumns()
		if sessions.isEmpty { placeholder.isHidden = false }
		onTerminalsChanged?()

		return DetachedTerminal(
			pane: pane,
			title: session.displayTitle,
			isRenamed: session.isRenamed,
			directory: session.directory
		)
	}
}


/// A split view that shares its width the way it was last shared.
///
/// The position has to be set when there is a width to set it against. A panel
/// that has just been shown, or a column whose contents have just changed, has
/// not been laid out yet — and a position set against zero collapses a column
/// to nothing, which looks like a split that never happened.
final class ColumnSplitView: NSSplitView {
	var fraction: CGFloat = 0.5
	private var placed = false

	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }

	override func layout() {
		super.layout()
		guard !placed, bounds.width > 1, arrangedSubviews.count > 1 else { return }
		placed = true
		setPosition(bounds.width * fraction, ofDividerAt: 0)
	}
}


/// One side of the panel: a strip of tabs and the pane they show.
///
/// A panel splits the way the editor does — each side keeps its own tabs —
/// because one strip across two panes cannot say which side a tab belongs to,
/// and every question after that has to be answered by guessing.
@MainActor
final class PanelColumn: NSView {
	let strip = PanelTabStrip()
	/// tmux's own windows, along the bottom where tmux itself puts them.
	///
	/// A separate strip rather than more tabs in the one above, because they
	/// are a different kind of thing: the top strip is what this panel holds —
	/// a terminal, a debugger, a profiler — and the bottom one is what tmux
	/// holds inside the terminal. Two lists, in the two places each is
	/// expected.
	let mirrorStrip = PanelTabStrip()
	let content = NSView()
	/// Drawn over the pane rather than behind it: a terminal fills its column,
	/// and a highlight under it is a highlight nobody sees.
	let preview = PanelContentView()
	let column: Int

	private var stripHeight: NSLayoutConstraint!
	private var mirrorHeight: NSLayoutConstraint!

	/// Whether tmux's windows get their own strip along the bottom.
	var showsMirrorStrip = false {
		didSet {
			guard showsMirrorStrip != oldValue else { return }
			mirrorStrip.isHidden = !showsMirrorStrip
			mirrorHeight.constant = showsMirrorStrip ? Theme.current.scaled(26) : 0
		}
	}

	init(column: Int) {
		self.column = column
		super.init(frame: .zero)

		mirrorStrip.isMirroringTmux = true
		mirrorStrip.showsPanelControls = false
		mirrorStrip.isHidden = true
		for view in [strip, content, preview, mirrorStrip] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		// Nothing to hit: it is a drawing, and the drop is decided from the
		// pointer's own position.
		preview.isHidden = true
		stripHeight = strip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))
		mirrorHeight = mirrorStrip.heightAnchor.constraint(equalToConstant: 0)
		NSLayoutConstraint.activate([
			strip.topAnchor.constraint(equalTo: topAnchor),
			strip.leadingAnchor.constraint(equalTo: leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: trailingAnchor),
			stripHeight,

			content.topAnchor.constraint(equalTo: strip.bottomAnchor),
			content.leadingAnchor.constraint(equalTo: leadingAnchor),
			content.trailingAnchor.constraint(equalTo: trailingAnchor),
			content.bottomAnchor.constraint(equalTo: mirrorStrip.topAnchor),

			mirrorStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
			mirrorStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
			mirrorStrip.bottomAnchor.constraint(equalTo: bottomAnchor),
			mirrorHeight,

			preview.topAnchor.constraint(equalTo: content.topAnchor),
			preview.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			preview.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			preview.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	func applyThemeChange() {
		stripHeight.constant = Theme.current.scaled(30)
		mirrorHeight.constant = showsMirrorStrip ? Theme.current.scaled(26) : 0
		strip.applyThemeChange()
		mirrorStrip.applyThemeChange()
	}

	/// Shows where a dropped tab would land, over the pane.
	func showPreview(_ zone: TerminalTabDrag.Zone?) {
		preview.isHidden = (zone == nil)
		preview.previewZone(zone)
		if zone != nil {
			// Above whatever the pane put there since the last drag.
			preview.removeFromSuperview()
			addSubview(preview, positioned: .above, relativeTo: nil)
			NSLayoutConstraint.activate([
				preview.topAnchor.constraint(equalTo: content.topAnchor),
				preview.leadingAnchor.constraint(equalTo: content.leadingAnchor),
				preview.trailingAnchor.constraint(equalTo: content.trailingAnchor),
				preview.bottomAnchor.constraint(equalTo: content.bottomAnchor),
			])
		}
	}

	/// Puts a pane in, taking whatever was there out.
	func show(_ view: NSView?) {
		guard content.subviews.first !== view else { return }
		content.subviews.forEach { $0.removeFromSuperview() }
		guard let view else { return }

		view.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(view)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: content.topAnchor),
			view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
		])
	}
}
