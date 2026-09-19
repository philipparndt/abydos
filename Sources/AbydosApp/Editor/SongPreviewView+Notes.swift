import AbydosKit
import AppKit

/// The song's arrangement, for the pane's *Notes*: running `mat export`, and
/// keeping what it last said.
///
/// Run beside every render, from the file on disk as the render reads it, and
/// on its own the first time a pane shows a song whose render came from the
/// cache. It is the arrangement without the audio — 14 ms for `neon.song` — so
/// the notes are there before the first stretch of sound.
///
/// An export that fails keeps the last one: the same save mid-line that fails
/// a render, whose error strip already says what is wrong with the file.
@MainActor
final class SongNotes {
	private(set) var arrangement: SongArrangement?
	/// Why there is nothing to draw, when `mat` cannot say.
	private(set) var unavailable: String?
	/// The song the arrangement is of.
	private var song: URL?
	/// Bumped by every export, so one that lands after a newer began is dropped.
	private var generation = 0
	private(set) var exports = 0
	/// An export landed with something new to draw.
	var onLanded: (() -> Void)?

	/// Exports `song` unless its arrangement has been asked for already.
	func need(song: URL, executable: String?) {
		guard self.song.map(FilePath.canonical) != FilePath.canonical(song) else { return }
		export(song: song, executable: executable)
	}

	func export(song: URL, executable: String?) {
		if self.song.map(FilePath.canonical) != FilePath.canonical(song) {
			arrangement = nil
			unavailable = nil
		}
		self.song = song
		guard let executable else { return }
		generation += 1
		exports += 1
		let asked = generation
		// Into a file rather than a pipe: what `mat` says about a broken song
		// comes on the other stream, and one pipe read to its end while the
		// other fills is a process that never ends.
		let written = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-arrangement-\(UUID().uuidString.prefix(8)).json")
		let arguments = SongArrangement.arguments(song: song, output: written)
		let directory = song.deletingLastPathComponent()
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let process = Process()
			process.executableURL = URL(fileURLWithPath: executable)
			process.arguments = arguments
			process.currentDirectoryURL = directory
			let errors = Pipe()
			process.standardOutput = FileHandle.nullDevice
			process.standardError = errors
			process.standardInput = FileHandle.nullDevice
			var said = Data()
			var status: Int32 = -1
			if (try? process.run()) != nil {
				said = errors.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				status = process.terminationStatus
			}
			let data = status == 0 ? try? Data(contentsOf: written) : nil
			try? FileManager.default.removeItem(at: written)
			let arranged = data.flatMap { try? SongArrangement.decode($0) }
			let complaint = String(decoding: said, as: UTF8.self)
			DispatchQueue.main.async {
				guard let self, self.generation == asked else { return }
				if let arranged {
					self.arrangement = arranged
					self.unavailable = nil
				} else if complaint.contains("unrecognized subcommand") {
					self.unavailable = "This mat cannot say how the song is arranged: update it to see its notes."
				}
				// A song that does not arrange keeps the last arrangement.
				self.onLanded?()
			}
		}
	}

	/// What each lane draws: a stem's lane every track in its layer on shared
	/// rows, and the mix's lane each track on rows of its own.
	func strips(for lanes: [SongCanvas.Lane], mix: Bool) -> [[SongNotesDrawing.Strip]] {
		guard let arrangement else { return [] }
		let tracks = arrangement.tracks
		func strip(_ chosen: [SongArrangement.Track]) -> SongNotesDrawing.Strip {
			SongNotesDrawing.Strip(
				tracks: chosen,
				colours: chosen.map { track in
					SongNotesDrawing.colour(ofTrack: tracks.firstIndex { $0.name == track.name } ?? 0)
				},
				rows: SongNoteRows(tracks: chosen)
			)
		}
		if mix {
			let heard = tracks.filter { !$0.notes.isEmpty || !$0.regions.isEmpty }
			return lanes.map { _ in heard.map { strip([$0]) } }
		}
		return lanes.map { lane in
			let inLayer = arrangement.tracks(inLayer: lane.name)
			let chosen = inLayer.isEmpty ? tracks.filter { lane.tracks.contains($0.name) } : inLayer
			return chosen.isEmpty ? [] : [strip(chosen)]
		}
	}

	/// The line the caret was last on, for a report.
	private(set) var caretLine: Int?

	/// What the caret on `line` lights: a pattern's regions, or a track's.
	func lit(atLine line: Int, in text: String) -> SongNotesDrawing.Lit {
		caretLine = line
		let source = SongSource.parse(text)
		if let track = source.track(atLine: line) { return SongNotesDrawing.Lit(track: track.name) }
		if let pattern = source.pattern(atLine: line) { return SongNotesDrawing.Lit(pattern: pattern.name) }
		return .nothing
	}

	/// Where a region was written: its `play` line, or with `pattern` the
	/// pattern's definition, in the file the song names — relative to the
	/// song's own directory.
	static func place(
		of region: SongArrangement.Region, pattern: Bool, song: URL
	) -> (file: URL, line: Int)? {
		let file = pattern ? region.patternFile : region.file
		guard let line = pattern ? region.patternLine : region.line, line > 0 else { return nil }
		guard let file, !file.isEmpty else { return (song, line) }
		let url = file.hasPrefix("/")
			? URL(fileURLWithPath: file)
			: song.deletingLastPathComponent().appendingPathComponent(file)
		return (url.standardizedFileURL, line)
	}
}

extension SongPreviewView {
	/// The lanes the canvas has, drawn as notes: called whenever the lanes or
	/// the arrangement change.
	func applyNotes() {
		notes.need(song: url, executable: executable)
		canvas.setNotes(
			notes.strips(for: canvas.lanes, mix: view == .mix),
			sixteenth: notes.arrangement?.sixteenthSeconds ?? 0
		)
		canvas.notesMessage = notes.unavailable
	}

	/// A region was clicked: its `play` line, or ⌥ its pattern, in its file.
	func reveal(region: SongArrangement.Region, pattern: Bool) {
		guard let place = SongNotes.place(of: region, pattern: pattern, song: url) else { return }
		onRevealPlace?(place.file, place.line)
	}

	/// How the notes are drawn now, for a driven run's report.
	var notesReport: String {
		let screen = canvas.notesOnScreen
		return " notes=\(canvas.showsNotes ? "shown" : "hidden") detail=[\(canvas.notesDetails.joined(separator: " "))]"
			+ " regions=\(screen.regions) regionsLit=\(screen.lit) exports=\(notes.exports)"
			+ " caret=\(notes.caretLine.map(String.init) ?? "-")"
			+ " lighting=\(canvas.notesLit.pattern.map { "pattern:" + $0 } ?? canvas.notesLit.track.map { "track:" + $0 } ?? "-")"
	}
}
