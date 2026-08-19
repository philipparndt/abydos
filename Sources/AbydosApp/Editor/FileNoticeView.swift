import AppKit
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

		let detail = NSTextField(labelWithString: content.detail)
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

	private func makeButton(title: String, symbol: String, action: @escaping () -> Void) -> NSButton {
		let button = NoticeButton(title: title, symbol: symbol)
		button.onClick = action
		return button
	}
}

// `NoticeButton` used to live here, private to this file. It moved to
// `NoticeButton.swift` when the backlog pane's empty state — the same sentence
// about a different subject — came to need the same button; see the note there.
