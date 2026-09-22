import AbydosKit
import AppKit

/// Driving the HTML preview: what its line says, and pressing what it offers.
///
/// **Never a bare "not found".** 0507's lesson, which this file exists to keep:
/// a report that can only say `no html pane` is consistent with the pane being
/// missing, with the tab in front being another file, and with there being no
/// tab at all — and the first of those gets assumed. What the tab in front *is*
/// costs one line and tells the three apart.
extension MainWindowController {
	/// One step at a time, comma separated: `report`, `press`.
	///
	/// `press` is the button on the caption line — *Load* under a page whose
	/// references were refused, *Block* under one that was allowed. A driven run
	/// still fetches nothing afterwards, which is the point of being able to
	/// photograph it: the line says the page is allowed *and* that a driven run
	/// reaches nothing.
	func driveHtmlForTesting(_ steps: String) {
		for (index, step) in steps.split(separator: ",").map(String.init).enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) { [weak self] in
				self?.stepHtmlForTesting(step.trimmingCharacters(in: .whitespaces))
			}
		}
	}

	private func stepHtmlForTesting(_ step: String) {
		guard let pane = htmlPreviewForTesting else {
			let groups = editorForTesting.groups
			let described = groups.isEmpty
				? "no editor group"
				: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")
			print("HTML: no html pane — \(described)")
			fflush(stdout)
			return
		}
		switch step {
		case "report":
			print("HTML: \(pane.reportForTesting)")
		case "press":
			let said = pane.pressOfferForTesting()
			print("HTML: pressed \(said)")
		default:
			print("HTML: no step called \(step)")
		}
		fflush(stdout)
	}

	private var htmlPreviewForTesting: HtmlPreviewView? {
		editorForTesting.activeGroup?.htmlPreview
	}
}
