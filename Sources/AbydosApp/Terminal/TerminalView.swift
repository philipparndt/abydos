import AppKit
import AbydosKit

/// Renders a `TerminalEngine`'s grid and forwards input to its process.
///
/// Same virtualisation principle as the code view: only the rows in the
/// viewport are drawn, and cells are batched into runs of identical attributes
/// so a full-colour screen costs a handful of draw calls rather than one per
/// character.
final class TerminalView: NSView, NSTextInputClient {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Where the cursor was when the program last had it visible.
	var settledCursor: (row: Int, column: Int)?

	/// When a program last asked for the cursor to go away.
	var cursorHiddenSince: Date?

	/// The cell the program was last told about, so a pointer wandering inside
	/// one cell does not send a report per pixel.
	var lastReportedMouseCell: GridCell?

	/// How far the pointer has to travel before a press-and-release becomes a
	/// drag the program hears about. See `ClickSlack` for what it is guarding.
	var clickSlack = ClickSlack()

	/// Drag reports the program has been sent, counted only so a driven run can
	/// say whether an unsteady click reached it.
	var forwardedDragsForTesting = 0

	/// The text being composed, which no program has been told about yet.
	var markedText = ""
	/// The key the input manager is being asked about, kept so a key it hands
	/// back can still be sent.
	var composingEvent: NSEvent?
	lazy var compositionLabel: NSTextField = {
		let label = NSTextField(labelWithString: "")
		label.drawsBackground = true
		label.isBordered = false
		label.isHidden = true
		return label
	}()
	/// When the bell last rang, or nil if it is not showing.
	var bellRangAt: Date?
	/// When the current frame was first held back, if it was.
	var heldFrameSince: Date?
	/// Which hyperlink the pointer is over, so it can be underlined and opened.
	var hoveredLink: UInt16 = 0
	/// Whatever is emulating this pane.
	///
	/// A `TerminalEngine` rather than a `TerminalEmulator` since item 0485, which
	/// is what makes `Settings.terminalGhosttyEngine` mean something. The property
	/// kept its name on purpose: renaming it would have turned eighty-four call
	/// sites into diff noise around the handful of lines that actually changed,
	/// and this is the file the item most wanted left recognisable.
	let emulator: TerminalEngine
	let pty: PseudoTerminal

	/// Fired when the process exits, so the panel can label the tab.
	var onProcessExit: ((Int32) -> Void)?
	/// Fired when output arrives, for views that summarise a session they are
	/// not showing.
	var onOutput: (() -> Void)?
	var onTitleChange: ((String) -> Void)?
	/// `abydos <file>` was typed in this pane.
	var onOpenFile: ((TerminalOpenRequest) -> Void)?

	var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	/// Glyphs already looked up, thrown away when the font changes.
	let glyphs = GlyphCache()
	/// Set up only when the setting asks for it, so the CoreGraphics path stays
	/// exactly as it was for anyone who has not.
	var metal: (renderer: TerminalMetalRenderer, view: TerminalMetalView)?
	/// Something changed and the screen has not been drawn since.
	var needsRender = false
	/// Drives drawing at the rate the display actually refreshes.
	var displayLink: CADisplayLink?
	/// Guards the resize callback against the redraw that caused it.
	var isPositioningMetalView = false
	/// Distance from the top of a cell to the baseline the text sits on.
	var baselineFromTop: CGFloat = 12
	/// The four faces a cell can ask for, worked out once per font change.
	///
	/// Deriving a bold or italic face goes through NSFontManager, which is not
	/// cheap, and it was being asked for once per run of every frame — several
	/// hundred times a frame on a busy screen.
	var faces = TerminalFaces(base: .monospacedSystemFont(ofSize: 12, weight: .regular))
	var cellWidth: CGFloat = 7
	var cellHeight: CGFloat = 16
	var baselineOffset: CGFloat = 4

	/// Follows output unless the user scrolls up to read history.
	var isPinnedToBottom = true
	/// Points a trackpad has moved that are not yet a whole line for the
	/// program. See `WheelSteps` for why a wheel and a trackpad differ.
	var wheelSteps = WheelSteps()

