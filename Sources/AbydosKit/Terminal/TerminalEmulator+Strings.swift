import Foundation

/// The two string sequences: APC, which carries kitty graphics, and OSC, which
/// carries the title, the clipboard, hyperlinks and the colour queries.
///
/// Both are open-ended — a payload that runs until a terminator — which is why
/// both have a ceiling on how much they may hold, and why they are the two that
/// answer the program back.
extension TerminalEmulator {
	// MARK: - APC

	/// APC carries the kitty graphics protocol, and nothing else anybody sends.
	///
	/// Terminated by ST, exactly as OSC is. It used to be discarded wholesale,
	/// which is why an image sent to this terminal did nothing at all.
	func consumeAPC(_ byte: UInt8) {
		if byte == 0x1B {
			finishAPC()
			state = .escape
			return
		}
		// A stream that never terminates must not be accumulated forever. Past
		// the cap the sequence is marked and dropped whole at the end rather
		// than delivered short: a truncated payload is a picture that fails to
		// decode, or worse decodes to something wrong, and neither says why.
		guard apcBytes.count < Self.longestAPC else {
			apcOverflowed = true
			return
		}
		apcBytes.append(byte)
	}

	/// Longest APC sequence held.
	///
	/// The protocol says a chunk should be at most 4096 bytes of base64, and
	/// this was 8192 on the strength of it. kitty's own `icat` does not follow
	/// its own recommendation when it believes the terminal can cope: it sends
	/// the whole image in two chunks of 131072. Everything past 8192 was
	/// swallowed, the base64 was truncated, the PNG did not decode and no
	/// picture appeared — which is why kitty's icat drew nothing here and
	/// everything in the terminals it was tested against.
	///
	/// Eight megabytes is far past any real chunk and still a bound. What a
	/// picture actually costs is capped separately, by the image store's own
	/// budget, once it is decoded.
	private static let longestAPC = 8 * 1024 * 1024

	private func finishAPC() {
		let bytes = apcBytes
		let overflowed = apcOverflowed
		apcBytes = []
		apcOverflowed = false
		guard !overflowed else {
			state = .ground
			return
		}
		state = .ground
		// `G` is kitty's; there is no other APC to answer.
		guard bytes.first == 0x47 else { return }

		let command = KittyGraphicsCommand(Array(bytes.dropFirst()))
		let result = graphics.apply(command, context: .init(
			scrollbackCount: screen.scrollback.count,
			cursorRow: cursorRow,
			cursorColumn: cursorColumn,
			rows: screen.rows,
			columns: screen.columns
		))

		if let response = result.response { onResponse?(response) }
		if let dirty = result.dirtyRows { screen.markDirty(absolute: dirty) }
		if let advance = result.cursorAdvance {
			// Down first, then across, so a picture wider than what is left of the
			// row still lands the cursor on the row the image ends on.
			//
			// A line feed for each row rather than one move to the row it ends on.
			// A move *clamps* at the last row, and a picture placed where fewer
			// rows are left than it needs then keeps the rows it was given —
			// rows below the bottom of the screen, which are never drawn, and
			// which overlap everything the shell erases from its next prompt
			// downwards, so `ESC[J` took the picture away. A feed makes the room
			// instead: the retired lines go into the scrollback, every absolute
			// row stays where it was, and the picture comes onto the screen.
			//
			// This is what a program placing a picture is asking for. It is told
			// nothing about how tall the pane is — `icat` outside tmux sends no
			// `r` at all — so making room is the terminal's part, exactly as it
			// is when a program prints that many lines.
			for _ in 0..<advance.rows { lineFeed() }
			for _ in 0..<advance.columns {
				if cursorColumn == screen.columns - 1 {
					cursorColumn = 0
					lineFeed()
				} else {
					cursorColumn += 1
				}
			}
		}
	}

	// MARK: - OSC

	func consumeOSC(_ byte: UInt8) {
		// Terminated by BEL or ST (ESC \).
		if byte == 0x07 {
			finishOSC()
			return
		}
		if byte == 0x1B {
			// The backslash of ST follows. Handing it back to the escape handler
			// consumes it; finishing straight to ground left it to be printed as
			// ordinary text.
			finishOSC()
			state = .escape
			return
		}
		oscBytes.append(byte)
	}

