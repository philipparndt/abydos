import Darwin
import Foundation

/// A terminal benchmark that we can run unattended, in two modes.
///
/// `fire` is a port of github.com/const-void/DOOM-fire-zig, which has become
/// the usual way to ask a terminal how much it can take: every cell of the
/// screen changes colour every frame, so there is no redraw shortcut to be had.
/// Ported rather than driven because the original waits for a keypress to stop,
/// which makes it useless in a script, and because a benchmark that lives here
/// can be run against a build without anyone installing a Zig toolchain.
///
/// `matrix` asks the other question. The fire is one glyph in every cell and a
/// new colour in every cell, so what it measures is how fast colours can be
/// changed; a terminal that caches one rasterised block and tints it sails
/// through. The rain is the opposite shape: hundreds of *different* glyphs on
/// screen at once, changing where they are rather than what colour they are, so
/// it lands on the glyph cache and on font fallback instead. Between them they
/// cover the two things a terminal renderer caches, and a build that regressed
/// in one of them will not always show it in the other.
///
/// Both report the same number: frames the program managed to write, over the
/// time it took. That is the writer's view — a terminal that swallows bytes and
/// never paints scores well on it — so read it next to whether the screen
/// actually moved.
///
///     firebench [--mode fire|matrix] [--seconds 20] [--report path]

// MARK: - Arguments

enum Mode: String, CaseIterable {
	case fire
	case matrix
	case plain
	case history
	case status
	case colour
	case glyphs
	case ascii

	/// What this mode is for, in the line that reports it.
	var explanation: String {
		switch self {
		case .fire: return "a truecolour change on every cell, the whole screen each frame"
		case .matrix: return "hundreds of different glyphs moving, on the glyph cache"
		case .plain: return "ordinary log output, which is what a build looks like"
		case .history: return "the same once scrollback is full, where a terminal lives"
		case .status: return "one row rewritten in place, which is a progress bar or a clock"
		case .colour: return "colour escapes and nothing else"
		case .glyphs: return "one wide glyph per cell and nothing else"
		case .ascii: return "one narrow glyph per cell and nothing else"
		}
	}
}

/// Ten seconds each when every mode is run, twenty for one asked for by name:
/// a suite that takes a minute and a half is one somebody runs, and a single
/// mode is usually being watched rather than collected.
var duration: Double?
var modeGiven = false
var reportPath: String?
var mode = Mode.fire
/// Frames a second to hold to, or nil to go as fast as the terminal will take.
///
/// The benchmark's whole point is the second one — a number you can only get
/// by never waiting. But the fire and the rain are also nice to look at, and at
/// nine hundred frames a second neither of them looks like anything: the fire
/// is a flat glare and the rain falls faster than it can be read. Held to
/// sixty they become what they are pictures of.
var frameRate: Double?
/// Whether the rain falls in letters instead of katakana.
///
/// Half-width katakana is what the film's rain is usually approximated with,
/// and it is what this uses — but only a font that has those glyphs can draw
/// them, and a terminal that will not fall back to one draws nothing at all.
/// Blank cells are not a benchmark of anything, so there is a way to ask for
/// characters every font on earth has.
var asciiRain = false
var arguments = Array(CommandLine.arguments.dropFirst())
while let flag = arguments.first {
	arguments.removeFirst()
	switch flag {
	case "--seconds":
		duration = arguments.first.flatMap(Double.init) ?? duration
		if !arguments.isEmpty { arguments.removeFirst() }
	case "--report":
		reportPath = arguments.first
		if !arguments.isEmpty { arguments.removeFirst() }
	case "--mode":
		guard let named = arguments.first, let chosen = Mode(rawValue: named) else {
			let known = Mode.allCases.map(\.rawValue).joined(separator: ", ")
			FileHandle.standardError.write(Data("firebench: --mode is one of \(known)\n".utf8))
			exit(2)
		}
		modeGiven = true
		mode = chosen
		arguments.removeFirst()
	case "--fps":
		// Bare `--fps` is sixty; a number after it is that instead.
		if let value = arguments.first.flatMap(Double.init), value > 0 {
			frameRate = value
			arguments.removeFirst()
		} else {
			frameRate = 60
		}
	case "--ascii":
		asciiRain = true
	case "--help", "-h":
		let known = Mode.allCases.map(\.rawValue).joined(separator: "|")
		print("usage: firebench [--mode \(known)] [--seconds N] [--fps [60]] "
			+ "[--ascii] [--report path]")
		print("")
		print("With no --mode, every one of them is run in turn for ten seconds each:")
		for mode in Mode.allCases {
			print("  \(mode.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))\(mode.explanation)")
		}
		exit(0)
	default:
		FileHandle.standardError.write(Data("unknown option \(flag)\n".utf8))
		exit(2)
	}
}

