import AppKit
import AbydosKit

/// The row above a song's text saying which of its files is being edited.
///
/// A song is written across files and they are all shown in the song's own tab,
/// so the tab bar's name — the song — is no longer the whole answer to "what am
/// I looking at". This row is the rest of it: the song, and every file it is
/// made of with the one being edited marked.
///
/// Asked for 2026-09-16: "we should add a navigation to the song editor with
/// also a breadcrump to jump back".
///
/// **The song is the root, and the file being edited is its child — the
/// song's own file too.** It was a breadcrumb whose first part held the menu,
/// `♪ ember.song ⌄ › drums.song`, and reported 2026-09-19: "the breadcrum is
/// conusing as it looks like the main item would be changed but in relaity we
/// are changing the children … the first item is always the initial opened
/// file, and this is then already shown as its own children item". A row of
/// every file came next and was too much — "only the main file, and the
/// current selected one. The current selected one gets the dropdown". So the
/// song is named once and goes back to its own file when clicked, and what
/// follows it is the file in front, lit, with the menu of the song's files on
/// it: `♪ ember.song › drums.song ⌄`, and `♪ ember.song › ember.song ⌄` on the
/// song itself.
@MainActor
final class SongFilesBar: NSView {
	/// A file of the song was chosen.
	var onChoose: ((URL) -> Void)?

	/// The song: goes back to its own file.
	private let song = NSButton()
	private let separator = NSTextField(labelWithString: "›")
	/// The file in front, with the menu of all of the song's files.
	private let current = NSButton()
	private var files: [URL] = []
	private var songURL: URL?
	private var shown: URL?

	static var height: CGFloat { Theme.current.scaled(24) }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true

		for button in [song, current] {
			button.isBordered = false
			button.bezelStyle = .inline
			button.setButtonType(.momentaryChange)
			button.translatesAutoresizingMaskIntoConstraints = false
			button.target = self
			button.alignment = .left
			button.setContentHuggingPriority(.required, for: .horizontal)
		}
		song.action = #selector(songPressed)
		current.action = #selector(currentPressed)
		// The chevron is the symbol rather than a "⌄" in the title: a glyph in
		// the text sits on the baseline, under the middle of the name beside
		// it. Reported 2026-09-16 with a picture: "the chevon shall be
		// centered". As an image the button centres it against the title.
		current.imagePosition = .imageTrailing
		current.imageHugsTitle = true
		current.wantsLayer = true
		current.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		separator.translatesAutoresizingMaskIntoConstraints = false

		addSubview(song)
		addSubview(separator)
		addSubview(current)
		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Self.height),
			song.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			song.centerYAnchor.constraint(equalTo: centerYAnchor),
			separator.leadingAnchor.constraint(equalTo: song.trailingAnchor, constant: Theme.current.scaled(4)),
			separator.centerYAnchor.constraint(equalTo: centerYAnchor),
			current.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: Theme.current.scaled(4)),
			current.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
			current.centerYAnchor.constraint(equalTo: centerYAnchor),
			current.heightAnchor.constraint(equalToConstant: Theme.current.scaled(18)),
		])
		applyTheme()
	}

	@available(*, unavailable) required init?(coder: NSCoder) { fatalError("no coder") }

	/// What the row says: the song, the files it is made of, and which of them
	/// is in front.
	func show(song songURL: URL, files: [URL], shown: URL) {
		self.songURL = songURL
		self.shown = shown
		// The song first, then the rest by the path somebody reads them as.
		let root = songURL.deletingLastPathComponent()
		self.files = [songURL] + files
			.filter { FilePath.canonical($0) != FilePath.canonical(songURL) }
			.sorted { Self.name(of: $0, under: root) < Self.name(of: $1, under: root) }
		applyTheme()
	}

	/// A file's name as this row says it: relative to the song's folder when it
	/// is under it, and the whole path when it is not.
	static func name(of file: URL, under root: URL) -> String {
		let path = file.standardizedFileURL.path
		let base = root.standardizedFileURL.path
		guard path.hasPrefix(base + "/") else { return file.lastPathComponent }
		return String(path.dropFirst(base.count + 1))
	}

	/// What the row shows, for a driven run: the song, the file in front, and
	/// what its menu offers.
	var reportForTesting: String {
		guard let songURL else { return "FILES: none" }
		let root = songURL.deletingLastPathComponent()
		return "FILES: ♪ \(songURL.lastPathComponent) › \(shown.map { Self.name(of: $0, under: root) } ?? "-") ⌄"
			+ " menu=[\(files.map { Self.name(of: $0, under: root) }.joined(separator: ", "))]"
	}

	private func isShown(_ file: URL) -> Bool {
		shown.map { FilePath.canonical($0) == FilePath.canonical(file) } == true
	}

	/// Back to the song's own file.
	@objc private func songPressed() {
		guard let songURL, !isShown(songURL) else { return }
		onChoose?(songURL)
	}

	/// Every file of the song, the one in front ticked.
	@objc private func currentPressed() {
		guard let songURL else { return }
		let menu = NSMenu()
		let root = songURL.deletingLastPathComponent()
		for file in files {
			let item = NSMenuItem(
				title: Self.name(of: file, under: root), action: #selector(choose(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = file
			item.state = isShown(file) ? .on : .off
			menu.addItem(item)
		}
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: current.bounds.height + 2), in: current)
	}

	@objc private func choose(_ item: NSMenuItem) {
		guard let file = item.representedObject as? URL, !isShown(file) else { return }
		onChoose?(file)
	}

	func applyTheme() {
		let theme = Theme.current
		layer?.backgroundColor = theme.editorBackground.cgColor
		song.attributedTitle = NSAttributedString(string: "♪ \(songURL?.lastPathComponent ?? "")", attributes: [
			.font: theme.uiFont(11, weight: .medium),
			.foregroundColor: theme.gitIgnored,
		])
		separator.attributedStringValue = NSAttributedString(string: "›", attributes: [
			.font: theme.uiFont(11), .foregroundColor: theme.gitIgnored,
		])
		let root = songURL?.deletingLastPathComponent()
		let here = shown.flatMap { file in root.map { Self.name(of: file, under: $0) } } ?? ""
		// The file in front is the lit one, as the tab in front is.
		current.attributedTitle = NSAttributedString(string: " \(here) ", attributes: [
			.font: theme.uiFont(11, weight: .semibold),
			.foregroundColor: theme.editorText,
		])
		current.layer?.cornerRadius = theme.scaled(4)
		current.layer?.backgroundColor = theme.selectionActive.withAlphaComponent(0.35).cgColor
		let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "This song's files")
		current.image = chevron?.withSymbolConfiguration(
			NSImage.SymbolConfiguration(pointSize: theme.scaled(8), weight: .semibold)
		)
		current.contentTintColor = theme.gitIgnored
		current.toolTip = shown?.path
		for view in [song, separator, current] as [NSView] { view.isHidden = songURL == nil }
	}
}
