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
///
/// **Every line printed here carries the load it was taken at.** It was the one
/// place in the suite that printed a rate without one, and 0474 — which is what
/// these numbers were written for — had to say in the item that its own table was
/// taken at load 25.9 and that the absolutes should not be quoted anywhere. A
/// figure with no load beside it is a figure somebody quotes.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ABYDOS_BENCH"] != nil))
struct TerminalThroughputTests {
	/// Best of several passes.
	///
	/// The mean moves by a tenth between runs on a machine doing anything else,
	/// which is enough to hide a real change or invent one. The best pass is the
	/// one least interrupted, and it is far steadier.
	/// Both engines, on the same bytes, so the comparison is like for like
	/// (item 0474). `ABYDOS_BENCH_ENGINE=abydos` or `=libghostty-vt` measures one
	/// of them alone, which is what to use when the machine is busy: two engines
	/// in one run take twice as long and give the second one a warmer machine.
	private func throughput(
		_ name: String,
		bytes: [UInt8],
		rows: Int = 40,
		columns: Int = 100,
		fillScrollback: Bool = false
	) {
		let wanted = ProcessInfo.processInfo.environment["ABYDOS_BENCH_ENGINE"]
		let engines: [(String, () -> TerminalEngine)] = [
			(TerminalEmulator.engineName, { TerminalEmulator(rows: rows, columns: columns) }),
			(GhosttyTerminalEngine.engineName, { GhosttyTerminalEngine(rows: rows, columns: columns) }),
		]
		for (engineName, make) in engines where wanted == nil || wanted == engineName {
			measure(name, engineName: engineName, engine: make(),
			        bytes: bytes, fillScrollback: fillScrollback)
		}
	}

	private func measure(
		_ name: String, engineName: String, engine: TerminalEngine,
		bytes: [UInt8], fillScrollback: Bool
	) {
		if fillScrollback {
			// A terminal that has been open a while sits with its history full,
			// and what it costs to retire a line is only visible there.
			engine.write(String(repeating: "filler\r\n", count: 5_200))
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
				engine.write(data)
				rounds += 1
				elapsed = -start.timeIntervalSinceNow
			}
			best = max(best, megabytes * Double(rounds) / elapsed)
		}
		print("BENCH [\(engineName)] \(name): \(String(format: "%.1f", best)) MB/s"
			+ "  [\(MachineLoad.said)]")
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

	/// What it costs to *read* the grid, which is the other half of the story
	/// (item 0474) and the half the write benchmark above hides.
	///
	/// Our engine fills `TerminalScreen` as it parses, so a frame reads it for
	/// nothing — `let screen = emulator.screen` is a retain. libghostty-vt keeps
	/// the grid on its own side of an FFI boundary, and its grid references are
	/// documented as valid only "until the next update to the terminal
	/// instance", so a snapshot means copying. This measures that copy.
	///
	/// **A byte goes in between every read** (item 0485), and that matters to what
	/// this measures. The engine caches its snapshot until the next write, because
	/// `TerminalView` reads `emulator.grid` about twenty times in a frame; reading
	/// it in a tight loop with nothing arriving would time the cache and report a
	/// number that is true and useless. A frame in a real terminal follows bytes
	/// arriving, so the loop makes bytes arrive — one mode set, which invalidates
	/// the snapshot without changing a single cell.
	///
	/// What 0474 measured here was the naive version: `grid_ref` per cell over
	/// *every* row, 4.372 ms a frame on this shape. Item 0485 made it the visible
	/// rows through `render.h`, with scrollback fetched only when something asks.
	@Test func gridSnapshotCost() {
		let rows = 40, columns = 100
		for (name, engine) in [
			(TerminalEmulator.engineName, TerminalEmulator(rows: rows, columns: columns) as TerminalEngine),
			(GhosttyTerminalEngine.engineName, GhosttyTerminalEngine(rows: rows, columns: columns)),
		] {
			engine.write(String(repeating: "a typical line of terminal output here\r\n", count: 5_200))
			var best = Double.greatestFiniteMagnitude
			for _ in 0..<5 {
				let start = Date()
				var reads = 0
				while -start.timeIntervalSinceNow < 0.1 {
					// Cheapest thing that says "the terminal changed" without moving
					// the cursor, scrolling, or touching a cell.
					engine.write("\u{1B}[?25h")
					let grid = engine.grid
					_ = grid.line(at: grid.totalLineCount - 1)?.cells.count
					reads += 1
				}
				best = min(best, -start.timeIntervalSinceNow / Double(reads))
			}
			print("BENCH [\(name)] grid snapshot: \(String(format: "%.3f", best * 1000)) ms/frame "
				+ "(\(String(format: "%.0f", 1 / best)) fps ceiling)  [\(MachineLoad.said)]")
		}
	}
}
