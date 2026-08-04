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

enum Mode: String {
	case fire
	case matrix
}

var duration: Double = 20
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
			FileHandle.standardError.write(Data("firebench: --mode is fire or matrix\n".utf8))
			exit(2)
		}
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
	case "--help", "-h":
		print("usage: firebench [--mode fire|matrix] [--seconds 20] [--fps [60]] [--report path]")
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
	var scalars = (0xFF66...0xFF9D).compactMap(Unicode.Scalar.init)
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
	rainHead = (0..<columns).map { _ in -Double(nextRandom(below: rows * 2)) }
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

		// Off the bottom, trail and all: wait a while and fall again, at a
		// different speed, so the columns never fall into step.
		if after > rows + rainPalette.count {
			rainHead[x] = -Double(nextRandom(below: rows))
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

// MARK: - Run

switch mode {
case .fire:   seedFire()
case .matrix: seedRain()
}

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

let start = Date()
nonisolated(unsafe) var frames = 0
nonisolated(unsafe) var totalBytes = 0

while -start.timeIntervalSinceNow < duration {
	// Followed live, so the picture fills the screen even if it was resized
	// after the benchmark started.
	let current = terminalSize()
	if current.columns != columns || current.rows != rows {
		columns = current.columns
		rows = current.rows
		switch mode {
		case .fire:   seedFire()
		case .matrix: seedRain()
		}
	}

	switch mode {
	case .fire:
		stepFire()
		drawFire()
	case .matrix:
		stepRain()
		drawRain()
	}

	totalBytes += output.count
	flush()
	frames += 1

	// Watching rather than measuring: sleep out whatever is left of this
	// frame's share of a second. Measured from the start rather than added up
	// frame by frame, so a slow frame is caught up with instead of pushing
	// every frame after it later.
	if let frameRate {
		let due = start.addingTimeInterval(Double(frames) / frameRate)
		let idle = due.timeIntervalSinceNow
		if idle > 0 { Thread.sleep(forTimeInterval: idle) }
	}
}

let elapsed = -start.timeIntervalSinceNow
restore()

let fps = Double(frames) / elapsed
let perFrame = frames > 0 ? totalBytes / frames : 0
let summary = String(
	format: "firebench: %@%@, %d frames in %.1fs [ %.2f fps ] %dx%d, %d B/frame, %.1f MB/s",
	mode.rawValue, frameRate.map { String(format: " held to %.0f", $0) } ?? "",
	frames, elapsed, fps, columns, rows, perFrame,
	Double(totalBytes) / elapsed / 1_048_576
)
print(summary)
// Written out as well, so a script can read the result without also watching
// the screen.
if let reportPath {
	try? (summary + "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
}
