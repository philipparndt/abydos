import AppKit
import AbydosKit

/// What was being drawn a moment ago, for the crash log to say.
///
/// There is one crash this exists for: an abort inside CoreText, raised while
/// measuring an attributed string, on a nil that no line of this app's source
/// can be seen to have produced. It has happened twice, months apart, and both
/// reports could say what CoreText was doing and nothing about what this app
/// was drawing — a release build symbolicates by nearest exported symbol, so
/// the two frames that mattered named the wrong functions entirely.
///
/// So the hand-drawn rows leave a note before they draw, and the uncaught
/// exception handler reads it. Two stores of an existing string per row: it is
/// not on the terminal's path, where a per-cell cost would matter, and a redraw
/// of a pane is tens of rows rather than thousands.
///
/// Nothing else may read this. It is not state — it is a note for a process
/// that is about to end.
enum LastDrawn {
	/// What it was: a row kind and something identifying, no formatting.
	static var what: String?
	/// The font it was about to be measured with, which is the value under
	/// suspicion.
	static var font: NSFont?

	static func note(_ what: String, font: NSFont) {
		Self.what = what
		Self.font = font
	}

	/// One line for the crash log, saying everything known about the moment.
	///
	/// Everything read here is read while the process is dying, so it is read
	/// defensively and says so where it cannot: a diagnostic that raises a
	/// second exception explains nothing.
	static var description: String {
		var parts: [String] = []
		parts.append("drawing: \(what ?? "nothing recorded")")
		if let font {
			parts.append("font: \(font.fontName) at \(font.pointSize)")
			// Whether the font can still be measured at all. A `copy` that comes
			// back nil is exactly the shape of the failure — CoreText copies the
			// attributes before it typesets — and it is the one thing that
			// cannot be read off a crash report afterwards.
			parts.append("font copies: \((font.copy() as? NSFont) != nil)")
		}
		parts.append("theme: \(Theme.current.name)")
		parts.append("scale: \(Settings.shared.activeScale)")
		parts.append("presenting: \(Settings.shared.presenting)")
		return parts.joined(separator: ", ")
	}
}
