import Foundation
import Testing
@testable import AbydosKit

/// Temporary probe for 0468: replay a captured `ABYDOS_TERM_LOG` through the
/// emulator and say how much of each picture the grid resolves to after each
/// `icat` run. Driven by `ICAT_LOG`, `ICAT_ROWS`, `ICAT_COLUMNS`.
struct Icat0468ReplayTests {
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

		let marker = [UInt8]("\u{1B}_Ga=T,q=2,f=100".utf8)
		var boundaries: [Int] = []
		if bytes.count >= marker.count {
			for index in 0...(bytes.count - marker.count)
			where Array(bytes[index..<(index + marker.count)]) == marker {
				boundaries.append(index)
			}
		}
		print("ICAT transfers at \(boundaries) in \(bytes.count) bytes, grid \(rows)x\(columns)")

		func report(_ label: String) {
			var runs: [UnicodePlaceholder.Run] = []
			let screen = terminal.screen
			for index in 0..<screen.totalLineCount {
				guard let line = screen.line(at: index) else { continue }
				runs += UnicodePlaceholder.runs(in: line.cells, screenRow: index)
			}
			let placements = terminal.graphics.placements(for: runs)
			let withoutImage = placements.filter { terminal.graphics.images[$0.imageID] == nil }
			let ids = Set(placements.map(\.imageID)).sorted()
			print(
				"ICAT \(label): images=\(terminal.graphics.images.count) "
				+ "virtual=\(terminal.graphics.virtualPlacements.count) "
				+ "runs=\(runs.count) placements=\(placements.count) "
				+ "rows=\(Set(placements.map(\.row)).count) "
				+ "withoutImage=\(withoutImage.count) shownIDs=\(ids) "
				+ "alt=\(terminal.isAlternateScreen) "
				+ "grid=\(screen.rows)x\(screen.columns) total=\(screen.totalLineCount)"
			)
		}

		var cursor = 0
		for (number, start) in boundaries.enumerated() {
			_ = start
			let end = number + 1 < boundaries.count ? boundaries[number + 1] : bytes.count
			terminal.write(Data(bytes[cursor..<end]))
			cursor = end
			report("after run \(number + 1)")
		}
	}
}
