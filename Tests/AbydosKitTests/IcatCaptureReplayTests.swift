import Foundation
import Testing
@testable import AbydosKit

/// Replays a real `ABYDOS_TERM_LOG` capture through the emulator and says, after
/// each `icat` run in it, how much of each picture the grid resolves to.
///
/// An instrument rather than a check, and here rather than in a scratch file
/// because both 0397 and 0468 built it from nothing and it is the question
/// either of them would ask first: *given exactly the bytes the terminal was
/// handed, does every placeholder cell still find its picture?* It answers that
/// away from a window, a display and a clock, so a capture taken on a machine
/// where the symptom happens can be read on one where it does not.
///
///     ABYDOS_TERM_LOG=/tmp/pane.log <the app> --terminal   # take the capture
///     ICAT_LOG=/tmp/pane.log ICAT_ROWS=39 ICAT_COLUMNS=153 \
///         xcrun swift test --filter IcatCaptureReplay      # read it
///
/// The rows and columns are the pane's, which `--report-geometry` prints. It
/// does nothing at all without `ICAT_LOG`, which is why it can live in the
/// suite: there is no capture checked in, and a fixture would only ever be a
/// recording of the case that already works.
struct IcatCaptureReplayTests {
	@Test func replayACapture() throws {
		let environment = ProcessInfo.processInfo.environment
		guard let path = environment["ICAT_LOG"] else { return }
		let rows = Int(environment["ICAT_ROWS"] ?? "") ?? 33
		let columns = Int(environment["ICAT_COLUMNS"] ?? "") ?? 155
		let cellWidth = Int(environment["ICAT_CELL_W"] ?? "") ?? 16
		let cellHeight = Int(environment["ICAT_CELL_H"] ?? "") ?? 38

		let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
		let terminal = TerminalEmulator(rows: rows, columns: columns)
		terminal.cellPixelSize = (width: cellWidth, height: cellHeight)

		// Fed in the pieces a run at a time, so the state can be read between
		// them: every `icat` transfer starts with the same header, and what is
		// between two of them is one command's worth of output plus whatever
		// tmux repainted around it.
		let marker = [UInt8]("\u{1B}_Ga=T".utf8)
		var starts: [Int] = []
		if bytes.count >= marker.count {
			for index in 0...(bytes.count - marker.count)
			where Array(bytes[index..<(index + marker.count)]) == marker {
				starts.append(index)
			}
		}
		print("ICAT \(starts.count) transfers in \(bytes.count) bytes, grid \(rows)x\(columns)")

		func report(_ label: String) {
			var runs: [UnicodePlaceholder.Run] = []
			let screen = terminal.screen
			for index in 0..<screen.totalLineCount {
				guard let line = screen.line(at: index) else { continue }
				runs += UnicodePlaceholder.runs(in: line.cells, screenRow: index)
			}
			let placements = terminal.graphics.placements(for: runs)
			// The number worth reading: a placeholder cell that resolved to a
			// placement whose picture the terminal no longer holds is a gap on
			// the screen with nothing in it.
			let withoutImage = placements.filter { terminal.graphics.images[$0.imageID] == nil }
			print(
				"ICAT \(label): images=\(terminal.graphics.images.count) "
				+ "virtual=\(terminal.graphics.virtualPlacements.count) "
				+ "runs=\(runs.count) placements=\(placements.count) "
				+ "rows=\(Set(placements.map(\.row)).count) "
				+ "withoutImage=\(withoutImage.count) "
				+ "shownIDs=\(Set(placements.map(\.imageID)).sorted()) "
				+ "alt=\(terminal.isAlternateScreen) "
				+ "grid=\(screen.rows)x\(screen.columns)"
			)
		}

		var cursor = 0
		for (number, _) in starts.enumerated() {
			let end = number + 1 < starts.count ? starts[number + 1] : bytes.count
			terminal.write(Data(bytes[cursor..<end]))
			cursor = end
			report("after transfer \(number + 1)")
		}
	}
}
