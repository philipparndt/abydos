import AppKit

/// Every editor area open in the app, whichever window it belongs to.
///
/// A tab dragged from one window into another has to find the group it came
/// from, and that group belongs to a controller the receiving window knows
/// nothing about. Without this the drop is simply ignored, which is what made
/// a torn-off tab impossible to bring back.
@MainActor
enum EditorAreas {
	private final class Box {
		weak var area: EditorAreaController?
		init(_ area: EditorAreaController) { self.area = area }
	}

	private static var boxes: [Box] = []

	static func register(_ area: EditorAreaController) {
		boxes.removeAll { $0.area == nil }
		guard !boxes.contains(where: { $0.area === area }) else { return }
		boxes.append(Box(area))
	}

	static func unregister(_ area: EditorAreaController) {
		boxes.removeAll { $0.area == nil || $0.area === area }
	}

	/// The area holding the group with this identifier, and the group itself.
	static func owner(ofGroup id: UUID) -> (area: EditorAreaController, group: EditorViewController)? {
		for box in boxes {
			guard let area = box.area else { continue }
			if let group = area.group(withID: id) { return (area, group) }
		}
		return nil
	}
}
