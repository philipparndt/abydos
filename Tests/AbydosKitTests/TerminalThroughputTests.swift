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
	/// **Both figures are printed, with and without the write** (item 0487). The
	/// write was added here by 0485 and nowhere else, and the effect on *our*
	/// engine — for which a snapshot is a retain and the write is the only work in
	/// the loop — was to slow this line by 2.8×. That was read as a regression in
	/// the draw path and it is the whole reason 0487 exists. A benchmark whose
	/// body changed between two runs cannot be compared across them, so it now
	/// says which of the two numbers it is quoting.
	@Test func gridSnapshotCost() {
		let rows = 40, columns = 100
		for (name, engine) in [
			(TerminalEmulator.engineName, TerminalEmulator(rows: rows, columns: columns) as TerminalEngine),
			(GhosttyTerminalEngine.engineName, GhosttyTerminalEngine(rows: rows, columns: columns)),
		] {
			engine.write(String(repeating: "a typical line of terminal output here\r\n", count: 5_200))
			for writing in [true, false] {
				var best = Double.greatestFiniteMagnitude
				for _ in 0..<5 {
					let start = Date()
					var reads = 0
					while -start.timeIntervalSinceNow < 0.1 {
						// Cheapest thing that says "the terminal changed" without moving
						// the cursor, scrolling, or touching a cell.
						if writing { engine.write("\u{1B}[?25h") }
						let grid = engine.grid
						_ = grid.line(at: grid.totalLineCount - 1)?.cells.count
						reads += 1
					}
					best = min(best, -start.timeIntervalSinceNow / Double(reads))
				}
				print("BENCH [\(name)] grid snapshot"
					+ (writing ? ", a byte in first" : ", nothing new (cache hit)")
					+ ": \(String(format: "%.3f", best * 1000)) ms/frame "
					+ "(\(String(format: "%.0f", 1 / best)) fps ceiling)  [\(MachineLoad.said)]")
			}
		}
	}

	// MARK: - The other half: what a frame asks for

	/// What one *frame* costs, which is what the benches above leave out.
	///
	/// This suite measured writes and not draws, and that is why item 0487 had
	/// one clue and it was the wrong one: the only number 0485 moved was the
	/// snapshot, and a snapshot is not a frame. `TerminalView` reads
	/// `emulator.grid` at thirty-two call sites, walks the visible rows off it,
	/// and asks for the cursor and the pictures besides — so a frame is measured
	/// here as the view asks for one.
	///
	/// **And the identical frame is measured off the concrete `TerminalEmulator`
	/// beside it**, which is what makes this the guard 0487 wanted rather than
	/// another absolute figure nobody can compare across a rebuild. 0485 turned
	/// the view's `TerminalEmulator` into a `TerminalEngine` existential, and the
	/// hypothesis was that the witness-table calls the optimiser can no longer
	/// specialise had made every frame more expensive for both engines. A ratio
	/// between the two answers that question in one run, at any load, and goes on
	/// answering it: if anybody makes `grid` cost the old engine something — a
	/// copy per access, a snapshot rebuilt rather than retained — this is the
	/// number that moves.
	///
	/// Two frames per engine, because a terminal draws both kinds and they cost
	/// different things. One after bytes have arrived, which is streaming output.
	/// One with nothing new, which is a cursor blink, a scroll, a window coming
	/// forward — and which is where a snapshot cache earns its keep, so the
	/// caching that 0485 added is visible here as the gap between the two rather
	/// than hidden inside one figure.
	@Test func drawPathCost() {
		let rows = 40, columns = 100
		let history = String(repeating: "a typical line of terminal output here\r\n", count: 5_200)

		let ours = TerminalEmulator(rows: rows, columns: columns)
		ours.write(history)
		let ghostty = GhosttyTerminalEngine(rows: rows, columns: columns)
		ghostty.write(history)

		var throughTheSeam = 0.0
		for (name, engine) in [
			(TerminalEmulator.engineName, ours as TerminalEngine),
			(GhosttyTerminalEngine.engineName, ghostty),
		] {
			for writing in [true, false] {
				let seconds = frameCost(writing: writing ? engine : nil) {
					_ = self.frameThroughTheSeam(engine, visibleRows: rows)
				}
				report(engine: name, how: "through the seam", writing: writing, seconds: seconds)
				if name == TerminalEmulator.engineName, writing { throughTheSeam = seconds }
			}
		}

		var concrete = 0.0
		for writing in [true, false] {
			let seconds = frameCost(writing: writing ? ours : nil) {
				_ = self.frameConcretely(ours, visibleRows: rows)
			}
			report(engine: TerminalEmulator.engineName, how: "concrete, as before 0485",
			       writing: writing, seconds: seconds)
			if writing { concrete = seconds }
		}

		// A ratio between two figures taken seconds apart in one run, which is the
		// one shape of timing assertion item 0472 keeps unconditional: a loaded
		// machine slows both halves and the ratio holds. Two, not 1.1 — the frame
		// is dominated by walking four thousand cells, which both halves do
		// identically, so the seam's share of it is small and a tight bound would
		// be measuring scheduling noise. What this catches is the thing worth
		// catching: `grid` becoming work rather than a retain.
		let ratio = throughTheSeam / max(concrete, .leastNormalMagnitude)
		print("BENCH [\(TerminalEmulator.engineName)] the seam costs a frame "
			+ "\(String(format: "%.2f", ratio))× what the concrete type does  [\(MachineLoad.said)]")
		#expect(ratio < 2.0)

		// And the absolute, which is a claim about a person rather than about the
		// seam: a frame's worth of asking the engine has to disappear inside the
		// 16.7 ms a 60 Hz frame gets. An order of magnitude below that is 1 ms,
		// which is also six times over 0485's measured 0.165 ms for libghostty-vt's
		// copy and a hundred times over ours. 0474 measured 4.372 ms here and that
		// is what a bound like this is for.
		if Stopwatch.maySay("BENCH", "the draw path") {
			#expect(throughTheSeam < 0.001)
		}
	}

	/// Microseconds rather than the milliseconds the write benches print: a frame
	/// here is single figures of them, and `%.3f` of a millisecond rounds our
	/// engine's whole frame to "0.002" — a number that cannot be compared with
	/// anything, which is the failure this test exists to prevent.
	private func report(engine: String, how: String, writing: Bool, seconds: Double) {
		print("BENCH [\(engine)] draw path, \(how), "
			+ (writing ? "a byte in first" : "nothing new")
			+ ": \(String(format: "%.2f", seconds * 1_000_000)) µs/frame "
			+ "(\(String(format: "%.0f", 1 / seconds)) fps ceiling)  [\(MachineLoad.said)]")
	}

	/// Best of five passes at one frame, optionally with output arriving first.
	///
	/// The write is the same mode set `gridSnapshotCost` uses — it says "the
	/// terminal changed" without moving the cursor, scrolling or touching a cell —
	/// so what it adds is an invalidated snapshot rather than a different screen.
	private func frameCost(writing engine: TerminalEngine?, _ frame: () -> Void) -> Double {
		var best = Double.greatestFiniteMagnitude
		for _ in 0..<5 {
			let start = Date()
			var frames = 0
			while -start.timeIntervalSinceNow < 0.1 {
				engine?.write("\u{1B}[?25h")
				frame()
				frames += 1
			}
			best = min(best, -start.timeIntervalSinceNow / Double(frames))
		}
		return best
	}

	/// One frame's worth of asking, through the seam.
	///
	/// Every line of it is a call `TerminalView` makes once per frame:
	/// `takeDirtyRange` and `grid` from `invalidateChangedRows` and `drawMarked`,
	/// `totalLineCount` from `shownLineCount`, `line(at:)` and the cells from the
	/// row loop, `scrollbackCount + cursorRow` from `invalidateCursorRows`, the
	/// cursor from `cursorPlace`, and the two graphics questions from
	/// `drawImages`. The cells are summed rather than drawn: what happens to a
	/// cell after it is read is the same whichever engine produced it.
	@inline(never)
	private func frameThroughTheSeam(_ engine: TerminalEngine, visibleRows: Int) -> Int {
		_ = engine.takeDirtyRange()
		let grid = engine.grid
		let total = engine.grid.totalLineCount
		var sum = 0
		for index in max(0, total - visibleRows)..<total {
			guard let line = grid.line(at: index) else { continue }
			for cell in line.cells { sum &+= Int(cell.scalar) }
		}
		sum &+= engine.grid.scrollbackCount + engine.cursorRow
		sum &+= engine.cursorColumn
		if engine.isCursorVisible { sum &+= 1 }
		if engine.graphics.hasVirtualPlacements { sum &+= engine.graphics.placements.count }
		return sum
	}

	/// The same frame off the concrete type, as `TerminalView` read it before 0485.
	///
	/// **The body is duplicated on purpose and must stay duplicated.** Sharing it
	/// would make one of the two a call into the other, and which of them the
	/// optimiser is allowed to specialise and inline is the entire subject of the
	/// measurement.
	@inline(never)
	private func frameConcretely(_ emulator: TerminalEmulator, visibleRows: Int) -> Int {
		_ = emulator.takeDirtyRange()
		let grid = emulator.screen
		let total = emulator.screen.totalLineCount
		var sum = 0
		for index in max(0, total - visibleRows)..<total {
			guard let line = grid.line(at: index) else { continue }
			for cell in line.cells { sum &+= Int(cell.scalar) }
		}
		sum &+= emulator.screen.scrollback.count + emulator.cursorRow
		sum &+= emulator.cursorColumn
		if emulator.isCursorVisible { sum &+= 1 }
		if emulator.graphics.hasVirtualPlacements { sum &+= emulator.graphics.placements.count }
		return sum
	}
}
