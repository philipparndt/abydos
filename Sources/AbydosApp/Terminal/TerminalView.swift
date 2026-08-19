import AppKit
import AbydosKit

/// Renders a `TerminalEngine`'s grid and forwards input to its process.
///
/// Same virtualisation principle as the code view: only the rows in the
/// viewport are drawn, and cells are batched into runs of identical attributes
/// so a full-colour screen costs a handful of draw calls rather than one per
/// character.
final class TerminalView: NSView, NSTextInputClient {
	/// Whatever is emulating this pane.
	///
	/// A `TerminalEngine` rather than a `TerminalEmulator` since item 0485, which
	/// is what makes `Settings.terminalGhosttyEngine` mean something. The property
	/// kept its name on purpose: renaming it would have turned eighty-four call
	/// sites into diff noise around the handful of lines that actually changed,
	/// and this is the file the item most wanted left recognisable.
	private let emulator: TerminalEngine
	private let pty: PseudoTerminal

	/// Fired when the process exits, so the panel can label the tab.
	var onProcessExit: ((Int32) -> Void)?
	/// Fired when output arrives, for views that summarise a session they are
	/// not showing.
	var onOutput: (() -> Void)?
	var onTitleChange: ((String) -> Void)?
	/// `abydos <file>` was typed in this pane.
	var onOpenFile: ((TerminalOpenRequest) -> Void)?

	private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	/// Glyphs already looked up, thrown away when the font changes.
	private let glyphs = GlyphCache()
	/// Set up only when the setting asks for it, so the CoreGraphics path stays
	/// exactly as it was for anyone who has not.
	private var metal: (renderer: TerminalMetalRenderer, view: TerminalMetalView)?
	/// Something changed and the screen has not been drawn since.
	private var needsRender = false
	/// Drives drawing at the rate the display actually refreshes.
	private var displayLink: CADisplayLink?
	/// Guards the resize callback against the redraw that caused it.
	private var isPositioningMetalView = false
	/// Distance from the top of a cell to the baseline the text sits on.
	private var baselineFromTop: CGFloat = 12
	/// The four faces a cell can ask for, worked out once per font change.
	///
	/// Deriving a bold or italic face goes through NSFontManager, which is not
	/// cheap, and it was being asked for once per run of every frame — several
	/// hundred times a frame on a busy screen.
	private var faces = TerminalFaces(base: .monospacedSystemFont(ofSize: 12, weight: .regular))
	private var cellWidth: CGFloat = 7
	private var cellHeight: CGFloat = 16
	private var baselineOffset: CGFloat = 4

	/// Follows output unless the user scrolls up to read history.
	private var isPinnedToBottom = true

	/// Highlighted while files are held over the view.
	private var isDropTarget = false
	/// Pictures turned into something drawable, by the id the program gave them.
	private var imageCache: [UInt32: CGImage] = [:]
	/// What the store's generation was when the cache was last checked.
	private var lastGraphicsGeneration = 0
	/// Where the cursor was last painted, so the cell it leaves is repainted.
	private var lastDrawnCursorRow: Int?

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
	private var dirtyRows = TerminalDirtyRows()

	/// Text selected with the mouse, in absolute rows. Nil when nothing is.
	private var selection: TerminalSelection?
	private var isSelecting = false
	private var lastDiscardedLineCount = 0
	private var cursorVisible = true
	private var cursorTimer: Timer?

	// No left margin: the terminal's own first column is where a terminal's
	// text starts, and an inset makes the panel look like a document with a
	// gutter rather than a screen. Set it back to 8 to have the breathing room.
	private static let horizontalInset: CGFloat = 0
	private static let verticalInset: CGFloat = 4

