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

	/// How long a toast stays in the corner.
	enum Lifetime {
		/// Eight seconds, then gone by itself. News: it was worth saying and it
		/// is not worth a gesture.
		case passing
		/// Until one of its answers is pressed.
		///
		/// **For a toast that is a question rather than news**, which is the one
		/// thing the corner could not do before: a question that timed out would
		/// answer itself with whichever answer doing nothing amounts to, and
		/// nothing on screen would say it had. The way out is one of the answers
		/// — a question that stays has to offer somebody a way of saying no —
		/// and it has no close cross for that reason.
		case untilAnswered
	}

	/// One of the answers a toast offers, drawn as a button under the sentence.
	///
	/// Several rather than one, because a question with a real answer usually
	/// has more than two: the devcontainer's are use it, work on this machine,
	/// and not now, and collapsing those onto a single click and a dismissal
	/// would lose the difference between the last two — which is the difference
	/// 0433 spent an item establishing.
	struct Answer {
		let title: String
		let perform: () -> Void

		init(_ title: String, perform: @escaping () -> Void) {
			self.title = title
			self.perform = perform
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
	/// The buttons under the sentence. Empty for everything that is not a
	/// question, which is nearly everything.
	let answers: [Answer]
	let lifetime: Lifetime
	/// A name for a toast that may have to be taken back before it is answered.
	///
	/// A question is about something — a project, a file — and that something can
	/// go away underneath it. Nothing else here needs a name, so this is nil for
	/// every toast that is news.
	let identifier: String?
	/// What to do if it is taken off the screen without being answered.
	///
	/// Not the same as any of the answers: nothing was decided, and whatever was
	/// holding the question open has to be told so it can ask again rather than
	/// waiting for ever on an answer that will not come.
	let onWithdrawn: (() -> Void)?

	init(
		kind: Kind = .error,
		title: String,
		detail: String? = nil,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil,
		answers: [Answer] = [],
		lifetime: Lifetime = .passing,
		identifier: String? = nil,
		onWithdrawn: (() -> Void)? = nil
	) {
		self.kind = kind
		self.title = title
		self.detail = detail
		self.actionTitle = actionTitle
		self.action = action
		self.answers = answers
		self.lifetime = lifetime
		self.identifier = identifier
		self.onWithdrawn = onWithdrawn
	}
}

extension Notification.Name {
	/// Something wants to be said in the corner.
	static let abydosToast = Notification.Name("abydos.toast")
	/// A question in the corner is no longer worth asking. The user info carries
	/// the identifier it was posted under.
	static let abydosToastWithdrawn = Notification.Name("abydos.toastWithdrawn")
}

extension Toast {
	/// Says something from anywhere, without needing to know which window.
	///
	/// Panes are built without a window and often before there is one, so
	/// reaching for the presenter directly would mean threading it through
	/// everything that might ever have bad news.
	static func post(_ title: String, detail: String? = nil, kind: Kind = .error) {
		post(Toast(kind: kind, title: title, detail: detail))
	}

	/// The same for a toast built by hand.
	@discardableResult
	static func post(_ toast: Toast) -> Bool {
		let taken = Taken()
		NotificationCenter.default.post(
			name: .abydosToast, object: nil, userInfo: ["toast": toast, "taken": taken]
		)
		return taken.value
	}

	/// Whether a window took the toast. A class, because the observers are called
	/// while `post` is still on the stack and this is how they answer it.
	final class Taken {
		var value = false
	}

	/// Puts a question in the corner, and keeps asking for somewhere to put it.
	///
	/// **A question must not be dropped, and it nearly was.** A toast goes to
	/// whichever window is speaking for the app, and while the app is starting up
	/// that is none of them: no key window, no main window, nothing on screen
	/// yet. For news that gap is harmless — it is one sentence, a second early.
	/// For the devcontainer question it was fatal, and measured rather than
	/// imagined: `warmUp` runs inside exactly that gap, the question went nowhere,
	/// and the project went on holding the guard that stops it being asked twice,
	/// so it could never be asked again and the strip said "starting in this
	/// project's devcontainer" for ever. It is the same gap 0433's modal had to
	/// wait out, and it is waited out the same way — a quarter of a second at a
	/// time.
	///
	/// **Ten seconds, and then it is withdrawn rather than forgotten**, so that
	/// whatever was holding the question open is told and the next file opened can
	/// ask again. Silence is the one outcome that must not be reachable.
	@MainActor
	static func ask(_ toast: Toast, attempt: Int = 0) {
		guard !post(toast) else { return }
		guard attempt < 40 else {
			toast.onWithdrawn?()
			return
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
			MainActor.assumeIsolated { ask(toast, attempt: attempt + 1) }
		}
	}

	/// Takes a question back, wherever it ended up.
	///
	/// **What this is for.** A question is about something, and that something
	/// can close underneath it — the project the container belongs to is shut,
	/// or the window that was showing it is pointed somewhere else. Leaving it
	/// there would put an answer about a project nobody is looking at one click
	/// from being given, over a window showing a different one entirely.
	/// Withdrawing decides nothing: `onWithdrawn` is what tells whoever was
	/// holding the question open that it may be asked again.
	static func withdraw(_ identifier: String) {
		NotificationCenter.default.post(
			name: .abydosToastWithdrawn, object: nil, userInfo: ["identifier": identifier]
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

	/// What has been said in this window, most recent last — for a driver that
	/// has to say what somebody would have read.
	///
	/// A toast is drawn over the window for a few seconds and is gone; a run
	/// that captures a screenshot a moment later catches nothing, and "nothing
	/// was said" and "it was said and faded" look identical.
	private(set) var saidForTesting: [String] = []

	/// The last toast's action, so a driver can press what was offered.
	private var lastOfferForTesting: (() -> Void)?

	/// Presses the last offer, and says whether there was one.
	@discardableResult
	func pressLastOfferForTesting() -> Bool {
		guard let action = lastOfferForTesting else { return false }
		action()
		return true
	}

	func show(_ toast: Toast) {
		saidForTesting.append(
			[toast.title, toast.detail].compactMap { $0 }.joined(separator: " — ")
				+ (toast.actionTitle.map { " [button: \($0)]" } ?? "")
		)
		if toast.action != nil { lastOfferForTesting = toast.action }
		guard let contentView = window?.contentView else { return }

		let host = self.host ?? {
			let created = ToastHostView()
			created.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(created, positioned: .above, relativeTo: nil)
			NSLayoutConstraint.activate([
				created.trailingAnchor.constraint(
					equalTo: contentView.trailingAnchor, constant: -Theme.current.scaled(16)
				),
				created.bottomAnchor.constraint(
					equalTo: contentView.bottomAnchor, constant: -Theme.current.scaled(16)
				),
				created.widthAnchor.constraint(equalToConstant: Theme.current.scaled(340)),
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
		view.onAnswered = { [weak self, weak view] answer in
			// Off the screen first, then the answer: an answer that opens a sheet
			// or shuts a project down must not do it with the question it came
			// from still sitting in the corner underneath.
			if let view { self?.dismiss(view) }
			answer.perform()
		}

		host.add(view)
		shown.append(view)

		// The oldest goes when the stack is full: a corner filling with news is
		// its own kind of interruption.
		//
		// **A question is never the one that goes.** Pushing it off would answer
		// it with whichever answer silence amounts to, decided by how much else
		// happened to be going on — so the cap counts only what can be pushed off,
		// and a corner full of questions is allowed to be taller than four rather
		// than quietly shorter by one decision. In practice there is at most one
		// question per project at a time, because whatever asks it holds a guard
		// across the asking.
		while shown.count > Self.maximumVisible,
		      let oldest = shown.first(where: { $0.expires }) {
			dismiss(oldest)
		}

		guard toast.lifetime == .passing else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { [weak self, weak view] in
			guard let view, view.isPointedAt == false else { return }
			self?.dismiss(view)
		}
	}

	/// Takes a question off the screen without answering it.
	func withdraw(_ identifier: String) {
		for view in shown where view.question == identifier {
			dismiss(view)
			view.toldItWasWithdrawn()
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

	// MARK: - Testing

	/// What is in the corner, since a toast cannot be told from an empty corner
	/// in a window rendering that has not finished loading — and a question that
	/// is still there after eight seconds is the whole point of one.
	///
	/// The detail as well as the title. A refusal's whole promise is the
	/// sentence explaining it — 0442's undo says "“alpha.py” cannot go back:
	/// something else is there now", and a report that shows only "Nothing was
	/// put back" cannot tell that apart from a refusal that explained nothing.
	func reportForTesting() -> String {
		guard !shown.isEmpty else { return "TOASTS: (none)" }
		return "TOASTS: " + shown.map { view in
			let answers = view.answerTitlesForTesting
			let detail = view.detailForTesting ?? ""
			return "[\(view.titleForTesting)"
				+ (detail.isEmpty ? "" : ": \(detail)")
				+ (view.expires ? "" : " (stays)")
				+ (answers.isEmpty ? "" : " {\(answers.joined(separator: " | "))}")
				+ "]"
		}.joined(separator: " ")
	}

	/// Presses one of a question's answers by its words, the way a click does.
	@discardableResult
	func answerForTesting(_ title: String) -> Bool {
		guard let view = shown.first(where: { $0.answerTitlesForTesting.contains(title) }),
		      let answer = view.answerForTesting(title)
		else { return false }
		dismiss(view)
		answer.perform()
		return true
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

/// One toast: an icon, a line of text, and a way to close it — or, when it is a
/// question, the answers to it.
private final class ToastView: NSView {
	var onDismiss: (() -> Void)?
	var onOpen: (() -> Void)?
	var onAnswered: ((Toast.Answer) -> Void)?
	private(set) var isPointedAt = false

	private let toast: Toast
	private var trackingArea: NSTrackingArea?

	/// Whether the corner may take this one away to make room. A question may
	/// not be: see `ToastPresenter.show`.
	var expires: Bool { toast.lifetime == .passing }
	/// Not `identifier`: `NSView` already has one, of another type entirely.
	var question: String? { toast.identifier }
	var titleForTesting: String { toast.title }
	var detailForTesting: String? { toast.detail }
	var answerTitlesForTesting: [String] { toast.answers.map(\.title) }
	func answerForTesting(_ title: String) -> Toast.Answer? {
		toast.answers.first { $0.title == title }
	}

	func toldItWasWithdrawn() { toast.onWithdrawn?() }

	init(toast: Toast) {
		self.toast = toast
		super.init(frame: .zero)
		wantsLayer = true
		layer?.cornerRadius = Theme.current.scaled(8)
		layer?.backgroundColor = Theme.current.sidebarBackground.withAlphaComponent(0.98).cgColor
		layer?.borderWidth = 1
		layer?.borderColor = Theme.current.separator.cgColor
		layer?.shadowOpacity = 0.35
		layer?.shadowRadius = Theme.current.scaled(10)
		layer?.shadowOffset = CGSize(width: 0, height: -Theme.current.scaled(2))

		toolTip = toast.detail ?? toast.title
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(
			greaterThanOrEqualToConstant: Theme.current.scaled(44)
		).isActive = true
		buildAnswers()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// The paragraph and the buttons, for a toast that is a question.
	///
	/// Views rather than drawing, unlike the rest of this, and for a reason: the
	/// paragraph wraps and the buttons are the only part of a toast anybody has
	/// to hit accurately. Both are things auto layout already does properly and
	/// neither is worth measuring by hand in a corner 340 points wide.
	///
	/// **Stacked rather than in a row.** A devcontainer's `name` is a sentence —
	/// "Python, with its language server in the container" is what the example
	/// project calls its own — so three answers side by side would be three
	/// truncations. Down the side they read as a list of things somebody could
	/// say, which is what they are.
	private func buildAnswers() {
		guard !toast.answers.isEmpty else { return }
		let inset = Theme.current.scaled(12)
		let textX = inset + Theme.current.scaled(22)

		let body = NSTextField(wrappingLabelWithString: toast.detail ?? "")
		body.font = Theme.current.uiFont(11)
		body.textColor = Theme.current.gitIgnored
		body.isSelectable = false
		body.translatesAutoresizingMaskIntoConstraints = false
		addSubview(body)

		let column = NSStackView(views: toast.answers.map { answer in
			let button = DrawnButton(title: answer.title) { [weak self] in self?.onAnswered?(answer) }
			(button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
			return button
		})
		column.orientation = .vertical
		column.alignment = .leading
		column.spacing = Theme.current.scaled(4)
		column.translatesAutoresizingMaskIntoConstraints = false
		addSubview(column)

		var constraints = [
			body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textX),
			body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			body.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(28)),
			column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textX),
			column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
			column.topAnchor.constraint(equalTo: body.bottomAnchor, constant: Theme.current.scaled(8)),
			column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.current.scaled(10)),
		]
		// A name long enough to run off the end is clamped rather than allowed to
		// widen the corner: the toast is one width and everything in it lives
		// inside it.
		for button in column.arrangedSubviews {
			constraints.append(
				button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset)
			)
		}
		NSLayoutConstraint.activate(constraints)
	}

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
		// A question has no cross and no click-anywhere: the only ways out of it
		// are its answers, which is what "stays until it is answered" means. A
		// stray click while reaching for a button must not be one of them.
		guard expires else { return }
		let point = convert(event.locationInWindow, from: nil)
		if closeRect.contains(point) {
			onDismiss?()
			return
		}
		onOpen?()
		onDismiss?()
	}

	/// Scaled like everything else it sits beside.
	///
	/// The text already was — `uiFont` multiplies by the scale — so at 2x the
	/// words grew inside a box that had not, which is what "the toasts are not
	/// scaled" looks like: the same rectangle with type too large for it.
	private var closeRect: NSRect {
		let size = Theme.current.scaled(16)
		return NSRect(
			x: bounds.maxX - Theme.current.scaled(26), y: Theme.current.scaled(10),
			width: size, height: size
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		let inset = Theme.current.scaled(12)

		if let icon = Theme.symbol(
			"\(toast.kind.symbol)", size: Theme.current.scaled(12), color: toast.kind.tint
		) {
			let size = Theme.current.scaled(14)
			icon.drawFitted(
				in: NSRect(x: inset, y: Theme.current.scaled(13), width: size, height: size)
			)
		}

		let textX = inset + Theme.current.scaled(22)
		let title = NSAttributedString(string: toast.title, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		title.draw(in: NSRect(
			x: textX, y: Theme.current.scaled(11),
			width: max(0, bounds.width - textX - Theme.current.scaled(34)),
			height: title.size().height
		))

		// The paragraph and the buttons are subviews for a question; the cross and
		// the "click for details" hint are for things a click can dismiss, and a
		// question is not one.
		guard expires else { return }

		// A hint about what a click does, only when it does anything.
		if let hint = toast.actionTitle ?? (toast.detail?.isEmpty == false ? "Click for details" : nil) {
			let more = NSAttributedString(string: hint, attributes: [
				.font: Theme.current.uiFont(10),
				.foregroundColor: Theme.current.gitIgnored,
			])
			more.draw(at: NSPoint(
				x: textX, y: Theme.current.scaled(11) + title.size().height + Theme.current.scaled(2)
			))
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
		// A question is as tall as its paragraph and its answers make it, and
		// those are subviews with constraints; anything stated here would fight
		// them.
		guard expires else { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
		return NSSize(
			width: NSView.noIntrinsicMetric,
			height: toast.actionTitle != nil || toast.detail?.isEmpty == false ? 52 : 40
		)
	}
}
