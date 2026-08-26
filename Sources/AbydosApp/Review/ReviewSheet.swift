import AppKit
import AbydosKit

/// Asking for the two things a review is written out of: a remark on a line,
/// and the verdict at the end.
///
/// Sheets rather than panes. Both are a moment somebody is in the middle of
/// something else — reading a diff — and a pane that stayed on screen would be
/// one more thing on a page that is already a list, a diff and a conversation.
enum ReviewSheet {
	/// Asks for a remark on one line, pre-filled with whatever was written
	/// there before.
	static func askForComment(
		on path: String,
		line: Int,
		existing: String,
		over window: NSWindow?,
		then write: @escaping (String) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = "Comment on line \(line)"
		// The file, because a page shows several and a sheet shows none.
		alert.informativeText = path
		alert.addButton(withTitle: existing.isEmpty ? "Write" : "Replace")
		alert.addButton(withTitle: "Cancel")

		let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 96))
		text.string = existing
		text.font = Theme.current.uiFont(12)
		text.isRichText = false
		text.isAutomaticQuoteSubstitutionEnabled = false
		let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 96))
		scroll.documentView = text
		scroll.hasVerticalScroller = true
		scroll.borderType = .bezelBorder
		alert.accessoryView = scroll

		// **Empty means take it back.** The way out of a remark somebody has
		// changed their mind about is to clear it, which is the same gesture as
		// writing one and needs no second command.
		let handle: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .alertFirstButtonReturn else { return }
			write(text.string)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: handle)
			window.makeFirstResponder(text)
		} else {
			handle(alert.runModal())
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
		let alert = NSAlert()
		alert.messageText = remarks == 0
			? "Submit a review"
			: "Submit a review with \(remarks) remark\(remarks == 1 ? "" : "s")"
		// **What has moved under it, said before anything is sent.** A review
		// that lands on the wrong lines is sent in the reviewer's name.
		alert.informativeText = warning ?? "The remarks are sent together, as one review."
		if warning != nil { alert.alertStyle = .warning }

		for verdict in ReviewVerdict.allCases {
			alert.addButton(withTitle: verdict.title)
		}
		alert.addButton(withTitle: "Cancel")

		let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 80))
		text.string = body
		text.font = Theme.current.uiFont(12)
		text.isRichText = false
		let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 80))
		scroll.documentView = text
		scroll.hasVerticalScroller = true
		scroll.borderType = .bezelBorder
		alert.accessoryView = scroll

		let handle: (NSApplication.ModalResponse) -> Void = { response in
			let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
			guard index >= 0, index < ReviewVerdict.allCases.count else { return }
			submit(ReviewVerdict.allCases[index], text.string)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: handle)
			window.makeFirstResponder(text)
		} else {
			handle(alert.runModal())
		}
	}
}
