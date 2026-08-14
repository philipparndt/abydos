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

/// The catch-up policy libghostty-vt had before item 0492, restorable at launch.
///
/// **So that a before and an after come out of one binary.** Two figures taken from
/// two builds are two figures, and this project has twice acted on a pair that could
/// not be compared — 0488 and 0489 were both reverted that way, and 0491 had to
/// refuse to print a number for exactly this reason. `ABYDOS_TERM_BEHIND` and
/// `ABYDOS_TERM_HOLD` are 0491's version of the same idea.
///
/// `ABYDOS_GHOSTTY_PER_WRITE=1` puts back both halves of the old behaviour: the
/// render state brought up to date on every write with the whole document reported
/// dirty, and `TerminalView` asking `grid` — a snapshot — for the numbers it now gets
/// from `TerminalMetrics`. Read once, at launch, because a policy that could change
/// between two frames is not a policy anybody can measure.
public enum TerminalCatchUp {
	public static let perWrite =
		ProcessInfo.processInfo.environment["ABYDOS_GHOSTTY_PER_WRITE"] != nil
}

/// How big the terminal is and how much history it has, without a snapshot of
/// its rows.
///
/// **Why this is separate from `TerminalGridReading`** (item 0492). A snapshot has
/// to keep the frame it was given, so for an engine that holds its grid on the far
/// side of an FFI boundary asking for one means *copying the visible rows* — eleven
/// thousand cells on a full-screen pane. That is the right price to draw a frame and
/// the wrong price to answer "how tall is the document".
///
/// `TerminalView` asked `emulator.grid` for exactly that, on the parse path, once
/// per delivery: `realignSelectionForDiscardedLines` wanted `discardedLineCount` and
/// `updateFrameSize` wanted the row count. At 1,400 deliveries a second that was
/// 1,400 snapshots a second to draw sixty frames, and it was half of why
/// libghostty-vt ran forty times slower in the app than our own engine while being
/// the faster parser of the two.
///
/// Every field here is a number both engines already have to hand. Nothing in it
/// requires copying a row, and nothing in it is allowed to.
public struct TerminalMetrics: Sendable, Equatable {
	/// Rows in the active grid, not counting scrollback.
	public var rows: Int
	public var columns: Int
	/// Scrollback plus active grid.
	public var totalLineCount: Int
	/// Where the active grid starts, in absolute indices.
	public var scrollbackCount: Int
	/// Lines that have fallen off the top for good.
	public var discardedLineCount: Int

	public init(
		rows: Int, columns: Int, totalLineCount: Int,
		scrollbackCount: Int, discardedLineCount: Int
	) {
		self.rows = rows
		self.columns = columns
		self.totalLineCount = totalLineCount
		self.scrollbackCount = scrollbackCount
		self.discardedLineCount = discardedLineCount
	}
}

// MARK: - The vocabulary the callers already speak

// These five names were `TerminalEmulator.MouseButton`, `.MouseTracking`,
// `.CursorShape`, `.ArrowKey` and `.ColourQuery`, and the protocol below needs
// them without naming one of its own implementations. They are typealiases
// rather than moved declarations for one reason: moving them would edit the old
// engine, and item 0485's rule is that the old path does not change. Every
// existing `TerminalEmulator.MouseButton` at a call site still compiles, and
// there is now one place to move them properly if the old engine ever goes.

public typealias TerminalMouseButton = TerminalEmulator.MouseButton
public typealias TerminalMouseTracking = TerminalEmulator.MouseTracking
public typealias TerminalCursorShape = TerminalEmulator.CursorShape
public typealias TerminalArrowKey = TerminalEmulator.ArrowKey
public typealias TerminalColourQuery = TerminalEmulator.ColourQuery