	/// When a key was last pressed, and what has happened to it since.
	///
	/// The echo of a keystroke is drawn as soon as it is parsed; everything
	/// else waits for the display's clock. The other two are for the probe,
	/// which answers "how long does a keystroke take to appear" — a question
	/// the code cannot answer by itself, because most of the wait is other
	/// people's: the shell's, tmux's, the display's.
	private var keyPressedAt: Date?
	private var keyEchoedAt: Date?
	private var keyParsedAt: Date?

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
		emulator = Self.makeEngine(rows: 24, columns: 80)
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
	/// False for a view that only displays output; there is nothing to type at.
	private var runsProcess = true

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { runsProcess }

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
			if let command = launch.1 {
				self.pty.start(
					executable: command.executable,
					arguments: command.arguments,
					workingDirectory: launch.0,
					rows: self.emulator.metrics.rows,
					columns: self.emulator.metrics.columns
				)
			} else {
				self.pty.startLoginShell(
					workingDirectory: launch.0,
					rows: self.emulator.metrics.rows,
					columns: self.emulator.metrics.columns
				)
			}
			self.startCursorBlink()
		}
	}

	/// Takes output from the process and asks for it to be parsed soon.
	private func enqueue(_ data: Data, arrivedAt: Date) {
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

	private func scheduleRedraw() {
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
	private func repaint() {
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
	private func requestFrame() {
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
	private var hasDrawnEcho = false

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
	private func positionMetalView() {
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

	// MARK: - Bell

	/// When the bell last rang, or nil if it is not showing.
	private var bellRangAt: Date?

	/// How long the picture takes to settle again.
	///
	/// Long enough to read as a fault in the tape rather than a glitch in the
	/// app, short enough that a program which rings twice in a second does not
	/// leave the screen permanently swimming.
	private static let bellDuration: TimeInterval = 0.65

	private func ringBell() {
		switch Settings.shared.terminalBellStyle {
		case "none":
			return
		case "vhs":
			// The visual bell is a shader. With the GPU renderer off there is
			// nothing to run it, so the beep stands in rather than the bell
			// doing nothing at all.
			guard metal != nil else {
				NSSound.beep()
				return
			}
			bellRangAt = Date()
			repaint()
		default:
			NSSound.beep()
		}
	}

	/// How much of the bell is left to show, and how long it has been going.
	private func bellState() -> (strength: Float, elapsed: Float) {
		guard let bellRangAt else { return (0, 0) }
		let elapsed = -bellRangAt.timeIntervalSinceNow
		guard elapsed < Self.bellDuration else {
			self.bellRangAt = nil
			return (0, 0)
		}

		// Decays as a curve rather than a line: most of the movement happens
		// early, which is how a tape settles, and the last of it fades out
		// instead of stopping.
		let remaining = Float(1 - elapsed / Self.bellDuration)
		return (remaining * remaining, Float(elapsed))
	}

	/// Whether the picture is still moving and needs another frame.
	private var isBellShowing: Bool { bellRangAt != nil }

	/// When the current frame was first held back, if it was.
	private var heldFrameSince: Date?
	/// How long to believe a program that says it is mid-repaint.
	private static let longestHeldFrame: TimeInterval = 0.1

	/// Draws what is on screen.
	private func renderMetal() {
		guard let metal, !isPositioningMetalView else { return }
		metal.renderer.bell = bellState()
		let probing = MetalProbe.enabled
		positionMetalView()

		let visible = visibleRect
		guard visible.width >= 1, visible.height >= 1 else { return }

		let screen = emulator.grid
		let first = max(0, Int(floor((visible.minY - Self.verticalInset) / cellHeight)))
		let last = min(shownLineCount, Int(ceil((visible.maxY - Self.verticalInset) / cellHeight)) + 1)
		guard last > first else { return }

		var rows: [(index: Int, line: TerminalLine)] = []
		rows.reserveCapacity(last - first)
		for index in first..<last {
			guard let line = screen.line(at: index) else { continue }
			rows.append((index, line))
		}

		var overlays: [TerminalMetalRenderer.Overlay] = []
		if let selection {
			for index in first..<last {
				guard let line = screen.line(at: index),
				      let range = selection.columnRange(onRow: index, columns: line.cells.count)
				else { continue }
				overlays.append(.init(
					row: index,
					columns: range,
					colour: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).components
				))
			}
		}
		metal.renderer.hoveredLink = hoveredLink

		var cursor: TerminalMetalRenderer.Cursor?
		if let place = cursorPlace(), place.row < shownLineCount {
			cursor = .init(
				row: place.row,
				column: place.column,
				colour: TerminalPalette.cursor.components,
				shape: emulator.cursorShape,
				// Outlined when the keyboard is somewhere else: the cursor is
				// still where it was, and typing would not go there.
				isFilled: hasKeyboardFocus,
				thickness: Float(1.5)
			)
		}

			InputProbe.frame(
				cursor: cursor != nil,
				row: cursor?.row ?? -1,
				column: cursor?.column ?? -1
			)

		let background = TerminalPalette.background.components
		let buildStart = probing ? Date() : nil
		let frame = TerminalMetalRenderer.Frame(
			cellSize: CGSize(width: cellWidth, height: cellHeight),
			inset: CGPoint(x: Self.horizontalInset, y: Self.verticalInset),
			origin: visible.origin,
			background: background,
			foreground: TerminalPalette.foreground.components,
			discardedLineCount: screen.discardedLineCount
		)
		// Before the cells: what this decides about pictures behind the text is
		// what stops those cells painting over them.
		metal.renderer.buildImages(
			placements: emulator.graphics.placements.filter { $0.rowRange.overlaps(first..<last) }
				+ placeholderPlacements(from: first, to: last),
			store: emulator.graphics,
			frame: frame
		)
		metal.renderer.build(
			rows: rows,
			// Everything the engine has reported since the last frame, as line
			// numbers. Taken here rather than in `invalidateChangedRows`, which
			// runs several times per frame and only gathers.
			changed: dirtyRows.take(discardedLineCount: screen.discardedLineCount),
			frame: frame,
			faces: faces,
			overlays: overlays,
			cursor: cursor
		)

		if let buildStart { MetalProbe.buildSeconds += -buildStart.timeIntervalSinceNow }

		let drawableStart = probing ? Date() : nil
		guard let drawable = metal.view.nextDrawable() else { return }
		if let drawableStart { MetalProbe.drawableSeconds += -drawableStart.timeIntervalSinceNow }

		let encodeStart = probing ? Date() : nil
		metal.renderer.render(
			to: drawable.texture,
			clear: background,
			viewport: SIMD2(Float(visible.width), Float(visible.height)),
			drawable: drawable
		)
		if let encodeStart { MetalProbe.encodeSeconds += -encodeStart.timeIntervalSinceNow }
		MetalProbe.renders += 1
		MetalProbe.cells += metal.renderer.cellsBuilt
		MetalProbe.rows += metal.renderer.rowsBuilt
		MetalProbe.instances += metal.renderer.instanceCount
	}

	/// Repaints the lines that changed, rather than the whole view.
	///
	/// Marking the whole view means AppKit cannot keep any of what it already
	/// has, which matters most while output streams past: a printed line changes
	/// one row, and the rest can be scrolled rather than drawn again.
	private func invalidateChangedRows() {
		pruneImageCache()
		if metal != nil {
			// Gathered rather than acted on. Output is parsed to a budget and
			// several batches of it arrive between two frames, so what the frame
			// needs is the union of what each of them changed — and the engine
			// hands its answer over once and forgets it.
			//
			// It used to be thrown away here, with a comment saying the GPU
			// redraws what is on screen and does not care how much of it
			// changed. That is true of the GPU and was never true of the work of
			// handing it the cells: item 0488 measured a quarter of a second per
			// second spent building 10,904 cells forty-three times, while the
			// GPU that received them idled at 9 ms.
			dirtyRows.note(emulator.takeDirtyRange())
			requestFrame()
			return
		}

		guard let range = emulator.takeDirtyRange() else {
			// The cursor may still have moved, which is a repaint of its own.
			invalidateCursorRows()
			return
		}

		// Beyond a certain share of the view, working out what to keep costs
		// more than painting it.
		let visibleRows = Int(ceil(visibleRect.height / max(1, cellHeight))) + 1
		guard range.count < max(4, visibleRows / 2) else {
			repaint()
			return
		}

		setNeedsDisplay(rect(forAbsoluteRows: range))
		invalidateCursorRows()
	}

	/// The cursor is drawn over a cell that is otherwise unchanged, so both the
	/// row it left and the row it is on have to be repainted.
	private func invalidateCursorRows() {
		let row = sizeAndHistory.scrollbackCount + emulator.cursorRow
		guard row != lastDrawnCursorRow else { return }
		if let previous = lastDrawnCursorRow {
			setNeedsDisplay(rect(forAbsoluteRows: previous...previous))
		}
		setNeedsDisplay(rect(forAbsoluteRows: row...row))
		lastDrawnCursorRow = row
	}

	private func rect(forAbsoluteRows range: ClosedRange<Int>) -> NSRect {
		let top = Self.verticalInset + CGFloat(range.lowerBound) * cellHeight
		let height = CGFloat(range.count) * cellHeight
		return NSRect(x: 0, y: top - 1, width: bounds.width, height: height + 2)
	}

	// MARK: - Metrics

	/// Logged once, so "which font is it actually using?" has a definite answer.
	private static var didLogFont = false

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		if !Self.didLogFont {
			Self.didLogFont = true
			FileHandle.standardError.write(Data("Abydos terminal font: \(font.fontName)\n".utf8))
		}

		// Cell metrics are rounded to whole points.
		//
		// A fractional advance accumulates across a row, so run backgrounds land
		// on sub-pixel boundaries and leave hairline seams between them — visible
		// as a step where a powerline separator meets the next segment. Whole-point
		// cells make neighbouring fills abut exactly.
		faces = TerminalFaces(base: font)
		glyphs.clear()
		let advance = faces.advance
		cellWidth = max(1, advance.rounded())
		cellHeight = max(1, (font.ascender - font.descender + font.leading).rounded() + 2)
		baselineOffset = (-font.descender + font.leading).rounded()
		// Where NSAttributedString would have put the baseline had it laid the
		// line out itself, which is what the glyphs have to line up with.
		baselineFromTop = (font.ascender + font.leading).rounded()
		updateCellPixelSize()
	}

	/// Tells the emulator and the process how large a cell is, in real pixels.
	///
	/// Pixels rather than points, and so scaled by the display. A program sizing
	/// a picture to the cell grid is sizing it to what will actually be shown,
	/// and reporting points on a Retina screen asks it for an image at half the
	/// resolution the screen can draw — which is the difference between a sharp
	/// picture and a soft one.
	///
	/// The screen when there is no window yet, rather than a flat two. Cells are
	/// measured before the view is in a window — the font is known long before
	/// anything is on screen — and assuming Retina there is a lie on a display
	/// that is not one: the pane told its program a cell was 16×38 where it is
	/// 8×19, and kitty's `icat`, which sizes a picture from exactly this, asked
	/// for half the cells it needed. The picture then changed size the moment
	/// anything resized the pane and the true number went out.
	/// A scale of zero is skipped rather than believed — see `CellPixelSize`,
	/// which is where that decision and its consequences are written down.
	private func updateCellPixelSize() {
		let size = CellPixelSize.pixels(
			cellWidth: Double(cellWidth),
			cellHeight: Double(cellHeight),
			scales: [
				window.map { Double($0.backingScaleFactor) },
				window?.screen.map { Double($0.backingScaleFactor) },
				NSScreen.main.map { Double($0.backingScaleFactor) },
				// A machine with no display at all, which is where 0397 left the
				// flat two: the last resort rather than the first answer.
				2,
			]
		)
		guard let size else { return }
		emulator.cellPixelSize = size
		pty.cellPixelSize = size
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = TerminalPalette.background.cgColor
		enclosingScrollView?.backgroundColor = TerminalPalette.background
		metal?.renderer.clearGlyphs()
		updateMetalEnabled()
		recomputeGridSize()
		repaint()
	}

	/// How many rows of the grid this pane actually shows.
	///
	/// Everything that walks rows — both renderers, the selection, the mouse,
	/// the document height — goes through this one definition rather than
	/// through the screen's own count.
	var shownLineCount: Int { sizeAndHistory.totalLineCount }

	/// How big the terminal is and how much history it has — **not a snapshot**.
	///
	/// Everything on this side of the seam that wants a count rather than a row goes
	/// through here, because the alternative is what item 0492 was: `emulator.grid`,
	/// asked once per delivery of output, copying eleven thousand cells out of
	/// libghostty-vt to read one integer. For our own engine the two are the same
	/// five field reads.
	///
	/// The environment variable is `TerminalCatchUp`'s, and it is here so that the
	/// before and the after can be measured out of one binary rather than two.
	private var sizeAndHistory: TerminalMetrics {
		guard TerminalCatchUp.perWrite else { return emulator.metrics }
		let grid = emulator.grid
		return TerminalMetrics(
			rows: grid.rows, columns: grid.columns,
			totalLineCount: grid.totalLineCount,
			scrollbackCount: grid.scrollbackCount,
			discardedLineCount: grid.discardedLineCount)
	}

	/// How much of the pane's height is not a whole row.
	///
	/// Always less than one row, and usually a point or two — which is why it
	/// went unnoticed at 1×. Scaling multiplies it: a four-point sliver becomes
	/// eight at 2×, which is enough of a line to read as a broken one against
	/// the top of the viewport. Reported so the panel can give it back rather
	/// than show it.
	var heightRemainder: CGFloat {
		guard let clip = enclosingScrollView?.contentView else { return 0 }
		let usable = clip.bounds.height - Self.verticalInset * 2
		guard usable > 0, cellHeight > 0 else { return 0 }
		return usable - floor(usable / cellHeight) * cellHeight
	}

	/// Keeps the grid the size of the pane, whatever else happened.
	///
	/// Everything that changes the pane's size or the size of a cell already
	/// asks for this, and a missed one is invisible until somebody types: the
	/// grid stays as wide as the pane used to be, the program is told the same,
	/// and every line then runs off the right-hand edge instead of wrapping —
	/// while the program's own idea of the text stays perfectly correct, so
	/// pressing return shows it laid out properly and nothing looks broken
	/// afterwards. Checking here costs a comparison per layout pass and repairs
	/// it whatever the cause was.
	override func layout() {
		super.layout()
		recomputeGridSize()
	}

	/// Derives rows and columns from the pane size and tells both the emulator
	/// and the process.
	private func recomputeGridSize() {
		guard let clip = enclosingScrollView?.contentView else { return }
		// Nothing to measure yet, so nothing is decided. A tab made without being
		// brought to the front is not laid out until somebody reveals it, and a
		// pane of no width answers the floor of `max(20, …)` — twenty columns.
		//
		// Harmless for a shell, which is told its size when it starts and is not
		// running before that. Permanent for a pane that is *written into* while
		// it is hidden, because scrollback does not reflow: 0459 photographed
		// four hundred lines of a build wrapped into a twenty-character column
		// down the left of a pane that was full width by the time anybody saw it.
		// Keeping the eighty columns it was made with is both wider and more
		// honest — eighty is a width, and twenty was a measurement of a view that
		// is not on screen.
		guard clip.bounds.width > 1, clip.bounds.height > 1 else { return }
		let usableWidth = clip.bounds.width - Self.horizontalInset * 2
		let usableHeight = clip.bounds.height - Self.verticalInset * 2

		let columns = max(20, Int(floor(usableWidth / max(1, cellWidth))))
		let rows = max(4, Int(floor(usableHeight / max(1, cellHeight))))

		let size = sizeAndHistory
		guard rows != size.rows || columns != size.columns else { return }
		// A resize reflows what the absolute rows mean, and there is no honest
		// mapping from the old grid to the new one.
		setSelection(nil)
		emulator.resize(rows: rows, columns: columns)
		pty.resize(rows: rows, columns: columns)
		updateFrameSize()
	}

	private func updateFrameSize() {
		// `sizeAndHistory` rather than `emulator.grid`, and it matters: this runs once
		// per turn of the main queue while output pours in, and for libghostty-vt a
		// snapshot means copying every visible cell across the FFI boundary (0492).
		let size = sizeAndHistory
		let totalRows = emulator.isAlternateScreen ? size.rows : size.totalLineCount
		let height = CGFloat(totalRows) * cellHeight + Self.verticalInset * 2
		let width = enclosingScrollView?.contentSize.width ?? bounds.width
		let newSize = NSSize(width: max(width, 10), height: max(height, 10))
		if abs(newSize.height - frame.height) > 0.5 || abs(newSize.width - frame.width) > 0.5 {
			setFrameSize(newSize)
		}
	}

	/// Puts the view at the top of the document, where the alternate screen is.
	func scrollToTop() {
		guard let scrollView = enclosingScrollView, scrollView.contentView.bounds.origin.y != 0
		else { return }
		scrollView.contentView.scroll(to: .zero)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	func scrollToBottom() {
		guard let scrollView = enclosingScrollView else { return }
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	/// Called by the container when the clip view's bounds change.
	func viewportChanged() {
		guard let scrollView = enclosingScrollView else {
			recomputeGridSize()
			return
		}

		// Decided before the grid changes, not after. A resize moves the bottom
		// of the document, so comparing the old offset against the new maximum
		// unpins a view that was following the output — leaving the prompt off
		// screen with stale lines showing in its place.
		let offset = scrollView.contentView.bounds.origin.y
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		isPinnedToBottom = offset >= maxY - cellHeight

		recomputeGridSize()
		if metal != nil { needsRender = true }

		if isPinnedToBottom { scrollToBottom() }
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		StallWatch.mark("terminal draw") { drawMarked(dirtyRect) }
	}

	private func drawMarked(_ dirtyRect: NSRect) {
		defer { if metal == nil { noteKeystrokeShown() } }
		TerminalPalette.background.setFill()
		dirtyRect.fill()

		let screen = emulator.grid
		let firstRow = max(0, Int(floor((dirtyRect.minY - Self.verticalInset) / cellHeight)))
		let lastRow = min(shownLineCount, Int(ceil((dirtyRect.maxY - Self.verticalInset) / cellHeight)) + 1)
		guard lastRow > firstRow else { return }

		// A picture below the text is drawn first so the characters land on top of
		// it; one above covers them. That is what the z key means, and it is the
		// only ordering the protocol asks for.
		drawImages(from: firstRow, to: lastRow, above: false)

		for index in firstRow..<lastRow {
			guard let line = screen.line(at: index) else { continue }
			draw(line: line, atRow: index)
		}

		drawImages(from: firstRow, to: lastRow, above: true)

		drawCursor()
		drawDropHighlight()
	}

	/// Draws the pictures whose rows fall in the band being repainted.
	private func drawImages(from firstRow: Int, to lastRow: Int, above: Bool) {
		let placements = emulator.graphics.placements + placeholderPlacements(from: firstRow, to: lastRow)
		guard !placements.isEmpty else { return }
		guard let context = NSGraphicsContext.current?.cgContext else { return }

		// Sorted so overlapping pictures stack the way the program asked, and
		// equal depths keep the order they were placed in.
		let shown = placements
			.filter { (above ? $0.z >= 0 : $0.z < 0) && $0.rowRange.overlaps(firstRow..<lastRow) }
			.sorted { $0.z < $1.z }
		guard !shown.isEmpty else { return }

		context.saveGState()
		// A picture is placed on a cell grid, so it is almost always being scaled
		// by some fraction to reach a whole number of cells. Left to the default
		// that scaling stair-steps every edge.
		context.interpolationQuality = .high
		for placement in shown {
			guard let image = cachedImage(for: placement.imageID),
			      let cropped = crop(image, to: placement.source)
			else { continue }

			// Turned over inside its own box: this view counts rows from the
			// top, and CoreGraphics draws a picture up from the bottom, so
			// without this every image comes out upside down. The Metal
			// renderer has its own orientation and gets it right, which is why
			// it showed in screenshots and not on screen.
			let box = rect(for: placement)
			context.saveGState()
			context.translateBy(x: 0, y: box.midY)
			context.scaleBy(x: 1, y: -1)
			context.translateBy(x: 0, y: -box.midY)
			context.draw(cropped, in: box)
			context.restoreGState()
		}
		context.restoreGState()
	}

	/// The pictures spelled out by placeholder characters on the rows being
	/// repainted.
	///
	/// Worked out from the grid every time rather than remembered, which is the
	/// point of the whole mechanism: the cells are ordinary text, so whatever
	/// moved them — scrolling, tmux redrawing its pane, a narrower window —
	/// has already moved the picture, and reading where they are now is reading
	/// where the picture is now.
	private func placeholderPlacements(from firstRow: Int, to lastRow: Int) -> [TerminalImagePlacement] {
		guard emulator.graphics.hasVirtualPlacements else { return [] }
		var runs: [UnicodePlaceholder.Run] = []
		for index in firstRow..<lastRow {
			guard let line = emulator.grid.line(at: index) else { continue }
			runs += UnicodePlaceholder.runs(in: line.cells, screenRow: index)
		}
		guard !runs.isEmpty else { return [] }
		return emulator.graphics.placements(for: runs)
	}

	/// Where on the view a placement goes.
	private func rect(for placement: TerminalImagePlacement) -> NSRect {
		let scale = window?.backingScaleFactor ?? 2
		let x = Self.horizontalInset + CGFloat(placement.column) * cellWidth
			+ CGFloat(placement.offsetX) / scale
		let y = Self.verticalInset + CGFloat(placement.row) * cellHeight
			+ CGFloat(placement.offsetY) / scale
		return NSRect(
			x: x.rounded(),
			y: y.rounded(),
			width: (CGFloat(placement.columns) * cellWidth).rounded(),
			height: (CGFloat(placement.rows) * cellHeight).rounded()
		)
	}

	/// The image behind an id, built once and kept.
	///
	/// Turning a few megabytes of pixels into a `CGImage` on every repaint would
	/// cost more than everything else the terminal draws put together, and a
	/// picture on screen is repainted whenever anything near it changes.
	private func cachedImage(for id: UInt32) -> CGImage? {
		if let cached = imageCache[id] { return cached }
		guard let image = emulator.graphics.images[id] else { return nil }

		guard let provider = CGDataProvider(data: Data(image.pixels) as CFData) else { return nil }

		let built = CGImage(
			width: image.width,
			height: image.height,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: image.width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)
		imageCache[id] = built
		return built
	}

	/// The part of an image a placement shows, or the whole of it.
	private func crop(_ image: CGImage, to source: TerminalImagePlacement.Rectangle) -> CGImage? {
		guard source.x != 0 || source.y != 0
			|| source.width != image.width || source.height != image.height
		else { return image }
		return image.cropping(to: CGRect(
			x: source.x, y: source.y, width: source.width, height: source.height
		))
	}

	/// Drops cached images the emulator no longer holds.
	private func pruneImageCache() {
		guard emulator.graphics.generation != lastGraphicsGeneration else { return }
		lastGraphicsGeneration = emulator.graphics.generation
		let live = emulator.graphics.images
		imageCache = imageCache.filter { live[$0.key] != nil }
	}

	/// Draws one row, batching neighbouring cells that share attributes.
	private func draw(line: TerminalLine, atRow index: Int) {
		let y = (Self.verticalInset + CGFloat(index) * cellHeight).rounded()

		var column = 0
		while column < line.cells.count {
			let attributes = line.cells[column].attributes

			// Extend the run while attributes match.
			var end = column + 1
			while end < line.cells.count, line.cells[end].attributes == attributes {
				end += 1
			}

			let x = (Self.horizontalInset + CGFloat(column) * cellWidth).rounded()
			// Computed from the run's end rather than its length, so consecutive
			// runs share an edge exactly instead of each rounding independently.
			let endX = (Self.horizontalInset + CGFloat(end) * cellWidth).rounded()
			let resolved = attributes.resolved

			let background = TerminalPalette.color(for: resolved.background, isForeground: false, bold: false)
			if resolved.background != .default {
				background.setFill()
				NSRect(x: x, y: y.rounded(), width: endX - x, height: cellHeight).fill()
			}

			// Separators are filled shapes in the run's foreground colour, sized to
			// the cell exactly — which is what removes the seam and the height
			// mismatch a font glyph leaves behind. Hidden means hidden, so they
			// are skipped along with the text.
			if !attributes.hidden {
				drawSeparators(of: line, from: column, to: end, attributes: attributes, y: y)
				drawText(of: line, from: column, to: end, attributes: attributes, y: y)
			}

			column = end
		}

		drawSelection(on: line, atRow: index, y: y)
	}

	/// A border while files are held over the view, so the drop has a target.
	private func drawDropHighlight() {
		guard isDropTarget else { return }
		let outline = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
		outline.lineWidth = 2
		Theme.current.gitModified.setStroke()
		outline.stroke()
	}

	/// Tints the selected cells.
	///
	/// Drawn over the text rather than behind it, so the characters keep their
	/// own colours — a terminal's palette carries meaning, and repainting a
	/// selected region in system selection colours would throw that away.
	private func drawSelection(on line: TerminalLine, atRow index: Int, y: CGFloat) {
		guard let selection,
		      let range = selection.columnRange(onRow: index, columns: line.cells.count)
		else { return }

		let x = (Self.horizontalInset + CGFloat(range.lowerBound) * cellWidth).rounded()
		let endX = (Self.horizontalInset + CGFloat(range.upperBound) * cellWidth).rounded()

		NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).setFill()
		NSRect(x: x, y: y.rounded(), width: endX - x, height: cellHeight).fill()
	}

	/// Draws the powerline separators in a run as geometry filling their cells.
	private func drawSeparators(
		of line: TerminalLine,
		from start: Int,
		to end: Int,
		attributes: TerminalAttributes,
		y: CGFloat
	) {
		let colour = TerminalPalette.color(
			for: attributes.resolved.foreground,
			isForeground: true,
			bold: attributes.bold
		)

		for cellIndex in start..<end {
			let scalar = line.cells[cellIndex].scalar
			guard PowerlineGlyph.isSeparator(scalar) else { continue }

			let cellX = (Self.horizontalInset + CGFloat(cellIndex) * cellWidth).rounded()
			let cellEnd = (Self.horizontalInset + CGFloat(cellIndex + 1) * cellWidth).rounded()
			PowerlineGlyph.draw(
				scalar: scalar,
				in: NSRect(x: cellX, y: y.rounded(), width: cellEnd - cellX, height: cellHeight),
				color: colour
			)
		}
	}

	/// Draws one attribute run's characters, each on its own grid column.
	///
	/// Split into segments rather than drawn as one string. The cell width is a
	/// whole number of points so run backgrounds abut exactly, but the font's
	/// own advance is fractional — letting it lay out a whole run makes the text
	/// creep away from the grid by a fraction of a pixel per character, which
	/// reaches a full cell by the time a prompt and a command have been typed.
	/// The cursor is drawn on the grid, so the text ends up sitting a character
	/// away from it.
	private func drawText(
		of line: TerminalLine,
		from start: Int,
		to end: Int,
		attributes: TerminalAttributes,
		y: CGFloat
	) {
		let faceIndex = TerminalFaces.index(bold: attributes.bold, italic: attributes.italic)
		let drawFont = faces.face(bold: attributes.bold, italic: attributes.italic)

		let resolved = attributes.resolved
		var foreground = TerminalPalette.color(
			for: resolved.foreground,
			isForeground: true,
			bold: attributes.bold
		)
		if attributes.dim { foreground = foreground.withAlphaComponent(TerminalPalette.dimAmount) }

		guard let context = NSGraphicsContext.current?.cgContext else { return }
		context.saveGState()
		// The view is flipped, so the glyphs would come out upside down without
		// undoing that for the text alone.
		context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
		context.setFillColor(foreground.cgColor)

		let baseline = y + baselineFromTop
		var runGlyphs: [CGGlyph] = []
		var runPositions: [CGPoint] = []
		var runFont: CTFont?

		// One glyph per cell, deliberately: no ligatures. A terminal is a grid,
		// and shaping a run as a whole so `->` becomes an arrow also lets the
		// text drift off that grid. Not wanted here, and drawing per cell is
		// what makes a screen of individually coloured cells affordable.
		//
		// Glyphs are drawn in batches sharing a font. Almost every batch is the
		// whole run; a batch ends only where a character had to come from a
		// fallback face, which is rare enough to be worth not checking for.
		func flush() {
			guard let font = runFont, !runGlyphs.isEmpty else {
				runGlyphs.removeAll(keepingCapacity: true)
				runPositions.removeAll(keepingCapacity: true)
				return
			}
			CTFontDrawGlyphs(font, runGlyphs, runPositions, runGlyphs.count, context)
			runGlyphs.removeAll(keepingCapacity: true)
			runPositions.removeAll(keepingCapacity: true)
			runFont = nil
		}

		// Ligatures, where they are asked for and where they can happen.
		//
		// Shaping is the opposite of what the rest of this does — it decides
		// its own positions, and those drift off a whole-point grid — so the
		// shaper is asked only *which* characters join, and the result is put
		// back on the columns. A run with no two ligature-forming marks side by
		// side cannot join anything, and that is nearly every run.
		//
		// Shaped in the stretches of the run the font can be asked about,
		// rather than in one piece. One character it cannot be asked about
		// used to take the whole run's ligatures with it, and that is the bug
		// this had: a tmux pane border is drawn in the *default* colour while
		// its pane is not the active one, so it shares the attributes of the
		// text either side and lands in the same run. Every line the border
		// crossed lost its ligatures, and making the other pane active —
		// which paints the border green — gave them back.
		var ligated = [Bool](repeating: false, count: max(0, end - start))
		if Settings.shared.fontLigatures {
			let spans = Ligatures.spans(in: start..<end) { canShape(line.cells[$0]) }
			for span in spans {
				guard Ligatures.mayLigate(line.cells[span].lazy.map(\.scalar)),
				      drawLigated(
					of: line, from: span.lowerBound, to: span.upperBound,
					font: drawFont, baseline: baseline, context: context
				      )
				else { continue }
				for cellIndex in span { ligated[cellIndex - start] = true }
			}
		}

		for cellIndex in start..<end {
			// Already drawn, by the shaper, with whatever it chose to join.
			if ligated[cellIndex - start] { continue }
			let cell = line.cells[cellIndex]
			// The trailing half of a wide glyph carries no character of its own.
			if cell.isWideTrailer { continue }
			// Blanks have nothing to draw, and separators are drawn as geometry.
			if cell.scalar == 0x20 || cell.scalar == 0 { continue }
			// A placeholder is a piece of a picture, not a character. Drawn as
			// one it is a private-use codepoint no font has, so the picture
			// arrives under a grid of missing-glyph boxes.
			if cell.scalar == UnicodePlaceholder.scalar { continue }
			if PowerlineGlyph.isSeparator(cell.scalar) { continue }

			guard let found = glyphs.glyph(for: cell.scalar, face: drawFont, faceIndex: faceIndex) else {
				continue
			}
			if let current = runFont, current !== found.font { flush() }
			runFont = found.font

			// Each glyph sits on its own column rather than following the one
			// before it. The cell width is a whole number of points while the
			// font's advance is fractional, and letting the text lay itself out
			// makes it creep off the grid by a fraction of a pixel per
			// character — a whole cell by the end of a typed command, which
			// leaves the text sitting a character away from the cursor.
			let x = (Self.horizontalInset + CGFloat(cellIndex) * cellWidth).rounded()
			runGlyphs.append(found.glyph)
			runPositions.append(CGPoint(x: x, y: -baseline))
		}
		flush()
		context.restoreGState()

		if attributes.underline || attributes.strikethrough {
			drawTextDecoration(from: start, to: end, y: y, colour: foreground, attributes: attributes)
		}
	}

	/// Whether a cell's character can be handed to the font at all.
	///
	/// A powerline separator is drawn as geometry, a box drawing is not
	/// something to let a shaper join, and a placeholder is a piece of a
	/// picture rather than a character. None of them belongs in a shaped span,
	/// and a span stops at one rather than giving up on the whole run.
	private func canShape(_ cell: TerminalCell) -> Bool {
		cell.scalar != 0 && cell.scalar != UnicodePlaceholder.scalar
			&& !PowerlineGlyph.isSeparator(cell.scalar) && !BoxDrawing.draws(cell.scalar)
			&& UnicodeScalar(cell.scalar) != nil
	}

	/// Draws a span with its ligatures joined, and says whether it could.
	///
	/// The shaper is asked what joins; where each piece goes is decided here.
	/// A ligature glyph replaces the characters it covers, so it is drawn at
	/// the column of the first of them — and in a monospaced font its advance
	/// is exactly that many cells, so the grid is kept without forcing it.
	///
	/// Returns false for a span this cannot handle — anything drawn as geometry
	/// rather than from the font, or a picture's placeholder — leaving the
	/// per-cell path to do it. Callers hand it spans that hold none of those,
	/// so this is a guard rather than the way out of a run.
	private func drawLigated(
		of line: TerminalLine,
		from start: Int,
		to end: Int,
		font drawFont: NSFont,
		baseline: CGFloat,
		context: CGContext
	) -> Bool {
		var text = ""
		// Which cell each UTF-16 offset of `text` came from.
		var cellOfOffset: [Int] = []
		for cellIndex in start..<end {
			let cell = line.cells[cellIndex]
			if cell.isWideTrailer { continue }
			if cell.scalar == 0 { return false }
			if cell.scalar == UnicodePlaceholder.scalar { return false }
			if PowerlineGlyph.isSeparator(cell.scalar) || BoxDrawing.draws(cell.scalar) { return false }
			guard let scalar = UnicodeScalar(cell.scalar) else { return false }
			let piece = cell.combining ?? String(Character(scalar))
			text += piece
			cellOfOffset.append(contentsOf: Array(repeating: cellIndex, count: piece.utf16.count))
		}
		guard !text.isEmpty else { return false }

		let attributed = NSAttributedString(string: text, attributes: [.font: drawFont])
		let ctLine = CTLineCreateWithAttributedString(attributed)
		guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { return false }

		for run in runs {
			let count = CTRunGetGlyphCount(run)
			guard count > 0 else { continue }
			var glyphs = [CGGlyph](repeating: 0, count: count)
			var indices = [CFIndex](repeating: 0, count: count)
			CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
			CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)

			let attributes = CTRunGetAttributes(run) as NSDictionary
			guard let runFont = attributes[kCTFontAttributeName as String] as! CTFont? else { continue }

			var positions = [CGPoint]()
			positions.reserveCapacity(count)
			for index in 0..<count {
				let offset = Int(indices[index])
				guard offset >= 0, offset < cellOfOffset.count else { return false }
				let column = cellOfOffset[offset]
				positions.append(CGPoint(
					x: (Self.horizontalInset + CGFloat(column) * cellWidth).rounded(),
					y: -baseline
				))
			}
			CTFontDrawGlyphs(runFont, glyphs, positions, count, context)
		}
		return true
	}

	/// Underlines and strikethroughs, which the glyphs no longer carry with them.
	private func drawTextDecoration(
		from start: Int,
		to end: Int,
		y: CGFloat,
		colour: NSColor,
		attributes: TerminalAttributes
	) {
		let x = (Self.horizontalInset + CGFloat(start) * cellWidth).rounded()
		let endX = (Self.horizontalInset + CGFloat(end) * cellWidth).rounded()
		let thickness = max(1, (cellHeight / 14).rounded())
		colour.setFill()

		if attributes.underline {
			// Just below the baseline, where a font would put it.
			let underlineY = (y + baselineFromTop + thickness).rounded()
			NSRect(x: x, y: underlineY, width: endX - x, height: thickness).fill()
		}
		if attributes.strikethrough {
			let strikeY = (y + baselineFromTop - cellHeight / 4).rounded()
			NSRect(x: x, y: strikeY, width: endX - x, height: thickness).fill()
		}
	}

	/// Draws the block cursor, turning the cell under it inside out.
	///
	/// The block is the cursor's colour and the character is cut out of it in
	/// the colour behind. Laying a translucent block over the character instead
	/// leaves it the same colour as what is now behind it, which is how it
	/// becomes unreadable exactly where you are looking.
	private func drawCursor() {
		guard let place = cursorPlace() else { return }
		// A cursor parked on a row this pane does not show — tmux putting it on
		// its own status bar while it draws there — would otherwise be drawn at
		// the foot of the pane, on a line that is not the one it is on.
		guard place.row < shownLineCount else { return }

		let screen = emulator.grid
		let row = place.row
		let column = place.column
		let x = (Self.horizontalInset + CGFloat(column) * cellWidth).rounded()
		let endX = (Self.horizontalInset + CGFloat(column + 1) * cellWidth).rounded()
		let y = (Self.verticalInset + CGFloat(row) * cellHeight).rounded()

		let box = NSRect(x: x, y: y, width: endX - x, height: cellHeight)

		// Outlined when the keyboard is somewhere else — the cursor is still
		// where it was, and the character underneath stays as it was written.
		guard hasKeyboardFocus else {
			TerminalPalette.cursor.setStroke()
			let path = NSBezierPath(rect: box.insetBy(dx: 0.75, dy: 0.75))
			path.lineWidth = 1.5
			path.stroke()
			return
		}

		TerminalPalette.cursor.setFill()
		box.fill()

		// The character again, in the colour of what is now behind it.
		guard let line = screen.line(at: row), column < line.cells.count else { return }
		let cell = line.cells[column]
		guard cell.scalar != 0x20, cell.scalar != 0, !cell.attributes.hidden else { return }

		var attributes = cell.attributes
		attributes.foreground = .default
		attributes.background = .default
		attributes.inverse = true
		drawText(of: line, from: column, to: column + 1, attributes: attributes, y: y)
	}

	/// Repaints when the window gains or loses the keyboard.
	///
	/// Becoming first responder is not the only way focus moves: switching to
	/// another app leaves this view first responder in a window that is no
	/// longer key, and the cursor has to say so.
	private func watchWindowFocus() {
		let centre = NotificationCenter.default
		for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
			centre.removeObserver(self, name: name, object: nil)
			guard let window else { continue }
			centre.addObserver(
				forName: name, object: window, queue: .main
			) { [weak self] _ in self?.repaint() }
		}
	}

	/// Whether the cursor is drawn at all.
	///
	/// A program repainting hides the cursor, draws, and shows it again. Those
	/// are three writes and they need not arrive in the same frame — so
	/// honouring the hide the instant it arrives turns an ordinary repaint into
	/// a blink, which is what a flickering cursor is. A hide is believed only
	/// once it has lasted longer than a repaint would.
	private func cursorPlace() -> (row: Int, column: Int)? {
		guard cursorVisible else { return nil }

		let here = (
			row: emulator.metrics.scrollbackCount + emulator.cursorRow,
			column: emulator.cursorColumn
		)
		guard !emulator.isCursorVisible else {
			cursorHiddenSince = nil
			settledCursor = here
			return here
		}

		// Hidden. A program does that while it repaints — park the cursor
		// somewhere convenient, write, put it back — and both showing it where
		// it was parked and taking it away for those few milliseconds are
		// wrong: one is a cursor that jumps about, the other is a cursor that
		// blinks. So it stays where it last settled.
		guard let since = cursorHiddenSince else {
			cursorHiddenSince = Date()
			// The hide may be meant, and nothing more may arrive to say so;
			// the screen has to be asked again once the moment has passed.
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorHideGrace) { [weak self] in
				self?.repaint()
			}
			return settledCursor
		}

		// Unless it stays hidden, which is a program saying it means it.
		guard -since.timeIntervalSinceNow < Self.cursorHideGrace else { return nil }
		return settledCursor
	}

	/// Where the cursor was when the program last had it visible.
	private var settledCursor: (row: Int, column: Int)?

	/// When a program last asked for the cursor to go away.
	private var cursorHiddenSince: Date?
	/// How long a hide has to last before it is taken seriously — longer than
	/// the gap between the writes of one repaint, shorter than a glance.
	private static let cursorHideGrace: TimeInterval = 0.12

	/// Whether typing would go into this terminal.
	///
	/// Which is what the cursor says: filled here, outlined everywhere else.
	private var hasKeyboardFocus: Bool {
		guard let window, window.isKeyWindow else { return false }
		return window.firstResponder === self
	}

	/// The cursor is drawn solid rather than blinking.
	///
	/// A blink repaints the whole view twice a second whatever the program is
	/// doing, which on a busy screen is indistinguishable from the program
	/// being slow — and there is nothing to gain from it: the cursor is already
	/// the only filled block on the line.
	private func startCursorBlink() {
		cursorTimer?.invalidate()
		cursorTimer = nil
		cursorVisible = true
	}

	override func becomeFirstResponder() -> Bool {
		cursorVisible = true
		reportFocus(true)
		repaint()
		announceKeyboardFocusChange()
		return true
	}

	override func resignFirstResponder() -> Bool {
		reportFocus(false)
		repaint()
		announceKeyboardFocusChange()
		return true
	}

	/// Tells a program that the window gained or lost the keyboard.
	///
	/// Only when it has asked (mode 1004). tmux passes it through to whatever
	/// is in the pane, which is how a full-screen program knows to stop
	/// animating while nobody is looking at it.
	private func reportFocus(_ hasFocus: Bool) {
		guard emulator.reportsFocus else { return }
		pty.write(hasFocus ? "\u{1B}[I" : "\u{1B}[O")
	}

	// MARK: - Input

	/// Claims the ⌘ movement keys before the menu sees them.
	///
	/// A ⌘ combination is offered around as a key equivalent first, and one
	/// that nothing claims never arrives as a keyDown. Only the three the
	/// terminal has a meaning for are taken — ⌘C, ⌘V and the rest stay with the
	/// menu, where they belong.
	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		guard window?.firstResponder === self,
		      event.modifierFlags.contains(.command),
		      let key = TerminalKeys.Key(rawValue: event.keyCode),
		      let sequence = TerminalKeys.editingSequence(for: key, option: false, command: true)
		else { return super.performKeyEquivalent(with: event) }

		isPinnedToBottom = true
		pty.write(sequence)
		scrollToBottom()
		return true
	}

	var totalRowsForTesting: Int { max(1, emulator.metrics.totalLineCount) }

	/// Where the process in the foreground of this terminal is.
	func currentDirectory() -> URL? { pty.currentDirectory() }

	/// The terminal device this pane's shell is on.
	var ttyName: String? { pty.ttyName }

	/// The numbers behind "the last line is not on screen": how tall the
	/// document is, where the clip view sits in it, and how much of the grid
	/// that leaves visible.
	var geometryForTesting: String {
		let clip = enclosingScrollView?.contentView.bounds ?? .zero
		let bottomOfLastRow = Self.verticalInset
			+ CGFloat(shownLineCount) * cellHeight
		// The width as well as the height. A grid wider than the pane is
		// invisible until somebody types: every line runs off the right-hand
		// edge instead of wrapping, because the program was told the width the
		// pane used to be and is writing to it.
		let fits = Int(floor((clip.width - Self.horizontalInset * 2) / max(1, cellWidth)))
		let windowWidth = window?.frame.width ?? 0
		// The clip view's bounds *and* its frame. They are the same number
		// unless something has scaled the view, and a scaled clip view is
		// exactly how a grid comes out a factor of the backing scale too wide.
		let clipFrame = enclosingScrollView?.contentView.frame.width ?? 0
		let scale = window?.backingScaleFactor ?? 0
		return String(
			format: "engine=%@ gpu=%@ link=%@ onScreen=%@ alt=%@ rows=%d columns=%d fits=%d "
				+ "window=%.0f clipW=%.0f "
				+ "clipFrameW=%.0f scale=%.1f cell=%.1f "
				+ "frame=%.1f clip=%.1f origin=%.1f "
				+ "lastRowBottom=%.1f visible=%@ widthOK=%@",
			// Which engine emulated this pane. There are two of them now (0474),
			// so the first question about any terminal bug report is which one
			// drew it, and this is where the answer is — off the running app,
			// rather than by asking somebody to remember a setting.
			engineNameForTesting,
			// And which renderer drew it, for the same reason and one more: every
			// number `ABYDOS_METAL_PROBE` prints is zero when this says no, and a
			// probe reporting zero renders looks exactly like a renderer doing
			// nothing rather than like a renderer that was never made.
			metal != nil ? "yes" : "no",
			// The two other ways that probe reads zero while everything works.
			// The GPU path draws on the display's clock, and AppKit stops that
			// clock for a view whose window nobody can see — so a benchmark run
			// behind another window renders nothing, draws its picture through
			// the CoreGraphics path instead, screenshots perfectly, and reports
			// zeroes. That cost an hour of item 0488 before either of these
			// existed to be asked.
			displayLink != nil ? "yes" : "no",
			(window?.occlusionState.contains(.visible) ?? false) ? "yes" : "no",
			emulator.isAlternateScreen ? "yes" : "no",
			emulator.metrics.rows, emulator.metrics.columns, max(20, fits),
			windowWidth, clip.width, clipFrame, scale, cellWidth,
			frame.height, clip.height, clip.origin.y, bottomOfLastRow,
			bottomOfLastRow <= clip.origin.y + clip.height + 0.5 ? "yes" : "NO",
			max(20, fits) == emulator.metrics.columns ? "yes" : "NO"
		) + " " + winsizeForTesting
	}

	/// The engine this pane is actually using.
	///
	/// Read off the instance rather than off the setting, which is the difference
	/// between reporting what is drawing and reporting what somebody asked for.
	/// A pane made before the setting was changed keeps the engine it was made
	/// with, and this says so. Item 0474 added it and item 0485 made it true.
	var engineNameForTesting: String { type(of: emulator).engineName }

	/// Builds the engine the setting asks for.
	///
	/// **The setting is read once, when a pane is made**, and not afterwards: an
	/// engine holds the scrollback, the modes and the images, and swapping one out
	/// under a running shell would throw all three away mid-session. Turning the
	/// setting on therefore applies to the next pane, which is the same rule
	/// `terminalGPURendering` follows.
	///
	/// If libghostty-vt will not start — the library missing, or
	/// `ghostty_terminal_new` failing — this falls back to ours rather than
	/// handing back an engine whose every call is a no-op. A pane that draws
	/// nothing is worse than a pane drawn by the other engine, and
	/// `--report-geometry` prints which one it got.
	private static func makeEngine(rows: Int, columns: Int) -> TerminalEngine {
		guard Settings.shared.terminalGhosttyEngine else {
			return TerminalEmulator(rows: rows, columns: columns)
		}
		let ghostty = GhosttyTerminalEngine(rows: rows, columns: columns)
		guard ghostty.isUsable else { return TerminalEmulator(rows: rows, columns: columns) }
		return ghostty
	}

	/// What the kernel says this pane is, which is what the program sizing a
	/// picture actually reads.
	///
	/// Read back off the device rather than from what was last handed to it: the
	/// claim worth checking is that the program on the other end can see the
	/// number, not that this file remembered writing it. `icat` derives how many
	/// cells a picture needs from one thing only — `ypixel / rows` and `xpixel /
	/// columns` — so a `c=`/`r=` that surprises somebody is answered here and
	/// nowhere else, and a cell of `0x0` is the terminal saying it cannot show
	/// pictures at all. 0397 had to work this out from `icat`'s own bytes; 0468
	/// wanted it from a running app and there was no way to ask.
	var winsizeForTesting: String {
		guard let reported = pty.reportedWindowSize else { return "winsize=none" }
		let cell = (
			width: reported.columns > 0 ? reported.pixelWidth / reported.columns : 0,
			height: reported.rows > 0 ? reported.pixelHeight / reported.rows : 0
		)
		return "winsize=\(reported.rows)x\(reported.columns)"
			+ " pixels=\(reported.pixelHeight)x\(reported.pixelWidth)"
			+ " ptyCell=\(cell.width)x\(cell.height)"
	}

	/// Draws what is on screen through Metal and writes it out as a PNG.
	///
	/// The same content the CoreGraphics path would draw, so the two can be put
	/// side by side.
	func renderWithMetalForTesting(to path: String) -> Bool {
		let scale = window?.backingScaleFactor ?? 2
		guard let renderer = TerminalMetalRenderer(scale: scale) else { return false }

		// A screenful, laid out as the view would.
		let rows = 40
		let width = max(bounds.width, 400)
		let height = CGFloat(rows) * cellHeight + Self.verticalInset * 2
		let screen = emulator.grid
		var lines: [(index: Int, line: TerminalLine)] = []
		for row in 0..<rows {
			guard let line = screen.line(at: row) else { continue }
			lines.append((row, line))
		}

		let background = TerminalPalette.background.components
		let frame = TerminalMetalRenderer.Frame(
			cellSize: CGSize(width: cellWidth, height: cellHeight),
			inset: CGPoint(x: Self.horizontalInset, y: Self.verticalInset),
			origin: .zero,
			background: background,
			foreground: TerminalPalette.foreground.components
		)
		renderer.buildImages(
			placements: emulator.graphics.placements
				+ placeholderPlacements(from: 0, to: screen.scrollbackCount + screen.rows),
			store: emulator.graphics,
			frame: frame
		)
		renderer.build(
			rows: lines,
			frame: frame,
			faces: faces,
			// Drawn whatever has focus: a window rendered offscreen has none,
			// and the cursor is one of the things worth being able to look at.
			cursor: .init(
				row: screen.scrollbackCount + emulator.cursorRow,
				column: emulator.cursorColumn,
				colour: TerminalPalette.cursor.components
			)
		)
		// Whatever the bell is doing right now, since that is usually the
		// reason for taking one of these offscreen.
		renderer.bell = bellState()
		return renderer.writePNG(
			to: path,
			points: SIMD2(Float(width), Float(height)),
			clear: background
		)
	}

	/// What is on the screen and in the scrollback, for a check that something
	/// typed into a terminal answered.
	var screenTextForTesting: String {
		let screen = emulator.grid
		return (0..<screen.totalLineCount)
			.compactMap { screen.line(at: $0)?.text }
			.joined(separator: "\n")
	}

	/// Feeds output straight to the emulator, bypassing the process.
	func writeForTesting(_ text: String) {
		emulator.write(text)
		displayIfNeeded()
	}

	/// Shows text that came from somewhere other than a pty.
	func append(_ text: String) {
		enqueue(Data(text.utf8), arrivedAt: Date())
	}

	@objc func clearConsole(_ sender: Any?) { clear() }

	/// Empties the screen and the scrollback, for a session starting again.
	func clear() {
		emulator.write("\u{1B}c")
		scheduleRedraw()
	}

	// MARK: - Dropping files

	/// Files dropped here are typed as paths.
	///
	/// What the terminal is running does not matter: the path arrives as
	/// keystrokes, so it works at a shell prompt and equally in an agent's
	/// prompt, which is the case this exists for.
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		guard !droppedURLs(from: sender).isEmpty else { return [] }
		isDropTarget = true
		repaint()
		return .copy
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		isDropTarget = false
		repaint()
	}

	override func draggingEnded(_ sender: NSDraggingInfo) {
		isDropTarget = false
		repaint()
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		isDropTarget = false
		repaint()

		let urls = droppedURLs(from: sender)
		guard !urls.isEmpty else { return false }

		window?.makeFirstResponder(self)
		send(TerminalDrop.text(for: urls))
		return true
	}

	private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
		let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
		let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
		return (objects as? [URL]) ?? []
	}

	override func keyDown(with event: NSEvent) {
		// ⌘K clears, as it does in Terminal and every editor's console. A
		// program is never sent it: nothing reads it, and every terminal on
		// this platform takes it for this.
		if event.modifierFlags.contains(.command),
		   event.charactersIgnoringModifiers?.lowercased() == "k" {
			clear()
			return
		}
		// A dead key or an input method has to compose before there is anything
		// to send. `^` and `` ` `` on a German layout could not be typed at all
		// while every event was encoded here: they carry no character of their
		// own, so there was nothing to encode.
		if TerminalKeys.needsComposition(
			characters: event.characters,
			keyCode: event.keyCode,
			control: event.modifierFlags.contains(.control),
			command: event.modifierFlags.contains(.command),
			option: event.modifierFlags.contains(.option),
			optionAsMeta: Settings.shared.terminalOptionAsMeta,
			composing: hasMarkedText()
		) {
			composingEvent = event
			let handled = inputContext?.handleEvent(event)
			composingEvent = nil
			TerminalView.compositionRouteForTesting = handled.map { "im:\($0)" } ?? "no context"
			return
		}

		guard let bytes = encode(event: event) else { return }
		send(typed: bytes)
	}

	/// What has been typed at the program while a test is watching.
	static var typedForTesting: [String]?

	/// Where the last key went, for a test to say why nothing was composed.
	static var compositionRouteForTesting = "encoded"

	/// Writes typed text to the program, and starts the stopwatch on it.
	private func send(typed text: String) {
		TerminalView.typedForTesting?.append(text)
		keyPressedAt = Date()
		keyEchoedAt = nil
		keyParsedAt = nil
		hasDrawnEcho = false
		// Typing always jumps back to the prompt, as every terminal does.
		isPinnedToBottom = true
		pty.write(text)
		scrollToBottom()
	}

	/// Records how long the last keystroke took to reach the screen.
	///
	/// Split three ways, because only the middle part is ours: the shell (and
	/// tmux, if it is in the way) has to echo the byte back before there is
	/// anything to draw at all.
	private func noteKeystrokeShown() {
		guard InputProbe.enabled, let pressed = keyPressedAt, let parsed = keyParsedAt else { return }
		let now = Date()
		InputProbe.record(
			echo: (keyEchoedAt ?? parsed).timeIntervalSince(pressed),
			parse: parsed.timeIntervalSince(keyEchoedAt ?? pressed),
			draw: now.timeIntervalSince(parsed),
			total: now.timeIntervalSince(pressed)
		)
		keyPressedAt = nil
		keyEchoedAt = nil
		keyParsedAt = nil
	}

	/// Types one character as the keyboard would, for measuring.
	func typeForTesting(_ character: String) {
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window?.windowNumber ?? 0, context: nil,
			characters: character, charactersIgnoringModifiers: character,
			isARepeat: false, keyCode: 0
		) else { return }
		keyDown(with: event)
	}

	/// The kitty or xterm form of a key, when the program has asked for it.
	///
	/// Only the keys that are genuinely ambiguous. Sending every keystroke
	/// through the protocol would be correct by the letter of it and would
	/// break the shells and programs that never asked.
	private func modifiedKeySequence(for event: NSEvent) -> String? {
		guard emulator.reportsModifiedKeys else { return nil }
		let flags = event.modifierFlags

		// ⌘ belongs to the app: ⌘K clears, ⌘V pastes, and a program should not
		// see either.
		guard !flags.contains(.command) else { return nil }

		let code: Int
		switch event.keyCode {
		case 36, 76: code = 13   // Return
		case 48: code = 9        // Tab
		case 51: code = 127      // Backspace
		case 53: code = 27       // Escape
		default:
			// Anything else only when Control is held, which is where the
			// pairs live: Ctrl+I is Tab, Ctrl+M is Return, Ctrl+/ is Ctrl+_.
			guard flags.contains(.control),
			      let scalar = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first,
			      scalar.isASCII
			else { return nil }
			code = Int(scalar.value)
		}

		// Every argument spelled out: a protocol requirement cannot carry default
		// values, and ⌘ is never passed on because the app keeps it.
		return emulator.encodeModifiedKey(
			code: code,
			shift: flags.contains(.shift),
			option: flags.contains(.option),
			control: flags.contains(.control),
			command: false
		)
	}

	/// What a key with Option held would send, for checking the wiring.
	///
	/// Through the same translation a keystroke goes through, because what was
	/// wrong was not the rule but which rule the view asked: a test of the rule
	/// alone would have passed while a German keyboard still could not type a
	/// brace.
	func optionKeyForTesting(bare: String, composed: String) -> String {
		let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.option],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: composed,
			charactersIgnoringModifiers: bare,
			isARepeat: false,
			keyCode: 0
		)
		guard let event else { return "no event" }
		return encode(event: event) ?? "nothing"
	}

	/// Feeds the view a burst of frames the way a program that has been
	/// running unwatched does, and says how many pictures came out of it.
	///
	/// Through `enqueue`, which is the path output actually takes: what was
	/// wrong was not the rule but how often it was consulted, and a test of the
	/// rule alone would have passed while the screen still replayed a minute of
	/// somebody's afternoon.
	/// Arrival times are spread backwards rather than all stamped now, and that
	/// is the whole point of the exercise: what makes this a backlog is that the
	/// frames in it were produced while nobody could see them. Twenty a second is
	/// what a spinner and a clock come to, so forty thousand of them is a little
	/// over half an hour of somebody's afternoon — and every frame but the last
	/// is history, which is what the rule has to notice (item 0491).
	func burstForTesting(frames: Int) {
		TerminalView.drawCountForTesting = 0
		let now = Date()
		for frame in 0..<frames {
			// A repaint of the kind an agent's window sends: home the cursor,
			// draw a spinner and a clock, over and over.
			let seconds = frame % 600
			let spinner = ["|", "/", "-", "\\"][frame % 4]
			let picture = "\u{1B}[H\u{1B}[2J\(spinner) working (\(seconds)s)\r\n"
			let age = Double(frames - frame) / 20
			enqueue(Data(picture.utf8), arrivedAt: now.addingTimeInterval(-age))
		}
	}

	/// Presses keys by their key code and says what each one did.
	///
	/// Through `keyDown`, not through the encoder: what was wrong was never the
	/// encoding but that the layout was never asked, and a test that called the
	/// encoder would have agreed with the view while `^` still typed nothing.
	/// The layout itself does the composing here — whichever one the machine is
	/// set to — so this shows what the keyboard in front of the user does.
	func deadKeyForTesting(presses: [(code: UInt16, shift: Bool)]) -> String {
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)
		window?.makeFirstResponder(self)
		var report: [String] = []
		for press in presses {
			TerminalView.typedForTesting = []
			TerminalView.compositionRouteForTesting = "encoded"
			// Built as a real keyboard event rather than by hand: the input
			// manager translates through the layout using what the event source
			// carries, and an NSEvent made from parts carries none of it — it
			// accepts the key and composes nothing, which looks exactly like the
			// bug this is here to catch.
			guard let raw = CGEvent(
				keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
				virtualKey: press.code,
				keyDown: true
			) else { return "no event" }
			if press.shift { raw.flags.insert(.maskShift) }
			guard let event = NSEvent(cgEvent: raw) else { return "no event" }
			keyDown(with: event)
			let typed = (TerminalView.typedForTesting ?? []).joined()
			report.append(
				"key \(press.code): \(TerminalView.compositionRouteForTesting) "
					+ "marked=\(markedText.isEmpty ? "-" : markedText) "
					// Escaped: a carriage return typed at the end of the report
					// would print as the cursor going back to the margin, which
					// reads as nothing having been sent at all.
					+ "typed=\(typed.isEmpty ? "-" : typed.debugDescription)"
			)
		}
		TerminalView.typedForTesting = nil
		return report.joined(separator: " | ")
	}

	/// Translates a key event into the bytes a terminal would send.
	private func encode(event: NSEvent) -> String? {
		let flags = event.modifierFlags

		// A program that asked to be told which key was pressed, rather than
		// which byte it maps to, gets that first: Shift+Enter and Enter are one
		// byte apart otherwise, and no program can tell them apart.
		if let modified = modifiedKeySequence(for: event) { return modified }

		// Keys with a fixed sequence, and the Option-as-Meta rule that goes with
		// them. Applied here rather than after the switch: returning early was
		// how ⌥Return came to send a bare carriage return, which submits the
		// line instead of breaking it.
		if let key = TerminalKeys.Key(rawValue: event.keyCode) {
			// Modified navigation first: ⌥← is a word movement, not an arrow
			// with a prefix, and ⌘← is the start of the line.
			if let editing = TerminalKeys.editingSequence(
				for: key,
				option: flags.contains(.option),
				command: flags.contains(.command)
			) {
				return editing
			}

			let base: String?
			switch key {
			case .upArrow:    base = emulator.encodeArrow(.up)
			case .downArrow:  base = emulator.encodeArrow(.down)
			case .rightArrow: base = emulator.encodeArrow(.right)
			case .leftArrow:  base = emulator.encodeArrow(.left)
			default:          base = TerminalKeys.sequence(for: key)
			}

			guard let base else { return nil }
			return TerminalKeys.applyingMeta(base, key: key, optionHeld: flags.contains(.option))
		}

		guard var characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }

		if flags.contains(.control) {
			// ⌃A…⌃Z and the handful of punctuation controls.
			guard let scalar = characters.lowercased().unicodeScalars.first else { return nil }
			switch scalar {
			case "a"..."z":
				return String(UnicodeScalar(scalar.value - 96)!)
			case "[": return "\u{1B}"
			case "\\": return "\u{1C}"
			case "]": return "\u{1D}"
			case " ", "2": return "\u{0}"
			default: return nil
			}
		}

		// Option: what the layout composed, or Meta when it composed nothing.
		// A German keyboard reaches `{` at ⌥8 and could not type one at all
		// while this prefixed ESC unconditionally.
		if flags.contains(.option) {
			return TerminalKeys.optionOutput(
				composed: event.characters,
				bare: characters,
				asMeta: Settings.shared.terminalOptionAsMeta
			)
		}

		// Otherwise send what was actually typed, so dead keys and IME work.
		if let typed = event.characters, !typed.isEmpty {
			characters = typed
		}
		return characters
	}

	// MARK: - Mouse

	/// Grid position under a pointer event, 1-based as the protocol expects.
	/// The cell under the pointer, in absolute rows including scrollback.
	///
	/// Rounded to the nearest boundary rather than truncated, so a drag that
	/// ends halfway across a cell includes the half it covers — which is what
	/// makes selecting up to the last character possible.
	private func selectionPosition(for event: NSEvent) -> TerminalPosition {
		position(for: event, roundingToBoundary: true)
	}

	/// The character under the pointer, as opposed to the nearest gap.
	///
	/// A double-click on the right half of a cell rounds up to the next
	/// boundary, which as a character index is the cell after the one that was
	/// clicked — so the word picked was the one to its right.
	private func characterPosition(for event: NSEvent) -> TerminalPosition {
		position(for: event, roundingToBoundary: false)
	}

	private func position(for event: NSEvent, roundingToBoundary: Bool) -> TerminalPosition {
		let point = convert(event.locationInWindow, from: nil)
		let row = Int(floor((point.y - Self.verticalInset) / max(1, cellHeight)))
		let exact = (point.x - Self.horizontalInset) / max(1, cellWidth)
		let column = Int(roundingToBoundary ? exact.rounded() : exact.rounded(.down))
		let lastRow = max(0, shownLineCount - 1)
		return TerminalPosition(
			row: max(0, min(row, lastRow)),
			column: max(0, min(column, emulator.metrics.columns))
		)
	}

	/// Selection is for reading output, so a program that tracks the mouse gets
	/// the events instead — unless Shift is held, the usual escape hatch.
	private var mouseSelects: Bool {
		emulator.mouseTracking == .off
	}

	/// Follows the selection when lines fall out of the top of scrollback.
	///
	/// Absolute rows are stable while the buffer only grows; once it is full,
	/// every discarded line renumbers everything above the selection, and a
	/// selection left alone would drift down the screen on its own.
	private func realignSelectionForDiscardedLines() {
		// **`metrics`, not `grid`.** This runs on every delivery of output, and asking
		// for a snapshot here was half of item 0492: 1,400 snapshots a second, each of
		// them eleven thousand cells copied out of libghostty-vt, to answer one number
		// that engine already had to hand.
		let discarded = sizeAndHistory.discardedLineCount
		defer { lastDiscardedLineCount = discarded }

		let shift = discarded - lastDiscardedLineCount
		guard shift > 0, var updated = selection else { return }

		updated.anchor.row -= shift
		updated.head.row -= shift
		// Scrolled off entirely; there is nothing left to keep highlighted.
		guard max(updated.anchor.row, updated.head.row) >= 0 else {
			setSelection(nil)
			return
		}
		updated.anchor.row = max(0, updated.anchor.row)
		updated.head.row = max(0, updated.head.row)
		setSelection(updated)
	}

	private func setSelection(_ new: TerminalSelection?) {
		guard new != selection else { return }
		selection = new
		repaint()
	}

	private func gridPosition(for event: NSEvent) -> (row: Int, column: Int) {
		let point = convert(event.locationInWindow, from: nil)
		let column = Int((point.x - Self.horizontalInset) / max(1, cellWidth)) + 1
		var row = Int((point.y - Self.verticalInset) / max(1, cellHeight))
		// The protocol addresses the visible grid, so scrollback is subtracted.
		row -= emulator.metrics.scrollbackCount
		return (max(1, row + 1), max(1, column))
	}

	/// Where in the window a grid cell is, for driving the pointer from a test.
	private func windowPoint(row: Int, column: Int) -> NSPoint {
		let x = Self.horizontalInset + (CGFloat(column - 1) + 0.5) * cellWidth
		let y = Self.verticalInset
			+ (CGFloat(row - 1 + emulator.metrics.scrollbackCount) + 0.5) * cellHeight
		return convert(NSPoint(x: x, y: y), to: nil)
	}

	private func mouseEventForTesting(_ type: NSEvent.EventType, row: Int, column: Int) -> NSEvent? {
		NSEvent.mouseEvent(
			with: type,
			location: windowPoint(row: row, column: column),
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window?.windowNumber ?? 0,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		)
	}

	/// Presses the right button on a cell and holds it.
	func rightPressForTesting(row: Int, column: Int) {
		window?.makeFirstResponder(self)
		guard let down = mouseEventForTesting(.rightMouseDown, row: row, column: column) else { return }
		rightMouseDown(with: down)
	}

	/// Drags to a cell with the right button held, then lets go.
	func rightDragForTesting(row: Int, column: Int) {
		guard let event = mouseEventForTesting(.rightMouseDragged, row: row, column: column) else { return }
		rightMouseDragged(with: event)
	}

	func rightReleaseForTesting(row: Int, column: Int) {
		guard let up = mouseEventForTesting(.rightMouseUp, row: row, column: column) else { return }
		rightMouseUp(with: up)
	}

	/// Moves the pointer over a cell without pressing anything.
	func moveMouseForTesting(row: Int, column: Int) {
		guard let event = mouseEventForTesting(.mouseMoved, row: row, column: column) else { return }
		mouseMoved(with: event)
	}

	/// The visible grid, so a test can aim at the last row.
	var gridSizeForTesting: (rows: Int, columns: Int) {
		(emulator.metrics.rows, emulator.metrics.columns)
	}

	private func modifiers(_ event: NSEvent) -> (Bool, Bool, Bool) {
		let flags = event.modifierFlags
		return (flags.contains(.shift), flags.contains(.option), flags.contains(.control))
	}

	/// Forwards a pointer event, returning true when the program consumed it.
	private func forwardMouse(
		_ event: NSEvent,
		button: TerminalEmulator.MouseButton,
		isRelease: Bool,
		isDrag: Bool = false
	) -> Bool {
		// Shift is the conventional override for "let the terminal handle it",
		// which is how selection stays possible while a program grabs the mouse.
		guard !event.modifierFlags.contains(.shift) else { return false }

		let position = gridPosition(for: event)
		let (shift, option, control) = modifiers(event)
		guard let sequence = emulator.encodeMouse(
			button: button,
			row: position.row,
			column: position.column,
			isRelease: isRelease,
			isDrag: isDrag,
			shift: shift,
			option: option,
			control: control
		) else { return false }

		lastReportedMouseCell = GridCell(row: position.row, column: position.column)
		pty.write(sequence)
		return true
	}

	/// The click that activates the window also lands in the terminal.
	///
	/// macOS swallows that first click by default, so clicking into an inactive
	/// window puts the app in front and nothing else — and the click has to be
	/// made again to reach what it was aimed at. In a terminal that is worse
	/// than elsewhere: the thing being aimed at is usually a tmux pane, and
	/// selecting one is what the click is *for*. The pane change goes to tmux
	/// on its own, since a click in a terminal with mouse reporting on is
	/// forwarded to whatever is running in it.
	///
	/// Safe here because a click in a terminal moves a selection or tells tmux
	/// which pane has the keyboard. Nothing is closed, deleted or run by one,
	/// which is what the default is guarding against.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)

		// A link under the pointer is what the click is for — unless a program
		// is taking the mouse, in which case it is the program's click.
		if mouseSelects, event.clickCount == 1, let link = link(at: event) {
			NSWorkspace.shared.open(link.url)
			return
		}

		guard mouseSelects || event.modifierFlags.contains(.shift) else {
			_ = forwardMouse(event, button: .left, isRelease: false)
			return
		}

		switch event.clickCount {
		case 2:
			let position = characterPosition(for: event)
			setSelection(emulator.grid.wordSelection(atRow: position.row, column: position.column))
		case 3...:
			setSelection(emulator.grid.lineSelection(atRow: characterPosition(for: event).row))
		default:
			let position = selectionPosition(for: event)
			isSelecting = true
			setSelection(TerminalSelection(anchor: position, head: position))
		}
	}

	override func mouseUp(with event: NSEvent) {
		if isSelecting {
			isSelecting = false
			// A click that never moved is a click, not an empty selection.
			if selection?.isEmpty == true { setSelection(nil) }
			return
		}
		_ = forwardMouse(event, button: .left, isRelease: true)
	}

	/// Tells a program where the pointer is, when it has asked to know.
	///
	/// Only mode 1003 asks — and tmux turns it on while one of its own menus is
	/// open, which is how the item under the pointer comes to be highlighted.
	/// Without this the menu appears and then sits there, dead.
	override func mouseMoved(with event: NSEvent) {
		updateHoveredLink(at: event)
		guard emulator.mouseTracking == .anyEvent else { return }
		// Not while the program is behind on what it has already been sent. A
		// motion report says where the pointer was; delivered after a long
		// paste has drained it says something untrue, and lands in the middle
		// of what was pasted.
		guard pty.pendingInputCount == 0 else { return }
		// A button is down: that is a drag, and dragging reports itself.
		guard NSEvent.pressedMouseButtons == 0 else { return }

		// Only when the pointer has actually left the cell it was last seen in
		// — including the cell it was clicked in. A menu opened by that click
		// is waiting for the pointer to move somewhere, and being told it is
		// still where it was reads as somewhere else entirely.
		let cell = gridPosition(for: event)
		let position = GridCell(row: cell.row, column: cell.column)
		guard position != lastReportedMouseCell else { return }
		lastReportedMouseCell = position

		_ = forwardMouse(event, button: .none, isRelease: false, isDrag: true)
	}

	/// Which hyperlink the pointer is over, so it can be underlined and opened.
	private var hoveredLink: UInt16 = 0

	private func updateHoveredLink(at event: NSEvent) {
		let link = self.link(at: event)?.id ?? 0
		guard link != hoveredLink else { return }
		hoveredLink = link
		// A pointer over something clickable should say so, and stop saying so
		// the moment it leaves.
		if link != 0 { NSCursor.pointingHand.set() } else { NSCursor.iBeam.set() }
		repaint()
	}

	/// The hyperlink under a pointer event, if the cell has one.
	private func link(at event: NSEvent) -> (id: UInt16, url: URL)? {
		let point = convert(event.locationInWindow, from: nil)
		let row = Int((point.y - Self.verticalInset) / max(1, cellHeight))
		let column = Int((point.x - Self.horizontalInset) / max(1, cellWidth))
		guard row >= 0, column >= 0,
		      let line = emulator.grid.line(at: row),
		      column < line.cells.count
		else { return nil }

		let id = line.cells[column].attributes.link
		guard id != 0, let text = emulator.link(for: id), let url = URL(string: text) else {
			return nil
		}
		return (id, url)
	}

	/// The cell the program was last told about, so a pointer wandering inside
	/// one cell does not send a report per pixel.
	private var lastReportedMouseCell: GridCell?

	/// A cell of the visible grid, as the mouse protocol addresses it.
	private struct GridCell: Equatable {
		let row: Int
		let column: Int
	}

	override func mouseDragged(with event: NSEvent) {
		guard isSelecting else {
			_ = forwardMouse(event, button: .left, isRelease: false, isDrag: true)
			return
		}
		guard var updated = selection else { return }
		updated.head = selectionPosition(for: event)
		setSelection(updated)

		// Dragging past an edge should keep going, the way it does in a list.
		autoscroll(with: event)
	}

	/// A drag with the right button held.
	///
	/// tmux's own menus are press-drag-release: the menu opens on the press and
	/// closes on the release, so the item under the pointer is chosen by
	/// dragging onto it. Without this the menu opens and nothing highlights,
	/// which is what right-clicking a tmux tab looked like.
	override func rightMouseDragged(with event: NSEvent) {
		guard !mouseSelects else { return }
		_ = forwardMouse(event, button: .right, isRelease: false, isDrag: true)
	}

	/// Everything past left and right, of which only the middle button is ours.
	///
	/// **`buttonNumber` is read.** macOS raises `otherMouseDown` for button 2 —
	/// the middle one — and for 3 and 4, the side buttons, and all three used to
	/// be forwarded as `.middle`. Middle is button 1 on the wire and middle
	/// click in a terminal is commonly paste, so a side button pressed over this
	/// view could put the selection into somebody's shell. `MouseButtons` says
	/// which number means what, in one place, because the window reads the same
	/// numbers to navigate on.
	///
	/// **Anything not forwarded travels up**, rather than stopping here. Both
	/// branches used to return without calling `super`: the one for a program
	/// that is not tracking the mouse, and the one where `forwardMouse` declines
	/// — shift held, or the emulator with nothing to encode. That is why a side
	/// button did nothing over a terminal even once the window knew what to do
	/// with one: the event never reached it. A view that does not act on an
	/// event has no business eating it.
	///
	/// Side buttons are not forwarded to the program at all, in any branch:
	/// `TerminalEmulator.MouseButton` is left, middle, right, none and the two
	/// scroll codes, and there is no code to send.
	override func otherMouseDown(with event: NSEvent) {
		MouseReport.say("terminal down", event, tracking: !mouseSelects)
		guard isMiddle(event), !mouseSelects,
		      forwardMouse(event, button: .middle, isRelease: false)
		else {
			super.otherMouseDown(with: event)
			return
		}
	}

	override func otherMouseUp(with event: NSEvent) {
		MouseReport.say("terminal up", event, tracking: !mouseSelects)
		guard isMiddle(event), !mouseSelects,
		      forwardMouse(event, button: .middle, isRelease: true)
		else {
			super.otherMouseUp(with: event)
			return
		}
	}

	override func otherMouseDragged(with event: NSEvent) {
		guard isMiddle(event), !mouseSelects,
		      forwardMouse(event, button: .middle, isRelease: false, isDrag: true)
		else {
			super.otherMouseDragged(with: event)
			return
		}
	}

	/// Whether this event is the one button this view forwards.
	private func isMiddle(_ event: NSEvent) -> Bool {
		MouseButtons.purpose(of: event.buttonNumber) == .middleClick
	}

	override func rightMouseDown(with event: NSEvent) {
		guard mouseSelects else {
			_ = forwardMouse(event, button: .right, isRelease: false)
			return
		}
		NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
	}

	override func rightMouseUp(with event: NSEvent) {
		guard mouseSelects else {
			_ = forwardMouse(event, button: .right, isRelease: true)
			return
		}
	}

	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		// AppKit recomputes isEnabled from the responder chain by default, which
		// discards whatever the items were built with.
		menu.autoenablesItems = false

		func item(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			return item
		}

		menu.addItem(item("Copy", #selector(copy(_:)), enabled: selection != nil))
		menu.addItem(item("Paste", #selector(paste(_:))))
		menu.addItem(.separator())
		menu.addItem(item("Select All", #selector(selectAll(_:))))
		menu.addItem(item("Clear Selection", #selector(clearSelection), enabled: selection != nil))
		menu.addItem(.separator())
		// What ⌘K does in every other terminal, and the only thing to do with
		// a console full of a run somebody has finished reading.
		menu.addItem(item("Clear", #selector(clearConsole(_:))))
		return menu
	}

	override func scrollWheel(with event: NSEvent) {
		// A program tracking the mouse gets wheel events as button 64/65.
		if emulator.mouseTracking != .off, !event.modifierFlags.contains(.shift) {
			let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))
			let button: TerminalEmulator.MouseButton = event.scrollingDeltaY > 0 ? .scrollUp : .scrollDown
            let position = gridPosition(for: event)
			for _ in 0..<steps {
				if let sequence = emulator.encodeMouse(
					button: button,
					row: position.row,
					column: position.column,
					isRelease: false,
					isDrag: false,
					shift: false,
					option: false,
					control: false
				) {
					pty.write(sequence)
				}
			}
			return
		}

		// On the alternate screen there is no scrollback to move through, so the
		// wheel drives the program's own cursor instead of doing nothing.
		if emulator.isAlternateScreen {
			let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))
			let key: TerminalEmulator.ArrowKey = event.scrollingDeltaY > 0 ? .up : .down
			pty.write(String(repeating: emulator.encodeArrow(key), count: steps))
			return
		}

		super.scrollWheel(with: event)
	}

	// MARK: - Actions

	@objc func copy(_ sender: Any?) {
		// Only what is selected. Copying the entire buffer when nothing is
		// selected is a surprise nobody wants pasted somewhere else.
		guard let selection else { return }
		let text = emulator.grid.text(in: selection)
		guard !text.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc override func selectAll(_ sender: Any?) {
		setSelection(emulator.grid.fullSelection)
	}

	@objc private func clearSelection() {
		setSelection(nil)
	}

	@objc func paste(_ sender: Any?) {
		guard let text = NSPasteboard.general.string(forType: .string) else { return }
		isPinnedToBottom = true
		scrollToBottom()

		// Through tmux, tmux does the pasting.
		//
		// Bracketed paste is a promise to the program reading the keyboard, and
		// through tmux there are two of them: tmux, which asks for the markers
		// so it can receive a paste, and whatever is in the pane, which asks
		// separately and changes its mind constantly — a shell turns them off
		// while a command runs and on while it is editing a line. What this
		// terminal sees is tmux's answer, so writing the markers ourselves is
		// answering the wrong program, and losing that race puts `^[[200~` in
		// the command line.
		if let tty = pty.ttyName {
			Task { @MainActor [weak self] in
				if let session = await TmuxMirror.session(forClient: tty),
				   await TmuxMirror.paste(text, intoSession: session) {
					return
				}
				self?.sendPaste(text)
			}
			return
		}
		sendPaste(text)
	}

	/// Types the text at the program, which is what a terminal does when there
	/// is nothing in the way that knows better.
	private func sendPaste(_ text: String) {
		// The markers tell the program the text arrived at once, which stops
		// shells from executing every pasted line as it lands.
		if emulator.bracketedPaste {
			pty.write("\u{1B}[200~" + text + "\u{1B}[201~")
		} else {
			pty.write(text)
		}
	}

	func sendInterrupt() {
		pty.interrupt()
	}

	func terminateProcess() {
		pty.terminate()
	}

	var isProcessRunning: Bool { pty.isRunning }

	/// The last few non-blank lines, for a progress summary elsewhere.
	func recentOutput(_ count: Int) -> [String] {
		emulator.grid.recentLines(count)
	}

	/// Writes text as though typed. Used to drive a session programmatically —
	/// the same entry point an agent prompt will take.
	func send(_ text: String) {
		isPinnedToBottom = true
		pty.write(text)
		scrollToBottom()
	}

	// MARK: - Composition

	/// The text being composed, which no program has been told about yet.
	private var markedText = ""

	/// The key the input manager is being asked about, kept so a key it hands
	/// back can still be sent.
	private var composingEvent: NSEvent?

	/// A key the input manager refused rather than composed.
	///
	/// Return pressed while an accent is pending: the layout commits the accent
	/// and passes the Return on as an editing command. Nothing here edits text,
	/// but the program is still owed that keystroke.
	override func doCommand(by selector: Selector) {
		guard let event = composingEvent, let bytes = encode(event: event) else { return }
		send(typed: bytes)
	}

	/// Shows or hides the composed text at the cursor.
	///
	/// A label on top rather than characters written into the screen: the grid
	/// belongs to the program, and a pending accent is not something the program
	/// has been sent. It also keeps working when the Metal renderer is drawing,
	/// which paints from the grid and knows nothing about this.
	private func setComposition(_ text: String) {
		guard markedText != text else { return }
		markedText = text

		guard !text.isEmpty, let place = cursorPlace(), place.row < shownLineCount else {
			compositionLabel.isHidden = true
			return
		}

		compositionLabel.attributedStringValue = NSAttributedString(
			string: text,
			attributes: [
				.font: font,
				.foregroundColor: TerminalPalette.foreground,
				.backgroundColor: TerminalPalette.background,
				// Underlined, which is how every input method says "not typed yet".
				.underlineStyle: NSUnderlineStyle.single.rawValue,
				.underlineColor: TerminalPalette.cursor,
			]
		)
		compositionLabel.sizeToFit()
		compositionLabel.frame.origin = CGPoint(
			x: (Self.horizontalInset + CGFloat(place.column) * cellWidth).rounded(),
			y: (Self.verticalInset + CGFloat(place.row) * cellHeight).rounded()
		)
		compositionLabel.frame.size.height = cellHeight
		if compositionLabel.superview !== self {
			addSubview(compositionLabel, positioned: .above, relativeTo: nil)
		}
		compositionLabel.isHidden = false
	}

	private lazy var compositionLabel: NSTextField = {
		let label = NSTextField(labelWithString: "")
		label.drawsBackground = true
		label.isBordered = false
		label.isHidden = true
		return label
	}()

	// MARK: - NSTextInputClient

	// Minimal conformance so IME candidates commit into the terminal.

	func insertText(_ string: Any, replacementRange: NSRange) {
		let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
		setComposition("")
		guard !text.isEmpty else { return }
		send(typed: text)
	}

	/// The half-finished text the layout is holding.
	///
	/// A dead key composes in two presses: the first shows the accent, the
	/// second decides whether it becomes `â` or stays `^` in front of whatever
	/// followed. The first press has to be visible or the keyboard looks broken,
	/// and the terminal itself must not see it — nothing has been typed yet.
	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
		setComposition((string as? String) ?? (string as? NSAttributedString)?.string ?? "")
	}

	func unmarkText() { setComposition("") }
	func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

	func markedRange() -> NSRange {
		markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count)
	}

	func hasMarkedText() -> Bool { !markedText.isEmpty }
	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
	func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
	func characterIndex(for point: NSPoint) -> Int { 0 }

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		guard let window else { return .zero }
		let row = emulator.metrics.scrollbackCount + emulator.cursorRow
		let rect = NSRect(
			x: Self.horizontalInset + CGFloat(emulator.cursorColumn) * cellWidth,
			y: Self.verticalInset + CGFloat(row) * cellHeight,
			width: cellWidth,
			height: cellHeight
		)
		return window.convertToScreen(convert(rect, to: nil))
	}
}

/// Scrolling container that keeps the terminal sized to its viewport.
final class TerminalPane: NSView {
	let terminalView: TerminalView
	private let scrollView = NSScrollView()

	/// A pane that shows output and runs nothing.
	convenience init(readOnly: Void) {
		self.init(terminalView: TerminalView.forOutput())
	}

	convenience init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		self.init(terminalView: TerminalView(workingDirectory: workingDirectory, command: command))
	}

	private init(terminalView: TerminalView) {
		self.terminalView = terminalView
		super.init(frame: .zero)

		scrollView.documentView = terminalView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = TerminalPalette.background
		scrollView.scrollerStyle = .overlay
		scrollView.contentView.postsBoundsChangedNotifications = true

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak self] _ in
			self?.terminalView.viewportChanged()
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		// The grid is measured in cells, so a resize changes rows and columns.
		terminalView.viewportChanged()
	}

	override func layout() {
		super.layout()
		// Catches the case where the pane gains its real size through layout
		// rather than an explicit frame change.
		terminalView.viewportChanged()
	}

	/// The view inside, for the panel to pass a resize down to.
	var terminalViewForTesting: TerminalView { terminalView }

	/// Shows text in the pane as though something in it had printed it.
	///
	/// A lone newline is turned into a return and a newline, because this is a
	/// terminal and not a text view: `\n` moves down a line and leaves the cursor
	/// in the column it was in, so output written the way a file is written comes
	/// out as a staircase. What already has its return keeps it — a `docker pull`
	/// redrawing one line with a bare `\r` is left exactly as it came.
	func write(_ text: String) {
		terminalView.append(
			text
				.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\n", with: "\r\n")
		)
	}

	/// Starts a shell in a pane that has only been showing output.
	func startProcess(
		_ command: (executable: String, arguments: [String]), workingDirectory: URL? = nil
	) {
		terminalView.startProcess(command, workingDirectory: workingDirectory)
	}

	/// Whether this pane is still only showing output.
	var showsOutputOnly: Bool { terminalView.showsOutputOnly }

	/// Where the shell in this terminal currently is.
	var currentDirectoryForTesting: URL? { terminalView.currentDirectory() }
	var ttyName: String? { terminalView.ttyName }
	var geometryForTesting: String { terminalView.geometryForTesting }
	var gridSizeForTesting: (rows: Int, columns: Int) { terminalView.gridSizeForTesting }

	func rightPressForTesting(row: Int, column: Int) {
		terminalView.rightPressForTesting(row: row, column: column)
	}

	func rightDragForTesting(row: Int, column: Int) {
		terminalView.rightDragForTesting(row: row, column: column)
	}

	func rightReleaseForTesting(row: Int, column: Int) {
		terminalView.rightReleaseForTesting(row: row, column: column)
	}

	func moveMouseForTesting(row: Int, column: Int) {
		terminalView.moveMouseForTesting(row: row, column: column)
	}

	/// Output arrived, which is the moment to check whether the shell has moved.
	var onOutput: (() -> Void)? {
		get { terminalView.onOutput }
		set { terminalView.onOutput = newValue }
	}

	func focus() {
		window?.makeFirstResponder(terminalView)
	}
}

