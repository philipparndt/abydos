import AppKit

/// The payload and drop zones for dragging an editor tab.
enum EditorTabDrag {
	static let pasteboardType = NSPasteboard.PasteboardType("dev.philipparndt.ideai.editor-tab")

	/// Where a tab was dropped within a group, which decides what happens.
	enum Zone {
		/// Into the group's own tab strip.
		case center
		case left, right, top, bottom

		/// Split orientation this zone implies, if any.
		var splitsVertically: Bool? {
			switch self {
			case .left, .right: return true
			case .top, .bottom: return false
			case .center: return nil
			}
		}

		/// Whether the new group goes before the existing one.
		var insertsBefore: Bool {
			self == .left || self == .top
		}
	}

	struct Payload {
		let groupID: UUID
		let index: Int
		let path: String
	}

	static func payload(from pasteboard: NSPasteboard) -> Payload? {
		guard let data = pasteboard.data(forType: pasteboardType),
		      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let group = (raw["group"] as? String).flatMap(UUID.init(uuidString:)),
		      let index = raw["index"] as? Int
		else { return nil }
		return Payload(groupID: group, index: index, path: raw["path"] as? String ?? "")
	}

	/// Classifies a point within a view into a drop zone.
	///
	/// Edge bands rather than quadrants: a quadrant split makes it far too easy
	/// to split when you meant to reorder, since most of the view would be an
	/// edge. A generous centre keeps "move into this group" the default.
	static func zone(for point: NSPoint, in bounds: NSRect) -> Zone {
		let horizontalBand = bounds.width * 0.25
		let verticalBand = bounds.height * 0.25

		if point.x < horizontalBand { return .left }
		if point.x > bounds.maxX - horizontalBand { return .right }
		if point.y < verticalBand { return .top }
		if point.y > bounds.maxY - verticalBand { return .bottom }
		return .center
	}

	/// The area a zone would occupy, used to preview the drop.
	static func highlightRect(for zone: Zone, in bounds: NSRect) -> NSRect {
		switch zone {
		case .center: return bounds
		case .left:   return NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
		case .right:  return NSRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height)
		case .top:    return NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 2)
		case .bottom: return NSRect(x: 0, y: bounds.midY, width: bounds.width, height: bounds.height / 2)
		}
	}
}