/// An engine: bytes in, grid and state out.
///
/// Only the members some caller actually uses. Deliberately *not* here:
/// `TerminalKeys`' AppKit key mapping, `Ligatures`, `ShapedRuns`, `GlyphAtlas`,
/// `RedrawThrottle`, the parse budget and the pty — none of them touch an
/// engine, and all of them stay exactly where they are whichever engine is on.
///
/// **`screen` is deliberately absent.** `TerminalView` used to reach through it
/// for six things — `text(in:)`, `wordSelection`, `lineSelection`,
/// `fullSelection`, `recentLines` and `selectableRowCount` — and that was the
/// seam leaking a concrete type. All six are written in terms of `line(at:)` and
/// `totalLineCount` and nothing else, so they moved to an extension on
/// `TerminalGridReading` (in `TerminalSelection.swift`) where both engines get
/// them from one implementation. Nothing was rewritten to make that happen; the
/// extension's `TerminalScreen` became `TerminalGridReading` and the bodies are
/// untouched.
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
	///
	/// **Not for metadata.** Ask `metrics` for the size, the scrollback offset or the
	/// discarded count: a snapshot copies rows, and on the parse path that is item
	/// 0492's fault.
	var grid: TerminalGridReading { get }

	/// The size and the history, cheaply — see `TerminalMetrics`.
	var metrics: TerminalMetrics { get }

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

	// MARK: What a program has asked the terminal to do
	//
	// Modes, in other words, and a VT state machine keeps every one of them by
	// definition. They are read-only here because the view only reads them: a
	// mode is set by the program, through the bytes, and a caller that wrote one
	// would be lying to the program about what it asked for.

	/// 2004 — whether a paste should be wrapped in `ESC [ 200 ~` … `ESC [ 201 ~`.
	var bracketedPaste: Bool { get }
	/// 2026 — whether a program is part-way through rewriting the screen, in
	/// which case what is on the grid is half-drawn and drawing it flickers.
	var isSynchronizingOutput: Bool { get }
	/// 1004 — whether the program wants to hear about focus coming and going.
	var reportsFocus: Bool { get }
	/// 9 / 1000 / 1002 / 1003 — how the program wants pointer events reported.
	var mouseTracking: TerminalMouseTracking { get }
	/// Whether either the kitty keyboard protocol or xterm's `modifyOtherKeys`
	/// is on, in which case an ambiguous key is sent in its unambiguous form.
	var reportsModifiedKeys: Bool { get }
	/// DECSCUSR — what shape the cursor should be drawn as.
	var cursorShape: TerminalCursorShape { get }

	// MARK: Encoding, on the way back to the program
	//
	// No default arguments, because a protocol requirement cannot have them. The
	// two callers that used to omit arguments now pass them, which is three lines
	// at the call sites and one fewer way for the two engines to differ.

	func encodeArrow(_ direction: TerminalArrowKey) -> String
	/// The kitty or xterm form of an ambiguous key, or nil when the program has
	/// not asked and the ordinary bytes should be sent.
	func encodeModifiedKey(
		code: Int, shift: Bool, option: Bool, control: Bool, command: Bool
	) -> String?
	/// A pointer event, or nil when the program is not tracking the mouse.
	/// Coordinates are 1-based.
	func encodeMouse(
		button: TerminalMouseButton, row: Int, column: Int,
		isRelease: Bool, isDrag: Bool, shift: Bool, option: Bool, control: Bool
	) -> String?

	// MARK: Things a program asks of the application, not of the grid

	/// BEL.
	var onBell: (() -> Void)? { get set }
	/// OSC 52 — a copy made inside tmux, or over ssh, reaching the clipboard of
	/// the machine somebody is sitting at.
	var onClipboardWrite: ((String) -> Void)? { get set }
	/// OSC 440 — `abydos <file>` typed in this pane.
	var onOpenFile: ((TerminalOpenRequest) -> Void)? { get set }
	/// A program asked what a colour is, and only whoever owns the palette can
	/// say. `nil` means "no such colour" and nothing is sent.
	var colourLookup: ((TerminalColourQuery) -> (red: Double, green: Double, blue: Double)?)? { get set }

	// MARK: Pictures and links

	/// The images on the screen and where they are shown.
	var graphics: TerminalImageStore { get }
	/// The address behind a hyperlink cell, by the id the cell carries.
	func link(for id: UInt16) -> String?

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

	/// Five field reads off a value type this engine fills as it parses. Ours never
	/// had item 0492's fault — this is the same numbers under the name the seam now
	/// uses, so that the *other* engine can answer them without copying a screen.
	public var metrics: TerminalMetrics {
		TerminalMetrics(
			rows: screen.rows,
			columns: screen.columns,
			totalLineCount: screen.totalLineCount,
			scrollbackCount: screen.scrollback.count,
			discardedLineCount: screen.discardedLineCount)
	}

	/// Nothing missing — this is the engine every terminal test was written
	/// against.
	public var unimplemented: [String] { [] }
}