	/// Highlighted while files are held over the view.
	var isDropTarget = false
	/// Pictures turned into something drawable, by the id the program gave them.
	var imageCache: [UInt32: CGImage] = [:]
	/// What the store's generation was when the cache was last checked.
	var lastGraphicsGeneration = 0
	/// Where the cursor was last painted, so the cell it leaves is repainted.
	var lastDrawnCursorRow: Int?

	/// Output read from the process but not yet parsed.
	///
	/// Parsed a little at a time rather than all at once. A program can produce
	/// output faster than any terminal can show it — a full-screen animation
	/// does exactly that — and parsing every byte the moment it arrives leaves
	/// the main thread no time to draw or to listen, which reads as a freeze
	/// however fast the parser is.
	private var pending: [PendingOutput] = []
	private var pendingBytes = 0

	/// A delivery from the pty, when it arrived, and how much of it is parsed.
	///
	/// The arrival time is what makes "behind" measurable. `!pending.isEmpty`
	/// answers "is there more to read", which is not the same question and is
	/// permanently true against a program that writes as fast as it is read
	/// (item 0491).
	///
	private struct PendingOutput {
		let data: Data
		let arrivedAt: Date
	}
	private var drainScheduled = false
	private var isReadingSuspended = false
	/// When the screen was last drawn, for pacing redraws while catching up.
	private var lastRedrawAt = Date.distantPast
	/// How many times the screen has actually been drawn, for a test to say
	/// whether a burst was replayed or held.
	static var drawCountForTesting = 0

	/// The grid a terminal starts with, before layout has told it anything.
	///
	/// **A constant here is wrong for exactly the output that cannot be fixed
	/// afterwards.** A pane starts its process once `launchWhenSized` sees it
	/// laid out — or, after twenty attempts, regardless — and a pane that starts
	/// unsized keeps whatever the emulator was constructed with, because
	/// `recomputeGridSize` returns early on a view with no bounds. Layout does
	/// correct the emulator and the pty a moment later, and it is too late by
	/// then: scrollback does not reflow, so everything printed in between stays
	/// wrapped at the constructed width for as long as the pane exists. A JVM's
	/// `-D` flags folded at eighty columns down the left of a much wider pane is
	/// what that looks like, and no resize will ever straighten it.
	///
	/// So the width a pane was last *measured* at is remembered and used instead.
	/// By the time anybody opens a second terminal there has been a first one,
	/// and its width is a much better guess: same window, same font, usually the
	/// same column of the panel.
	///
	/// It stays a guess, and it is allowed to be — `recomputeGridSize` overrides
	/// it the moment the pane is measured. The point is only that the guess it
	/// replaces was a fixed 24×80 that no pane in this app has ever been.
	static var lastMeasuredGrid: (rows: Int, columns: Int)?

	/// When the backlog started, or nil while caught up. A burst is held back
	/// rather than drawn frame by frame, and this is how long it has lasted.
	private var behindSince: Date?

	/// How long parsing may take before yielding so the screen can be drawn.
	///
	/// A deadline checked between deliveries, not inside one: a delivery is
	/// however many bytes were in the pty when it was read, up to 512 KB, and it
	/// goes into the engine whole. So this bounds the parse work per frame only
	/// as far as one delivery fits in a frame, and an engine that takes longer
	/// than that over one is an engine that costs frames. Deliberately not
	/// sliced; item 0491 says what that was measured to cost.
	private static let parseBudget: TimeInterval = 0.006
	/// How far behind the picture may fall before the process is made to wait,
	/// and how far it has to have caught up before the process runs again.
	///
	/// A tenth of a second is about six frames: long enough that an ordinary
	/// program never touches it, short enough that nobody sees the delay. There
	/// is nothing to be gained by letting it grow — a deeper queue does not parse
	/// any faster, so every extra millisecond of it is a millisecond the screen
	/// is out of date for no return.
	private static let backlogHoldTime: TimeInterval = 0.1
	private static let backlogResumeTime: TimeInterval = 0.03
	/// The same limits in bytes, as the backstop for one very large delivery.
	private static let backlogHighWater = 4 << 20
	private static let backlogLowWater = 1 << 20