/// The four faces a terminal cell can ask for, and what each one advances by.
///
/// Derived once per font change. Asking NSFontManager to convert a font is
/// slow enough to matter when it happens for every run of every frame, and the
/// advance was being measured through a string-keyed cache that allocated its
/// key on each lookup.
struct TerminalFaces {
	let regular: NSFont
	let bold: NSFont
	let italic: NSFont
	let boldItalic: NSFont
	/// Advance of the regular face, which is what the cell grid is built on.
	let advance: CGFloat
	/// Distance from the top of a cell down to the baseline.
	let baselineFromTop: CGFloat

	private let advances: (CGFloat, CGFloat, CGFloat, CGFloat)

	init(base: NSFont) {
		let manager = NSFontManager.shared
		regular = base
		bold = manager.convert(base, toHaveTrait: .boldFontMask)
		italic = manager.convert(base, toHaveTrait: .italicFontMask)
		boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)

		func width(_ font: NSFont) -> CGFloat {
			("0" as NSString).size(withAttributes: [.font: font]).width
		}
		advances = (width(regular), width(bold), width(italic), width(boldItalic))
		advance = advances.0
		baselineFromTop = (base.ascender + base.leading).rounded()
	}

	/// Which of the four faces a pair of flags asks for.
	static func index(bold isBold: Bool, italic isItalic: Bool) -> UInt8 {
		(isBold ? 1 : 0) | (isItalic ? 2 : 0)
	}

	func face(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
		switch (isBold, isItalic) {
		case (false, false): return regular
		case (true, false):  return bold
		case (false, true):  return italic
		case (true, true):   return boldItalic
		}
	}

	func advance(bold isBold: Bool, italic isItalic: Bool) -> CGFloat {
		switch (isBold, isItalic) {
		case (false, false): return advances.0
		case (true, false):  return advances.1
		case (false, true):  return advances.2
		case (true, true):   return advances.3
		}
	}
}


