import AppKit
import AbydosKit

/// The cells the switcher's one table draws: an action, a heading, a branch, a
/// run, a file and a project. Six kinds of row in one list, which is what makes
/// it a palette rather than a menu.
// MARK: - Cells

final class SwitcherActionCell: NSView {
	let title: String
	let symbol: String
	/// The key this already answers to, so the palette teaches it rather than
	/// being the only way to reach it.
	let shortcut: String?
	/// Where it lives — the menu it was found under — for telling two commands
	/// of the same name apart.
	let detail: String?

	init(title: String, symbol: String, shortcut: String? = nil, detail: String? = nil) {
		self.title = title
		self.symbol = symbol
		self.shortcut = shortcut
		self.detail = detail
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let tint = Theme.current.sidebarText
		var x: CGFloat = 12

		// Colour baked into the symbol configuration — see Theme.symbol.
		if let rendered = Theme.symbol(symbol, size: 12 * Theme.current.scale, color: tint) {
			// respectFlipped: this view is flipped; without it the glyph mirrors.
			rendered.drawFitted(in: NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14))
		}
		x += 22

		// The shortcut first, from the right, so the name can be shortened
		// against it rather than drawn underneath it.
		var rightEdge = bounds.maxX - 12
		if let shortcut, !shortcut.isEmpty {
			let keys = NSAttributedString(string: shortcut, attributes: [
				.font: Theme.current.uiFont(12),
				.foregroundColor: tint.withAlphaComponent(0.75),
			])
			let size = keys.size()
			keys.draw(at: NSPoint(x: rightEdge - size.width, y: bounds.midY - size.height / 2))
			rightEdge -= size.width + 14
		}

		let attributed = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(13),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		attributed.draw(at: NSPoint(x: x, y: bounds.midY - attributed.size().height / 2))
		x += attributed.size().width + 8

		guard let detail, !detail.isEmpty, x < rightEdge - 20 else { return }
		let where_ = NSAttributedString(string: detail, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: tint.withAlphaComponent(0.55),
		])
		where_.draw(with: NSRect(x: x, y: bounds.midY - where_.size().height / 2,
		                        width: rightEdge - x, height: where_.size().height),
		            options: [.usesLineFragmentOrigin])
	}
}

final class SwitcherHeaderCell: NSView {
	let title: String

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// A hairline above the group, except at the very top of the list.
		if bounds.minY > 0 {
			Theme.current.separator.setFill()
			NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
		}

		let attributed = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(11, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		attributed.draw(at: NSPoint(x: 12, y: bounds.height - attributed.size().height - 4))
	}
}

/// One branch, laid out like a project so the two lists read as one.
final class SwitcherBranchCell: NSView {
	let name: String
	let isCurrent: Bool
	let filter: String

	init(name: String, isCurrent: Bool, filter: String) {
		self.name = name
		self.isCurrent = isCurrent
		self.filter = filter
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let tint = Theme.current.sidebarText
		let iconSize = Theme.current.scaled(13)
		if let icon = Theme.symbol("arrow.trianglehead.branch", size: 11 * Theme.current.scale, color: tint)
			?? Theme.symbol("arrow.triangle.branch", size: 11 * Theme.current.scale, color: tint) {
			icon.drawFitted(in: NSRect(
				x: Theme.current.scaled(12),
				y: bounds.midY - iconSize / 2,
				width: iconSize,
				height: iconSize
			))
		}

		let text = NSMutableAttributedString(string: name, attributes: [
			.font: Theme.current.uiFont(13, weight: isCurrent ? .semibold : .regular),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		if !filter.isEmpty,
		   let range = name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			text.addAttribute(
				.foregroundColor,
				value: Theme.current.gitModified,
				range: NSRange(range, in: name)
			)
		}
		let size = text.size()
		text.draw(at: NSPoint(x: Theme.current.scaled(33), y: bounds.midY - size.height / 2))

		guard isCurrent else { return }
		let marker = NSAttributedString(string: "current", attributes: [
			.font: Theme.current.monoFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		])
		let markerSize = marker.size()
		marker.draw(at: NSPoint(
			x: bounds.maxX - Theme.current.scaled(12) - ceil(markerSize.width),
			y: bounds.midY - markerSize.height / 2
		))
	}
}

/// One thing that can be run: what it is called, and where it runs.
///
/// The same three-column shape as the file rows — glyph, name, right-aligned
/// detail in the fixed face — because a run row answers the same question a
/// file row does. Two configurations called `run Main` come from two modules
/// and were told apart by nothing at all when the module lived inside the name
/// of every row in the section.
final class SwitcherRunCell: NSView {
	let title: String
	let place: String?
	let chip: String?
	let symbol: String
	let filter: String

	init(title: String, place: String?, chip: String?, symbol: String, filter: String) {
		self.title = title
		self.place = place
		self.chip = chip
		self.symbol = symbol
		self.filter = filter
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let tint = Theme.current.sidebarText
		let iconSize = Theme.current.scaled(13)
		if let icon = Theme.symbol(symbol, size: 11 * Theme.current.scale, color: tint) {
			icon.drawFitted(in: NSRect(
				x: Theme.current.scaled(12),
				y: bounds.midY - iconSize / 2,
				width: iconSize,
				height: iconSize
			))
		}

		let name = NSMutableAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(13, weight: chip == "current" ? .semibold : .regular),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		if !filter.isEmpty,
		   let range = title.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			name.addAttribute(
				.foregroundColor, value: Theme.current.gitModified, range: NSRange(range, in: title)
			)
		}
		let nameX = Theme.current.scaled(33)
		let nameSize = name.size()
		name.draw(at: NSPoint(x: nameX, y: bounds.midY - nameSize.height / 2))

