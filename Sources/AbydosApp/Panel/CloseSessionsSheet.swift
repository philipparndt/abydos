import AppKit
import AbydosKit

/// The sheet behind "Close Sessions…" on the session tag's menu: every session
/// the server has, a box beside each, and one button that kills the ticked
/// ones.
///
/// An `NSAlert` with a list in it rather than a window of its own, like the
/// pull sheet and the backup sweep: the question is short, the answer is a
/// set of ticks, and a sheet is dismissed the way every other sheet here is.
/// What is offered and what may be closed is decided in `TmuxSessionClosing`;
/// this draws it.
@MainActor
enum CloseSessionsSheet {
	/// What the sheet answers in a driven run, as the names to tick. A driven
	/// run that opens a sheet is a driven run that stops.
	static var answerForTesting: [String]?

	/// A server's worth of sessions as they actually accumulate, for
	/// `--close-sessions`: the long-lived one with the work in it, and the
	/// one-window ones each project's terminal left behind.
	static var sampleForTesting: [TmuxMirror.SessionSummary] {
		[
			.init(name: "work", windowCount: 8, isAttached: true, created: 1),
			.init(name: "abydos", windowCount: 1, isAttached: false, created: 2),
			.init(name: "musik-as-text", windowCount: 1, isAttached: false, created: 3),
			.init(name: "songs", windowCount: 1, isAttached: false, created: 4),
			.init(name: "other", windowCount: 2, isAttached: true, created: 5),
			.init(name: "rebase-demo", windowCount: 1, isAttached: false, created: 6),
			.init(name: "big-repo", windowCount: 1, isAttached: false, created: 7),
			.init(name: "grass", windowCount: 1, isAttached: false, created: 8),
			.init(name: "export", windowCount: 1, isAttached: false, created: 9),
			.init(name: "cuts", windowCount: 1, isAttached: false, created: 10),
			.init(name: "audio-demo", windowCount: 1, isAttached: false, created: 11),
			.init(name: "plain-folder", windowCount: 1, isAttached: false, created: 12),
			.init(name: "rusty", windowCount: 1, isAttached: false, created: 13),
			.init(name: "blank", windowCount: 1, isAttached: false, created: 14),
		]
	}

	/// Puts the sheet up and hands back what was chosen, already filtered to
	/// what may be closed. Nothing is called for a cancel.
	static func ask(
		_ offers: [TmuxSessionClosing.Offer],
		over window: NSWindow?,
		then close: @escaping ([String]) -> Void
	) {
		if let canned = answerForTesting {
			close(TmuxSessionClosing.closable(canned, among: offers))
			return
		}

		let alert = NSAlert()
		alert.messageText = "Close tmux sessions"
		alert.informativeText = "A closed session takes every window in it, and whatever "
			+ "is running there. The session this window's tabs are showing stays."
		let closeButton = alert.addButton(withTitle: "Close")
		closeButton.isEnabled = false
		alert.addButton(withTitle: "Cancel")

		let picker = Picker(offers: offers, enabling: closeButton)
		alert.accessoryView = picker.view

		let answer: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .alertFirstButtonReturn else { return }
			close(TmuxSessionClosing.closable(picker.ticked, among: offers))
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: answer)
		} else {
			answer(alert.runModal())
		}
	}

	/// The list of boxes, and the button that lights up once one is ticked.
	///
	/// An object rather than closures because the boxes need a target, and a
	/// target has to be something that lives as long as the sheet.
	/// Isolated in its own right: a type nested in a `@MainActor` enum does not
	/// inherit that isolation, and every line of this touches AppKit.
	@MainActor
	private final class Picker: NSObject {
		let view: NSView
		private let boxes: [NSButton]
		private let offers: [TmuxSessionClosing.Offer]
		private let closeButton: NSButton
		private let selectAll: NSButton

		init(offers: [TmuxSessionClosing.Offer], enabling closeButton: NSButton) {
			self.offers = offers
			self.closeButton = closeButton

			let theme = Theme.current
			boxes = offers.map { offer in
				let box = NSButton(checkboxWithTitle: offer.name, target: nil, action: nil)
				// The name in one weight and what stands beside it in another,
				// so a row reads as a name with a note rather than as a
				// sentence.
				let title = NSMutableAttributedString(
					string: offer.name,
					attributes: [.font: theme.uiFont(13), .foregroundColor: NSColor.labelColor]
				)
				title.append(NSAttributedString(
					string: "   " + offer.detail,
					attributes: [
						.font: theme.uiFont(11),
						.foregroundColor: NSColor.secondaryLabelColor,
					]
				))
				box.attributedTitle = title
				box.isEnabled = offer.isClosable
				box.toolTip = offer.isClosable
					? nil
					: "This window's tabs are showing it. Closing its last window closes it."
				return box
			}

			selectAll = NSButton(title: "Select All", target: nil, action: nil)
			selectAll.bezelStyle = .rounded
			selectAll.controlSize = .small
			selectAll.font = theme.uiFont(11)
			selectAll.isEnabled = offers.contains(where: \.isClosable)

			let list = NSStackView(views: boxes)
			list.orientation = .vertical
			list.alignment = .leading
			list.spacing = 4
			list.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
			let listHeight = list.fittingSize.height
			list.frame = NSRect(x: 0, y: 0, width: 360, height: listHeight)

			// Flipped, so a list taller than the scroll view starts at its top
			// rather than at its bottom: the first session is the one somebody
			// expects to see first.
			let document = FlippedView(frame: list.frame)
			document.addSubview(list)
			let scroll = NSScrollView()
			scroll.documentView = document
			scroll.hasVerticalScroller = listHeight > 280
			scroll.borderType = .bezelBorder
			scroll.drawsBackground = false
			let scrollHeight = min(listHeight, 280)

			let stack = NSStackView(views: [selectAll, scroll])
			stack.orientation = .vertical
			stack.alignment = .leading
			stack.spacing = 6
			scroll.translatesAutoresizingMaskIntoConstraints = false
			scroll.widthAnchor.constraint(equalToConstant: 360).isActive = true
			scroll.heightAnchor.constraint(equalToConstant: scrollHeight).isActive = true
			stack.frame = NSRect(x: 0, y: 0, width: 360, height: scrollHeight + 30)
			view = stack

			super.init()
			for box in boxes {
				box.target = self
				box.action = #selector(toggled)
			}
			selectAll.target = self
			selectAll.action = #selector(selectAllPressed)
		}

		/// The names whose box is ticked, in the order they are listed.
		var ticked: [String] {
			zip(boxes, offers).compactMap { box, offer in box.state == .on ? offer.name : nil }
		}

		@objc private func toggled() {
			closeButton.isEnabled = !ticked.isEmpty
			refreshSelectAll()
		}

		/// Ticks every box that can be ticked, or clears them all when they
		/// already are: one button that means whichever of the two is useful.
		@objc private func selectAllPressed() {
			let closable = zip(boxes, offers).filter { $0.1.isClosable }.map(\.0)
			let allOn = closable.allSatisfy { $0.state == .on }
			for box in closable { box.state = allOn ? .off : .on }
			toggled()
		}

		private func refreshSelectAll() {
			let closable = zip(boxes, offers).filter { $0.1.isClosable }.map(\.0)
			let allOn = !closable.isEmpty && closable.allSatisfy { $0.state == .on }
			selectAll.title = allOn ? "Select None" : "Select All"
		}
	}

	private final class FlippedView: NSView {
		override var isFlipped: Bool { true }
	}
}