// Refuses to run into a pipe. The whole point is to make a terminal work, and
// without one there is no back-pressure and nothing to measure — only several
// hundred megabytes of escape codes going somewhere nobody will read them.
guard isatty(STDOUT_FILENO) == 1 else {
	FileHandle.standardError.write(Data("firebench: stdout is not a terminal\n".utf8))
	exit(2)
}

// MARK: - Terminal

/// Columns and rows, asked of the terminal itself.
func terminalSize() -> (columns: Int, rows: Int) {
	var size = winsize()
	guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else {
		return (80, 24)
	}
	return (Int(size.ws_col), Int(size.ws_row))
}

let escape = "\u{1B}["
nonisolated(unsafe) var output = [UInt8]()
output.reserveCapacity(1 << 20)

func emit(_ text: String) {
	output.append(contentsOf: text.utf8)
}

func flush() {
	output.withUnsafeBufferPointer { buffer in
		var offset = 0
		while offset < buffer.count {
			let written = write(STDOUT_FILENO, buffer.baseAddress! + offset, buffer.count - offset)
			if written <= 0 { break }
			offset += written
		}
	}
	output.removeAll(keepingCapacity: true)
}

/// The colour escapes, built once. Producing them per cell would be measuring
/// this program rather than the terminal.
let foreground = (0..<256).map { Array("\(escape)38;5;\($0)m".utf8) }
let background = (0..<256).map { Array("\(escape)48;5;\($0)m".utf8) }
let halfBlock = Array("▀".utf8)
let newline = Array("\r\n".utf8)
let space: UInt8 = 0x20

/// Deliberately not seeded from the clock: two runs of the benchmark should
/// differ because the terminal did, not because what was drawn did.
nonisolated(unsafe) var randomState: UInt64 = 0x2545_F491_4F6C_DD1D

func nextRandom64() -> UInt64 {
	randomState ^= randomState << 13
	randomState ^= randomState >> 7
	randomState ^= randomState << 17
	return randomState
}

func nextRandom() -> Int {
	Int(nextRandom64() & 3)
}

/// A whole number below `bound`, which is never zero here.
func nextRandom(below bound: Int) -> Int {
	Int(nextRandom64() % UInt64(max(1, bound)))
}

nonisolated(unsafe) var columns = terminalSize().columns
nonisolated(unsafe) var rows = terminalSize().rows

// MARK: - Fire

/// The palette from the original: xterm-256 indices from black up to white.
let palette: [Int] = [
	0, 233, 234, 52, 53, 88, 89, 94, 95, 96, 130, 131, 132, 133,
	172, 214, 215, 220, 220, 221, 3, 226, 227, 230, 195, 230,
]
let white = palette.count - 1

nonisolated(unsafe) var fireWidth = columns
nonisolated(unsafe) var fireHeight = rows * 2
nonisolated(unsafe) var cells = [UInt8](repeating: 0, count: fireWidth * fireHeight)
nonisolated(unsafe) var previousHigh = -1
nonisolated(unsafe) var previousLow = -1

/// Lights the bottom row, which is where the fire comes from.
func seedFire() {
	fireWidth = columns
	fireHeight = rows * 2
	cells = [UInt8](repeating: 0, count: fireWidth * fireHeight)
	let lastRow = (fireHeight - 1) * fireWidth
	for x in 0..<fireWidth { cells[lastRow + x] = UInt8(white) }
	previousHigh = -1
	previousLow = -1
}

func stepFire() {
	// Spread, exactly as the original does: each cell drifts up and sideways by
	// a random amount and loses heat on the way.
	cells.withUnsafeMutableBufferPointer { buffer in
		for x in 0..<fireWidth {
			for y in 0..<fireHeight {
				let index = y * fireWidth + x
				let value = buffer[index]

				if value == 0 {
					if index >= fireWidth { buffer[index - fireWidth] = 0 }
					continue
				}

				let drift = nextRandom()
				let destination = index >= drift + 1 ? index - drift + 1 : index
				guard destination >= fireWidth else { continue }
				let decay = UInt8(drift & 1)
				buffer[destination - fireWidth] = value > decay ? value - decay : 0
			}
		}
	}
}

