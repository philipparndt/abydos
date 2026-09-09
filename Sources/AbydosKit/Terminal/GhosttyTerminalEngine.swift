import Foundation
// Only the umbrella header, never a sub-header. Measured reason: two of the
// breaking changes in libghostty-vt's last four months were declarations moving
// between sub-headers with their names and signatures untouched
// (`ghostty_terminal_selection_*` from terminal.h to selection.h,
// `GhosttyFormatterFormat` from formatter.h to types.h). Including only the
// umbrella makes both of those non-events.
import GhosttyVt

/// libghostty-vt as an engine under our terminal, off by default (item 0474).
///
/// ghostty's terminal state machine with no pty and no renderer: bytes in, grid
/// out. The parts we would be buying from it are the ones we have repeatedly got
/// wrong ourselves — wrapping, reflow on resize, scrollback, and the cursor
/// arithmetic that 0468 turned out to be.
///
/// ## What is implemented and what refuses
///
/// Text is implemented: codepoints, grapheme clusters, wide cells, SGR colours
/// and attributes, scrollback, wrapping, reflow, cursor, alternate screen,
/// title. That is enough to run a shell and read it.
///
/// **Kitty graphics works, including inside tmux** (item 0485). 0474 concluded it
/// could not, because the part of the `U=1` unicode-placeholder protocol that
/// turns placeholder cells into picture fragments is not exported and the geometry
/// calls refuse virtual placements outright. That was right about the API and
/// wrong about what is needed from it: those calls answer "where on the screen is
/// this placement", and for a placeholder picture the *cells* answer that.
/// `GhosttyGraphicsBridge` is where this is set out, with the evidence.
///
/// - The **`t=f` real placement** used outside tmux is libghostty-vt's entirely,
///   `ghostty_kitty_graphics_placement_grid_size` included — which does the
///   pixels-to-cells arithmetic 0468 was about.
/// - The **`U=1` placeholders** used inside tmux are libghostty-vt's store read
///   through our `UnicodePlaceholder` decoder, which needs three things off a
///   cell and two off the store and gets all five.
///
/// ## Two things the library requires that are easy to get silently wrong
///
/// - Kitty graphics is **off** until a non-zero storage limit is set, and file
///   media are **off** by default (`image_limits = .direct`). A forgotten
///   storage limit looks exactly like "this terminal has no graphics".
/// - Query responses (`a=q`, DSR, DA) are **not even encoded** unless a
///   `WRITE_PTY` callback is installed. Outside tmux `icat` asks three questions
///   and waits, so with no callback it hangs rather than misdraws.
///
/// Both are set up in `init`, so that if graphics is ever finished here the
/// plumbing is not the missing piece.
public final class GhosttyTerminalEngine: TerminalEngine {
	public static var engineName: String { "libghostty-vt" }

	private var terminal: GhosttyTerminal?
	private var pendingResponse = ""

	/// Kitty graphics, in the type both drawing paths already read.
	///
	/// libghostty-vt parses the escapes, reassembles the chunks, inflates,
	/// decodes and evicts; this store holds a copy of what it ended up with, and
	/// `UnicodePlaceholder` on top of the grid supplies the `U=1` half the library
	/// does not export. See `GhosttyGraphicsBridge`, which is where item 0485's
	/// first question is answered.
	///
	/// Computed rather than stored, so that reading it brings the store up to date
	/// first (item 0492): `syncGraphics` runs on the read now, and a caller reaching
	/// straight for `graphics.placements` must not be handed the state as of some
	/// earlier frame.
	public var graphics: TerminalImageStore { bringUpToDate(); return imageStore }
	private let imageStore = TerminalImageStore()
	/// libghostty-vt's own storage stamp, so an unchanged store costs one call.
	private var graphicsGeneration: UInt64 = 0

	public var onUpdate: (() -> Void)?
	public var onResponse: ((String) -> Void)?
	public var onBell: (() -> Void)?
	public var onClipboardWrite: ((String) -> Void)?
	public var onOpenFile: ((TerminalOpenRequest) -> Void)?
	/// A program asked what a colour is.
	///
	/// Ours answers the query itself, from this closure. libghostty-vt answers
	/// OSC 4/10/11/12 from **its own** palette, which is the better arrangement
	/// but means the palette has to be in the library rather than in a callback.
	/// So setting this pushes the whole palette across once, and the terminal
	/// replies for itself from then on — the same answers, encoded by the engine
	/// that received the question.
	public var colourLookup: ((TerminalColourQuery) -> (red: Double, green: Double, blue: Double)?)? {
		didSet { applyPalette() }
	}

