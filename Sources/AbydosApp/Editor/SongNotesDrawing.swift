import AbydosKit
import AppKit

/// A lane of a song drawn as its arrangement: the regions its `play` lines
/// put on the timeline, and the notes in them — the view somebody who reads
/// songs in Logic or GarageBand reads a song in.
///
/// Asked for 2026-09-18: "add another visualization for the users that are
/// used to logic and co: add patterns and notes of cause this requires a
/// appropiate zoom level". So what is drawn is what there is room for, chosen
/// per strip from points (`SongNotesDetail`): regions with a silhouette of
/// their notes when the whole song is on screen, the notes on their rows
/// closer in, and their names and a key strip closer still.
///
/// It draws into a rect it is given and knows nothing of the pane or the
/// canvas: the arrangement, where on screen a second is, and what is lit.
enum SongNotesDrawing {
	/// What one strip of a lane draws: the tracks in it, on shared rows. A
	/// stem's lane is one strip of every track in its layer; the mix's lane
	/// is a strip per track.
	struct Strip {
		var tracks: [SongArrangement.Track]
		/// Each track's colour, in the order of `tracks`.
		var colours: [NSColor]
		var rows: SongNoteRows
	}

	/// What the caret lights: every region of a pattern, or every region of a
	/// track.
	struct Lit: Equatable {
		var pattern: String?
		var track: String?

		static let nothing = Lit()

		func lights(_ region: SongArrangement.Region, of track: SongArrangement.Track) -> Bool {
			(pattern != nil && !region.isAudio && region.name == pattern) || (self.track != nil && track.name == self.track)
		}
	}

	/// How the timeline is on screen.
	struct Window {
		var start: Double
		var span: Double
		var width: CGFloat

		func x(_ seconds: Double) -> CGFloat {
			span > 0 ? CGFloat((seconds - start) / span) * width : 0
		}

		var end: Double { start + span }
	}

	/// A track's colour, by its place in the song: the git graph's, which are
	/// chosen to be told apart at a glance.
	static func colour(ofTrack index: Int) -> NSColor {
		CommitRowView.colour(forBranch: index)
	}

	/// The top of a region, where its name goes, when the strip is tall enough
	/// to spare it; its notes are drawn under it.
	private static func nameBand(in rect: NSRect) -> CGFloat {
		rect.height >= Theme.current.scaled(30) ? Theme.current.scaled(12) : 0
	}

	/// The detail a strip is drawn at, for a report.
	static func detail(of strip: Strip, in rect: NSRect, window: Window, sixteenth: Double) -> SongNotesDetail {
		let body = rect.height - nameBand(in: rect)
		let row = strip.rows.count > 0 ? Double(body) / Double(strip.rows.count) : 0
		let points = window.span > 0 ? sixteenth / window.span * Double(window.width) : 0
		return SongNotesDetail.chosen(sixteenth: points, row: row)
	}

	static func draw(
		_ strip: Strip, in rect: NSRect, window: Window, sixteenth: Double, lit: Lit, enabled: Bool
	) {
		guard let context = NSGraphicsContext.current?.cgContext, rect.height > 2 else { return }
		let detail = detail(of: strip, in: rect, window: window, sixteenth: sixteenth)
		context.saveGState()
		context.clip(to: rect)
		if !enabled { context.setAlpha(0.35) }
		let band = nameBand(in: rect)
		let body = NSRect(x: rect.minX, y: rect.minY + band, width: rect.width, height: rect.height - band)
		let rowHeight = strip.rows.count > 0 ? body.height / CGFloat(strip.rows.count) : 0
		var drewNotes = false

		for (index, track) in strip.tracks.enumerated() {
			let colour = strip.colours[index]
			for region in visible(track.regions, in: window) {
				drawRegion(region, of: track, colour: colour, in: rect, window: window, band: band, lit: lit)
			}
			// Notes clipped to their region: humanize moves a note a few
			// milliseconds, and the region is where the source put it.
			for note in visibleNotes(track.notes, in: window) {
				guard let row = strip.rows.row(of: note) else { continue }
				let left = rect.minX + window.x(note.start)
				var right = rect.minX + window.x(note.end)
				var from = left
				if let index = note.region, track.regions.indices.contains(index) {
					let region = track.regions[index]
					from = max(left, rect.minX + window.x(region.start))
					right = min(right, rect.minX + window.x(region.end))
				}
				let top = body.maxY - rowHeight * CGFloat(row + 1)
				drewNotes = true
				drawNote(
					note, NSRect(x: from, y: top, width: right - from, height: rowHeight),
					colour: colour, detail: detail
				)
			}
		}
		// Keys beside notes, not over a stretch where the strip plays nothing.
		if detail == .named, drewNotes { drawKeys(strip.rows, in: body, rowHeight: rowHeight) }
		context.restoreGState()
	}