func drawFire() {
	// Paint two rows per line: the upper half block takes the foreground, and
	// what shows through behind it is the lower row.
	emit("\(escape)H")
	cells.withUnsafeBufferPointer { buffer in
		var y = 0
		while y + 1 < fireHeight {
			for x in 0..<fireWidth {
				let high = Int(buffer[y * fireWidth + x])
				let low = Int(buffer[(y + 1) * fireWidth + x])
				if low != previousLow { output.append(contentsOf: background[palette[low]]) }
				if high != previousHigh { output.append(contentsOf: foreground[palette[high]]) }
				output.append(contentsOf: halfBlock)
				previousHigh = high
				previousLow = low
			}
			output.append(contentsOf: newline)
			y += 2
		}
	}
}

// MARK: - Matrix

/// Half-width katakana, which a terminal draws in one cell, and the digits —
/// the alphabet the film's rain is usually approximated with. Built once, in
/// UTF-8, for the same reason the colours are.
let rainGlyphs: [[UInt8]] = {
	// Letters and digits when asked: printable ASCII is the one alphabet no
	// font can be missing, so the rain falls whatever is installed.
	var scalars = asciiRain ? [] : (0xFF66...0xFF9D).compactMap(Unicode.Scalar.init)
	if asciiRain {
		scalars += (0x41...0x5A).compactMap(Unicode.Scalar.init)
		scalars += (0x61...0x7A).compactMap(Unicode.Scalar.init)
	}
	scalars += (0x30...0x39).compactMap(Unicode.Scalar.init)
	return scalars.map { Array(String($0).utf8) }
}()

/// White at the head, then green fading to almost nothing. The length of this
/// is the length of a trail: a cell is dropped once it has aged past the end.
let rainPalette = [231, 194, 157, 120, 83, 46, 40, 34, 28, 22]

/// Which glyph is in each cell, and how faded it is — -1 for a cell with
/// nothing in it.
nonisolated(unsafe) var rainGlyph = [UInt8]()
nonisolated(unsafe) var rainShade = [Int8]()
/// Where each column's head is, in rows. Negative while it waits to fall again.
nonisolated(unsafe) var rainHead = [Double]()
/// How fast, in rows per frame. Never more than one, so a column ages its own
/// trail exactly once per row it moves — which is what gives every column the
/// same length of trail whatever its speed, as the film's do.
nonisolated(unsafe) var rainSpeed = [Double]()

func seedRain() {
	rainGlyph = [UInt8](repeating: 0, count: columns * rows)
	rainShade = [Int8](repeating: -1, count: columns * rows)
	// Started within a screen of the top rather than two, so the rain is
	// already falling everywhere by the time anybody looks at it.
	rainHead = (0..<columns).map { _ in -Double(nextRandom(below: max(2, rows / 2))) }
	rainSpeed = (0..<columns).map { _ in 0.15 + Double(nextRandom(below: 85)) / 100 }
}

func stepRain() {
	for x in 0..<columns {
		let before = Int(rainHead[x].rounded(.down))
		rainHead[x] += rainSpeed[x]
		let after = Int(rainHead[x].rounded(.down))
		guard after != before else { continue }

		// A trail ages by where its head has got to, not by how long the
		// program has been running: a slow column would otherwise have its
		// trail die out just behind it.
		for y in 0..<rows {
			let index = y * columns + x
			guard rainShade[index] >= 0 else { continue }
			let aged = rainShade[index] + 1
			rainShade[index] = aged < Int8(rainPalette.count) ? aged : -1
		}

		if after >= 0, after < rows {
			let index = after * columns + x
			rainGlyph[index] = UInt8(nextRandom(below: rainGlyphs.count))
			rainShade[index] = 0
		}

		// Off the bottom, trail and all: fall again from just above the top, at
		// a different speed so the columns never fall into step. A short wait
		// rather than a screen's worth — the gap is what decides how much rain
		// is on screen at once, and a screen of it was a drizzle.
		if after > rows + rainPalette.count {
			rainHead[x] = -Double(nextRandom(below: max(2, rows / 4)))
			rainSpeed[x] = 0.15 + Double(nextRandom(below: 85)) / 100
		}
	}

	// The flicker: glyphs already on screen change to other glyphs where they
	// stand. It is what the rain looks like, and it is the part a terminal
	// cannot cache — a cell that changed colour may be the same picture tinted,
	// and a cell that changed glyph never is.
	for _ in 0..<max(1, columns * rows / 64) {
		let index = nextRandom(below: columns * rows)
		guard rainShade[index] >= 0 else { continue }
		rainGlyph[index] = UInt8(nextRandom(below: rainGlyphs.count))
	}
}