	// Read across the FFI boundary by `refreshState`, which runs on the *read* and
	// not on the write (item 0492). Every one of these is therefore a computed
	// property over a cached value, and the cache is what `bringUpToDate` fills.
	public var cursorRow: Int { bringUpToDate(); return cachedCursorRow }
	public var cursorColumn: Int { bringUpToDate(); return cachedCursorColumn }
	public var isCursorVisible: Bool { bringUpToDate(); return cachedCursorVisible }
	public var isAlternateScreen: Bool { bringUpToDate(); return cachedAlternateScreen }
	public private(set) var title: String?

	private var cachedCursorRow = 0
	private var cachedCursorColumn = 0
	private var cachedCursorVisible = true
	private var cachedAlternateScreen = false

	/// libghostty-vt's render state, kept for the life of the engine.
	///
	/// `render.h` is what its own documentation points at instead of grid
	/// references — "the grid reference APIs are **not** meant to be used as the
	/// core of a render loop" — and it is also the only place some state is
	/// reported at all, the cursor's visual shape among it.
	///
	/// **Updated once before each read, not once per write** (item 0492): 18.5 µs a
	/// call against 4.7 µs to parse the kilobyte that provoked it, paid 1,400 times a
	/// second to be read 60 times. Its dirty tracking is consumed by the update, which
	/// is also where `noteDirtyRows` gets the rows that changed.
	private var renderState: GhosttyRenderState?

	/// Everything about reading the screen back out, which owns state of its own:
	/// the anchor that counts pruned lines, the snapshot cache, and the table
	/// URIs are interned into. See `GhosttyScreenReader`.
	private var screen: GhosttyScreenReader!

	private var rows: Int
	private var columns: Int
	private var dirty: ClosedRange<Int>?

	public var cellPixelSize: (width: Int, height: Int) = (0, 0) {
		didSet {
			guard cellPixelSize != oldValue else { return }
			imageStore.cellPixelSize = cellPixelSize
			applySize()
		}
	}

	/// Named plainly, because this string is shown in the settings window and in
	/// `--report-geometry`. Somebody turning the engine on should learn what is
	/// missing there rather than by noticing it.
	public var unimplemented: [String] {
		var missing = [
			// libghostty-vt reports only *APC* sequences it does not know
			// (`GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_APC`), so an OSC it has never
			// heard of is swallowed and there is no callback to hang this on. It
			// refuses: `abydos <file>` in a pane does nothing at all rather than
			// opening the wrong thing.
			"OSC 440: `abydos <file>` typed in a pane will not open it "
				+ "(libghostty-vt reports unknown APC sequences but not unknown OSC ones)",
			// Measured in 0474 and reproduced by three escapes in
			// `GhosttyEngineTests.theParkRuleIsWhereTheTwoEnginesDiffer`.
			"tmux's prompts draw one row too high when tmux's status bar is off "
				+ "(libghostty-vt clamps the off-screen cursor park; item 0404 is the same fault in ours)",
			// The kitty protocol is honoured; xterm's older `CSI > 4 ; 2 m` cannot
			// be, because libghostty-vt does not report its state and its own
			// encoder emits that form whether or not it was asked for. A program
			// using it gets ordinary bytes, which is what a terminal without the
			// feature does — the conservative direction rather than a sequence
			// nobody asked for. `GhosttyKeyEncoding` has the measurement.
			"xterm's modifyOtherKeys (`CSI > 4 ; 2 m`) is not reported by libghostty-vt, "
				+ "so an ambiguous key sends its ordinary bytes; the kitty protocol works",
		]
		// A pane with no view attached has no cell size, and a cell of no pixels
		// is how a terminal says it cannot show pictures. Named only when it is
		// actually true, so the list shrinks to nothing once a view is there.
		if cellPixelSize.width <= 0 || cellPixelSize.height <= 0 {
			missing.append("Kitty graphics: no cell size yet, so nothing can be placed")
		}
		return missing
	}

	public init(rows: Int = 24, columns: Int = 80) {
		self.rows = max(1, rows)
		self.columns = max(1, columns)

		var handle: GhosttyTerminal?
		// `ghostty_terminal_new(allocator, out, cols, rows)` — cols before rows,
		// and both `uint16_t`. This signature is one of the two places
		// libghostty-vt has actually broken in the last four months (it used to
		// take a `GhosttyTerminalOptions` struct), which is why construction is
		// wrapped here rather than called from several places.
		guard ghostty_terminal_new(nil, &handle, UInt16(self.columns), UInt16(self.rows)) == GHOSTTY_SUCCESS,
		      let handle
		else { return }
		terminal = handle

		// Query responses have to have somewhere to go or they are not encoded
		// at all — the library checks for this callback before it bothers to
		// build the reply.
		let this = Unmanaged.passUnretained(self).toOpaque()
		ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_USERDATA, this)
		let writePty: GhosttyTerminalWritePtyFn = { _, userdata, data, len in
			guard let userdata, let data else { return }
			let engine = Unmanaged<GhosttyTerminalEngine>
				.fromOpaque(userdata).takeUnretainedValue()
			engine.pendingResponse += String(
				decoding: UnsafeBufferPointer(start: data, count: len), as: UTF8.self)
		}
		ghostty_terminal_set(
			handle, GHOSTTY_TERMINAL_OPT_WRITE_PTY,
			unsafeBitCast(writePty, to: UnsafeMutableRawPointer.self))