	private static func drawRegion(
		_ region: SongArrangement.Region, of track: SongArrangement.Track, colour: NSColor,
		in rect: NSRect, window: Window, band: CGFloat, lit: Lit
	) {
		let theme = Theme.current
		let left = rect.minX + window.x(region.start)
		let right = rect.minX + window.x(region.end)
		guard right - left >= 1 else { return }
		let box = NSRect(x: left, y: rect.minY + 1, width: right - left, height: rect.height - 2)
		let isLit = lit.lights(region, of: track)
		let shape = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
		colour.withAlphaComponent(isLit ? 0.34 : 0.18).setFill()
		shape.fill()
		(isLit ? theme.caret : colour.withAlphaComponent(0.75)).setStroke()
		shape.lineWidth = isLit ? 1.5 : 1
		shape.stroke()

		// Where each pass begins again, as a notch at the top: one `x4` line is
		// one region of four passes, as the source says it.
		let passWidth = region.pass > 0 ? window.x(region.pass) - window.x(0) : 0
		if region.repeatCount > 1, passWidth >= 6 {
			colour.withAlphaComponent(0.75).setFill()
			for pass in 1..<region.repeatCount {
				let x = (left + passWidth * CGFloat(pass)).rounded()
				NSRect(x: x, y: box.minY, width: 1, height: max(4, band)).fill()
			}
		}

		let name = NSAttributedString(string: region.name + transposition(region), attributes: [
			.font: theme.uiFont(9.5, weight: isLit ? .bold : .medium),
			.foregroundColor: isLit ? theme.caret : theme.editorText,
		])
		let size = name.size()
		// On screen even when the region began to the left of it, as a DAW
		// keeps a long region's name in view.
		let at = max(left, rect.minX) + 4
		guard min(right, rect.maxX) - at >= size.width + 2, box.height >= size.height else { return }
		let y = band > 0 ? box.minY + (band - size.height) / 2 + 1 : box.midY - size.height / 2
		name.draw(at: NSPoint(x: at, y: y))
	}

	private static func transposition(_ region: SongArrangement.Region) -> String {
		guard region.transpose != 0 else { return "" }
		let semitones = Int(region.transpose.rounded())
		return semitones > 0 ? " +\(semitones)" : " −\(-semitones)"
	}

	private static func drawNote(
		_ note: SongArrangement.Note, _ cell: NSRect, colour: NSColor, detail: SongNotesDetail
	) {
		// Clipped to its region, a note can be left with nothing.
		guard cell.width >= 0 else { return }
		let height = cell.height >= 3 ? cell.height - 1 : max(1, cell.height)
		let box = NSRect(x: cell.minX, y: cell.minY, width: max(1, cell.width), height: height)
		switch detail {
		case .regions:
			// The silhouette: where the notes are, without being told apart.
			colour.withAlphaComponent(0.7).setFill()
			box.fill()
		case .notes, .named:
			colour.withAlphaComponent(0.35 + 0.65 * CGFloat(min(1, max(0, note.velocity)))).setFill()
			let shape = NSBezierPath(roundedRect: box, xRadius: min(2, height / 3), yRadius: min(2, height / 3))
			shape.fill()
			if note.accent {
				Theme.current.editorText.withAlphaComponent(0.7).setStroke()
				shape.lineWidth = 1
				shape.stroke()
			}
			guard detail == .named else { return }
			let name = NSAttributedString(string: note.name, attributes: [
				.font: Theme.current.uiFont(min(10, max(7, height - 2)), weight: .medium),
				.foregroundColor: Theme.current.editorBackground,
			])
			let size = name.size()
			guard size.width + 4 <= box.width, size.height <= box.height + 3 else { return }
			name.draw(at: NSPoint(x: box.minX + 2, y: box.midY - size.height / 2))
		}
	}

