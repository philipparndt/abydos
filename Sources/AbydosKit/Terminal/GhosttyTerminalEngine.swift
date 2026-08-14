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

	/// Hyperlink addresses, interned so a cell can carry a `UInt16` the way ours
	/// does.
	///
	/// libghostty-vt hands back the URI itself (`grid_ref_hyperlink_uri`) rather
	/// than an index, which is the better shape — but `TerminalCell.attributes`
	/// has a `UInt16` and the renderer, the hover cursor and `link(for:)` are all
	/// written to it. So the snapshot interns, and this is the table. It only ever
	/// grows: a URI that has left the screen may still be under a selection made
	/// before it did.
	private var links: [String] = []
	private var linkIndex: [String: UInt16] = [:]

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

		applySize()
		// Nothing is brought up to date here. `isStale` starts true, so the first
		// caller to read anything — the cursor shape before a single byte has arrived,
		// among them — gets a render state built for it then (item 0492).
	}

	deinit {
		// The anchor first: a tracked reference may outlive its terminal, but
		// freeing it while the terminal is still there is the documented order.
		if let anchor { ghostty_tracked_grid_ref_free(anchor) }
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

	// MARK: - Hyperlinks

	public func link(for id: UInt16) -> String? {
		guard id > 0, Int(id) <= links.count else { return nil }
		return links[Int(id) - 1]
	}

	/// The id a URI is known by, assigning one the first time it is seen.
	fileprivate func internedLink(_ uri: String) -> UInt16 {
		if let existing = linkIndex[uri] { return existing }
		// 0 means "no link", so ids start at 1 — the same numbering ours uses.
		guard links.count < Int(UInt16.max) else { return 0 }
		links.append(uri)
		let id = UInt16(links.count)
		linkIndex[uri] = id
		return id
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
	fileprivate var currentWriteCount: Int { writeCount }

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
			dirty = 0...max(0, totalLineCount - 1)
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
			dirty = 0...max(0, totalLineCount - 1)
			return
		}

		var state = GHOSTTY_RENDER_STATE_DIRTY_FULL
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &state) == GHOSTTY_SUCCESS
		else {
			dirty = 0...max(0, totalLineCount - 1)
			return
		}

		// Cleared whatever it said, and before the rows: a return in between would
		// leave the global flag set and every later frame would read `FULL`.
		var clean = GHOSTTY_RENDER_STATE_DIRTY_FALSE
		_ = ghostty_render_state_set(renderState, GHOSTTY_RENDER_STATE_OPTION_DIRTY, &clean)

		if state == GHOSTTY_RENDER_STATE_DIRTY_FULL {
			clearRowDirtyFlags()
			note(dirty: 0...max(0, totalLineCount - 1))
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
			note(dirty: 0...max(0, totalLineCount - 1))
			return
		}
		defer { ghostty_render_state_row_iterator_free(rowIterator) }
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator) == GHOSTTY_SUCCESS
		else {
			note(dirty: 0...max(0, totalLineCount - 1))
			return
		}

		// Absolute rows, which is what the seam speaks: viewport row 0 is the first
		// row of the active grid, and everything above it is scrollback.
		let firstRow = scrollbackCount
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
		var screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
		if ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen) == GHOSTTY_SUCCESS {
			cachedAlternateScreen = screen != GHOSTTY_TERMINAL_SCREEN_PRIMARY
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
			of: terminal, scrollbackCount: scrollbackCount)
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
		note(dirty: 0...max(0, totalLineCount - 1))
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
		note(dirty: 0...max(0, totalLineCount - 1))
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
			totalLineCount: totalLineCount,
			scrollbackCount: scrollbackCount,
			discardedLineCount: discardedLineCount)
	}

	public func takeDirtyRange() -> ClosedRange<Int>? {
		// The rows that changed are read off the render state, and the render state is
		// brought up to date here rather than on the parse path (item 0492).
		bringRenderStateUpToDate()
		defer { dirty = nil }
		return dirty
	}

	// MARK: - Grid out

	// `size_t`, not `uint32_t`. Every one of these output types is documented in
	// the header and getting one wrong is a silent stack write of the wrong
	// width, which is exactly the kind of bug that passes its tests: the first
	// draft of this file read both of these into a `UInt32` and the suite was
	// green.
	private var totalLineCount: Int {
		guard let terminal else { return rows }
		var total = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &total) == GHOSTTY_SUCCESS
		else { return rows }
		return total
	}

	/// Lines that have fallen off the top for good.
	///
	/// **libghostty-vt does not report this**, which 0474 named as the one thing
	/// genuinely missing. It prunes its own scrollback and says nothing about how
	/// much it threw away, so absolute indices from an older frame could not be
	/// told apart from current ones and the engine used to answer 0 — which the
	/// `unimplemented` list had to admit made the scrollbar and selection
	/// realignment wrong.
	///
	/// The answer is the tracked grid reference the header points at: it "follows
	/// its cell across … scrolling, scrollback pruning, resize/reflow". So an
	/// anchor is pinned to the bottom row after every write, and how far its
	/// absolute index has *fallen* between two writes is exactly how many lines
	/// were pruned in between. Re-anchoring each time keeps the anchor inside the
	/// active grid, where nothing can prune it.
	///
	/// The one case it cannot be exact about, stated rather than hidden: a single
	/// write that scrolls so far that the anchor itself is pruned. Then the anchor
	/// reports no value, and all that is known is that *at least* everything up to
	/// it went, so that lower bound is what gets added. The count is then low, and
	/// the visible consequence is a selection made before the burst sitting a few
	/// rows off. Ours is exact here because it does its own pruning and can count.
	public private(set) var discardedLineCount = 0

	/// The anchor, and the absolute index it was at when it was last set.
	private var anchor: GhosttyTrackedGridRef?
	private var anchorIndex = 0

	func updateDiscardedLineCount() {
		guard let terminal else { return }
		let bottom = max(0, totalLineCount - 1)

		if let anchor {
			var coordinate = GhosttyPointCoordinate()
			var pruned = 0
			if ghostty_tracked_grid_ref_point(anchor, GHOSTTY_POINT_TAG_SCREEN, &coordinate)
				== GHOSTTY_SUCCESS {
				// Its index can only have gone *down*, and only by pruning.
				pruned = max(0, anchorIndex - Int(coordinate.y))
			} else {
				// Gone. At least everything up to and including it was pruned.
				pruned = anchorIndex + 1
			}
			discardedLineCount += pruned
			// A line leaving history renumbers every absolute row, and
			// `TerminalDirtyRows` unions ranges taken at different moments as absolute
			// rows — which is only sound because the moment of renumbering is also a
			// moment the whole document is marked.
			// `TerminalDirtyRangeTests.aDiscardedLineDirtiesEverything` asserts that of
			// our engine; this is the same promise from this one, and it has to be made
			// here rather than in `noteDirtyRows` because pruning is counted on the
			// parse path and the rows are read on the frame.
			if pruned > 0 { note(dirty: 0...bottom) }
		}

		var point = GhosttyPoint()
		point.tag = GHOSTTY_POINT_TAG_SCREEN
		point.value.coordinate.x = 0
		point.value.coordinate.y = UInt32(bottom)
		if let anchor {
			_ = ghostty_tracked_grid_ref_set(anchor, terminal, point)
		} else {
			var created: GhosttyTrackedGridRef?
			guard ghostty_terminal_grid_ref_track(terminal, point, &created) == GHOSTTY_SUCCESS
			else { return }
			anchor = created
		}
		anchorIndex = bottom
	}

	/// Shrinks the scrollback budget so a test can see pruning happen.
	///
	/// libghostty-vt's default byte budget is large enough that reaching it in a
	/// test would mean writing a hundred thousand lines, and the thing worth
	/// testing is the counting rather than the budget.
	func setScrollbackByteLimitForTesting(_ bytes: Int) {
		guard let terminal else { return }
		var limit = bytes
		ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, &limit)
	}

	private var scrollbackCount: Int {
		guard let terminal else { return 0 }
		var back = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &back) == GHOSTTY_SUCCESS
		else { return 0 }
		return back
	}

	/// A snapshot: the visible rows copied, the scrollback fetched if asked for.
	///
	/// The protocol promises a grid that survives later writes, and
	/// libghostty-vt's grid references explicitly do not: an untracked reference
	/// "is only valid until the next update to the terminal instance … even if a
	/// seemingly unrelated part of the grid is changed". So the rows have to be
	/// copied out while we hold the terminal.
	///
	/// **What changed for item 0485**: it used to copy *every* row. 0474 measured
	/// that at 4.372 ms a frame on a 40-row screen with 5,200 lines of history —
	/// 524,000 cells across FFI to draw forty rows — which gave back the 17× the
	/// parser wins. The cost is now O(viewport): the active grid is copied, and a
	/// row in scrollback is copied only when something asks for it, which happens
	/// when somebody scrolls up, drags a selection through history, or copies.
	///
	/// A row fetched late is fetched from a terminal that may have moved on, so
	/// `GhosttyGrid` records the write count it was made at and **refuses** —
	/// returns nil — rather than hand back a row from a different moment. In
	/// practice it never has to: the view snapshots and walks the snapshot inside
	/// one turn of the main queue, and writes happen on the same queue.
	/// The snapshot for the current state of the terminal, made once.
	///
	/// Cached because `TerminalView` reads `emulator.grid` about twenty times in a
	/// frame — for the row count, the column count, the scrollback offset, a line,
	/// the selection — and for our own engine every one of those is a retain of a
	/// value type. A fresh copy each time would multiply the per-frame cost by
	/// twenty and hide it behind an innocent-looking `.rows`. Thrown away by the
	/// next write, which is the only thing that can make it wrong.
	private var cachedGrid: GhosttyGrid?

	public var grid: TerminalGridReading {
		bringRenderStateUpToDate()
		if let cachedGrid, cachedGrid.matches(writeCount: writeCount) { return cachedGrid }
		let scrollback = scrollbackCount
		let made = GhosttyGrid(
			rows: rows, columns: columns,
			totalLineCount: totalLineCount,
			scrollbackCount: scrollback,
			discardedLineCount: discardedLineCount,
			// The render state for the rows on screen, which is what a frame reads
			// and what its documentation says to use. `copyLines` — grid references
			// — remains for scrollback, which the render state does not cover and
			// which is not a render loop.
			visible: visibleRows(from: scrollback),
			source: self,
			writeCount: writeCount)
		cachedGrid = made
		return made
	}

	/// Whether the last read of the visible rows came from the render state.
	///
	/// A test asserts this, because the fallback below produces *identical* rows —
	/// that is what makes it a safe fallback — and a silent permanent fallback
	/// would therefore be invisible. It is the difference between the render path
	/// being on `render.h` and merely being able to be.
	public private(set) var usedRenderStateForVisibleRows = false

	/// The rows on screen: the render state if it will answer, grid references if
	/// it will not.
	private func visibleRows(from scrollback: Int) -> [TerminalLine] {
		if let fromRenderState = copyVisibleRowsFromRenderState() {
			usedRenderStateForVisibleRows = true
			return fromRenderState
		}
		usedRenderStateForVisibleRows = false
		return copyLines(from: scrollback, count: rows)
	}

	/// The rows on screen, from the render state.
	///
	/// **This is the hot path, and `render.h` is what it is meant to use.** Grid
	/// references say so themselves: "the grid reference APIs are *not* meant to be
	/// used as the core of a render loop. They are not built to sustain the
	/// framerates needed for rendering large screens. Use the render state API for
	/// that." The difference in practice is that a grid reference costs a point
	/// resolution *per cell* — `ghostty_terminal_grid_ref` walks the page list to
	/// find the node — while the render state hands out a row iterator and then a
	/// cell iterator that simply advance.
	///
	/// Two things still need a grid reference and are asked for per *row* rather
	/// than per cell, only when the row says it has them: a grapheme cluster's
	/// codepoints, and a hyperlink's URI. The render state reports the cluster
	/// length and can write the codepoints, but there is no URI accessor on it at
	/// all, so a row carrying a link falls back for that row alone. Ordinary output
	/// has neither, and pays for neither.
	///
	/// Returns nil if there is no render state, in which case the caller falls back
	/// to `copyLines`, which is the obviously-correct version and the one the
	/// differential tests were first written against.
	private func copyVisibleRowsFromRenderState() -> [TerminalLine]? {
		guard let renderState else { return nil }

		var iterator: GhosttyRenderStateRowIterator?
		guard ghostty_render_state_row_iterator_new(nil, &iterator) == GHOSTTY_SUCCESS,
		      let rowIterator = iterator
		else { return nil }
		defer { ghostty_render_state_row_iterator_free(rowIterator) }
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator) == GHOSTTY_SUCCESS
		else { return nil }

		var cellsHandle: GhosttyRenderStateRowCells?
		guard ghostty_render_state_row_cells_new(nil, &cellsHandle) == GHOSTTY_SUCCESS,
		      let cells = cellsHandle
		else { return nil }
		defer { ghostty_render_state_row_cells_free(cells) }

		var lines: [TerminalLine] = []
		lines.reserveCapacity(rows)
		var codepoints = [UInt32](repeating: 0, count: 16)
		// The absolute index of the first row on screen, for the rows that have to
		// fall back to a grid reference.
		let firstRow = scrollbackCount

		while ghostty_render_state_row_iterator_next(rowIterator) {
			var line = TerminalLine(columns: columns)

			var rawRow = GhosttyRow()
			var hasHyperlink = false
			if ghostty_render_state_row_get(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &rawRow) == GHOSTTY_SUCCESS {
				ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_HYPERLINK, &hasHyperlink)
			}

			guard ghostty_render_state_row_get(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellsHandle) == GHOSTTY_SUCCESS
			else {
				lines.append(line)
				continue
			}

			var column = 0
			while column < columns, ghostty_render_state_row_cells_next(cells) {
				defer { column += 1 }

				var rawCell = GhosttyCell()
				guard ghostty_render_state_row_cells_get(
					cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &rawCell) == GHOSTTY_SUCCESS
				else { continue }

				var scalar: UInt32 = 0
				var wide: Int32 = 0
				ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_CODEPOINT, &scalar)
				ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_WIDE, &wide)

				var cell = TerminalCell(scalar: scalar == 0 ? 0x20 : scalar)
				cell.isWideTrailer = wide == 2

				// The *raw* style, so a palette index stays an index and the editor's
				// theme decides what "red" is. The render state also offers resolved
				// RGB, which is what a renderer with no theme of its own would want.
				var styled = false
				ghostty_render_state_row_cells_get(
					cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &styled)
				if styled {
					var style = GhosttyStyle()
					style.size = MemoryLayout<GhosttyStyle>.size
					if ghostty_render_state_row_cells_get(
						cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style) == GHOSTTY_SUCCESS {
						cell.attributes = attributes(from: style)
					}
				}

				// A grapheme cluster, when there is one. The length comes off the
				// render state; the codepoints go into a buffer we own.
				var clusterLength: UInt32 = 0
				ghostty_render_state_row_cells_get(
					cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &clusterLength)
				if clusterLength > 1 {
					if Int(clusterLength) > codepoints.count {
						codepoints = [UInt32](repeating: 0, count: Int(clusterLength))
					}
					let wrote = codepoints.withUnsafeMutableBufferPointer { buffer in
						ghostty_render_state_row_cells_get(
							cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
							buffer.baseAddress) == GHOSTTY_SUCCESS
					}
					if wrote {
						var text = ""
						for index in 0..<Int(clusterLength) {
							if let unicode = UnicodeScalar(codepoints[index]) {
								text.unicodeScalars.append(unicode)
							}
						}
						cell.combining = text
					}
				}
				line.cells[column] = cell
			}

			// A row with a link on it: the URIs are not on the render state, so this
			// one row is read again through grid references. Rare enough that a whole
			// extra row costs less than a check per cell would.
			if hasHyperlink,
			   let refetched = copyLines(from: firstRow + lines.count, count: 1).first {
				for index in 0..<min(line.cells.count, refetched.cells.count) {
					line.cells[index].attributes.link = refetched.cells[index].attributes.link
				}
			}
			lines.append(line)
		}

		// The render state should hand back exactly the rows on screen. If it hands
		// back a different number the caller is being lied to about the size of the
		// grid, and falling back is better than drawing a short screen.
		guard lines.count == rows else { return nil }
		return lines
	}

	/// Rows `from ..< from + count`, in absolute indices, through grid references.
	///
	/// Not the render path — see `copyVisibleRowsFromRenderState` — but the right
	/// tool for scrollback, which the render state does not cover: a grid reference
	/// is documented as "a snapshot … meant to be read and have their values cached
	/// immediately", which is exactly what a scroll back into history is.
	func copyLines(from: Int, count: Int) -> [TerminalLine] {
		guard let terminal, count > 0 else { return [] }
		var lines: [TerminalLine] = []
		lines.reserveCapacity(count)
		var codepoints = [UInt32](repeating: 0, count: 16)
		var uriBytes = [UInt8](repeating: 0, count: 512)

		for y in from..<(from + count) {
			var line = TerminalLine(columns: columns)
			for x in 0..<columns {
				var point = GhosttyPoint()
				point.tag = GHOSTTY_POINT_TAG_SCREEN
				point.value.coordinate.x = UInt16(x)
				point.value.coordinate.y = UInt32(max(0, y))

				var ref = GhosttyGridRef()
				ref.size = MemoryLayout<GhosttyGridRef>.size
				guard ghostty_terminal_grid_ref(terminal, point, &ref) == GHOSTTY_SUCCESS else { continue }

				var cellHandle = GhosttyCell()
				guard ghostty_grid_ref_cell(&ref, &cellHandle) == GHOSTTY_SUCCESS else { continue }

				var scalar: UInt32 = 0
				var wide: Int32 = 0
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_CODEPOINT, &scalar)
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_WIDE, &wide)

				var cell = TerminalCell(scalar: scalar == 0 ? 0x20 : scalar)
				// `wide` is a four-way — narrow 0, wide 1, spacer-**tail** 2,
				// spacer-**head** 3 — and only the tail is our `isWideTrailer`. A
				// spacer *head* is the blank left at the end of a row when a wide
				// glyph would not fit in the last column, which is a real cell
				// with nothing in it rather than the second half of anything.
				cell.isWideTrailer = wide == 2
				cell.attributes = attributes(of: cellHandle, at: &ref)

				// A grapheme cluster is more than its base codepoint. Ask only
				// when the cell says it has one, because this call is not free.
				var hasText = false
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_HAS_TEXT, &hasText)
				if hasText {
					var written = 0
					let result = codepoints.withUnsafeMutableBufferPointer { buffer in
						ghostty_grid_ref_graphemes(&ref, buffer.baseAddress, buffer.count, &written)
					}
					if result == GHOSTTY_SUCCESS, written > 1 {
						var text = ""
						for index in 0..<written {
							if let unicode = UnicodeScalar(codepoints[index]) {
								text.unicodeScalars.append(unicode)
							}
						}
						cell.combining = text
					}
				}

				// A hyperlink, if the cell has one. libghostty-vt hands back the URI
				// itself rather than an index, so it is interned here into the
				// `UInt16` our cells carry — asked for only when the cell says there
				// is one, which on ordinary output is never.
				var hasHyperlink = false
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_HAS_HYPERLINK, &hasHyperlink)
				if hasHyperlink {
					var written = 0
					let result = uriBytes.withUnsafeMutableBufferPointer { buffer in
						ghostty_grid_ref_hyperlink_uri(&ref, buffer.baseAddress, buffer.count, &written)
					}
					if result == GHOSTTY_SUCCESS, written > 0 {
						cell.attributes.link = internedLink(
							String(decoding: uriBytes.prefix(written), as: UTF8.self))
					}
				}
				line.cells[x] = cell
			}
			lines.append(line)
		}
		return lines
	}

	private func attributes(
		of cell: GhosttyCell, at ref: inout GhosttyGridRef
	) -> TerminalAttributes {
		let plain = TerminalAttributes()
		var styled = false
		ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_STYLING, &styled)
		guard styled else { return plain }

		var style = GhosttyStyle()
		style.size = MemoryLayout<GhosttyStyle>.size
		guard ghostty_grid_ref_style(&ref, &style) == GHOSTTY_SUCCESS else { return plain }
		return attributes(from: style)
	}

	/// One `GhosttyStyle` as our attributes. Shared by both read paths, so the
	/// render state and grid references cannot come to disagree about a colour.
	private func attributes(from style: GhosttyStyle) -> TerminalAttributes {
		var attributes = TerminalAttributes()
		// The *raw* style, not the resolved foreground colour. Resolving would
		// put a palette index through the palette and hand back RGB, and this
		// app deliberately keeps a colour unresolved so the editor's theme
		// decides what "red" is.
		attributes.foreground = colour(style.fg_color)
		attributes.background = colour(style.bg_color)
		attributes.bold = style.bold
		attributes.italic = style.italic
		attributes.dim = style.faint
		attributes.inverse = style.inverse
		attributes.hidden = style.invisible
		attributes.strikethrough = style.strikethrough
		// Ours is a Bool and theirs is an SGR underline style, so every kind of
		// underline but "none" becomes true. That is the same flattening
		// `TerminalEmulator` already does with SGR 4:3.
		attributes.underline = style.underline != 0
		return attributes
	}

	private func colour(_ value: GhosttyStyleColor) -> TerminalColor {
		switch value.tag {
		case GHOSTTY_STYLE_COLOR_PALETTE: return .indexed(UInt8(truncatingIfNeeded: value.value.palette))
		case GHOSTTY_STYLE_COLOR_RGB:
			let rgb = value.value.rgb
			return .rgb(rgb.r, rgb.g, rgb.b)
		default: return .default
		}
	}
}