	private func finishOSC() {
		// Decoded as UTF-8, not byte-per-character. A title is arbitrary text and
		// routinely contains an emoji; treating each byte as a scalar turned
		// "\u{23F3}" into "\u{00E2}\u{008F}\u{00B3}" and put mojibake in the tab.
		let text = String(decoding: oscBytes, as: UTF8.self)
		oscBytes = []
		state = .ground

		let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		guard let code = Int(parts.first ?? "") else { return }
		let body = parts.count > 1 ? String(parts[1]) : ""

		switch code {
		case 0, 2:
			title = body
		case 4:
			applyPaletteRequest(body)
		case 8:
			applyHyperlink(body)
		case 10, 11, 12:
			applyColourRequest(code: code, body: body)
		case 52:
			applyClipboard(body)
		case TerminalOpenRequest.osc:
			applyOpenRequest(body)
		default:
			break
		}
	}

	/// OSC 440 — a program asking this window to open a file.
	///
	/// Two messages share the code. `?` is the question a command asks before
	/// it commits to anything: it is answered only by this app, so a command
	/// that gets no answer knows it is somewhere else and can fall back to
	/// `open -a` rather than writing an escape into the void. `open;…` is the
	/// request itself.
	private func applyOpenRequest(_ body: String) {
		if body == "?" {
			onResponse?(TerminalOpenRequest.reply)
			return
		}
		guard let request = TerminalOpenRequest(body: body) else { return }
		onOpenFile?(request)
	}

	/// OSC 52 — a program handing something to the clipboard.
	///
	/// Only writing. A program that asks to *read* the clipboard is refused in
	/// silence: anything that can run in a terminal could then take whatever
	/// somebody last copied, which is a password as often as not.
	private func applyClipboard(_ body: String) {
		let parts = body.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2 else { return }
		let payload = String(parts[1])
		guard payload != "?" else { return }

		guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else { return }
		onClipboardWrite?(String(decoding: data, as: UTF8.self))
	}

	/// OSC 10, 11, 12 — the default foreground, background and cursor colours.
	///
	/// A query is what matters: a program asks what the background is so it can
	/// choose a palette that can be read against it, and one that gets no
	/// answer guesses — which is how a light theme ends up with grey-on-white
	/// diffs.
	private func applyColourRequest(code: Int, body: String) {
		let query: ColourQuery = code == 10 ? .foreground : (code == 11 ? .background : .cursor)
		for request in body.split(separator: ";") where request == "?" {
			guard let colour = colourLookup?(query) else { continue }
			onResponse?("\u{1B}]\(code);\(Self.xtermColour(colour))\u{1B}\\")
		}
	}

	/// OSC 4 — a palette entry, asked about by number.
	private func applyPaletteRequest(_ body: String) {
		let fields = body.split(separator: ";", omittingEmptySubsequences: false)
		var index = 0
		for (position, field) in fields.enumerated() {
			if position % 2 == 0 {
				index = Int(field) ?? -1
			} else if field == "?", index >= 0 {
				guard let colour = colourLookup?(.palette(index)) else { continue }
				onResponse?("\u{1B}]4;\(index);\(Self.xtermColour(colour))\u{1B}\\")
			}
		}
	}

	/// OSC 8 — the text that follows belongs to an address.
	///
	/// `OSC 8 ; params ; uri ST` opens one and `OSC 8 ; ; ST` closes it, so a
	/// program brackets the text it wants to make clickable. The parameters
	/// carry an id for linking runs that are far apart, which nothing here
	/// needs: what matters is which address a cell belongs to.
	private func applyHyperlink(_ body: String) {
		let parts = body.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		let uri = parts.count > 1 ? String(parts[1]) : ""
		guard !uri.isEmpty else {
			attributes.link = 0
			return
		}

		// Only the addresses a screenful can hold: a program printing thousands
		// of links should not grow a table nobody will look at again.
		if let existing = links.firstIndex(of: uri) {
			attributes.link = UInt16(existing + 1)
			return
		}
		guard links.count < Int(UInt16.max) - 1 else { return }
		links.append(uri)
		attributes.link = UInt16(links.count)
	}

	/// `rgb:RRRR/GGGG/BBBB`, which is the form every terminal answers in.
	static func xtermColour(_ colour: (red: Double, green: Double, blue: Double)) -> String {
		func component(_ value: Double) -> String {
			String(format: "%04x", Int((max(0, min(1, value)) * 65535).rounded()))
		}
		return "rgb:\(component(colour.red))/\(component(colour.green))/\(component(colour.blue))"
	}
}