		var right = bounds.maxX - Theme.current.scaled(12)
		if let chip {
			let mark = NSAttributedString(string: chip, attributes: [
				.font: Theme.current.monoFont(11),
				.foregroundColor: Theme.current.gitIgnored,
			])
			let markSize = mark.size()
			mark.draw(at: NSPoint(x: right - ceil(markSize.width), y: bounds.midY - markSize.height / 2))
			right -= ceil(markSize.width) + Theme.current.scaled(10)
		}

		guard let place else { return }
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .right
		paragraph.lineBreakMode = .byTruncatingHead
		let trail = NSMutableAttributedString(string: place, attributes: [
			.font: Theme.current.monoFont(11),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		if !filter.isEmpty,
		   let range = place.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			trail.addAttribute(
				.foregroundColor, value: Theme.current.gitModified, range: NSRange(range, in: place)
			)
		}
		let left = nameX + ceil(nameSize.width) + Theme.current.scaled(12)
		let available = right - left
		guard available > Theme.current.scaled(30) else { return }
		trail.draw(in: NSRect(
			x: left, y: bounds.midY - trail.size().height / 2,
			width: available, height: trail.size().height
		))
	}
}

/// One file, on one line: its name, and the directory it is in beside it.
///
/// The directory is not decoration. A project holds four files called
/// `spec.md`, and the name alone tells them apart not at all — which is the
/// difference between a list that can be chosen from and one that has to be
/// opened four times.
final class SwitcherFileCell: NSView {
	let path: String
	let filter: String

	init(path: String, filter: String) {
		self.path = path
		self.filter = filter
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let name = (path as NSString).lastPathComponent
		let directory = (path as NSString).deletingLastPathComponent

		let iconSize = Theme.current.scaled(13)
		if let icon = FileIcon.image(forFileNamed: name) {
			icon.drawFitted(in: NSRect(
				x: Theme.current.scaled(12),
				y: bounds.midY - iconSize / 2,
				width: iconSize,
				height: iconSize
			))
		}

		let title = NSMutableAttributedString(string: name, attributes: [
			.font: Theme.current.uiFont(13),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		// Lit where the typing matched, so it is clear why this row is here —
		// and, when the match is in a directory above, the name lights nowhere
		// and the path beside it does instead.
		if !filter.isEmpty,
		   let range = name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			title.addAttribute(
				.foregroundColor,
				value: Theme.current.gitModified,
				range: NSRange(range, in: name)
			)
		}

		let nameX = Theme.current.scaled(33)
		let titleSize = title.size()
		title.draw(at: NSPoint(x: nameX, y: bounds.midY - titleSize.height / 2))

		guard !directory.isEmpty else { return }

		// Right-aligned and truncated at the front, as the project rows are: the
		// tail of a path is the part that says which one this is.
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .right
		paragraph.lineBreakMode = .byTruncatingHead

		let trail = NSMutableAttributedString(string: directory, attributes: [
			.font: Theme.current.monoFont(11),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		if !filter.isEmpty,
		   let range = directory.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			trail.addAttribute(
				.foregroundColor,
				value: Theme.current.gitModified,
				range: NSRange(range, in: directory)
			)
		}

		let left = nameX + ceil(titleSize.width) + Theme.current.scaled(12)
		let available = bounds.maxX - Theme.current.scaled(12) - left
		guard available > Theme.current.scaled(30) else { return }
		trail.draw(in: NSRect(
			x: left,
			y: bounds.midY - trail.size().height / 2,
			width: available,
			height: trail.size().height
		))
	}
}

/// One project, on one line.
///
/// The colour is a rail on the leading edge rather than a lettered square: the
/// initials never said anything the name beside them did not, and the square is
/// most of what made this list look like somebody else's IDE. On one line
/// instead of two, twice as many projects fit — and the paths, right-aligned in
/// a fixed face, line up into a column that can be read down.
final class SwitcherProjectCell: NSView {
	let entry: RecentProject
	let isOpen: Bool
	let filter: String

	init(entry: RecentProject, isOpen: Bool, filter: String) {
		self.entry = entry
		self.isOpen = isOpen
		self.filter = filter
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	static var railWidth: CGFloat { Theme.current.scaled(3) }
	static var leading: CGFloat { Theme.current.scaled(13) }
	static var trailing: CGFloat { Theme.current.scaled(12) }

	override func draw(_ dirtyRect: NSRect) {
		ProjectBadge.color(for: entry.name, colorIndex: entry.colorIndex).setFill()
		NSRect(x: 0, y: 0, width: Self.railWidth, height: bounds.height).fill()

		let name = NSMutableAttributedString(string: entry.name, attributes: [
			.font: Theme.current.uiFont(13, weight: isOpen ? .semibold : .regular),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		// What the typing matched, lit — so it is clear why this row is here.
		if !filter.isEmpty,
		   let range = entry.name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			name.addAttribute(
				.foregroundColor,
				value: Theme.current.gitModified,
				range: NSRange(range, in: entry.name)
			)
		}

		let nameSize = name.size()
		let nameX = Self.leading
		name.draw(at: NSPoint(x: nameX, y: bounds.midY - nameSize.height / 2))

		// A fixed face, right-aligned, truncated at the front: the tail of a
		// path is the part that says which one this is, and `/var/folders/…`
		// is never it.
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .right
		paragraph.lineBreakMode = .byTruncatingHead

		let path = NSAttributedString(string: entry.displayPath, attributes: [
			.font: Theme.current.monoFont(11),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		let left = nameX + ceil(nameSize.width) + Theme.current.scaled(12)
		let available = bounds.maxX - Self.trailing - left
		guard available > Theme.current.scaled(30) else { return }
		path.draw(in: NSRect(
			x: left,
			y: bounds.midY - path.size().height / 2,
			width: available,
			height: path.size().height
		))
	}
}