	/// The two rules item 0491 replaced, kept switchable so both sides can be
	/// measured out of **one** binary.
	///
	/// That is not a convenience. The measurements this item exists to correct
	/// were taken from two different builds with a setting changed in between,
	/// and the setting turned out to be what moved the number — so a comparison
	/// that cannot be made out of one binary in one sitting is not a comparison.
	/// `ABYDOS_TERM_BEHIND=queue` asks "is the queue empty" again, and
	/// `ABYDOS_TERM_HOLD=bytes` makes the process wait on four megabytes rather
	/// than on a tenth of a second.
	private static let behindMeansQueueNotEmpty =
		ProcessInfo.processInfo.environment["ABYDOS_TERM_BEHIND"] == "queue"
	private static let holdsOnBytesOnly =
		ProcessInfo.processInfo.environment["ABYDOS_TERM_HOLD"] == "bytes"

	/// What the engine has said changed since the last frame was built.
	///
	/// The GPU path builds these rows and copies the rest out of the frame
	/// before, which is item 0488; `TerminalDirtyRows` is where the two awkward
	/// parts of that live — the union across batches, and the fact that a line
	/// leaving history renumbers every absolute row.
	var dirtyRows = TerminalDirtyRows()

	/// Text selected with the mouse, in absolute rows. Nil when nothing is.
	var selection: TerminalSelection?
	var isSelecting = false
	var lastDiscardedLineCount = 0
	var cursorVisible = true
	var cursorTimer: Timer?

	// No left margin: the terminal's own first column is where a terminal's
	// text starts, and an inset makes the panel look like a document with a
	// gutter rather than a screen. Set it back to 8 to have the breathing room.
	static let horizontalInset: CGFloat = 0
	static let verticalInset: CGFloat = 4

	/// When a key was last pressed, and what has happened to it since.
	///
	/// The echo of a keystroke is drawn as soon as it is parsed; everything
	/// else waits for the display's clock. The other two are for the probe,
	/// which answers "how long does a keystroke take to appear" — a question
	/// the code cannot answer by itself, because most of the wait is other
	/// people's: the shell's, tmux's, the display's.
	var keyPressedAt: Date?
	var keyEchoedAt: Date?
	var keyParsedAt: Date?

	/// Coalesces repaints to one per runloop turn.
	///
	/// A full-screen program repaints by emitting many small writes; redrawing on
	/// each one both wastes work and visibly tears, because the screen is
	/// composited mid-update. Batching to a single pass per turn is what removes
	/// the flicker.
	private var redrawScheduled = false

	// MARK: - Init

	/// A view that shows output but runs nothing.
	///
	/// The debug console is a terminal in every way that matters — the program
	/// under the debugger prints the same escape sequences it would anywhere
	/// else — except that nothing types into it and no shell belongs behind it.
	static func forOutput() -> TerminalView {
		TerminalView(workingDirectory: nil, command: nil, startsProcess: false)
	}