/// A glyph for one code point, together with the font that actually has it.
///
/// Looked up once and kept. Turning a character into a glyph means asking
/// CoreText, and asking it for a font that can draw one means asking the whole
/// fallback cascade — neither is something to do sixty times a second for every
/// cell on the screen.
private struct CachedGlyph {
	let glyph: CGGlyph
	let font: CTFont
}

private struct GlyphKey: Hashable {
	let scalar: UInt32
	/// Which of the four faces asked for it.
	let face: UInt8
}

/// Glyphs by code point and face.
///
/// Kept on the view rather than shared, so changing the font throws away the
/// glyphs that went with it.
private final class GlyphCache {
	private var entries: [GlyphKey: CachedGlyph?] = [:]

	func clear() { entries.removeAll(keepingCapacity: true) }

	/// The glyph to draw for a code point, or nil when nothing can draw it.
	fileprivate func glyph(for scalar: UInt32, face: NSFont, faceIndex: UInt8) -> CachedGlyph? {
		let key = GlyphKey(scalar: scalar, face: faceIndex)
		if let known = entries[key] { return known }

		let found = Self.lookUp(scalar: scalar, in: face)
		entries[key] = found
		return found
	}

	fileprivate static func lookUp(scalar: UInt32, in face: NSFont) -> CachedGlyph? {
		guard let unicode = UnicodeScalar(scalar) else { return nil }
		var utf16 = Array(String(unicode).utf16)
		var glyphs = [CGGlyph](repeating: 0, count: utf16.count)

		let ctFace = face as CTFont
		if CTFontGetGlyphsForCharacters(ctFace, &utf16, &glyphs, utf16.count), glyphs[0] != 0 {
			return CachedGlyph(glyph: glyphs[0], font: ctFace)
		}

		// The terminal's own face has no glyph for it — emoji, CJK and the
		// powerline range all come from somewhere else. CoreText knows where.
		guard let fallback = GlyphFallback.font(for: unicode, from: ctFace),
		      CTFontGetGlyphsForCharacters(fallback, &utf16, &glyphs, utf16.count),
		      glyphs[0] != 0
		else { return nil }
		return CachedGlyph(glyph: glyphs[0], font: fallback)
	}
}