		// BEL. Ours fires `onBell` from the parser; theirs from a callback.
		let bell: GhosttyTerminalBellFn = { _, userdata in
			guard let userdata else { return }
			Unmanaged<GhosttyTerminalEngine>.fromOpaque(userdata)
				.takeUnretainedValue().onBell?()
		}
		ghostty_terminal_set(
			handle, GHOSTTY_TERMINAL_OPT_BELL,
			unsafeBitCast(bell, to: UnsafeMutableRawPointer.self))

		// OSC 52, and iTerm2's OSC 1337 Copy, normalised to one shape by the
		// library — base64, multipart chunks and selectors already undone. This is
		// how a copy made inside tmux, or over ssh, reaches the clipboard of the
		// machine somebody is sitting at.
		let clipboard: GhosttyTerminalClipboardWriteFn = { _, userdata, write in
			guard let userdata, let write else {
				return GHOSTTY_CLIPBOARD_WRITE_RESULT_INVALID_DATA
			}
			let engine = Unmanaged<GhosttyTerminalEngine>
				.fromOpaque(userdata).takeUnretainedValue()
			// The standard clipboard only. A program writing the X11 primary
			// selection is asking for something macOS does not have.
			guard write.pointee.location == GHOSTTY_CLIPBOARD_LOCATION_STANDARD else {
				return GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED
			}
			// Every entry is the same value in a different MIME type; the first
			// that is text is the one this app can put on a pasteboard.
			guard let contents = write.pointee.contents, write.pointee.contents_len > 0 else {
				return GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS
			}
			for index in 0..<write.pointee.contents_len {
				let entry = contents[index]
				guard let data = entry.data.ptr, entry.data.len > 0 else { continue }
				let text = String(
					decoding: UnsafeBufferPointer(start: data, count: entry.data.len), as: UTF8.self)
				engine.onClipboardWrite?(text)
				return GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS
			}
			return GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED
		}
		ghostty_terminal_set(
			handle, GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE,
			unsafeBitCast(clipboard, to: UnsafeMutableRawPointer.self))

