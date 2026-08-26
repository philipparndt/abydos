import AppKit
import QuickLookUI
import AbydosKit

/// Shown in the editor area when a file cannot be displayed as text.
///
/// Deliberately not an alert: a modal interrupts, has to be dismissed before you
/// can do anything, and leaves you with nothing to show for it. As editor
/// content it can sit there, explain itself, and offer the two things actually
/// worth doing with a binary file.
final class FileNoticeView: NSView {
	var onOpenExternally: (() -> Void)?
	var onOpenHexEditor: (() -> Void)?
	var onPreviewModel: (() -> Void)?

	private let url: URL
	private let reason: String

	init(url: URL, reason: String) {
		self.url = url
		self.reason = reason
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		let content = FileNotice.content(for: url, reason: reason)

		let icon = NSImageView()
		icon.image = FileIcon.image(for: FileNode(url: url, isDirectory: false), isExpanded: false)
		icon.imageScaling = .scaleProportionallyUpOrDown
		icon.translatesAutoresizingMaskIntoConstraints = false
		icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

		let title = NSTextField(labelWithString: url.lastPathComponent)
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		title.textColor = Theme.current.sidebarHeaderText
		title.alignment = .center

		// The size on the same grey line as the sentence, separated the way this
		// app separates a fact from a fact elsewhere. A line of its own would
		// make two greys where the eye expects one.
		let said = content.size.map { "\(content.detail)  ·  \($0)" } ?? content.detail
		let detail = NSTextField(labelWithString: said)
		detail.font = .systemFont(ofSize: 12)
		detail.textColor = Theme.current.gitIgnored
		detail.alignment = .center

		let last = makeLastRow(for: content)

		let stack = NSStackView(views: [icon, title, detail, last])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 10
		stack.setCustomSpacing(16, after: detail)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
		])
	}

	/// The buttons, or the path when there is nothing the buttons could do.
	private func makeLastRow(for content: FileNotice.Content) -> NSView {
		guard content.offersActions else {
			// Selectable, because the one thing somebody does with a path they
			// were shown is copy it — into a terminal, or into a search.
			let path = NSTextField(labelWithString: content.path ?? url.path)
			path.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
			path.textColor = Theme.current.gitIgnored
			path.alignment = .center
			path.isSelectable = true
			// Middle, not tail: the end of a path is the part that identifies
			// it, and a truncated tail would leave four projects' `main.py`
			// looking identical — which is the question this row is answering.
			path.lineBreakMode = .byTruncatingMiddle
			path.toolTip = url.path
			return path
		}

		var actions: [NSView] = []
		// **Quick Look leads for anything the system can show.** The obvious
		// thing to do with a video is watch it, and the notice for one offered a
		// hex editor and another application. Same argument as the model preview
		// below: what somebody wants is to look at it.
		if content.offersQuickLook {
			actions.append(makeButton(title: "Quick Look", symbol: "eye") { [weak self] in
				self?.showQuickLook()
			})
		}
		// A model file is far more often something to look at than to inspect
		// byte by byte, so the preview leads when one is available.
		if ModelPreview.canPreview(url), ModelPreview.isAvailable {
			actions.append(makeButton(title: "Preview in GoSTL", symbol: "cube") { [weak self] in
				self?.onPreviewModel?()
			})
		}
		actions.append(makeButton(title: "Open in Hex Editor", symbol: "number") { [weak self] in
			self?.onOpenHexEditor?()
		})
		actions.append(makeButton(title: "Open Externally", symbol: "arrow.up.forward.app") { [weak self] in
			self?.onOpenExternally?()
		})

		let buttons = NSStackView(views: actions)
		buttons.orientation = .horizontal
		buttons.spacing = 10
		return buttons
	}

	// MARK: - Quick Look

	/// Opens the system's preview panel on this file.
	///
	/// **Through the responder chain, which is the only way that works.**
	/// `QLPreviewPanel` asks the key window's responder chain who wants to
	/// control it, and a `dataSource` set on the shared panel from outside that
	/// conversation is replaced the moment somebody answers. So this view
	/// answers: it takes first responder, says yes, and hands itself over.
	func showQuickLook() {
		window?.makeFirstResponder(self)
		guard let panel = QLPreviewPanel.shared() else { return }
		// **Handed over directly as well as through the chain.** The documented
		// route is the three `…PreviewPanelControl` methods below, and the panel
		// walks the responder chain to find whoever answers them — but it only
		// does that when the application is the active one, and it is not always:
		// a window brought up without the app being brought forward leaves the
		// panel open, controlled by nobody, showing nothing at all. Measured that
		// way before this line existed.
		//
		// Setting it here costs nothing when the chain does answer: it answers
		// with this same object.
		panel.dataSource = self
		panel.delegate = self
		panel.makeKeyAndOrderFront(nil)
		panel.reloadData()
	}

	override var acceptsFirstResponder: Bool { true }

	var urlForTesting: URL { url }

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = self
		panel.delegate = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		// Only what this view put there. The panel outlives the tab, and clearing
		// somebody else's source would leave their panel blank.
		guard panel.dataSource === self else { return }
		panel.dataSource = nil
		panel.delegate = nil
	}

	/// Space opens it too, the way it does in the Finder and in the tree.
	override func keyDown(with event: NSEvent) {
		if event.charactersIgnoringModifiers == " ", FileNotice.offersQuickLook(
			forExtension: url.pathExtension
		) {
			showQuickLook()
			return
		}
		super.keyDown(with: event)
	}

	private func makeButton(title: String, symbol: String, action: @escaping () -> Void) -> NSButton {
		let button = NoticeButton(title: title, symbol: symbol)
		button.onClick = action
		return button
	}
}

extension FileNoticeView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		url as NSURL
	}

	/// Zooms out of the notice rather than appearing from nowhere, which is what
	/// the panel does everywhere else on this machine.
	func previewPanel(
		_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!
	) -> NSRect {
		guard let window else { return .zero }
		return window.convertToScreen(convert(bounds, to: nil))
	}
}

// `NoticeButton` used to live here, private to this file. It moved to
// `NoticeButton.swift` when the backlog pane's empty state — the same sentence
// about a different subject — came to need the same button; see the note there.
