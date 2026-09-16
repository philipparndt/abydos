import AppKit
import AbydosKit

/// The row above a song's text saying which of its files is being edited.
///
/// A song is written across files and they are all shown in the song's own tab,
/// so the tab bar's name — the song — is no longer the whole answer to "what am
/// I looking at". This row is the rest of it: the song, a menu of every file it
/// is made of, and where in them the text below is.
///
/// Asked for 2026-09-16: "we should add a navigation to the song editor with
/// also a breadcrump to jump back".
@MainActor
final class SongFilesBar: NSView {
	/// A file of the song was chosen.
	var onChoose: ((URL) -> Void)?

	private let song = NSButton()
	private let trail = NSTextField(labelWithString: "")
	private var files: [URL] = []
	private var songURL: URL?
	private var shown: URL?

	static var height: CGFloat { Theme.current.scaled(24) }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true

		song.isBordered = false
		song.bezelStyle = .inline
		song.setButtonType(.momentaryChange)
		// The chevron is the symbol rather than a "⌄" in the title: a glyph in
		// the text sits on the baseline, under the middle of the name beside
		// it. Reported 2026-09-16 with a picture: "the chevon shall be
		// centered". As an image the button centres it against the title.
		song.imagePosition = .imageTrailing
		song.imageHugsTitle = true
		song.translatesAutoresizingMaskIntoConstraints = false
		song.target = self
		song.action = #selector(songPressed)
		song.alignment = .left

		trail.translatesAutoresizingMaskIntoConstraints = false
		trail.lineBreakMode = .byTruncatingHead
		trail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		addSubview(song)
		addSubview(trail)
		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Self.height),
			song.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			song.centerYAnchor.constraint(equalTo: centerYAnchor),
			trail.leadingAnchor.constraint(equalTo: song.trailingAnchor, constant: Theme.current.scaled(2)),
			trail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
			trail.centerYAnchor.constraint(equalTo: centerYAnchor),
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

	@objc private func songPressed() {
		guard let songURL else { return }
		let menu = NSMenu()
		let root = songURL.deletingLastPathComponent()
		for file in files {
			let item = NSMenuItem(
				title: Self.name(of: file, under: root), action: #selector(choose(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = file
			item.state = shown.map { FilePath.canonical($0) == FilePath.canonical(file) } == true ? .on : .off
			menu.addItem(item)
		}
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
	}

	@objc private func choose(_ item: NSMenuItem) {
		guard let file = item.representedObject as? URL else { return }
		onChoose?(file)
	}

	func applyTheme() {
		let theme = Theme.current
		layer?.backgroundColor = theme.editorBackground.cgColor
		let name = songURL?.lastPathComponent ?? ""
		song.attributedTitle = NSAttributedString(string: "♪ \(name)", attributes: [
			.font: theme.uiFont(11, weight: .medium),
			.foregroundColor: theme.editorText,
		])
		let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "This song's files")
		song.image = chevron?.withSymbolConfiguration(
			NSImage.SymbolConfiguration(pointSize: theme.scaled(8), weight: .semibold)
		)
		song.contentTintColor = theme.gitIgnored
		song.isHidden = songURL == nil
		let root = songURL?.deletingLastPathComponent()
		let here = shown.flatMap { file in root.map { Self.name(of: file, under: $0) } } ?? ""
		let isSong = songURL.map { file in shown.map { FilePath.canonical($0) == FilePath.canonical(file) } == true } ?? false
		trail.attributedStringValue = NSAttributedString(
			string: isSong || here.isEmpty ? "" : "  ›  " + here.replacingOccurrences(of: "/", with: "  ›  "),
			attributes: [
				.font: theme.uiFont(11, weight: .regular),
				.foregroundColor: theme.gitIgnored,
			]
		)
	}
}