/// Splits a keystroke into where its time actually goes.
///
/// `echo` is the round trip through the pty — the shell, and tmux if it is in
/// the way — which no terminal can do anything about. `parse` and `draw` are
/// ours: how long the bytes wait to be read, and how long the picture then
/// waits for a frame.
enum InputProbe {
	static let enabled = ProcessInfo.processInfo.environment["ABYDOS_INPUT_PROBE"] != nil
	nonisolated(unsafe) private static var samples: [(echo: Double, parse: Double, draw: Double, total: Double)] = []

	static func record(echo: Double, parse: Double, draw: Double, total: Double) {
		samples.append((echo, parse, draw, total))
		let ms = { (value: Double) in String(format: "%6.2f", value * 1000) }
		FileHandle.standardError.write(Data(
			"INPUT echo=\(ms(echo)) parse=\(ms(parse)) draw=\(ms(draw)) total=\(ms(total))\n".utf8
		))
	}

	nonisolated(unsafe) private static var frames = 0
	nonisolated(unsafe) private static var framesWithoutCursor = 0

	/// Frames drawn without the cursor in them, which is what a flicker is: a
	/// picture taken while a program had hidden it to repaint.
	nonisolated(unsafe) private static var places: [(row: Int, column: Int)] = []

	static func frame(cursor: Bool, row: Int = 0, column: Int = 0) {
		frames += 1
		if !cursor { framesWithoutCursor += 1 }
		places.append((row, column))
	}

