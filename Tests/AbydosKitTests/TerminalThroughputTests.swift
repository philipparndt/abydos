import Foundation
import Testing
@testable import AbydosKit

/// Terminal throughput, so a change to the parser can be shown to have helped.
///
/// Numbers, not pass or fail: these print what the parser manages and assert
/// only that it manages something.
///
/// Off unless asked for. They saturate a core for as long as they run, which is
/// enough to make the timing-sensitive tests elsewhere fail when the suite runs
/// them in parallel. Run with:
///
///     ABYDOS_BENCH=1 swift test -c release --filter TerminalThroughput
///
/// In release, and it matters: a debug build spends its time in exclusivity
/// checks and generic metadata lookups that the optimiser removes entirely, so
/// debug numbers are roughly a tenth of the truth and point at the wrong costs.
/// The app itself ships release.
///
/// ABYDOS_BENCH_SECONDS lengthens each pass, for sampling under a profiler.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ABYDOS_BENCH"] != nil))
struct TerminalThroughputTests {
	/// Best of several passes.
	///
	/// The mean moves by a tenth between runs on a machine doing anything else,
	/// which is enough to hide a real change or invent one. The best pass is the
	/// one least interrupted, and it is far steadier.
	private func throughput(
		_ name: String,
		bytes: [UInt8],
		rows: Int = 40,
		columns: Int = 100,
		fillScrollback: Bool = false
	) {
		let emulator = TerminalEmulator(rows: rows, columns: columns)
		if fillScrollback {
			// A terminal that has been open a while sits with its history full,
			// and what it costs to retire a line is only visible there.
			emulator.write(String(repeating: "filler\r\n", count: 5_200))
		}
		let megabytes = Double(bytes.count) / 1_048_576
		let data = Data(bytes)
		var best = 0.0
		// Long enough to sample under a profiler when asked for.
		let seconds = ProcessInfo.processInfo.environment["ABYDOS_BENCH_SECONDS"]
			.flatMap(Double.init) ?? 0.1

		for _ in 0..<5 {
			let start = Date()
			var elapsed = 0.0
			var rounds = 0
			while elapsed < seconds {
				emulator.write(data)
				rounds += 1
				elapsed = -start.timeIntervalSinceNow
			}
			best = max(best, megabytes * Double(rounds) / elapsed)
		}
		print("BENCH \(name): \(String(format: "%.1f", best)) MB/s")
	}

	@Test func plainOutput() {
		var chunk = ""
		for i in 0..<2000 {
			chunk += "\u{1B}[3\(i % 8)m[\(i)] some typical log line with words \u{1B}[0m\r\n"
		}
		throughput("plain log output", bytes: Array(chunk.utf8))
	}

	/// Splits the fire workload apart, so it is clear which half costs what.
	@Test func fireComponents() {
		var colours = ""
		var glyphs = ""
		var ascii = ""
		for row in 0..<40 {
			for column in 0..<100 {
				colours += "\u{1B}[38;2;\((row * 6 + column) % 256);\((column * 3) % 256);0m"
				glyphs += "\u{2580}"
				ascii += "x"
			}
			colours += "\r\n"
			glyphs += "\r\n"
			ascii += "\r\n"
		}
		throughput("  colour changes only", bytes: Array(colours.utf8))
		throughput("  wide-ish glyphs only", bytes: Array(glyphs.utf8))
		throughput("  ascii only", bytes: Array(ascii.utf8))
	}

	/// The same output once history is full, which is where a terminal spends
	/// almost all of its life.
	@Test func plainOutputWithFullScrollback() {
		var chunk = ""
		for i in 0..<2000 {
			chunk += "\u{1B}[3\(i % 8)m[\(i)] some typical log line with words \u{1B}[0m\r\n"
		}
		throughput("plain, history full", bytes: Array(chunk.utf8), fillScrollback: true)
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