/// The snapshot `GhosttyTerminalEngine.grid` hands out.
///
/// The visible rows are copied when the snapshot is made, because that is what a
/// frame reads and it has to survive whatever the terminal does next. Scrollback
/// is not: on a full buffer that would be five thousand rows copied to draw
/// forty, which is 0474's 4.372 ms a frame. A scrollback row is fetched the first
/// time somebody asks for it — scrolling up, dragging a selection back through
/// history, Select All, `recentLines` — and then kept.
///
/// A class rather than a struct because of that keeping: the cache is shared by
/// every copy of the snapshot, and a value type would either lose it or copy it.
final class GhosttyGrid: TerminalGridReading {
	let rows: Int
	let columns: Int
	let totalLineCount: Int
	let scrollbackCount: Int
	let discardedLineCount: Int

	/// Rows `scrollbackCount ..< totalLineCount`, copied up front.
	private let visible: [TerminalLine]
	/// Rows below that, copied on demand and then remembered.
	private var history: [Int: TerminalLine] = [:]
	private weak var source: GhosttyTerminalEngine?
	/// What the engine's write count was when this snapshot was made.
	private let writeCount: Int

	init(
		rows: Int, columns: Int, totalLineCount: Int, scrollbackCount: Int,
		discardedLineCount: Int, visible: [TerminalLine],
		source: GhosttyTerminalEngine, writeCount: Int
	) {
		self.rows = rows
		self.columns = columns
		self.totalLineCount = totalLineCount
		self.scrollbackCount = scrollbackCount
		self.discardedLineCount = discardedLineCount
		self.visible = visible
		self.source = source
		self.writeCount = writeCount
	}

	/// Whether this snapshot still describes the terminal as it is now.
	func matches(writeCount: Int) -> Bool { self.writeCount == writeCount }

	func line(at index: Int) -> TerminalLine? {
		guard index >= 0, index < totalLineCount else { return nil }
		if index >= scrollbackCount {
			let offset = index - scrollbackCount
			guard offset < visible.count else { return nil }
			return visible[offset]
		}
		if let cached = history[index] { return cached }
		// **A refusal, not a guess.** Once the engine has taken more bytes, the row
		// at this index is not the row this snapshot was describing, and handing
		// back the new one would be the "silently misrenders" failure in its
		// quietest form — a selection copying text it was never over. In practice
		// this never fires: the view snapshots and walks the snapshot within one
		// turn of the main queue, and writes are on the same queue.
		guard let source, source.currentWriteCount == writeCount else { return nil }
		guard let fetched = source.copyLines(from: index, count: 1).first else { return nil }
		history[index] = fetched
		return fetched
	}
}
