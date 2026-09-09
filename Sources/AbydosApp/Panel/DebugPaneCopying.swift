import AppKit
import AbydosKit

/// The variables tree's context menu: copying a name, a value or both, and
/// watching whatever was clicked.
///
/// Every one of these acts on the row the menu was opened on rather than on the
/// selection, because a right-click on an unselected row is a right-click on
/// that row — which is what `clickedRowItem` is for.
extension DebugPane {
	// MARK: - Copying

	func makeVariablesMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	/// The row the menu was opened on, whichever kind it is.
	var clickedRowItem: Any? {
		let row = variablesOutline.clickedRow >= 0
			? variablesOutline.clickedRow
			: variablesOutline.selectedRow
		guard row >= 0 else { return nil }
		return variablesOutline.item(atRow: row)
	}

	func copy(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc func copyValue() {
		switch clickedRowItem {
		case let node as VariableNode: copy(node.variable.value)
		case let node as WatchNode: copy(node.watch.value ?? "")
		default: break
		}
	}

	@objc func copyName() {
		switch clickedRowItem {
		case let node as VariableNode: copy(node.variable.name)
		case let node as WatchNode: copy(node.watch.expression)
		default: break
		}
	}

	/// Copies `name: value`, which is what goes into a note or a message.
	@objc func copyBoth() {
		switch clickedRowItem {
		case let node as VariableNode: copy("\(node.variable.name) = \(node.variable.value)")
		case let node as WatchNode: copy("\(node.watch.expression) = \(node.watch.value ?? "")")
		default: break
		}
	}

	/// Watches whatever was clicked, so a local can be followed across frames.
	@objc func watchClicked() {
		switch clickedRowItem {
		case let node as VariableNode: session?.addWatch(node.variable.name)
		case let node as WatchNode: session?.addWatch(node.watch.expression)
		default: break
		}
	}

	@objc func removeClickedWatch() {
		guard let node = clickedRowItem as? WatchNode else { return }
		session?.removeWatch(id: node.watch.id)
	}

	@objc func removeAllWatches() {
		session?.removeAllWatches()
	}
}
