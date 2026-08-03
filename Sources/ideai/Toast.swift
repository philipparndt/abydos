import AppKit

/// Something the app has to say that the user did not ask about.
///
/// A modal that appears on its own takes the keyboard, stops everything, and
/// demands to be dismissed before the sentence it contains can even be acted
/// on — for news as minor as "no go.mod here". A toast says it in the corner,
/// goes away by itself, and opens the full story if it turns out to matter.
///
/// The rule this exists to enforce: nothing interrupts unless the user asked a
/// question. Confirmations before something destructive are still modal,
/// because those *are* the answer to something they just did.
struct Toast {
	enum Kind {
		case error, warning, information

		var symbol: String {
			switch self {
			case .error: return "exclamationmark.triangle.fill"
			case .warning: return "exclamationmark.circle.fill"
			case .information: return "info.circle.fill"
			}
		}

		var tint: NSColor {
			switch self {
			case .error: return .hex(0xE05252)
			case .warning: return .hex(0xD9A343)
			case .information: return .hex(0x56A8F5)
			}
		}
	}

	let kind: Kind
	/// One line, read at a glance from the corner of the eye.
	let title: String
	/// The rest, shown only if the toast is clicked.
	let detail: String?
	/// What a click should do instead of opening the detail, and the words for
	/// it.
	///
	/// News about somewhere else — a Claude session two tabs away wanting an
	/// answer — is worth more as a way of getting there than as a paragraph.
	let action: (() -> Void)?
	let actionTitle: String?

	init(
		kind: Kind = .error,
		title: String,
		detail: String? = nil,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		self.kind = kind
		self.title = title
		self.detail = detail
		self.actionTitle = actionTitle
		self.action = action
	}
}

extension Notification.Name {
	/// Something wants to be said in the corner.
	static let ideaiToast = Notification.Name("ideai.toast")
}

extension Toast {
	/// Says something from anywhere, without needing to know which window.
	///
	/// Panes are built without a window and often before there is one, so
	/// reaching for the presenter directly would mean threading it through
	/// everything that might ever have bad news.
	static func post(_ title: String, detail: String? = nil, kind: Kind = .error) {
		NotificationCenter.default.post(
			name: .ideaiToast,
			object: nil,
			userInfo: ["toast": Toast(kind: kind, title: title, detail: detail)]
		)
	}
}

/// Shows toasts in the corner of a window, newest at the bottom.
@MainActor
final class ToastPresenter {
	private weak var window: NSWindow?
	private var host: ToastHostView?
	private var shown: [ToastView] = []

	private static let maximumVisible = 4
	private static let lifetime: TimeInterval = 8

	init(window: NSWindow?) {
		self.window = window
	}

	func show(_ toast: Toast) {
		guard let contentView = window?.contentView else { return }

		let host = self.host ?? {
			let created = ToastHostView()
			created.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(created, positioned: .above, relativeTo: nil)
			NSLayoutConstraint.activate([
				created.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
				created.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
				created.widthAnchor.constraint(equalToConstant: 340),
			])
			self.host = created
			return created
		}()

		let view = ToastView(toast: toast)
		view.onDismiss = { [weak self, weak view] in
			guard let view else { return }
			self?.dismiss(view)
		}
		view.onOpen = { [weak self] in
			guard let action = toast.action else {
				self?.present(toast)
				return
			}
			action()
		}

		host.add(view)
		shown.append(view)

		// The oldest goes when the stack is full: a corner filling with news
		// is its own kind of interruption.
		while shown.count > Self.maximumVisible, let oldest = shown.first {
			dismiss(oldest)
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { [weak self, weak view] in
			guard let view, view.isPointedAt == false else { return }
			self?.dismiss(view)
		}
	}

	private func dismiss(_ view: ToastView) {
		shown.removeAll { $0 === view }
		view.removeFromHost()
		if shown.isEmpty {
			host?.removeFromSuperview()
			host = nil
		}
	}

	/// The full story, in a dialog — which is fine, because by now it was asked
	/// for.
	private func present(_ toast: Toast) {
		DetailDialog(
			title: toast.title,
			detail: toast.detail ?? "",
			isError: toast.kind == .error
		).show(over: window)
	}
}

/// Stacks the toasts, and lets clicks through everywhere else.
private final class ToastHostView: NSView {
	private let stack = NSStackView()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		stack.orientation = .vertical
		stack.alignment = .trailing
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func add(_ view: ToastView) {
		stack.addArrangedSubview(view)
		view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}

	/// Only the toasts themselves take clicks; the rest of the corner belongs
	/// to whatever is underneath.
	override func hitTest(_ point: NSPoint) -> NSView? {
		let hit = super.hitTest(point)
		return hit === self || hit === stack ? nil : hit
	}
}

/// One toast: an icon, a line of text, and a way to close it.
private final class ToastView: NSView {
	var onDismiss: (() -> Void)?
	var onOpen: (() -> Void)?
	private(set) var isPointedAt = false

	private let toast: Toast
	private var trackingArea: NSTrackingArea?

	init(toast: Toast) {
		self.toast = toast
		super.init(frame: .zero)
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.backgroundColor = Theme.current.sidebarBackground.withAlphaComponent(0.98).cgColor
		layer?.borderWidth = 1
		layer?.borderColor = Theme.current.separator.cgColor
		layer?.shadowOpacity = 0.35
		layer?.shadowRadius = 10
		layer?.shadowOffset = CGSize(width: 0, height: -2)

		toolTip = toast.detail ?? toast.title
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	func removeFromHost() {
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.15
			animator().alphaValue = 0
		} completionHandler: { [weak self] in
			self?.removeFromSuperview()
		}
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	// Hovering holds it open: reading it should not be a race.
	override func mouseEntered(with event: NSEvent) { isPointedAt = true }
	override func mouseExited(with event: NSEvent) { isPointedAt = false }

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if closeRect.contains(point) {
			onDismiss?()
			return
		}
		onOpen?()
		onDismiss?()
	}

	private var closeRect: NSRect {
		NSRect(x: bounds.maxX - 26, y: 10, width: 16, height: 16)
	}

	override func draw(_ dirtyRect: NSRect) {
		let inset: CGFloat = 12

		if let icon = Theme.symbol("\(toast.kind.symbol)", size: 12, color: toast.kind.tint) {
			icon.drawFitted(in: NSRect(x: inset, y: 13, width: 14, height: 14))
		}

		let textX = inset + 22
		let title = NSAttributedString(string: toast.title, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		title.draw(in: NSRect(
			x: textX, y: 11, width: max(0, bounds.width - textX - 34), height: title.size().height
		))

		// A hint about what a click does, only when it does anything.
		if let hint = toast.actionTitle ?? (toast.detail?.isEmpty == false ? "Click for details" : nil) {
			let more = NSAttributedString(string: hint, attributes: [
				.font: Theme.current.uiFont(10),
				.foregroundColor: Theme.current.gitIgnored,
			])
			more.draw(at: NSPoint(x: textX, y: 11 + title.size().height + 2))
		}

		let cross = NSBezierPath()
		cross.lineWidth = 1.3
		let box = closeRect.insetBy(dx: 4, dy: 4)
		cross.move(to: NSPoint(x: box.minX, y: box.minY))
		cross.line(to: NSPoint(x: box.maxX, y: box.maxY))
		cross.move(to: NSPoint(x: box.maxX, y: box.minY))
		cross.line(to: NSPoint(x: box.minX, y: box.maxY))
		Theme.current.gitIgnored.setStroke()
		cross.stroke()
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: toast.actionTitle != nil || toast.detail?.isEmpty == false ? 52 : 40
		)
	}
}