	init(
		workingDirectory: URL?,
		command: (executable: String, arguments: [String])? = nil,
		startsProcess: Bool = true
	) {
		// The last measured pane's grid, or the traditional default when this is
		// the first terminal of the session and there is nothing better to say.
		let initial = Self.lastMeasuredGrid ?? (rows: 24, columns: 80)
		emulator = Self.makeEngine(rows: initial.rows, columns: initial.columns)
		pty = PseudoTerminal()
		super.init(frame: .zero)

		wantsLayer = true
		layer?.backgroundColor = TerminalPalette.background.cgColor
		updateMetrics()

		emulator.onUpdate = { [weak self] in
			self?.realignSelectionForDiscardedLines()
			self?.scheduleRedraw()
			self?.onOutput?()
		}
		// Replies such as the cursor-position report must go back to the process,
		// otherwise shells that ask for it hang.
		emulator.onResponse = { [weak self] response in
			self?.pty.write(response)
		}
		emulator.onBell = { [weak self] in self?.ringBell() }

		// A copy made inside tmux, or on the other end of an ssh connection,
		// lands on the clipboard of the machine somebody is sitting at.
		emulator.onClipboardWrite = { text in
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(text, forType: .string)
		}

		// `abydos <file>`, typed in this pane. It goes to whoever owns the pane
		// rather than being acted on here: what the request asks for is an
		// editor, a keyboard and a panel, and a terminal view has none of them.
		emulator.onOpenFile = { [weak self] request in
			self?.onOpenFile?(request)
		}

		// What a program asks for when it wants to know whether it is being
		// read on a light background or a dark one.
		emulator.colourLookup = { query in
			let colour: NSColor
			switch query {
			case .foreground: colour = TerminalPalette.foreground
			case .background: colour = TerminalPalette.background
			case .cursor: colour = TerminalPalette.cursor
			case let .palette(index):
				guard index >= 0, index < 256 else { return nil }
				colour = TerminalPalette.color(
					for: .indexed(UInt8(index)), isForeground: true, bold: false
				)
			}
			guard let srgb = colour.usingColorSpace(.sRGB) else { return nil }
			return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
		}

		pty.onOutput = { [weak self] data, arrivedAt in
			self?.enqueue(data, arrivedAt: arrivedAt)
		}
		pty.onExit = { [weak self] code in
			self?.emulator.write("\r\n[process exited with status \(code)]\r\n")
			self?.onProcessExit?(code)
		}

		self.pendingLaunch = startsProcess ? (workingDirectory, command) : nil
		self.runsProcess = startsProcess
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		displayLink?.invalidate()
		cursorTimer?.invalidate()
		pty.terminate()
	}

	private var pendingLaunch: (URL?, (executable: String, arguments: [String])?)?

	/// What the pane's process is told about the pane, on top of what every
	/// shell in this app is told: the tab's identity as `ABYDOS_TERMINAL`, so a
	/// hook running in it can say which tab it is in. Set before the launch;
	/// the process starts once the pane has a size.
	var launchEnvironment: [String: String] = [:]
	/// False for a view that only displays output; there is nothing to type at.
	var runsProcess = true

	/// What ⌃C should stop, for a view that shows output and owns no process.
	///
	/// **Set only by a pane that has something to stop**, which is what keeps
	/// this to the debugger's console: the two streaming-log panes and the
	/// devcontainer's *preparing* terminal are read-only too, and what stopping
	/// means for each of them is a separate question nobody has answered. Where
	/// this is nil the view behaves exactly as it did — it refuses the keyboard
	/// and no key reaches it.
	var onInterrupt: (() -> Void)?

	override var isFlipped: Bool { true }
	/// A shell takes the keyboard because everything is typed at it. A view that
	/// only shows output takes it **only when there is something ⌃C could
	/// stop** — which is one key, not a keyboard: see `keyDown`.
	override var acceptsFirstResponder: Bool { runsProcess || onInterrupt != nil }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let motionTracking { removeTrackingArea(motionTracking) }

