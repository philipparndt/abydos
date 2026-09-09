import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// Debugging in the editor: the breakpoints in the gutter, the line execution
/// stopped on, and the values shown beside the code.
extension EditorViewController {
	// MARK: - Debugging

	/// Sets the breakpoints to draw, keyed by absolute path.
	func setBreakpoints(_ breakpoints: [String: [Int: CodeView.BreakpointMark]]) {
		breakpointsByFile = breakpoints
		for tab in tabs { applyDebugState(to: tab) }
	}

	/// Lines with a play button, keyed by absolute file path.
	func setRunnableLines(_ lines: [String: Set<Int>]) {
		runnableLinesByFile = lines
		for tab in tabs { applyDebugState(to: tab) }
	}

	/// The variables of the frame execution is stopped in, to be drawn beside
	/// the code that names them.
	///
	/// The same route the marker, the breakpoints and the runnable lines take:
	/// one function pushes per-file debug state into every tab, so a second way
	/// in would be a second place for a tab to be missed.
	func setInlineValues(_ values: InlineValueSet?) {
		// A tree of values from a program that is running again is worse than no
		// tree: the values leaving is exactly the moment it goes.
		if values == nil { dismissOpenValue() }
		inlineValues = values
		for tab in tabs { applyDebugState(to: tab) }
	}

	/// Marks where execution stopped, clearing it elsewhere.
	func setExecutionLocation(file: String?, line: Int?) {
		if let file, let line {
			executionLocation = (file, line)
		} else {
			executionLocation = nil
		}
		for tab in tabs { applyDebugState(to: tab) }
	}

	func applyDebugState(to tab: Tab) {
		guard let codeView = tab.codeView else { return }
		let path = FilePath.canonical(tab.url)

		// Breakpoints are stored the way a debug adapter numbers lines, from 1;
		// the view draws rows, which start at 0. The execution line below has
		// always converted — breakpoints did not, so every marker was drawn one
		// line below the line it was set on.
		let stored = breakpointsByFile[path] ?? [:]
		var marks: [Int: CodeView.BreakpointMark] = [:]
		for (line, mark) in stored { marks[line - 1] = mark }
		codeView.setBreakpoints(marks)
		// Keyed by the resolved path: /tmp is a symlink to /private/tmp, and a
		// project reached through any symlinked directory would otherwise match
		// nothing and silently show no play buttons.
		codeView.setRunnableLines(runnableLinesByFile[path] ?? [])

		// The marker belongs only in the file execution actually stopped in.
		if let location = executionLocation, location.file == path {
			codeView.setExecutionLine(location.line - 1)
		} else {
			codeView.setExecutionLine(nil)
		}

		// And so do the values: a variable is in scope in the frame it belongs
		// to, so every other file gets none. Canonicalised here for the same
		// reason the breakpoints are — /tmp is a symlink to /private/tmp, and a
		// frame reached through a symlinked directory would match nothing.
		if let values = inlineValues, FilePath.canonical(URL(fileURLWithPath: values.file)) == path {
			codeView.setInlineValues(values.values)
		} else {
			codeView.setInlineValues(nil)
		}
	}

	/// Draws every row of the file in front, which is what scrolling it does.
	func scrollStoppedFileForTesting() {
		guard let codeView = activeTab?.codeView else { return }
		codeView.drawEveryRowForTesting()
	}

	/// Opens the first value on the stopped line that has something under it.
	///
	/// Every tab rather than the one in front, for the same reason the values
	/// report reads them all: stopping moves the keyboard about, and "the active
	/// tab" is not a thing worth making a driven check depend on.
	func openFirstInlineValueForTesting() -> String? {
		for tab in tabs {
			guard let codeView = tab.codeView,
			      let found = codeView.firstOpenableInlineValueForTesting()
			else { continue }
			openInlineValue(found.hint, at: found.rect, over: codeView)
			return found.hint.text
		}
		return nil
	}

	func openValueReportForTesting() -> String {
		guard let popup = openValuePopup else { return "nothing is open" }
		return "\(popup.placementForTesting)\n\(popup.reportForTesting)"
	}

	/// Sends selectors at the editor the way a key binding would, and says what
	/// was named — for `--unhandled-motions`.
	///
	/// **Not a key press, and the reason is the finding.** The four motions this
	/// editor still does not handle are all `select…` and none of them has a
	/// default binding on this system, so there is no key that reaches them —
	/// which is exactly why nobody noticed they were missing. What can be driven
	/// is the path a binding would take: `doCommand(by:)`, the same function the
	/// key would arrive at.
	func exerciseUnhandledMotionsForTesting() -> String {
		guard let codeView = activeTab?.codeView else { return "no file in front" }
		for name in ["selectWord:", "selectParagraph:", "noop:", "complete:", "selectWord:"] {
			codeView.doCommand(by: Selector(name))
		}
		return UnhandledMotions.reportForTesting
	}

