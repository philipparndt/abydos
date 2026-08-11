import Foundation

// The seam between the terminal panel and whatever emulates the terminal
// underneath it (item 0474).
//
// There are two engines: `TerminalEmulator`, which is ours and is the default,
// and `GhosttyTerminalEngine`, which is libghostty-vt and is off unless
// `Settings.terminalGhosttyEngine` says otherwise.
//
// **This file exists so that nothing in the old engine has to change.** Every
// requirement below is something `TerminalEmulator` and `TerminalScreen`
// already had before this file was written, spelled with the name they already
// used; the conformances at the bottom are empty or one line, and no file of
// the old engine was edited to make them fit. That is what makes the option
// safe to land: with the setting off, the bytes take the identical path through
// the identical code, and the 2,410-test suite is still testing the thing it
// was written for.
//
// It also means the seam is shaped by what the *callers* ask for rather than by
// what either engine offers. Everything here was read off the call sites in
// `TerminalView`, `TerminalSelection` and the tests. Two things the item
// expected to be here are absent, because measuring the callers said they were
// never there:
//
// - **`TmuxMirror` is not a caller.** All 473 lines of it are a `tmux(1)`
//   subprocess wrapper — `list-windows`, `list-clients`, `set-option`,
//   `paste-buffer`. It never reads the grid, and `@ai_status` is a tmux window
//   option rather than anything on screen. It is not affected by the engine.
// - **There is no prompt detection.** No OSC 133, no semantic marks, no OSC 7
//   (`TerminalDirectory` says why it asks the pty instead). So there is nothing
//   to put behind the seam, and nothing to port.

/// What the grid looks like to anything that reads it.
///
/// A separate protocol from the engine because the render path deliberately
/// takes a *snapshot* — `let screen = emulator.screen` — and then walks it while
/// the engine carries on being written to. Whatever an engine returns here has
/// to keep the frame it was given.
///
/// Indices are absolute: 0 is the oldest line still kept, and
/// `totalLineCount - 1` is the bottom of the active grid. That is the numbering
/// the dirty ranges, the scrollbar and the selection already use.
public protocol TerminalGridReading {
	/// Rows in the active grid, not counting scrollback.
	var rows: Int { get }
	var columns: Int { get }
	/// Scrollback plus active grid.
	var totalLineCount: Int { get }
	/// Lines that have fallen off the top for good, so absolute indices from an
	/// older frame can be recognised as gone.
	var discardedLineCount: Int { get }
	/// Where the active grid starts, in absolute indices.
	var scrollbackCount: Int { get }
	/// The line at an absolute index, or nil when it is out of range.
	func line(at index: Int) -> TerminalLine?
}

/// An engine: bytes in, grid and state out.
///
/// Only the members some caller actually uses. Deliberately *not* here:
/// `TerminalKeys`' AppKit key mapping, `Ligatures`, `ShapedRuns`, `GlyphAtlas`,
/// `RedrawThrottle`, the parse budget and the pty — none of them touch an
/// engine, and all of them stay exactly where they are whichever engine is on.
public protocol TerminalEngine: AnyObject {
	/// Which engine this is, for `--report-geometry` and for bug reports.
	///
	/// A terminal bug now has two possible homes, and the first question about
	/// any report is which engine drew it. This is how that gets answered
	/// without asking the reporter to remember a setting.
	static var engineName: String { get }

	// Bytes in. Synchronous, and `onUpdate` fires at the end of each call.
	func write(_ data: Data)
	func write(_ string: String)

	func resize(rows: Int, columns: Int)
	func reset()

	/// The grid, as a snapshot that survives later writes.
	var grid: TerminalGridReading { get }

	var cursorRow: Int { get }
	var cursorColumn: Int { get }
	var isCursorVisible: Bool { get }

	var title: String? { get }
	var isAlternateScreen: Bool { get }

	/// Written from outside, by the view that knows how big a cell is drawn.
	/// The engine needs it to work out how many cells an image covers, and 0468
	/// is what happens when it is wrong.
	var cellPixelSize: (width: Int, height: Int) { get set }

	/// Rows changed since this was last asked, in absolute indices, or nil for
	/// none. Taking it clears it.
	func takeDirtyRange() -> ClosedRange<Int>?

	var onUpdate: (() -> Void)? { get set }
	var onResponse: ((String) -> Void)? { get set }

	/// What this engine cannot do yet, in words fit to show somebody.
	///
	/// Empty for a complete engine. Non-empty is a promise that the missing
	/// parts *refuse* rather than draw something plausible — an engine that
	/// silently misrenders is worse than no option at all, because the person
	/// who notices weeks later cannot tell whether it was the engine, the seam
	/// or a real bug.
	var unimplemented: [String] { get }
}

// MARK: - Our own engine, conforming without being touched

extension TerminalScreen: TerminalGridReading {
	/// The one name the old type did not already have. `scrollback.count` is
	/// spelled out at six call sites in `TerminalView`; this is that number
	/// under a name the protocol can require.
	public var scrollbackCount: Int { scrollback.count }
}

extension TerminalEmulator: TerminalEngine {
	public static var engineName: String { "abydos" }

	/// `screen` is already a `Sendable` value type, so returning it *is* the
	/// snapshot the protocol asks for. This is why the seam costs the old engine
	/// nothing: the render path was already written this way.
	public var grid: TerminalGridReading { screen }

	/// Nothing missing — this is the engine every terminal test was written
	/// against.
	public var unimplemented: [String] { [] }
}