	/// Frames whose cursor was somewhere the frames on either side were not —
	/// a position the terminal passed through rather than settled in, which is
	/// the cursor appearing where it never really was.
	private static var transientPlaces: Int {
		guard places.count > 2 else { return 0 }
		var count = 0
		for index in 1..<(places.count - 1) where
			places[index] != places[index - 1] && places[index - 1] == places[index + 1] {
			count += 1
		}
		return count
	}

	static func report() {
		FileHandle.standardError.write(Data(
			"INPUTSUM frames=\(frames) withoutCursor=\(framesWithoutCursor) transient=\(transientPlaces) \n".utf8
		))
		guard !samples.isEmpty else { return }
		func line(_ name: String, _ values: [Double]) -> String {
			let sorted = values.sorted()
			let ms = { (value: Double) in String(format: "%6.2f", value * 1000) }
			let mean = values.reduce(0, +) / Double(values.count)
			return "INPUTSUM \(name) mean=\(ms(mean)) median=\(ms(sorted[sorted.count / 2])) "
				+ "min=\(ms(sorted[0])) max=\(ms(sorted[sorted.count - 1]))"
		}
		let text = [
			line("echo ", samples.map(\.echo)),
			line("parse", samples.map(\.parse)),
			line("draw ", samples.map(\.draw)),
			line("total", samples.map(\.total)),
			"INPUTSUM samples=\(samples.count)",
		].joined(separator: "\n") + "\n"
		FileHandle.standardError.write(Data(text.utf8))
	}
}

