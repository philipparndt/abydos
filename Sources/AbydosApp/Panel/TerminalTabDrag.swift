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
		/// Which column of that panel it was dragged from. A panel that is
		/// split has a strip per column, and an index means nothing without
		/// knowing which strip it counts along.
		let column: Int
		let index: Int
	}

	static func payload(from pasteboard: NSPasteboard) -> Payload? {
		guard let data = pasteboard.data(forType: pasteboardType),
		      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let panel = (raw["panel"] as? String).flatMap(UUID.init(uuidString:)),
		      let index = raw["index"] as? Int
		else { return nil }
		return Payload(panelID: panel, column: raw["column"] as? Int ?? 0, index: index)
	}

	static func item(panelID: UUID, column: Int, index: Int) -> NSPasteboardItem? {
		let item = NSPasteboardItem()
		guard let data = try? JSONSerialization.data(
			withJSONObject: ["panel": panelID.uuidString, "column": column, "index": index]
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


/// A terminal taken out of wherever it was.
struct DetachedTerminal {
	let pane: TerminalPane
	let title: String
	let isRenamed: Bool
	let directory: URL?
}

/// Something a terminal can be dragged out of.
@MainActor
protocol TerminalDragSource: AnyObject {
	/// Gives up the terminal at this index, removing it from the source.
	func detachTerminal(at index: Int) -> DetachedTerminal?
}

/// Who owns which terminals, so a tab dropped in one window can be found in
/// another.
///
/// A drag carries an identifier, not an object: the pasteboard holds bytes.
/// This is how those bytes find the panel — or the torn-off window — that the
/// tab came from, which is what lets a terminal be dragged back in.
@MainActor
enum TerminalDragSources {
	private static var sources: [UUID: WeakSource] = [:]

	private struct WeakSource {
		weak var value: (any TerminalDragSource)?
	}

	static func register(_ source: any TerminalDragSource, as id: UUID) {
		sources[id] = WeakSource(value: source)
		sources = sources.filter { $0.value.value != nil }
	}

	static func unregister(_ id: UUID) {
		sources.removeValue(forKey: id)
	}

	static func source(for id: UUID) -> (any TerminalDragSource)? {
		sources[id]?.value
	}
}
