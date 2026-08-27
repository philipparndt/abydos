import AppKit
import AbydosKit

/// Asking for the two things a review is written out of: a remark on some
/// lines, and the verdict at the end.
///
/// **Not an `NSAlert`.** The first version of both of these was one, with the
/// text field handed over as an `accessoryView`, and it looked exactly like
/// what it was: a system error dialog with a box wedged into it. An alert sizes
/// its accessory to whatever it feels like — the box came out clipped at the
/// bottom, so the second line of a remark was somewhere under the buttons — and
/// it stacks its buttons vertically once there are more than two, which turned
/// three verdicts into a column of pills with the destructive one at the
/// bottom.
///
/// So these are plain sheets: a window, laid out here, with the text taking the
/// room and the buttons on one row at the foot of it. Sheets rather than panes
/// because both are a moment somebody is in the middle of something else —
/// reading a diff — and a pane that stayed would be one more thing on a page
/// that is already a list, a diff and a conversation.
enum ReviewSheet {
	/// Asks for a remark on one line or a run of them, pre-filled with whatever
	/// was written there before.
	static func askForComment(
		on path: String,
		from: Int,
		to: Int,
		existing: String,
		over window: NSWindow?,
		then write: @escaping (String) -> Void
	) {
		let place = from == to ? "line \(from)" : "lines \(from)–\(to)"
		let sheet = Sheet(
			title: "Comment on \(place)",
			subtitle: path,
			body: existing,
			// **Empty means take it back.** The way out of a remark somebody has
			// changed their mind about is to clear it, which is the same gesture
			// as writing one and needs no second command.
			hint: existing.isEmpty ? nil : "Clearing the text takes the remark back.",
			buttons: [existing.isEmpty ? "Write" : "Save"],
			height: 150
		)
		sheet.present(over: window) { chosen, text in
			guard chosen == 0 else { return }
			write(text)
		}
	}

	/// Asks for the verdict and the covering note.
	///
	/// Three buttons because there are three answers, and they are GitHub's
	/// three. Approving with nothing written is a review, which is why the note
	/// is optional.
	static func askForVerdict(
		remarks: Int,
		body: String,
		warning: String?,
		over window: NSWindow?,
		then submit: @escaping (ReviewVerdict, String) -> Void
	) {
		let sheet = Sheet(
			title: "Submit a review",
			subtitle: remarks == 0
				? "Nothing is written on a line. The note below is the whole review."
				: "\(remarks) remark\(remarks == 1 ? "" : "s") on lines, sent together as one review.",
			body: body,
			// **What has moved under it, said before anything is sent.** A
			// review that lands on the wrong lines is sent in the reviewer's
			// name.
			hint: warning,
			hintIsWarning: warning != nil,
			buttons: ReviewVerdict.allCases.map(\.title),
			height: 190
		)
		sheet.present(over: window) { chosen, text in
			guard chosen >= 0, chosen < ReviewVerdict.allCases.count else { return }
			submit(ReviewVerdict.allCases[chosen], text)
		}
	}

	/// A sheet with a heading, a line under it, a text box that gets the room,
	/// and a row of buttons.
	private final class Sheet: NSObject, NSTextViewDelegate {
		private let window: NSWindow
		private let text = NSTextView()
		private var answer: ((Int, String) -> Void)?
		/// Which button each index is, so ⎋ and ⏎ can find them.
		private var buttons: [NSButton] = []

		init(
			title: String,
			subtitle: String,
			body: String,
			hint: String? = nil,
			hintIsWarning: Bool = false,
			buttons titles: [String],
			height: CGFloat
		) {
			let width = Theme.current.scaled(520)
			window = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: width, height: height + 120),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			super.init()

			let content = ColoredView(color: Theme.current.sidebarBackground)
			window.contentView = content

			let heading = NSTextField(labelWithString: title)
			heading.font = Theme.current.uiFont(15, weight: .semibold)
			heading.textColor = Theme.current.sidebarText

			let under = NSTextField(wrappingLabelWithString: subtitle)
			under.font = Theme.current.uiFont(11.5)
			under.textColor = Theme.current.gitIgnored