/// Temporary: splits a GPU frame into where its time actually goes.
enum MetalProbe {
	static let enabled = ProcessInfo.processInfo.environment["ABYDOS_METAL_PROBE"] != nil
	nonisolated(unsafe) static var buildSeconds = 0.0
	nonisolated(unsafe) static var drawableSeconds = 0.0
	nonisolated(unsafe) static var encodeSeconds = 0.0
	nonisolated(unsafe) static var parseSeconds = 0.0
	nonisolated(unsafe) static var renders = 0
	/// Cells a frame turned into instances, which is what item 0488 is about.
	///
	/// It used to be the instance count, and while every cell on screen was
	/// built every frame the two were the same number — 10,904 either way. They
	/// are not the same number any more, so both are printed: `cells/render` is
	/// the work done, `instances/render` is what the GPU was handed, and it is
	/// still the whole screen because the rows that were not built are still in
	/// the buffer from the frame that did build them.
	nonisolated(unsafe) static var cells = 0
	nonisolated(unsafe) static var rows = 0
	nonisolated(unsafe) static var instances = 0

	/// The inputs to the redraw policy, since the policy is now a claim about
	/// them (item 0491).
	///
	/// `stale` is the worst the picture got: how many milliseconds behind the pty
	/// the oldest unparsed delivery was when the drain reached it. `delivery` is
	/// the longest single `write` — the parse work that could not be broken up,
	/// and therefore the floor under how long a frame can be blocked.
	nonisolated(unsafe) static var worstStaleSeconds = 0.0
	nonisolated(unsafe) static var worstDeliverySeconds = 0.0
	nonisolated(unsafe) static var worstDeliveryBytes = 0
	nonisolated(unsafe) static var deliveries = 0

