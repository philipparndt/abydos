import AbydosKit
import AppKit

/// What `Export ▸` offers over a diagram, in one place.
///
/// There are two of these menus — the preview pane's own and the file's in the
/// project tree — and 0429 says whatever the export asks has to work from both.
/// One list, built here, so they cannot drift apart the way two hand-written
/// menus eventually would.
///
/// **How the export asks, and why it asks like this.** Three shapes were on the
/// table. `Export ▸ PNG ▸ Light` is a third level of menu, which is a maze to
/// walk for a thing somebody does often. A setting hides the choice at the
/// moment of choosing — and the moment of choosing is the point: which of a
/// README, a wiki and a slide wants dark is not something a preference set last
/// month knows. So the items are named after what they produce:
///
///     Export ▸ PNG (Dark)      ← the theme the app is wearing, first
///             ▸ SVG (Dark)
///             ▸ PNG (Light)
///             ▸ SVG (Light)
///
/// Four items rather than two, and every one of them says exactly what file it
/// will write — which matters because the name of that file follows
/// (`diagram-dark.png`). Both are qualified rather than only the odd one out: an
/// unqualified `PNG` beside a `PNG (Light)` reads as "the normal one", and in a
/// dark window the normal one is the dark one, which is the opposite of what it
/// would be read as.
///
/// The pair on screen comes first, because it is the one almost every export
/// wants and the eye lands on the top of a submenu.
///
/// **And when the file has chosen, there is nothing to choose.** A diagram that
/// states its own look is drawn that way whichever item is picked, so offering
/// two of them would be offering a difference that does not exist. The menu
/// falls back to plain `PNG` / `SVG`, which is what it has always been.
///
/// **The second group, and why a `.drawio` has one.** A picture beside a
/// document is a derived artefact: `diagram.png` is regenerated, committed and
/// never touched by hand. draw.io has a second form that nothing else here has —
/// `architecture.drawio.png`, a real PNG carrying the whole `<mxfile>`, which is
/// *one file that is both the picture and the document*. It renders wherever a
/// PNG renders and reopens in draw.io with every page. That is the form people
/// commit, and until now this app could read one and not write one.
///
/// It is the same bytes the first group already writes — every picture exported
/// from a diagram carries the document — so the only thing the second group
/// changes is the **name**, and the name is the whole point: `architecture.png`
/// is a name any screenshot could have, and nobody reading a repository can tell
/// that this one is also a document.
///
///     Export ▸ PNG (Dark)              → architecture-dark.png
///             ▸ SVG (Dark)
///             ▸ PNG (Light)
///             ▸ SVG (Light)
///             ──────────
///             ▸ Editable PNG (Dark)    → architecture-dark.drawio.png
///             ▸ Editable SVG (Dark)
///             ▸ Editable PNG (Light)
///             ▸ Editable SVG (Light)
///
/// Both groups are qualified by theme, for the reason the first group is: an
/// unqualified item beside a qualified one reads as "the normal one", and in a
/// dark window the normal one is the dark one.
enum DiagramExportMenu {
	/// One item: what it says, what it writes, and which way round.
	struct Entry {
		let title: String
		let format: DiagramFormat
		/// Nil when the file states its own look and there is nothing to impose.
		let theme: DiagramTheme?
		/// Whether this writes `x.drawio.png` — the picture that is also the
		/// document — rather than `x.png`.
		var editable = false

		/// What goes in `representedObject`, since a menu item carries a value
		/// rather than a closure here.
		var code: String {
			let choice = theme.map { "\(format.rawValue):\($0.rawValue)" } ?? format.rawValue
			return editable ? "editable:" + choice : choice
		}
	}

	/// The items to offer.
	///
	/// - Parameters:
	///   - theme: the palette the app is wearing.
	///   - stated: what the file says about its own look, when it says anything.
	///   - editable: whether this file has an editable-picture form at all, which
	///     is draw.io and nothing else. A `.puml` has no document to put inside a
	///     PNG, so offering it one would be offering a file that is a picture
	///     under a name saying otherwise.
	static func entries(
		theme: DiagramTheme, stated: String?, editable: Bool = false
	) -> [Entry] {
		func group(_ isEditable: Bool) -> [Entry] {
			let what = isEditable ? "Editable " : ""
			guard stated == nil else {
				return DiagramFormat.allCases.map {
					Entry(
						title: what + $0.rawValue.uppercased(), format: $0, theme: nil,
						editable: isEditable
					)
				}
			}
			return [theme, theme.other].flatMap { wanted in
				DiagramFormat.allCases.map {
					Entry(
						title: "\(what)\($0.rawValue.uppercased()) (\(wanted.title))",
						format: $0, theme: wanted, editable: isEditable
					)
				}
			}
		}
		return group(false) + (editable ? group(true) : [])
	}

	/// The format, theme and kind an item's code meant.
	static func choice(
		for code: String
	) -> (format: DiagramFormat, theme: DiagramTheme?, editable: Bool)? {
		var rest = Substring(code)
		var editable = false
		if rest.hasPrefix("editable:") {
			editable = true
			rest = rest.dropFirst("editable:".count)
		}
		let parts = rest.split(separator: ":", maxSplits: 1)
		guard let first = parts.first, let format = DiagramFormat(rawValue: String(first)) else {
			return nil
		}
		guard parts.count == 2 else { return (format, nil, editable) }
		return (format, DiagramTheme(rawValue: String(parts[1])), editable)
	}

	/// Refills a submenu with the items for this file, keeping the target and
	/// action the caller wired up.
	///
	/// Rebuilt on every `willOpenMenu` rather than once, because both the theme
	/// and whether the file has stated a look change while a menu exists.
	static func fill(
		_ menu: NSMenu, theme: DiagramTheme, stated: String?,
		target: AnyObject?, action: Selector, enabled: Bool, editable: Bool = false
	) {
		menu.removeAllItems()
		var divided = false
		for entry in entries(theme: theme, stated: stated, editable: editable) {
			// One line between the two groups, because they write different kinds
			// of file and the second is the one somebody has to notice.
			if entry.editable, !divided, !menu.items.isEmpty {
				menu.addItem(.separator())
				divided = true
			}
			let item = NSMenuItem(title: entry.title, action: action, keyEquivalent: "")
			item.target = target
			item.representedObject = entry.code
			item.isEnabled = enabled
			menu.addItem(item)
		}
	}
}
