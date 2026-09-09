import AppKit
import AbydosKit

/// ⌘Z for a tick made from a card.
///
/// A task ticked from a card's tip is one character written to `tasks.md` at
/// the moment of the click, and until 2026-09-09 there was no way back from it
/// but a text editor: the row went from the tip the instant it was ticked, and
/// neither the tip nor this pane owned an undo manager, so ⌘Z found nobody. A
/// slipped click on a list of thirty ticked the wrong one, and the wrong tick is
/// the one the house rules argue hardest against — a `[x]` means somebody could
/// go and look at it.
///
/// The pane owns the manager (`tickUndo`, answered from `undoManager`), so the
/// Edit menu's *Undo* reaches it while the board or the tip has the keyboard and
/// names the action *Tick*. Only this window's ticks are registered: a tick an
/// agent wrote is not this window's to undo. The registrations go with the
/// project, since a line number in a file of another project means nothing.
extension BacklogPane {
	/// A tick the tip wrote, to be taken back by ⌘Z. Registered with what the
	/// untick needs to refuse a line that has moved on: the file, the line, and
	/// the words that were ticked.
	func registerTick(file: URL, line: Int, text: String) {
		tickUndo.registerUndo(withTarget: self) { pane in
			pane.untick(file: file, line: line, text: text)
		}
		tickUndo.setActionName("Tick")
	}

	/// The untick itself, written the way the tick was — see
	/// `BacklogItem.unticking` — and registered again for redo.
	private func untick(file: URL, line: Int, text: String) {
		do {
			guard try BacklogItem.untick(line: line, text: text, in: file) else {
				onNotify?("That task has moved", "The line no longer reads as the task that was ticked; nothing was written.")
				reload()
				return
			}
			tickUndo.registerUndo(withTarget: self) { pane in pane.retick(file: file, line: line, text: text) }
			tickUndo.setActionName("Tick")
			reload()
		} catch {
			onNotify?("Could not write", file.path)
		}
	}

	/// Redo: the tick again, through the same check the tip makes.
	private func retick(file: URL, line: Int, text: String) {
		do {
			guard try BacklogItem.tick(line: line, in: file) else {
				onNotify?("That task has moved", "The line no longer reads as the open task; nothing was written.")
				reload()
				return
			}
			registerTick(file: file, line: line, text: text)
			reload()
		} catch {
			onNotify?("Could not write", file.path)
		}
	}

	/// Forgets the ticks of a project that is no longer showing.
	func forgetTickUndo() { tickUndo.removeAllActions() }
}