func drawRain() {
	emit("\(escape)H")
	var previousColour = -1
	for y in 0..<rows {
		for x in 0..<columns {
			let index = y * columns + x
			let shade = Int(rainShade[index])
			// Nothing here: a space, and no colour, because a space has no
			// colour to get wrong and the escape would be bytes for nothing.
			guard shade >= 0 else {
				output.append(space)
				continue
			}
			let colour = rainPalette[shade]
			if colour != previousColour {
				output.append(contentsOf: foreground[colour])
				previousColour = colour
			}
			output.append(contentsOf: rainGlyphs[Int(rainGlyph[index])])
		}
		// No newline after the last row: it would scroll the screen out from
		// under a picture that is drawn from the top corner every frame.
		if y + 1 < rows { output.append(contentsOf: newline) }
	}
}


// MARK: - The patterns that are not pictures

/// The rest of the modes write text rather than draw something, and they are
/// here because the numbers were only ever available on the wrong side of the
/// line: `TerminalThroughputTests` measures an engine in-process, with no pty,
/// no drain, no renderer and no app. This measures what a terminal actually
/// does with the same bytes.
///
/// The byte patterns match that suite's deliberately, so the two can be read
/// against each other — where they disagree, the difference is everything
/// between the parser and the screen.

/// One line of log per row, coloured the way a build's output is.
func drawPlain() {
	for row in 0..<rows {
		lineCounter += 1
		emit("\(escape)3\(lineCounter % 8)m[\(lineCounter)] some typical log line with words \(escape)0m")
		if row + 1 < rows { output.append(contentsOf: newline) }
	}
}

/// A screenful of log once, and then one row of it rewritten where it stands.
///
/// Every other pattern here changes the whole screen between one frame and the
/// next — that is what makes them benchmarks — and so none of them could show
/// what item 0488 is about. A progress bar, a clock, a status line, vim's ruler
/// and a shell echoing a keystroke are all this shape instead: a screen that is
/// almost entirely the same as the one before it.
///
/// The row is addressed rather than reprinted, and the screen does not scroll,
/// so what the terminal is told changed is one row out of however many it has.
/// A renderer that believes it draws one row and a renderer that draws the
/// screen produce the identical picture here, which is exactly why the number to
/// watch is not this program's frame rate but `ABYDOS_METAL_PROBE`'s
/// `cells/render`.
func drawStatus(_ frame: Int) {
	// The backdrop, once. Printed rather than addressed so it scrolls into
	// history as real output would, and so the rows below carry text: a blank
	// row and a full one cost a renderer that builds every row the same, and it
	// should be obvious in the numbers if one ever does not.
	if frame == 0 {
		for row in 0..<rows {
			lineCounter += 1
			emit("\(escape)3\(lineCounter % 8)m[\(lineCounter)] some typical log line with words\(escape)0m")
			if row + 1 < rows { output.append(contentsOf: newline) }
		}
		return
	}
	// A third of the way down, so that a renderer getting the row wrong is
	// wrong somewhere visible rather than at an edge.
	let row = max(1, rows / 3)
	emit("\(escape)\(row);1H\(escape)2K  frame \(frame) — every other row is unchanged")
}

/// A truecolour escape per cell and nothing drawn: the half of the fire that is
/// escape parsing rather than glyphs.
func drawColour() {
	for row in 0..<rows {
		for column in 0..<columns {
			emit("\(escape)38;2;\((row * 6 + column) % 256);\((column * 3) % 256);0m")
		}
		if row + 1 < rows { output.append(contentsOf: newline) }
	}
}

/// One glyph per cell, the same one, with no colour changes at all: the other
/// half, which lands on the glyph cache and on nothing else.
func drawGlyphs(_ glyph: [UInt8]) {
	for row in 0..<rows {
		for _ in 0..<columns { output.append(contentsOf: glyph) }
		if row + 1 < rows { output.append(contentsOf: newline) }
	}
}

nonisolated(unsafe) var lineCounter = 0
let narrowGlyph = Array("x".utf8)

