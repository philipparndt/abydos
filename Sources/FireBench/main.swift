import Darwin
import Foundation

/// The DOOM fire benchmark, as a program we can run unattended.
///
/// A port of github.com/const-void/DOOM-fire-zig, which has become the usual
/// way to ask a terminal how much it can take: every cell of the screen changes
/// colour every frame, so there is no redraw shortcut to be had. Ported rather
/// than driven because the original waits for a keypress to stop, which makes
/// it useless in a script, and because a benchmark that lives here can be run
/// against a build without anyone installing a Zig toolchain.
///
/// It reports the same number the original does: frames the program managed to
/// write, over the time it took. That is the writer's view — a terminal that
/// swallows bytes and never paints scores well on it — so read it next to
/// whether the fire actually moved.
///
///     firebench [--seconds 20]

// MARK: - Arguments

var duration: Double = 20
var reportPath: String?
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
	case "--help", "-h":
		print("usage: firebench [--seconds 20] [--report path]")
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

// MARK: - Fire

/// The palette from the original: xterm-256 indices from black up to white.
let palette: [Int] = [
	0, 233, 234, 52, 53, 88, 89, 94, 95, 96, 130, 131, 132, 133,
	172, 214, 215, 220, 220, 221, 3, 226, 227, 230, 195, 230,
]
let white = palette.count - 1

/// The colour escapes, built once. Producing them per cell would be measuring
/// this program rather than the terminal.
let foreground = (0..<256).map { Array("\(escape)38;5;\($0)m".utf8) }
let background = (0..<256).map { Array("\(escape)48;5;\($0)m".utf8) }
let halfBlock = Array("▀".utf8)
let newline = Array("\r\n".utf8)

/// Deliberately not seeded from the clock: two runs of the benchmark should
/// differ because the terminal did, not because the fire did.
nonisolated(unsafe) var randomState: UInt64 = 0x2545_F491_4F6C_DD1D

func nextRandom() -> Int {
	randomState ^= randomState << 13
	randomState ^= randomState >> 7
	randomState ^= randomState << 17
	return Int(randomState & 3)
}

nonisolated(unsafe) var columns = terminalSize().columns
nonisolated(unsafe) var rows = terminalSize().rows
nonisolated(unsafe) var fireWidth = columns
nonisolated(unsafe) var fireHeight = rows * 2
nonisolated(unsafe) var cells = [UInt8](repeating: 0, count: fireWidth * fireHeight)

/// Lights the bottom row, which is where the fire comes from.
func seedFire() {
	for index in 0..<(fireWidth * fireHeight) { cells[index] = 0 }
	let lastRow = (fireHeight - 1) * fireWidth
	for x in 0..<fireWidth { cells[lastRow + x] = UInt8(white) }
}

seedFire()

// Alternate screen and no cursor, so the benchmark leaves the shell as it
// found it however it ends.
emit("\(escape)?1049h\(escape)?25l\(escape)2J")
flush()

func restore() {
	emit("\(escape)0m\(escape)?25h\(escape)?1049l")
	flush()
}

// Ctrl-C should still put the terminal back.
signal(SIGINT) { _ in
	restore()
	exit(130)
}

// MARK: - Run

let start = Date()
nonisolated(unsafe) var frames = 0
nonisolated(unsafe) var totalBytes = 0
nonisolated(unsafe) var previousHigh = -1
nonisolated(unsafe) var previousLow = -1

while -start.timeIntervalSinceNow < duration {
	// Followed live, so the fire fills the screen even if it was resized after
	// the benchmark started.
	let current = terminalSize()
	if current.columns != columns || current.rows != rows {
		columns = current.columns
		rows = current.rows
		fireWidth = columns
		fireHeight = rows * 2
		cells = [UInt8](repeating: 0, count: fireWidth * fireHeight)
		seedFire()
		previousHigh = -1
		previousLow = -1
	}

	// Spread, exactly as the original does: each cell drifts up and sideways
	// by a random amount and loses heat on the way.
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

	totalBytes += output.count
	flush()
	frames += 1
}

let elapsed = -start.timeIntervalSinceNow
restore()

let fps = Double(frames) / elapsed
let perFrame = frames > 0 ? totalBytes / frames : 0
let summary = String(
	format: "firebench: %d frames in %.1fs [ %.2f fps ] %dx%d, %d B/frame, %.1f MB/s",
	frames, elapsed, fps, columns, rows, perFrame,
	Double(totalBytes) / elapsed / 1_048_576
)
print(summary)
// Written out as well, so a script can read the result without also reading
// the fire.
if let reportPath {
	try? (summary + "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
}
