import Foundation
import Testing
@testable import IdeaiKit

/// Terminal throughput, so a change to the parser can be shown to have helped.
///
/// Numbers, not pass or fail: these print what the parser manages and assert
/// only that it manages something.
struct TerminalThroughputTests {
	private func throughput(_ name: String, bytes: [UInt8], rows: Int = 40, columns: Int = 100) {
		let emulator = TerminalEmulator(rows: rows, columns: columns)
		let megabytes = Double(bytes.count) / 1_048_576
		let data = Data(bytes)

		let start = Date()
		var total = 0.0
		var rounds = 0
		while total < 0.25 {
			emulator.write(data)
			rounds += 1
			total = -start.timeIntervalSinceNow
		}
		let mbPerSecond = megabytes * Double(rounds) / total
		print("BENCH \(name): \(String(format: "%.1f", mbPerSecond)) MB/s")
	}

	@Test func plainOutput() {
		var chunk = ""
		for i in 0..<2000 {
			chunk += "\u{1B}[3\(i % 8)m[\(i)] some typical log line with words \u{1B}[0m\r\n"
		}
		throughput("plain log output", bytes: Array(chunk.utf8))
	}

	/// What the DOOM fire benchmark does: a truecolour change on every cell and
	/// the whole screen repainted each frame.
	@Test func doomFire() {
		var frame = "\u{1B}[H"
		for row in 0..<40 {
			for column in 0..<100 {
				let r = (row * 6 + column) % 256
				frame += "\u{1B}[38;2;\(r);\((column * 3) % 256);0m▀"
			}
			frame += "\r\n"
		}
		let bytes = Array(frame.utf8)
		print("BENCH fire frame size: \(bytes.count) bytes; 60fps needs \(String(format: "%.1f", Double(bytes.count) * 60 / 1_048_576)) MB/s")
		throughput("doom fire", bytes: bytes)
	}
}