/// Fills the scrollback before `history` is measured, so what is timed is a
/// terminal that has to evict a line for every line it takes — which is where
/// one spends almost all of its life, and which `plain` on a fresh screen is
/// not.
func fillScrollback() {
	for _ in 0..<4000 {
		lineCounter += 1
		emit("\(escape)3\(lineCounter % 8)m[\(lineCounter)] some typical log line with words \(escape)0m\r\n")
		if output.count > 1 << 18 { flush() }
	}
	flush()
	lineCounter = 0
}

// MARK: - Run

// Alternate screen, no cursor, and no wrapping — a glyph in the bottom right
// corner scrolls a terminal that is still allowed to wrap. Restored however
// this ends, so the shell is left as it was found.
emit("\(escape)?1049h\(escape)?25l\(escape)?7l\(escape)2J")
flush()

func restore() {
	emit("\(escape)0m\(escape)?7h\(escape)?25h\(escape)?1049l")
	flush()
}

// Ctrl-C should still put the terminal back.
signal(SIGINT) { _ in
	restore()
	exit(130)
}

/// One mode, for a while, reported as a line.
///
/// A function rather than the loop this used to be, because the default is now
/// every mode in turn: each needs its own clock, its own counters and its own
/// seed, and a mode that resizes the screen must not be measured against a
/// frame drawn at the old size.
@MainActor func run(_ mode: Mode, seconds: Double) -> String {
	switch mode {
	case .fire: seedFire()
	case .matrix: seedRain()
	case .history: fillScrollback()
	default: break
	}
	emit("\(escape)2J")
	flush()

	// `status` is paced whether or not anybody asked, and it is the one mode
	// that is. The others are measurements of how much a terminal can take, and
	// the way to find that out is never to wait. This one is a measurement of
	// what one *frame* costs a terminal that has almost nothing to redraw — and
	// a pattern going flat out never gets a frame drawn at all: forty bytes a
	// time, hundreds of thousands of times a second, keeps the parser
	// permanently behind, and a terminal that is behind holds its redraws back
	// and paints once a quarter second. Which is correct of it, and measures the
	// throttle instead of the thing being asked about.
	let pace = frameRate ?? (mode == .status ? 60 : nil)

	let start = Date()
	var frames = 0
	var totalBytes = 0

	while -start.timeIntervalSinceNow < seconds {
		// Followed live, so the picture fills the screen even if it was resized
		// after the benchmark started.
		let current = terminalSize()
		if current.columns != columns || current.rows != rows {
			columns = current.columns
			rows = current.rows
			switch mode {
			case .fire: seedFire()
			case .matrix: seedRain()
			default: break
			}
		}

		switch mode {
		case .fire:
			stepFire()
			drawFire()
		case .matrix:
			stepRain()
			drawRain()
		case .plain, .history:
			drawPlain()
		case .status:
			drawStatus(frames)
		case .colour:
			drawColour()
		case .glyphs:
			drawGlyphs(halfBlock)
		case .ascii:
			drawGlyphs(narrowGlyph)
		}

		totalBytes += output.count
		flush()
		frames += 1

		// Watching rather than measuring: sleep out whatever is left of this
		// frame's share of a second. Measured from the start rather than added
		// up frame by frame, so a slow frame is caught up with instead of
		// pushing every frame after it later.
		if let pace {
			let due = start.addingTimeInterval(Double(frames) / pace)
			let idle = due.timeIntervalSinceNow
			if idle > 0 { Thread.sleep(forTimeInterval: idle) }
		}
	}

	let elapsed = -start.timeIntervalSinceNow
	let perFrame = frames > 0 ? totalBytes / frames : 0
	return String(
		format: "firebench: %-8@%@ %5d frames in %4.1fs [ %7.2f fps ] %dx%d, %7d B/frame, %6.1f MB/s",
		mode.rawValue, pace.map { String(format: " held to %.0f", $0) } ?? "",
		frames, elapsed, Double(frames) / elapsed, columns, rows, perFrame,
		Double(totalBytes) / elapsed / 1_048_576
	)
}

// One mode if one was asked for, otherwise all of them: the whole point of the
// others is that they can be read against each other, and a suite nobody runs
// because it has to be run eight times is a suite of one.
let wanted = modeGiven ? [mode] : Mode.allCases
let each = duration ?? (modeGiven ? 20 : 10)
var summaries: [String] = []
for one in wanted {
	summaries.append(run(one, seconds: each))
}

restore()
for line in summaries { print(line) }
// Written out as well, so a script can read the result without also watching
// the screen.
if let reportPath {
	try? (summaries.joined(separator: "\n") + "\n").write(
		toFile: reportPath, atomically: true, encoding: .utf8
	)
}