	/// Walks what is open with the arrow keys, and says where it ended up.
	func walkOpenValueForTesting(_ keys: [String]) -> String {
		openValuePopup?.walkForTesting(keys) ?? "nothing is open"
	}

	/// The same, but reported after whatever the walk asked for has arrived.
	func walkOpenValueThenSettleForTesting(_ keys: [String], then say: @escaping (String) -> Void) {
		guard let popup = openValuePopup else { return say("nothing is open") }
		popup.walkThenSettleForTesting(keys, then: say)
	}

	/// What colour the opened value draws its selected row in.
	func openValueSelectionColourForTesting() -> String {
		openValuePopup?.selectionColourForTesting ?? "nothing is open"
	}

	/// What the opened value's menu offers, and what it copies.
	func openValueMenuForTesting() -> String {
		guard let popup = openValuePopup else { return "nothing is open" }
		return "menu: \(popup.menuTitlesForTesting)\n"
			+ "  name -> \(popup.copyForTesting("name"))\n"
			+ "  value -> \(popup.copyForTesting("value"))\n"
			+ "  both -> \(popup.copyForTesting("both"))\n"
			+ "  tree -> \(popup.copyForTesting("tree"))"
	}

	/// Opens a field inside what is open, for the claim about lazy children.
	func expandInsideOpenValueForTesting() -> String {
		openValuePopup?.expandFirstChildForTesting() ?? "nothing is open"
	}

	/// What a click on the value named would do, without doing it — for the
	/// claim that a piece of text is not a door.
	func inlineValueClickForTesting(named name: String) -> String {
		for tab in tabs {
			guard let codeView = tab.codeView,
			      let answer = codeView.clickAnswerForTesting(named: name)
			else { continue }
			return answer
		}
		return "no value called \(name) is on screen"
	}


	/// Opens a value beside the code into a tree of its own.
	func openInlineValue(_ hint: InlineValueHint, at rect: NSRect, over view: NSView) {
		guard let onVariableChildren else { return }
		openValuePopup?.dismiss()
		// **The variable, not the hint.** A hint carries the value cut to what
		// fits at the end of a line — ellipsis and all — which is right on the
		// line and wrong everywhere else: copying one out of this window handed
		// back `…` in the middle of a struct. The frame's own answer is what the
		// window is opened on, and the adapter's children carry their full
		// values already.
		let root = inlineValues?.values[hint.name] ?? Variable(
			name: hint.name,
			value: hint.value,
			type: nil,
			variablesReference: hint.variablesReference
		)
		let popup = VariableTreePopup(root: root, children: onVariableChildren)
		openValuePopup = popup
		popup.show(over: view, at: rect)
	}


	/// Closes what is open, which the end of a stop does.
	func dismissOpenValue() {
		openValuePopup?.dismiss()
		openValuePopup = nil
	}

	/// What a server said about each open file, and how loudly it is drawn.
	///
	/// Every tab rather than the one in front: a Cadova model opens with a
	/// preview beside it, and "the file in front" is then whichever half the
	/// driver last touched — which is not a thing worth making a report depend
	/// on.
	func diagnosticReportForTesting() -> String {
		let coded = tabs.filter { $0.codeView != nil }
		guard !coded.isEmpty else { return "no code view is open" }
		return coded.map { tab in
			"\(tab.url.lastPathComponent):\n\(tab.codeView?.diagnosticReportForTesting ?? "")"
		}.joined(separator: "\n")
	}

	/// What each open file has beside its code, for `--debug-inspect`.
	///
	/// **Every tab, not the one in front**, because the claim has two halves:
	/// the frame's file shows its variables, and every other file shows none. A
	/// report of the front tab alone can only ever say the first.
	func inlineValueReportForTesting() -> String {
		guard !tabs.isEmpty else { return "no file is open" }
		return tabs.map { tab in
			let name = tab.url.lastPathComponent
			guard let codeView = tab.codeView else { return "\(name): not a code view" }
			return "\(name):\n\(codeView.inlineValueReportForTesting())"
		}.joined(separator: "\n")
	}

	/// A short selection, suitable for seeding a search field.
	func selectedTextForSearch() -> String? {
		guard let text = activeTab?.codeView?.selectedText() ?? pdfPreview?.selectedText,
		      !text.isEmpty, !text.contains("\n")
		else {
			return nil
		}
		return text
	}
}