	/// The key strip along the lane's left edge: the black keys shaded, each
	/// C named, and each drum row by its sound.
	private static func drawKeys(_ rows: SongNoteRows, in body: NSRect, rowHeight: CGFloat) {
		let theme = Theme.current
		let width = theme.scaled(30)
		let strip = NSRect(x: body.minX, y: body.minY, width: width, height: body.height)
		theme.editorBackground.withAlphaComponent(0.92).setFill()
		strip.fill()
		for row in 0..<rows.count {
			let top = body.maxY - rowHeight * CGFloat(row + 1)
			let key = NSRect(x: strip.minX, y: top, width: width, height: rowHeight)
			var label: String?
			if row < rows.drums.count {
				label = rows.drums[row]
			} else if let pitches = rows.pitches {
				let midi = pitches.lowerBound + row - rows.drums.count
				if [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12) {
					theme.editorText.withAlphaComponent(0.12).setFill()
					key.fill()
				}
				if midi % 12 == 0 { label = SongArrangement.name(ofMidi: Double(midi)) }
			}
			theme.separator.withAlphaComponent(0.4).setFill()
			NSRect(x: strip.minX, y: top, width: width, height: 1).fill()
			guard let label else { continue }
			let text = NSAttributedString(string: label, attributes: [
				.font: theme.uiFont(min(9, max(7, rowHeight - 2))),
				.foregroundColor: theme.gitIgnored,
			])
			let size = text.size()
			guard size.height <= rowHeight + 3 else { continue }
			text.draw(in: NSRect(x: key.minX + 2, y: key.midY - size.height / 2, width: width - 3, height: size.height))
		}
		theme.separator.setFill()
		NSRect(x: strip.maxX, y: strip.minY, width: 1, height: strip.height).fill()
	}

	// MARK: - Finding things

	/// The regions that reach into the window, by a search over their starts:
	/// a region starting past the window's end is not drawn, and none that
	/// ends before it.
	static func visible(_ regions: [SongArrangement.Region], in window: Window) -> ArraySlice<SongArrangement.Region> {
		let upTo = firstIndex(in: regions, where: { $0.start >= window.end })
		return regions[..<upTo].drop { $0.end <= window.start }
	}

	/// The notes that reach into the window. Notes are found by their start,
	/// and a long one that began before the window still sounds in it, so the
	/// search begins the longest note's length early.
	static func visibleNotes(_ notes: [SongArrangement.Note], in window: Window) -> [SongArrangement.Note] {
		let longest = notes.lazy.map(\.duration).max() ?? 0
		let from = firstIndex(in: notes, where: { $0.start >= window.start - longest })
		let upTo = firstIndex(in: notes, where: { $0.start >= window.end })
		guard from < upTo else { return [] }
		return notes[from..<upTo].filter { $0.end > window.start }
	}

	private static func firstIndex<T>(in items: [T], where isPast: (T) -> Bool) -> Int {
		var low = 0
		var high = items.count
		while low < high {
			let middle = (low + high) / 2
			if isPast(items[middle]) { high = middle } else { low = middle + 1 }
		}
		return low
	}

	/// The region under a point of a strip, and the track it is in: the last
	/// drawn wins, as it is the one on top.
	static func region(
		at point: NSPoint, in strip: Strip, rect: NSRect, window: Window
	) -> (track: SongArrangement.Track, region: SongArrangement.Region)? {
		guard rect.contains(point) else { return nil }
		let seconds = window.start + Double((point.x - rect.minX) / max(1, window.width)) * window.span
		for track in strip.tracks.reversed() {
			if let region = track.regions.last(where: { $0.start <= seconds && seconds < max($0.end, $0.start + 1e-6) }) {
				return (track, region)
			}
		}
		return nil
	}
}
