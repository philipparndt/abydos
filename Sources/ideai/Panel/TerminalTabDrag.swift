import AppKit

/// Dragging a terminal tab: what travels on the pasteboard, and where a drop
/// means what.
///
/// Its own pasteboard type rather than the editor's. A terminal and a source
/// file are not interchangeable — a shell dropped into an editor group would
/// have to become a tab that shows a process, which is a different app — so
/// the two kinds of tab simply do not accept each other's drags.
enum TerminalTabDrag {
	static let pasteboardType = NSPasteboard.PasteboardType("dev.philipparndt.ideai.terminal-tab")

	/// Where a tab was let go inside the panel.
	enum Zone {
		/// Onto the pane itself: just show it.
		case center
		/// Onto an edge: beside what is there, in a column of its own.
		case left, right

		var insertsBefore: Bool { self == .left }
	}

	struct Payload {
		let panelID: UUID
		let index: Int
	}

	static func payload(from pasteboard: NSPasteboard) -> Payload? {
		guard let data = pasteboard.data(forType: pasteboardType),
		      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let panel = (raw["panel"] as? String).flatMap(UUID.init(uuidString:)),
		      let index = raw["index"] as? Int
		else { return nil }
		return Payload(panelID: panel, index: index)
	}

	static func item(panelID: UUID, index: Int) -> NSPasteboardItem? {
		let item = NSPasteboardItem()
		guard let data = try? JSONSerialization.data(
			withJSONObject: ["panel": panelID.uuidString, "index": index]
		) else { return nil }
		item.setData(data, forType: pasteboardType)
		return item
	}

	/// Which part of the pane a point is in.
	///
	/// Only the left and right quarter split. Terminals side by side is what a
	/// person wants — logs beside a shell — and above-and-below inside a strip
	/// that is already short would give each of them nothing.
	static func zone(for point: NSPoint, in bounds: NSRect) -> Zone {
		let band = bounds.width * 0.25
		if point.x < band { return .left }
		if point.x > bounds.maxX - band { return .right }
		return .center
	}

	static func highlightRect(for zone: Zone, in bounds: NSRect) -> NSRect {
		switch zone {
		case .center: return bounds
		case .left: return NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
		case .right: return NSRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height)
		}
	}
}