		// Kitty graphics is off until a non-zero storage limit is set, and a
		// forgotten limit looks exactly like "this terminal has no graphics" — the
		// library will not even answer `a=q` in that state. The same 128 MB budget
		// our own store uses, so a picture that fits one fits the other.
		var storageLimit = KittyGraphics.memoryBudget
		ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT, &storageLimit)
		// And PNG, which is what `icat` sends (`f=100`), needs a decoder from us.
		GhosttyPngDecoder.install()

		var render: GhosttyRenderState?
		if ghostty_render_state_new(nil, &render) == GHOSTTY_SUCCESS { renderState = render }

		screen = GhosttyScreenReader(of: self)
		applySize()
		// Nothing is brought up to date here. `isStale` starts true, so the first
		// caller to read anything — the cursor shape before a single byte has arrived,
		// among them — gets a render state built for it then (item 0492).
	}

	deinit {
		// The anchor first: a tracked reference may outlive its terminal, but
		// freeing it while the terminal is still there is the documented order.
		screen?.releaseAnchor()
		if let renderState { ghostty_render_state_free(renderState) }
		if let terminal { ghostty_terminal_free(terminal) }
	}

	/// True when the library is actually there. False means every call below is
	/// a no-op — which is a refusal, not a silent fallback: `unimplemented`
	/// carries the reason and the panel shows it.
	public var isUsable: Bool { terminal != nil }

	/// Pushes whatever `colourLookup` says into the library's palette.
	///
	/// A colour comes back as three `Double`s in 0…1, and the library wants bytes.
	/// An entry the closure has no answer for is left as the library's own
	/// default, which is a refusal to guess rather than a black square.
	private func applyPalette() {
		guard let terminal, let lookup = colourLookup else { return }

		func push(_ option: GhosttyTerminalOption, _ query: TerminalColourQuery) {
			guard let colour = lookup(query) else { return }
			var rgb = GhosttyColorRgb(
				r: UInt8(clamping: Int(colour.red * 255)),
				g: UInt8(clamping: Int(colour.green * 255)),
				b: UInt8(clamping: Int(colour.blue * 255)))
			ghostty_terminal_set(terminal, option, &rgb)
		}
		push(GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, .foreground)
		push(GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, .background)
		push(GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, .cursor)

		// The palette goes across as one array of 256, which is the only shape the
		// option takes. Start from the library's own so an entry we cannot answer
		// keeps whatever it already was.
		var palette = [GhosttyColorRgb](repeating: GhosttyColorRgb(r: 0, g: 0, b: 0), count: 256)
		palette.withUnsafeMutableBufferPointer { buffer in
			guard let base = buffer.baseAddress else { return }
			_ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLOR_PALETTE, base)
			for index in 0..<256 {
				guard let colour = lookup(.palette(index)) else { continue }
				base[index] = GhosttyColorRgb(
					r: UInt8(clamping: Int(colour.red * 255)),
					g: UInt8(clamping: Int(colour.green * 255)),
					b: UInt8(clamping: Int(colour.blue * 255)))
			}
			ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, base)
		}
	}

	// MARK: - Modes
	//
	// Every one of these is state a VT machine keeps by definition, and
	// libghostty-vt answers them all through one call —
	// `GHOSTTY_TERMINAL_DATA_MODE` with the mode packed into a `uint16_t`. Read
	// rather than mirrored: mirroring would mean a second copy of the truth, kept
	// up to date by hand, which is how the two engines would come to disagree.

	/// One DEC private mode. `false` for anything the library will not answer,
	/// which for a mode is the same thing as "off".
	private func mode(_ value: UInt16) -> Bool {
		guard let terminal else { return false }
		// DEC private, so the ANSI bit (15) stays clear. Packed here rather than
		// through `ghostty_mode_new`, which is a `static inline` in the header.
		var config = GhosttyTerminalModeConfig(mode: value, value: false)
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &config) == GHOSTTY_SUCCESS
		else { return false }
		return config.value
	}

	public var bracketedPaste: Bool { mode(2004) }
	public var isSynchronizingOutput: Bool { mode(2026) }
	public var reportsFocus: Bool { mode(1004) }

	/// The strongest tracking mode the program has asked for.
	///
	/// `GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING` answers "any of them", which is not
	/// enough: the view treats click, drag and motion differently, and a program
	/// that asked for presses only must not be sent every movement. So the four
	/// modes are read individually, strongest first.
	public var mouseTracking: TerminalMouseTracking {
		if mode(1003) { return .anyEvent }
		if mode(1002) { return .buttonEvent }
		if mode(1000) { return .click }
		// X10 (mode 9) is press-only and has no separate case on our side; a
		// program that asked for it gets presses, which is what it wanted.
		if mode(9) { return .click }
		return .off
	}

	/// 1006 — SGR mouse reporting, which is the only form that can address a
	/// terminal wider than 223 columns.
	private var usesSgrMouse: Bool { mode(1006) }

	/// What shape the cursor should be, as the program last asked (DECSCUSR).
	///
	/// **From the render state**, which is the only place libghostty-vt reports it.
	/// `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE` is a trap here and cost a crash to
	/// find: despite the name it is the cursor's *SGR style* — the attributes newly
	/// printed characters get — and its output type is a whole `GhosttyStyle`. Read
	/// into a four-byte enum, as the first draft did, it writes a large struct over
	/// a small stack slot and the process traps. The shape is
	/// `GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE`, on the render state.
	///
	/// Blinking is not honoured — a cursor that blinks repaints the screen twice a
	/// second whatever the program is doing — but the shape is: vim in insert mode
	/// asks for a bar, and a block there is a lie about what typing will do.
	public var cursorShape: TerminalCursorShape {
		bringRenderStateUpToDate()
		guard let render = renderState else { return .block }
		var style = GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK
		guard ghostty_render_state_get(
			render, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &style) == GHOSTTY_SUCCESS
		else { return .block }
		switch style {
		case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR: return .bar
		case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE: return .underline
		// A hollow block is a block that is not focused, and whether this pane has
		// the keyboard is the view's own business — it draws the outline itself.
		default: return .block
		}
	}

	/// Whether the kitty keyboard protocol's disambiguation is on.
	///
	/// Bit 1 only, which is the one that matters: "disambiguate escape codes" is
	/// how a program tells Shift+Enter from Enter. xterm's older
	/// `modifyOtherKeys` is *not* part of this answer and cannot be — see
	/// `GhosttyKeyEncoding` for the measurement, and `unimplemented` for the
	/// admission.
	public var reportsModifiedKeys: Bool {
		guard let terminal else { return false }
		return GhosttyKeyEncoding.kittyFlags(terminal: terminal) & 1 != 0
	}

	// MARK: - Encoding, on the way back to the program
	//
	// The arithmetic is `TerminalEmulator`'s, on purpose, so that a pane sends the
	// same bytes under either engine. What libghostty-vt supplies is the state
	// that decides it. `GhosttyKeyEncoding` records why its own encoders are not
	// used, with what was measured.

	public func encodeArrow(_ direction: TerminalArrowKey) -> String {
		// DECCKM, mode 1: every full-screen program turns it on, and an arrow key
		// sent in the wrong form moves the cursor in a shell instead of in vim.
		let prefix = mode(1) ? "\u{1B}O" : "\u{1B}["
		return prefix + direction.rawValue
	}

	public func encodeModifiedKey(
		code: Int, shift: Bool, option: Bool, control: Bool, command: Bool
	) -> String? {
		guard let terminal, GhosttyKeyEncoding.kittyFlags(terminal: terminal) & 1 != 0
		else { return nil }

		// 1 is "no modifiers", and each one adds its bit.
		var modifiers = 1
		if shift { modifiers += 1 }
		if option { modifiers += 2 }
		if control { modifiers += 4 }
		if command { modifiers += 8 }
		// Nothing held is what it always was; a protocol that changed those would
		// break every program that only asked about the modified ones.
		guard modifiers > 1 else { return nil }
		return "\u{1B}[\(code);\(modifiers)u"
	}

	/// A pointer event, in the form the program asked for.
	///
	/// **libghostty-vt's own mouse encoder is deliberately not used here**, and it
	/// is the one place in this engine where that decision went the other way.
	/// Two reasons, both about behaviour rather than taste:
	///
	/// - It takes positions in *surface pixels* and divides by a cell size, so it
	///   would depend on `cellPixelSize` being right — and a cell of no pixels,
	///   which is what a terminal with no view attached has, is documented as
	///   invalid input. Our callers already know the cell.
	/// - It keeps motion-deduplication state
	///   (`GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL`), and the scroll wheel sends
	///   several events at the same cell on purpose — five notches is five reports.
	///   Silently swallowing four of them is exactly the class of difference this
	///   item exists to avoid.
	///
	/// What *does* come from libghostty-vt is everything that decides the answer:
	/// the tracking mode and the SGR format are its modes, read above.
	public func encodeMouse(
		button: TerminalMouseButton, row: Int, column: Int,
		isRelease: Bool, isDrag: Bool, shift: Bool, option: Bool, control: Bool
	) -> String? {
		let tracking = mouseTracking
		guard tracking != .off else { return nil }
		if isDrag, tracking == .click { return nil }
		if button == .none, tracking != .anyEvent { return nil }

		var code = button.rawValue
		if isDrag { code += 32 }
		if shift { code += 4 }
		if option { code += 8 }
		if control { code += 16 }

		let row = max(1, min(row, rows))
		let column = max(1, min(column, columns))

		if usesSgrMouse {
			return "\u{1B}[<\(code);\(column);\(row)\(isRelease ? "m" : "M")"
		}
		let legacyCode = isRelease ? 3 : code
		guard column + 32 < 256, row + 32 < 256 else { return nil }
		let columnByte = Character(UnicodeScalar(UInt8(column + 32)))
		let rowByte = Character(UnicodeScalar(UInt8(row + 32)))
		return "\u{1B}[M\(Character(UnicodeScalar(UInt8(legacyCode + 32))))\(columnByte)\(rowByte)"
	}

	// MARK: - Bytes in

	public func write(_ data: Data) {
		guard let terminal else { return }
		data.withUnsafeBytes { raw in
			guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
			ghostty_terminal_vt_write(terminal, base, raw.count)
		}
		afterWrite()
	}

	public func write(_ string: String) {
		guard let terminal else { return }
		let bytes = Array(string.utf8)
		bytes.withUnsafeBufferPointer { buffer in
			guard let base = buffer.baseAddress else { return }
			ghostty_terminal_vt_write(terminal, base, buffer.count)
		}
		afterWrite()
	}

	/// How many times bytes have gone in, so a snapshot can tell whether the
	/// terminal has moved on since it was taken.
	private var writeCount = 0

	/// Brings the render state up to the terminal as it is now.
	///
	/// One phase, not two. The two-phase form exists so a renderer thread can hold
	/// a lock over the terminal for the `begin` alone; this engine is written to
	/// and read from the same queue, so there is no lock to shorten and the
	/// convenience call is the honest one.
	///
	/// **Once per frame, not once per write** (item 0492). It used to run from
	/// `afterWrite`, at 18.5 µs a call on a 40×100 screen with history against 4.7 µs
	/// to parse the kilobyte that provoked it — four times the cost of the work it was
	/// reacting to, and it was the smaller half of what that item found. `render.h`
	/// exists to be brought up to date when a frame is about to be drawn — its own
	/// documentation says "update it from a terminal instance whenever you need" — and
	/// the terminal accumulates its dirty state until an update consumes it, so
	/// skipping updates loses nothing but the work.
	func updateRenderState() {
		guard let terminal, let renderState else { return }
		renderStateUpdates += 1
		_ = ghostty_render_state_update(renderState, terminal)
	}

	/// How many times the render state has been brought up to date.
	///
	/// The one number that says whether item 0492's fault is back. It is not a
	/// timing, so a test can assert on it at any load: a thousand writes and one read
	/// is one update, and a thousand updates is the old behaviour whatever the
	/// machine was doing.
	public private(set) var renderStateUpdates = 0

	private func afterWrite() {
		writeCount += 1
		isStale = true
		isRenderStateStale = true
		// The one thing that stays on the parse path, and it is here for accuracy
		// rather than for cost: the anchor that counts pruned lines has to be
		// re-pinned to the bottom row *often*, because a burst that scrolls further
		// than the whole buffer between two pinnings prunes the anchor itself and the
		// count then falls back to a lower bound. Three FFI calls, and `writePathCosts`
		// cannot even measure them against a 4.67 µs write — so it is not what was
		// wrong, and it stays where it is exact.
		updateDiscardedLineCount()
		// Everything else that used to be here is now `bringUpToDate()`, run at most
		// once before the next read rather than once per write (item 0492) — except
		// when somebody is measuring the difference, which is what this is for.
		if TerminalCatchUp.perWrite {
			bringRenderStateUpToDate()
			dirty = 0...max(0, screen.totalLineCount - 1)
		}
		// What is left is the two things a caller cannot ask for later: a reply the
		// program is waiting on, and the notification that says bytes arrived.
		if !pendingResponse.isEmpty {
			let response = pendingResponse
			pendingResponse = ""
			onResponse?(response)
		}
		onUpdate?()
	}

	// MARK: - Two tiers of catching up (item 0492)
	//
	// The engine is written to far more often than it is read — 1,400 deliveries a
	// second against 60 frames, on item 0491's measurement — so nothing that a
	// caller could ask for later happens on the parse path. What is left is split in
	// two, because the two halves differ by forty times.
	//
	// `TerminalThroughputTests.writePathCosts` prints these, per write, on a 40×100
	// screen with 5,200 lines of history and a kilobyte a write:
	//
	// | per write | measured |
	// |---|---|
	// | `ghostty_terminal_vt_write` — the actual parse | 4.67 µs |
	// | the cheap tier: cursor, size, screen, graphics, anchor | below noise, −0.01 µs |
	// | `ghostty_render_state_update` | 18.48 µs |
	// | a grid snapshot — the visible rows copied | 194.22 µs |
	//
	// So the cheap tier stays wherever it likes and the other two are what item 0492
	// was about. The snapshot is the larger by ten times and is not even in this file's
	// gift: `TerminalView` used to ask for one on the parse path, once per delivery, to
	// read a line count off it. `TerminalMetrics` is where that went.
	//
	// The cheap tier answers everything but the rows: where the cursor is, how big
	// the grid is, how much history there is, which pictures exist. The expensive one
	// is the render state, and only two things need it — the rows of a frame, and the
	// dirty rows that say which of them to draw.

	/// True when the cheap tier is behind the terminal.
	private var isStale = true
	/// True when the render state is behind the terminal.
	private var isRenderStateStale = true

	/// Brings the cheap state up to the terminal as it is now.
	///
	/// Six `ghostty_terminal_get` calls and a graphics generation check, so it is
	/// safe to call from every accessor and from twenty places in a frame.
	private func bringUpToDate() {
		guard isStale, terminal != nil else { return }
		isStale = false
		refreshState()
		syncGraphics()
	}

	/// Brings the render state up to date, which is the expensive half.
	///
	/// Only the rows of a frame and the dirty range need this, so only `grid` and
	/// `takeDirtyRange` — and `cursorShape`, which the library reports nowhere else —
	/// ask for it. Calling it from the parse path is what item 0492 was filed about.
	private func bringRenderStateUpToDate() {
		bringUpToDate()
		guard isRenderStateStale, terminal != nil else { return }
		isRenderStateStale = false
		updateRenderState()
		noteDirtyRows()
	}

	/// The rows the render state says changed, unioned into the dirty range.
	///
	/// **This is what 0488's row cache was being denied** (item 0492). The engine
	/// used to answer `0...totalLineCount - 1` after every write, which is a truthful
	/// "everything may have changed" and defeats a cache whose whole point is to keep
	/// the rows that did not.
	///
	/// libghostty-vt keeps dirtiness at two layers and `render.h` exports both: a
	/// global state that is `FALSE`, `PARTIAL` or `FULL`, and a flag per row. `FULL`
	/// means something changed that is not a row — the viewport moved, the palette
	/// changed, the screen was swapped — and the honest answer to that is still the
	/// whole document. `PARTIAL` is the case worth having: the prompt rewritten under
	/// cursor-up dirties one row out of forty-seven.
	///
	/// The update call does not clear either layer — its documentation is explicit
	/// that "setting one dirty state doesn't unset the other" — so both are cleared
	/// here, and nothing else in this engine reads them.
	private func noteDirtyRows() {
		guard let renderState else {
			dirty = 0...max(0, screen.totalLineCount - 1)
			return
		}

		var state = GHOSTTY_RENDER_STATE_DIRTY_FULL
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &state) == GHOSTTY_SUCCESS
		else {
			dirty = 0...max(0, screen.totalLineCount - 1)
			return
		}

		// Cleared whatever it said, and before the rows: a return in between would
		// leave the global flag set and every later frame would read `FULL`.
		var clean = GHOSTTY_RENDER_STATE_DIRTY_FALSE
		_ = ghostty_render_state_set(renderState, GHOSTTY_RENDER_STATE_OPTION_DIRTY, &clean)

		if state == GHOSTTY_RENDER_STATE_DIRTY_FULL {
			clearRowDirtyFlags()
			note(dirty: 0...max(0, screen.totalLineCount - 1))
			return
		}
		if state == GHOSTTY_RENDER_STATE_DIRTY_FALSE {
			// Nothing changed, so nothing to draw again — and no rows to clear,
			// because a clean frame has none set.
			return
		}

		var iterator: GhosttyRenderStateRowIterator?
		guard ghostty_render_state_row_iterator_new(nil, &iterator) == GHOSTTY_SUCCESS,
		      let rowIterator = iterator
		else {
			note(dirty: 0...max(0, screen.totalLineCount - 1))
			return
		}
		defer { ghostty_render_state_row_iterator_free(rowIterator) }
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator) == GHOSTTY_SUCCESS
		else {
			note(dirty: 0...max(0, screen.totalLineCount - 1))
			return
		}

		// Absolute rows, which is what the seam speaks: viewport row 0 is the first
		// row of the active grid, and everything above it is scrollback.
		let firstRow = screen.scrollbackCount
		var row = 0
		var lowest = Int.max
		var highest = Int.min
		var off = false
		while ghostty_render_state_row_iterator_next(rowIterator) {
			defer { row += 1 }
			var isDirty = false
			guard ghostty_render_state_row_get(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &isDirty) == GHOSTTY_SUCCESS,
				isDirty
			else { continue }
			lowest = min(lowest, firstRow + row)
			highest = max(highest, firstRow + row)
			_ = ghostty_render_state_row_set(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY, &off)
		}
		guard lowest <= highest else { return }
		note(dirty: lowest...highest)
	}

	/// Unsets every row's dirty flag, for the `FULL` case where they were not read.
	///
	/// Left set they would come back as a `PARTIAL` frame's answer later, naming rows
	/// that changed before the last frame rather than since it.
	private func clearRowDirtyFlags() {
		guard let renderState else { return }
		var iterator: GhosttyRenderStateRowIterator?
		guard ghostty_render_state_row_iterator_new(nil, &iterator) == GHOSTTY_SUCCESS,
		      let rowIterator = iterator
		else { return }
		defer { ghostty_render_state_row_iterator_free(rowIterator) }
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator) == GHOSTTY_SUCCESS
		else { return }
		var off = false
		while ghostty_render_state_row_iterator_next(rowIterator) {
			_ = ghostty_render_state_row_set(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY, &off)
		}
	}

	/// Unions a range into what `takeDirtyRange` will hand over.
	///
	/// Several batches of output are parsed between two frames and each of them may
	/// bring the engine up to date, so the range a frame is given has to be the union
	/// of all of them — the same reason `TerminalDirtyRows` exists on the other side.
	private func note(dirty range: ClosedRange<Int>) {
		guard let existing = dirty else {
			dirty = range
			return
		}
		dirty = min(existing.lowerBound, range.lowerBound)...max(existing.upperBound, range.upperBound)
	}

	// `internal` rather than `private` so `TerminalThroughputTests.writePathCosts`
	// can time each phase on its own (item 0492). Their cost per call is the whole
	// question that item was filed to answer, and a profile of `afterWrite` as one
	// lump is what had it guessing.
	func refreshState() {
		guard let terminal else { return }
		var cx: UInt16 = 0, cy: UInt16 = 0, visible = false
		var cols: UInt16 = 0, rowCount: UInt16 = 0
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_X, &cx)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &cy)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_VISIBLE, &visible)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &cols)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ROWS, &rowCount)
		cachedCursorColumn = Int(cx)
		cachedCursorRow = Int(cy)
		cachedCursorVisible = visible
		columns = Int(cols)
		rows = Int(rowCount)

		// `GhosttyTerminalScreen *`, so the imported enum type rather than a
		// guessed integer width.
		var active = GHOSTTY_TERMINAL_SCREEN_PRIMARY
		if ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &active) == GHOSTTY_SUCCESS {
			cachedAlternateScreen = active != GHOSTTY_TERMINAL_SCREEN_PRIMARY
		}
	}

	/// Copies libghostty-vt's kitty storage into ours, when it has changed.
	///
	/// Two stamps, not one. libghostty-vt's own generation says whether the set of
	/// images and placements changed; it deliberately does *not* change when a
	/// placement merely *moves*, because scrolling moves placements without
	/// touching storage. So a pane that has ever shown a picture re-reads the
	/// geometry each write, and a pane that never has — which is nearly all of
	/// them — costs exactly one FFI call.
	func syncGraphics() {
		guard let terminal else { return }
		guard let snapshot = GhosttyGraphicsBridge.snapshot(
			of: terminal, scrollbackCount: screen.scrollbackCount)
		else { return }
		guard snapshot.generation != 0 || graphicsGeneration != 0 else { return }
		graphicsGeneration = snapshot.generation
		imageStore.adopt(
			images: snapshot.images,
			placements: snapshot.placements,
			virtual: snapshot.virtual)
	}

	// MARK: - Size

	public func resize(rows: Int, columns: Int) {
		self.rows = max(1, rows)
		self.columns = max(1, columns)
		applySize()
		// A resize reflows, so nothing about the old picture survives; the range says
		// so, and the two stale flags send the rest through the next read.
		isStale = true
		isRenderStateStale = true
		refreshState()
		note(dirty: 0...max(0, screen.totalLineCount - 1))
	}

	private func applySize() {
		guard let terminal else { return }
		// The cell pixel size goes in on the same call as the grid size. This is
		// the library's only route for it, and it is what
		// `placement_grid_size` divides by — a cell of no pixels is how a
		// terminal says it cannot show pictures at all, which is 0468's other
		// half.
		ghostty_terminal_resize(
			terminal, UInt16(columns), UInt16(rows),
			UInt32(max(0, cellPixelSize.width)), UInt32(max(0, cellPixelSize.height)))
	}

	public func reset() {
		guard let terminal else { return }
		ghostty_terminal_reset(terminal)
		isStale = true
		isRenderStateStale = true
		refreshState()
		note(dirty: 0...max(0, screen.totalLineCount - 1))
	}

	/// The size and the history, without copying a row.
	///
	/// Two `ghostty_terminal_get` calls on top of the cheap tier, and that is the
	/// point of it existing (item 0492): the parse path used to reach for `grid` to
	/// answer these, and `grid` copies the visible rows.
	public var metrics: TerminalMetrics {
		bringUpToDate()
		return TerminalMetrics(
			rows: rows,
			columns: columns,
			totalLineCount: screen.totalLineCount,
			scrollbackCount: screen.scrollbackCount,
			discardedLineCount: screen.discardedLineCount)
	}

	public func takeDirtyRange() -> ClosedRange<Int>? {
		// The rows that changed are read off the render state, and the render state is
		// brought up to date here rather than on the parse path (item 0492).
		bringRenderStateUpToDate()
		defer { dirty = nil }
		return dirty
	}

	// MARK: - Grid out

	/// The screen as a grid, which `GhosttyScreenReader` copies out.
	///
	/// The render state is brought up to date here and not there: staleness is
	/// this class's business, since it is what takes the bytes that cause it.
	public var grid: TerminalGridReading {
		bringRenderStateUpToDate()
		return screen.grid
	}

	/// Lines that have fallen off the top for good, which the reader counts with
	/// a tracked grid reference because the library does not report it.
	public var discardedLineCount: Int { screen.discardedLineCount }

	/// Whether the last read of the visible rows came from the render state.
	///
	/// A test asserts this, because the fallback produces *identical* rows — that
	/// is what makes it a safe fallback — and a silent permanent fallback would
	/// therefore be invisible.
	public var usedRenderStateForVisibleRows: Bool { screen.usedRenderStateForVisibleRows }

	public func link(for id: UInt16) -> String? { screen.link(for: id) }

	/// Rows `from ..< from + count`, in absolute indices. Used by a test that
	/// compares the two read paths cell for cell.
	func copyLines(from: Int, count: Int) -> [TerminalLine] {
		screen.copyLines(from: from, count: count)
	}

	func updateDiscardedLineCount() { screen.updateDiscardedLineCount() }

	/// Shrinks the scrollback budget so a test can see pruning happen.
	func setScrollbackByteLimitForTesting(_ bytes: Int) {
		screen.setScrollbackByteLimitForTesting(bytes)
	}
}

/// What the reader is allowed to ask of the engine, and the one thing it says
/// back. Deliberately five handles and a notification rather than the engine
/// itself, so that what crosses between them is written down.
extension GhosttyTerminalEngine: GhosttyScreen {
	var screenTerminal: GhosttyTerminal? { terminal }
	var screenRenderState: GhosttyRenderState? { renderState }
	var screenRows: Int { rows }
	var screenColumns: Int { columns }
	var screenWriteCount: Int { writeCount }
	func screenNoteDirty(_ range: ClosedRange<Int>) { note(dirty: range) }
}