			text.string = body
			text.font = Theme.terminalFont(size: Theme.current.fontSize)
			text.textColor = Theme.current.sidebarText
			text.backgroundColor = Theme.current.editorBackground
			text.insertionPointColor = Theme.current.sidebarText
			text.isRichText = false
			text.isAutomaticQuoteSubstitutionEnabled = false
			text.isAutomaticDashSubstitutionEnabled = false
			text.textContainerInset = NSSize(width: 6, height: 6)
			text.isVerticallyResizable = true
			text.autoresizingMask = [.width]
			text.textContainer?.widthTracksTextView = true

			let scroll = NSScrollView()
			scroll.documentView = text
			scroll.hasVerticalScroller = true
			scroll.drawsBackground = true
			scroll.backgroundColor = Theme.current.editorBackground
			scroll.borderType = .noBorder
			scroll.wantsLayer = true
			scroll.layer?.cornerRadius = 5
			scroll.layer?.borderWidth = 1
			scroll.layer?.borderColor = Theme.current.gitIgnored.withAlphaComponent(0.35).cgColor

			let note = NSTextField(wrappingLabelWithString: hint ?? "")
			note.font = Theme.current.uiFont(11)
			note.textColor = hintIsWarning ? Theme.current.gitConflict : Theme.current.gitIgnored
			note.isHidden = hint == nil

			// The verdicts on the right, in GitHub's order, with the last one —
			// the affirmative — where the return key is expected. Cancel on the
			// left, away from them.
			let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelled))
			cancel.bezelStyle = .rounded
			cancel.keyEquivalent = "\u{1b}"

			let row = NSStackView(views: [cancel])
			row.orientation = .horizontal
			row.spacing = Theme.current.scaled(8)
			row.setViews([cancel], in: .leading)
			for (index, title) in titles.enumerated() {
				let button = NSButton(title: title, target: self, action: #selector(chosen(_:)))
				button.bezelStyle = .rounded
				button.tag = index
				if index == titles.count - 1 { button.keyEquivalent = "\r" }
				buttons.append(button)
				row.addView(button, in: .trailing)
			}

			for view in [heading, under, scroll, note, row] as [NSView] {
				content.addSubview(view)
				view.translatesAutoresizingMaskIntoConstraints = false
			}

			let inset = Theme.current.scaled(18)
			NSLayoutConstraint.activate([
				heading.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
				heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
				heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),

				under.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
				under.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
				under.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

				scroll.topAnchor.constraint(equalTo: under.bottomAnchor, constant: inset * 0.6),
				scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
				scroll.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
				// **The box gets the room**, which is the whole complaint about
				// the alert this replaces: it is what somebody is here to fill
				// in, so it takes the height and the buttons take what is left.
				scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: height),

				note.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
				note.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
				note.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

				row.topAnchor.constraint(equalTo: note.bottomAnchor, constant: inset * 0.6),
				row.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
				row.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
				row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset),
			])

			// **Sized from the layout, not from a number.** The complaint that
			// led here was a text box clipped at the bottom, which is what
			// happens whenever a fixed height and a set of constraints disagree
			// about how much room the contents need. Asking the content view is
			// the only way the two cannot disagree.
			content.layoutSubtreeIfNeeded()
			window.setContentSize(NSSize(
				width: width,
				height: max(content.fittingSize.height, height + 120)
			))
		}

		func present(over host: NSWindow?, then answer: @escaping (Int, String) -> Void) {
			self.answer = answer
			guard let host else {
				// No window to hang it off — a driven run, or a pane not on
				// screen. Answering nothing is better than a modal nobody can
				// see and nobody can dismiss.
				answer(-1, text.string)
				return
			}
			host.beginSheet(window) { _ in }
			window.makeFirstResponder(text)
			// So the sheet is not held only by AppKit for the moment between
			// being shown and being answered.
			Self.showing = self
		}

		/// The one on screen. A sheet has no other owner while it is up.
		private static var showing: Sheet?

		@objc private func cancelled() { finish(-1) }

		@objc private func chosen(_ sender: NSButton) { finish(sender.tag) }

		private func finish(_ index: Int) {
			let said = text.string
			window.sheetParent?.endSheet(window)
			Self.showing = nil
			answer?(index, said)
			answer = nil
		}
	}
}