	static func note(staleBy: TimeInterval) {
		worstStaleSeconds = max(worstStaleSeconds, staleBy)
	}

	static func note(delivery seconds: TimeInterval, bytes: Int) {
		deliveries += 1
		if seconds > worstDeliverySeconds {
			worstDeliverySeconds = seconds
			worstDeliveryBytes = bytes
		}
	}

	static func start() {
		guard enabled else { return }
		Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
			let ms = { (value: Double) in String(format: "%.0f", value * 1000) }
			let per = { (total: Int) in renders > 0 ? total / renders : 0 }
			var line = "METALPROBE renders=\(renders) cells/render=\(per(cells)) "
			line += "rows/render=\(per(rows)) instances/render=\(per(instances)) "
			line += "parse=\(ms(parseSeconds))ms build=\(ms(buildSeconds))ms "
			line += "drawable=\(ms(drawableSeconds))ms encode=\(ms(encodeSeconds))ms "
			line += "stale=\(ms(worstStaleSeconds))ms deliveries=\(deliveries) "
			line += "worst=\(ms(worstDeliverySeconds))ms/\(worstDeliveryBytes / 1024)K\n"
			FileHandle.standardError.write(Data(line.utf8))
			buildSeconds = 0; drawableSeconds = 0; encodeSeconds = 0; parseSeconds = 0
			renders = 0; cells = 0; rows = 0; instances = 0
			worstStaleSeconds = 0; worstDeliverySeconds = 0; worstDeliveryBytes = 0
			deliveries = 0
		}
	}
}
