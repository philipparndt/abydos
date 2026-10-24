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

/// Boards that live on the server: File ▸ Open vboard Board… and the copy.
extension MainWindowController {
	/// The server named in the settings, when one can be used. Never on a
	/// driven run, which reaches no server.
	var usableVboardServer: URL? {
		guard !DrivenRun.isActive, case .server(let url, _) = VboardServerAddress(Settings.shared.vboardServer) else {
			return nil
		}
		return url
	}

	/// File ▸ Open vboard Board…: one of the server's boards, live in a tab.
	@objc func openServerBoard(_ sender: Any?) {
		guard let server = usableVboardServer else { return }
		let picker = VboardBoardPicker(server: server)
		picker.onChoose = { [weak self] board, server in
			guard let self, let group = self.editor.activeGroup else { return }
			self.leaveTerminalFullScreen()
			group.openServerBoard(board, server: server)
			self.giveTheEditorTheWindow()
		}
		picker.show(over: window)
	}

	/// File ▸ Save a Copy of the Board…: the server's board in front, written as
	/// a `.vboard` where somebody picks, the project by default.
	@objc func saveCopyOfBoard(_ sender: Any?) {
		guard let window, let pane = editor.activeGroup?.activeBoard, pane.canSaveCopy,
		      let board = pane.serverBoard
		else { return }
		let panel = NSSavePanel()
		panel.directoryURL = project?.root
		panel.nameFieldStringValue = board.name
			.replacingOccurrences(of: "/", with: "-")
			.replacingOccurrences(of: ":", with: "-") + ".vboard"
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, let url = panel.url else { return }
			Task { @MainActor in
				if let why = await pane.saveCopy(to: url) {
					Toast.post("Could not save a copy of \(board.name)", detail: why)
				} else {
					Toast.post("Saved a copy of \(board.name)", detail: url.lastPathComponent, kind: .information)
				}
			}
		}
	}
}
