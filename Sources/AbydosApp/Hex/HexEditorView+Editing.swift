import AbydosKit
import AppKit

/// Typing, deleting, and the pasteboard.
///
/// **Overwrite is the mode.** A hex editor is opened to change a byte far
/// more often than to add one, and an insert that shifts a gigabyte of
/// structure by one byte is almost always a mistake. Insert is a switch the
/// bar shows while it is on, and Delete removes bytes only while it is.
extension HexEditorView {
	// MARK: - Typing

	override func insertText(_ insertString: Any) {
		guard let text = insertString as? String, !text.isEmpty else { return }
		switch activeColumn {
		case .hex:
			for character in text { typeHex(character) }
		case .text:
			guard let data = text.data(using: encoding.stringEncoding), !data.isEmpty else {
				NSSound.beep()
				return
			}
			put(data)
		}
	}

	private func typeHex(_ character: Character) {
		guard let nibble = character.hexDigitValue else {
			if character == " " { return }
			NSSound.beep()
			return
		}
		if let high = pendingNibble {
			pendingNibble = nil
			put(Data([high << 4 | UInt8(nibble)]))
		} else {
			// The first half: the byte is not changed until the second half
			// arrives, so ⎋ can take it back and a half byte is never written.
			if let selection {
				// Typing onto a selection begins at its start, and in insert
				// mode replaces it.
				if insertMode {
					document.delete(selection)
					documentChanged()
				}
				moveCaret(to: selection.lowerBound, extending: false)
			}
			pendingNibble = UInt8(nibble)
			needsDisplay = true
		}
	}

	/// Writes bytes at the caret: over what is there, or in front of it in
	/// insert mode, or over the selection when there is one.
	func put(_ data: Data) {
		guard !data.isEmpty else { return }
		undo.beginUndoGrouping()
		defer { undo.endUndoGrouping() }
		if let selection {
			if insertMode {
				document.replace(selection, with: data)
			} else {
				document.overwrite(data, at: selection.lowerBound)
			}
			let at = selection.lowerBound + data.count
			anchor = nil
			caret = at
		} else if insertMode {
			document.insert(data, at: caret)
			caret += data.count
		} else {
			document.overwrite(data, at: caret)
			caret += data.count
		}
		documentChanged()
		scrollCaretToVisible()
	}

	// MARK: - Deleting

	func deleteBackward() {
		pendingNibble = nil
		guard insertMode else { return }
		if let selection {
			document.delete(selection)
			anchor = nil
			caret = selection.lowerBound
		} else if caret > 0 {
			document.delete((caret - 1)..<caret)
			caret -= 1
		}
		documentChanged()
	}

	func deleteForward() {
		pendingNibble = nil
		guard insertMode else { return }
		if let selection {
			document.delete(selection)
			anchor = nil
			caret = selection.lowerBound
		} else if caret < document.count {
			document.delete(caret..<(caret + 1))
		}
		documentChanged()
	}

	// MARK: - The pasteboard

	/// The shapes a selection is copied in.
	enum CopyShape: String, CaseIterable {
		case hex = "Copy as Hex"
		case text = "Copy as Text"
		case cArray = "Copy as C Array"
		case base64 = "Copy as Base64"
	}

	/// The bytes the copy is of: the selection, or the byte at the caret.
	private var copied: Data {
		document.bytes(in: selection ?? caret..<min(document.count, caret + 1))
	}

	func text(for shape: CopyShape, of bytes: Data) -> String {
		switch shape {
		case .hex:
			return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
		case .text:
			return bytes.map { encoding.isPrintable($0) ? (String(data: Data([$0]), encoding: encoding == .latin1 ? .isoLatin1 : .ascii) ?? ".") : "." }.joined()
		case .cArray:
			return "{ " + bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ") + " }"
		case .base64:
			return bytes.base64EncodedString()
		}
	}

	func copy(as shape: CopyShape) {
		let bytes = copied
		guard !bytes.isEmpty else { return }
		let board = NSPasteboard.general
		board.clearContents()
		board.setString(text(for: shape, of: bytes), forType: .string)
		// The raw bytes go along too, so a paste into another hex tab is
		// bytes and not a re-parse of the text.
		board.setData(bytes, forType: .init("public.data"))
	}

	@objc func copy(_ sender: Any?) {
		copy(as: activeColumn == .hex ? .hex : .text)
	}

	@objc func copyAsHex(_ sender: Any?) { copy(as: .hex) }
	@objc func copyAsText(_ sender: Any?) { copy(as: .text) }
	@objc func copyAsCArray(_ sender: Any?) { copy(as: .cArray) }
	@objc func copyAsBase64(_ sender: Any?) { copy(as: .base64) }

	@objc func cut(_ sender: Any?) {
		copy(sender)
		if insertMode { deleteForward() }
	}

	@objc func paste(_ sender: Any?) {
		paste(from: NSPasteboard.general)
	}

	/// Raw bytes when the board has them, hex text when it parses as hex —
	/// whitespace, `0x` prefixes and commas ignored — and the text's own
	/// bytes otherwise.
	func paste(from board: NSPasteboard) {
		if let data = board.data(forType: .init("public.data")), !data.isEmpty {
			put(data)
			return
		}
		guard let string = board.string(forType: .string), !string.isEmpty else { return }
		put(Self.bytes(fromPasted: string, encoding: encoding))
	}

	static func bytes(fromPasted string: String, encoding: ByteEncoding) -> Data {
		if case .success(let pattern) = BytePattern.hex(string), pattern.fixed.allSatisfy({ $0 }) {
			return Data(pattern.bytes)
		}
		return string.data(using: encoding.stringEncoding) ?? Data(string.utf8)
	}

	@objc func toggleInsertMode(_ sender: Any?) {
		setInsertMode(!insertMode)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		let menu = NSMenu()
		func add(_ title: String, _ action: Selector, enabled: Bool = true) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			menu.addItem(item)
		}
		let hasBytes = document.count > 0
		add(CopyShape.hex.rawValue, #selector(copyAsHex(_:)), enabled: hasBytes)
		add(CopyShape.text.rawValue, #selector(copyAsText(_:)), enabled: hasBytes)
		add(CopyShape.cArray.rawValue, #selector(copyAsCArray(_:)), enabled: hasBytes)
		add(CopyShape.base64.rawValue, #selector(copyAsBase64(_:)), enabled: hasBytes)
		menu.addItem(.separator())
		add("Paste", #selector(paste(_:)))
		add("Select All", #selector(selectAll(_:)), enabled: hasBytes)
		menu.addItem(.separator())
		let insert = NSMenuItem(title: "Insert Mode", action: #selector(toggleInsertMode(_:)), keyEquivalent: "")
		insert.target = self
		insert.state = insertMode ? .on : .off
		menu.addItem(insert)
		return menu
	}

}

extension HexEditorView: NSMenuItemValidation {
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		if item.action == #selector(toggleInsertMode(_:)) { item.state = insertMode ? .on : .off }
		return true
	}
}
