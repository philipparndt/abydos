import AbydosKit
import AppKit

/// Driving a `.vboard` tab: what it is showing and why.
///
/// A driven run never reaches a vboard server, so what there is to report is
/// the tab's own state and sentence — which is the claim a driven run can
/// make: that it said why it did not go anywhere, and went nowhere.
extension MainWindowController {
	/// One step at a time, comma separated: `report`.
	func driveBoardForTesting(_ steps: String) {
		for (index, step) in steps.split(separator: ",").map(String.init).enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) { [weak self] in
				self?.stepBoardForTesting(step.trimmingCharacters(in: .whitespaces))
			}
		}
	}

	private func stepBoardForTesting(_ step: String) {
		guard let board = editorForTesting.activeGroup?.activeBoard else {
			let groups = editorForTesting.groups
			let described = groups.isEmpty
				? "no editor group"
				: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")
			print("BOARD: no board tab — \(described)")
			fflush(stdout)
			return
		}
		switch step {
		case "report": print("BOARD: \(board.reportForTesting)")
		default: print("BOARD: no step called \(step)")
		}
		fflush(stdout)
	}
}