		// Only while this window has the keyboard: a pointer crossing a
		// background window is not something to report to a program in it.
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		motionTracking = area
	}

	/// An I-beam over the whole grid, because all of it is selectable text.
	///
	/// **Not `NSCursor.iBeam.set()`, which is what was here.**
	/// `updateHoveredLink` sets the cursor, but it returns unless the link under
	/// the pointer *changed* — so it says I-beam on the way off a hyperlink and
	/// never on the way across ordinary output, which is nearly all of a
	/// terminal. The pointer stayed an arrow over text that drags into a
	/// selection. A rect is also the only form that holds: AppKit re-applies
	/// these as the pointer moves, over the top of any one-shot `set()`.
	///
	/// The pointing hand over a hyperlink still wins — `updateHoveredLink` runs
	/// from `mouseMoved`, after the rects have been applied for that event.
	override func resetCursorRects() {
		super.resetCursorRects()
		addCursorRect(bounds, cursor: .iBeam)
	}

	private var motionTracking: NSTrackingArea?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		updateDisplayLink()
		watchWindowFocus()
		guard window != nil else { return }
		// Only now is the display known, and with it how many pixels a cell is.
		updateCellPixelSize()
		guard let launch = pendingLaunch else {
			updateMetalEnabled()
			viewportChanged()
			return
		}
		pendingLaunch = nil

		// Files dropped from the tree, or from any app that offers URLs.
		registerForDraggedTypes([.fileURL])

		updateMetalEnabled()

		launchWhenSized(launch)
	}

	/// Starts a process in a view that was opened without one.
	///
	/// The one caller is a terminal that showed something being got ready before
	/// it could be a shell — a devcontainer being pulled, built and installed
	/// into. It is the *same* view, deliberately: what was printed while the
	/// container was coming up is above the prompt afterwards, in the scrollback,
	/// which is what a terminal is for and what a log pane swapped for a shell
	/// could never be.
	///
	/// Nothing is cleared. A failure leaves the view exactly as it was, with
	/// nothing typed into it, because there is nothing to type at.
	func startProcess(
		_ command: (executable: String, arguments: [String]), workingDirectory: URL? = nil
	) {
		guard !runsProcess, !pty.isRunning else { return }
		runsProcess = true
		// Files dropped from the tree, which a view showing output has no use for
		// and a shell does.
		registerForDraggedTypes([.fileURL])
		launchWhenSized((workingDirectory, command))
	}

	/// Whether anything is typed at this view yet.
	var showsOutputOnly: Bool { !runsProcess }

	/// Waits until the pane has a real size before starting the child.
	///
	/// Measuring too early yields a grid a few rows tall. A full-screen program
	/// like tmux lays its status bar out once, at whatever size it was told, and
	/// never learns better unless something resizes afterwards — which is why the
	/// status line ended up near the top until the pane was dragged.
	private func launchWhenSized(_ launch: (URL?, (executable: String, arguments: [String])?), attempt: Int = 0) {
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }

			let height = self.enclosingScrollView?.contentView.bounds.height ?? 0
			let width = self.enclosingScrollView?.contentView.bounds.width ?? 0
			let isSized = height >= self.cellHeight * 4 && width >= self.cellWidth * 20

			// Give layout a few turns, then start anyway rather than never.
			guard isSized || attempt >= 20 else {
				self.launchWhenSized(launch, attempt: attempt + 1)
				return
			}

			self.recomputeGridSize()
			let environment = self.launchEnvironment.isEmpty ? nil : self.launchEnvironment
			if let command = launch.1 {
				self.pty.start(
					executable: command.executable,
					arguments: command.arguments,
					workingDirectory: launch.0,
					environment: environment,
					rows: self.emulator.metrics.rows,
					columns: self.emulator.metrics.columns
				)
			} else {
				self.pty.startLoginShell(
					workingDirectory: launch.0,
					environment: environment,
					rows: self.emulator.metrics.rows,
					columns: self.emulator.metrics.columns
				)
			}
			self.startCursorBlink()
		}
	}

	/// Takes output from the process and asks for it to be parsed soon.
	func enqueue(_ data: Data, arrivedAt: Date) {
		if InputProbe.enabled, keyPressedAt != nil, keyEchoedAt == nil { keyEchoedAt = Date() }
		pending.append(PendingOutput(data: data, arrivedAt: arrivedAt))
		pendingBytes += data.count
		applyBackPressure()
		scheduleDrain()
	}

	/// How far behind the program the picture on screen is, in seconds.
	///
	/// The oldest delivery nobody has parsed yet, measured from when it came off
	/// the pty. Zero when everything that has arrived has been parsed, which is
	/// the only state in which the grid is what the program last said.
	///
	/// This is the measurement item 0491 exists to introduce, and what it
	/// replaces is `!pending.isEmpty` — "there are bytes I have not parsed" —
	/// which is a different question with a different answer. Against a program
	/// that writes as fast as it is read the queue is never empty, so the old
	/// question was permanently answered yes and the screen was permanently held
	/// at one frame a second. Worse, it got *more* wrong as the parser got
	/// faster: a drain that keeps up reads more per second and empties the queue
	/// less often. Seconds behind have no such coupling — a hundred milliseconds
	/// behind is a hundred milliseconds behind whatever the parser costs and
	/// whichever pattern the program is writing.
	/// Both queues, because there are two and only one of them used to be
	/// counted: what has been handed over and not parsed, and what the pty has
	/// read and not handed over yet.
	private var staleBy: TimeInterval {
		let queued = pending.first.map { -$0.arrivedAt.timeIntervalSinceNow } ?? 0
		let held = pty.undeliveredBacklog.oldestAt.map { -$0.timeIntervalSinceNow } ?? 0
		return max(queued, held)
	}

	/// Everything read from the process and not yet on the grid.
	private var backlogBytes: Int { pendingBytes + pty.undeliveredBacklog.bytes }

	/// Makes the program wait when the picture would otherwise fall behind it.
	///
	/// Two limits, and the one that matters is the first. **Time**, because a
	/// backlog is only harmful in proportion to how long it takes to show: a
	/// queue holding a second of parsing is a screen a second out of date, and
	/// no amount of it improves throughput — the parser is the limit either way,
	/// and everything queued beyond what it can take is staleness bought for
	/// nothing. **Bytes**, still, as the backstop for a single enormous
	/// delivery, since one read gathers up to 512 KB and the time limit cannot
	/// see inside it.
	///
	/// This also shortens the exposure item 0468 found — a macOS pty discards
	/// unread output 600 ms after the child exits — because a queue bounded at a
	/// tenth of a second drains, and resumes, far sooner than one bounded at
	/// four megabytes, which on a slow pattern took seconds.
	private func applyBackPressure() {
		let behind = Self.holdsOnBytesOnly ? 0 : staleBy
		let bytes = backlogBytes
		if !isReadingSuspended, behind >= Self.backlogHoldTime || bytes >= Self.backlogHighWater {
			isReadingSuspended = true
			pty.setReadingSuspended(true)
		} else if isReadingSuspended, behind <= Self.backlogResumeTime, bytes <= Self.backlogLowWater {
			isReadingSuspended = false
			pty.setReadingSuspended(false)
		}
	}

	private func scheduleDrain() {
		guard !drainScheduled, !pending.isEmpty else { return }
		drainScheduled = true

		// A delay rather than an immediate hop, for two reasons. Blocks queued
		// on the main queue are all run before the display cycle, so re-queueing
		// at once would starve drawing exactly as parsing everything inline did.
		// And a program repainting writes its picture in several goes: two
		// milliseconds of gathering is what turns those into one picture rather
		// than three, one of which has the cursor somewhere it never really was.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { [weak self] in
			self?.drain()
		}
	}

	/// Parses what has arrived, for as long as the budget allows.
	private func drain() {
		StallWatch.mark("terminal parse") { drainMarked() }
	}

	private func drainMarked() {
		drainScheduled = false
		let deadline = Date().addingTimeInterval(Self.parseBudget)

		while !pending.isEmpty {
			if MetalProbe.enabled { MetalProbe.note(staleBy: staleBy) }
			let chunk = pending.removeFirst()
			pendingBytes -= chunk.data.count
			let parseStart = MetalProbe.enabled ? Date() : nil
			emulator.write(chunk.data)
			if let parseStart {
				let spent = -parseStart.timeIntervalSinceNow
				MetalProbe.parseSeconds += spent
				MetalProbe.note(delivery: spent, bytes: chunk.data.count)
			}
			if Date() >= deadline { break }
		}

		if let title = emulator.title { onTitleChange?(title) }

		// Caught up enough that the process may carry on — or, having spent the
		// budget without catching up, far enough behind that it should wait.
		// Asked here as well as on arrival because staleness grows with the clock
		// and not only with what the program sends.
		applyBackPressure()

		// Caught up: draw what it all came to. Redraws asked for while there
		// was still a backlog were skipped, and this is the one that shows the
		// picture they were each a step towards.
		if pending.isEmpty {
			behindSince = nil
			scheduleRedraw()
		}
		scheduleDrain()
	}

	func scheduleRedraw() {
		guard !redrawScheduled else { return }

		// Held back only while the picture is genuinely out of date: each frame
		// drawn out of a backlog paints a screen the program has already
		// replaced, which is what a locked screen looks like when it comes back
		// — an agent's clock sprinting through minutes it already spent. What
		// says so is how many seconds behind the oldest unparsed delivery is,
		// not whether there is anything left to parse; item 0491 is the day that
		// distinction cost.
		let behind = Self.behindMeansQueueNotEmpty
			? (pending.isEmpty ? 0 : .greatestFiniteMagnitude)
			: staleBy
		if behind >= RedrawThrottle.liveWindow {
			if behindSince == nil { behindSince = Date() }
		} else {
			behindSince = nil
		}
		guard RedrawThrottle.shouldDraw(
			staleBy: behind,
			sinceLastDraw: Date().timeIntervalSince(lastRedrawAt),
			behindFor: behindSince.map { -$0.timeIntervalSinceNow } ?? 0
		) else { return }

		redrawScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.redrawScheduled = false
			self.lastRedrawAt = Date()
			TerminalView.drawCountForTesting += 1

			// The alternate screen is one screenful that never scrolls: the
			// document is exactly the grid and the view sits at the top of it.
			// Left alone it keeps whatever height the scrollback had when the
			// program took over — a document thousands of points tall, scrolled
			// to the end of it — and the screen is then somewhere above the
			// window. That is a terminal gone blank, or, when the mismatch is a
			// single row, a last line nobody can see.
			self.updateFrameSize()
			if self.emulator.isAlternateScreen {
				self.scrollToTop()
			} else if self.isPinnedToBottom {
				self.scrollToBottom()
			}
			if InputProbe.enabled, self.keyEchoedAt != nil, self.keyParsedAt == nil {
				self.keyParsedAt = Date()
			}
			self.invalidateChangedRows()
		}
	}

	// MARK: - GPU

	/// Asks for the screen to be drawn again, whichever renderer is in use.
	///
	/// Marking the view for display reaches CoreGraphics only; the GPU path
	/// draws when it is told to.
	func repaint() {
		guard let metal else {
			needsDisplay = true
			return
		}
		// Everything that calls this is saying the whole picture may differ for a
		// reason the engine cannot have reported — a theme, a font, the keyboard
		// arriving, a link under the pointer. The renderer keeps what it built
		// for each row and has no way to know about any of them, so this is
		// where it is told.
		metal.renderer.invalidateRows()
		requestFrame()
	}

	/// Asks the GPU path for a frame, now or at the next tick of the display.
	///
	/// Normally noted rather than drawn: asking for a drawable waits for the
	/// display, and doing that while output pours in makes everything that
	/// produced the change wait with it.
	///
	/// But when nothing has been drawn for a frame or more there is nothing to
	/// coalesce with and the drawable is free, so waiting buys nothing and
	/// costs half a frame on average — which, for somebody typing, is most of
	/// the delay between pressing a key and seeing it.
	func requestFrame() {
		needsRender = true

		// Only for somebody's own typing coming back. A program painting the
		// screen does it in stages — the cursor parked somewhere while a line
		// is rewritten, hidden while it draws — and every one of those stages
		// drawn as it arrives is a cursor that flickers and appears in places
		// it was never meant to be seen. Those wait for the display's clock,
		// as they always did, and only the state they settle in is shown.
		guard isEchoingKeystroke else { return }
		guard pending.isEmpty, !drainScheduled else { return }
		guard -lastRenderedAt.timeIntervalSinceNow >= frameInterval else { return }
		// One frame per keystroke: whatever the program does afterwards is the
		// program's own repainting.
		hasDrawnEcho = true

		// The scroll view has just been told the document grew and where to
		// sit; drawing before it has laid that out would put the picture a line
		// from where it belongs and the next frame would put it back.
		enclosingScrollView?.layoutSubtreeIfNeeded()

		// Handed over inside a transaction of its own. The layer presents with
		// the transaction, and outside the display link's tick there is no
		// saying when the one already open will commit — which is the
		// difference between a frame appearing now and a frame appearing
		// twice.
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		renderIfNeeded()
		CATransaction.commit()
	}

	/// Whether what has just been parsed is the echo of a key that was pressed.
	///
	/// Bounded in time because not every key produces output — a shell may
	/// ignore it entirely — and a keystroke that was never echoed must not
	/// license an immediate frame minutes later.
	private var isEchoingKeystroke: Bool {
		guard let pressed = keyPressedAt, !hasDrawnEcho else { return false }
		return -pressed.timeIntervalSinceNow < Self.echoWindow
	}

	/// Whether this keystroke has already had its frame.
	var hasDrawnEcho = false

	/// How long after a key is pressed its echo is still its echo.
	private static let echoWindow: TimeInterval = 0.15

	/// When the last frame was handed over, and how long a frame lasts here.
	///
	/// The display link knows the real rate — 60 on these monitors, 120 on a
	/// laptop — and the fallback only matters before it has ticked once.
	private var lastRenderedAt = Date.distantPast
	private var frameInterval: TimeInterval {
		let duration = displayLink?.duration ?? 0
		return duration > 0 ? duration : 1.0 / 60
	}

	/// Turns the GPU path on or off to match the setting.
	func updateMetalEnabled() {
		let wanted = Settings.shared.terminalGPURendering
		if wanted, metal == nil {
			let scale = window?.backingScaleFactor ?? 2
			guard let renderer = TerminalMetalRenderer(scale: scale) else { return }
			let view = TerminalMetalView(device: renderer.device)
			view.scale = scale
			view.onResize = { [weak self] in self?.renderMetal() }
			addSubview(view)
			metal = (renderer, view)
		} else if !wanted, let existing = metal {
			existing.view.removeFromSuperview()
			metal = nil
		}
		updateDisplayLink()
		repaint()
	}

	/// Keeps the drawable over the part of the document that is on screen.
	///
	/// The view spans every line of history, which no drawable can, so the layer
	/// rides on top of the visible window and is told where that is.
	func positionMetalView() {
		guard let metal else { return }
		let visible = visibleRect
		// Resizing the view asks for a redraw, and this is called from one — so
		// the request is noted and answered by the redraw already under way.
		if metal.view.frame != visible {
			isPositioningMetalView = true
			metal.view.frame = visible
			isPositioningMetalView = false
		}
		metal.view.scale = window?.backingScaleFactor ?? 2
		metal.renderer.scale = window?.backingScaleFactor ?? 2
	}

	/// Starts and stops the clock that drawing runs on.
	private func updateDisplayLink() {
		let wanted = metal != nil && window != nil
		if wanted, displayLink == nil {
			let link = displayLink(target: self, selector: #selector(renderIfNeeded))
			link.add(to: .main, forMode: .common)
			displayLink = link
		} else if !wanted, let link = displayLink {
			link.invalidate()
			displayLink = nil
		}
	}

	/// Draws, at most once per refresh of the display.
	///
	/// Asking for a drawable waits until the display has finished with the last
	/// one. Measured inline, that wait was sixty per cent of the main thread —
	/// and since output was parsed on the same thread, everything the terminal
	/// was being sent waited for the screen. Nothing is gained by it: the
	/// display shows sixty frames a second whatever we do.
	@objc private func renderIfNeeded() {
		// While the bell is showing, every frame differs from the last even
		// though nothing was printed, so the usual "only when something
		// changed" rule has to be suspended for its duration.
		if isBellShowing { needsRender = true }
		guard needsRender, metal != nil else { return }

		// A program part-way through rewriting the screen has said so, and what
		// is on the grid meanwhile is half-drawn. Waiting for it to finish is
		// the difference between a pane resize that redraws and one that
		// flickers.
		if emulator.isSynchronizingOutput {
			let now = Date()
			if heldFrameSince == nil { heldFrameSince = now }
			// Unless it has been holding too long. A program that sets the mode
			// and then stops — or is killed — must not freeze the screen.
			if now.timeIntervalSince(heldFrameSince ?? now) < Self.longestHeldFrame { return }
		}
		heldFrameSince = nil

		needsRender = false
		lastRenderedAt = Date()
		renderMetal()
		noteKeystrokeShown()
	}
}
