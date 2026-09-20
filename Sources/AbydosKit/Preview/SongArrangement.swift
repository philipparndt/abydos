import Foundation

/// A song as `mat` arranged it: its tracks, the regions each `play` line put
/// on the timeline, and the notes in them — what the pane draws as *Notes*.
///
/// Read from `mat export`, which is the arrangement without the audio: 14 ms
/// for `neon.song`, against some 23 s for its render with stems, so the notes
/// are there long before the sound is. Worked out by `mat` rather than again
/// here from the text, since where a `play` lands is `at`, `rest`, `repeat`
/// and `include` together, and a second reading of those would drift from the
/// one the song is rendered by.
///
/// Only what is drawn is decoded. Most of the export's bytes — 1.5 MB for
/// neon — are instruments' zones and settings, which are not declared here and
/// so are skipped.
public struct SongArrangement: Equatable, Sendable {
	public struct Note: Equatable, Sendable {
		/// Seconds.
		public var start: Double
		public var duration: Double
		/// The MIDI note, also for a drum (its General MIDI mapping).
		public var midi: Double
		/// The drum's name, `kick`; nil for a pitched note.
		public var drum: String?
		public var velocity: Double
		public var accent: Bool
		/// Which of its track's regions placed it; nil from a `mat` whose
		/// export has no regions.
		public var region: Int?

		public var end: Double { start + duration }

		/// What the note is called: `E♭4`, or the drum's name.
		public var name: String { drum ?? SongArrangement.name(ofMidi: midi) }
	}

	/// One `play` line: a pattern, or a stretch of the track's audio.
	public struct Region: Equatable, Sendable {
		public var isAudio: Bool
		/// The pattern's name.
		public var name: String
		/// Seconds.
		public var start: Double
		public var end: Double
		/// One pass, in seconds; `repeat` of them make the region.
		public var pass: Double
		public var repeatCount: Int
		public var transpose: Double
		/// The file the `play` line is in, as the song names it — relative to
		/// the song's directory — and its line, 1-based.
		public var file: String
		public var line: Int
		/// Where the pattern is defined.
		public var patternFile: String?
		public var patternLine: Int?
		/// The `play` line says `mute`: the block is where it would be and
		/// nothing in it sounds. See `SongBlockMute`.
		public var isMuted = false
	}

	public struct Track: Equatable, Sendable {
		public var name: String
		public var layer: String
		/// By start.
		public var regions: [Region]
		/// By start.
		public var notes: [Note]
	}

	public var tempo: Double
	public var barSeconds: Double
	public var beatsPerBar: Int
	public var tracks: [Track]

	/// A sixteenth note, in seconds: the unit the detail is chosen by.
	public var sixteenthSeconds: Double { tempo > 0 ? 15 / tempo : 0 }

	public func tracks(inLayer layer: String) -> [Track] {
		tracks.filter { $0.layer == layer }
	}

	// MARK: - Running it

	/// The arguments that write a song's arrangement: `mat export <song> -o <file>`.
	public static func arguments(song: URL, output: URL) -> [String] {
		["export", song.path, "-o", output.path]
	}

	// MARK: - Reading it

	public static func decode(_ data: Data) throws -> SongArrangement {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		let raw = try decoder.decode(Raw.self, from: data)
		let beats = raw.meter.first ?? 4
		let tracks = raw.tracks.map { track in
			// Regions come in the order their `play` lines are written, which is
			// not always the order they sound in — an `at` can go back — and they
			// are searched by start. So they are sorted, and each note's index
			// follows its region to its new place.
			let written = track.regions ?? []
			let order = written.indices.sorted { written[$0].start < written[$1].start }
			var moved = [Int](repeating: 0, count: written.count)
			for (place, index) in order.enumerated() { moved[index] = place }
			return Track(
				name: track.name, layer: track.layer,
				regions: order.map { written[$0] }.map {
					Region(
						isAudio: $0.kind == "audio", name: $0.name, start: $0.start, end: $0.end, pass: $0.pass,
						repeatCount: $0.repeat, transpose: $0.transpose, file: $0.file, line: $0.line,
						patternFile: $0.patternFile, patternLine: $0.patternLine,
						isMuted: $0.muted ?? false
					)
				},
				notes: track.notes.map {
					Note(
						start: $0.start, duration: $0.duration, midi: $0.midi, drum: $0.pitch.drum,
						velocity: $0.velocity, accent: $0.accent,
						region: $0.region.flatMap { moved.indices.contains($0) ? moved[$0] : nil }
					)
				}.sorted { $0.start < $1.start }
			)
		}
		return SongArrangement(
			tempo: raw.tempo, barSeconds: raw.barSeconds, beatsPerBar: beats, tracks: tracks
		)
	}

	/// The export as `mat` writes it, as far as it is read.
	private struct Raw: Decodable {
		/// `{"Note": 60.0}` or `{"Drum": "kick"}`.
		struct Pitch: Decodable {
			var drum: String?
			enum CodingKeys: String, CodingKey { case drum = "Drum" }
		}
		struct Note: Decodable {
			var start: Double
			var duration: Double
			var pitch: Pitch
			var midi: Double
			var velocity: Double
			var accent: Bool
			var region: Int?
		}
		struct Region: Decodable {
			var kind: String
			var name: String
			var start: Double
			var end: Double
			var pass: Double
			var `repeat`: Int
			var transpose: Double
			var file: String
			var line: Int
			var patternFile: String?
			var patternLine: Int?
			/// Only on a muted region, and absent from a `mat` before 4c678d7.
			var muted: Bool?
		}
		struct Track: Decodable {
			var name: String
			var layer: String
			var notes: [Note]
			/// Absent from a `mat` from before c036a81.
			var regions: [Region]?
		}
		var tempo: Double
		var meter: [Int]
		var barSeconds: Double
		var tracks: [Track]
	}

	// MARK: - Names

	private static let pitchClasses = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

	/// A MIDI note's name, `C4` for 60 and flats for the black keys, as the
	/// songs write them: `mat`'s export carries the number, not the spelling.
	public static func name(ofMidi midi: Double) -> String {
		let note = Int(midi.rounded())
		let octave = Int((Double(note) / 12).rounded(.down)) - 1
		return pitchClasses[((note % 12) + 12) % 12] + "\(octave)"
	}
}

/// How much of an arrangement there is room to draw.
public enum SongNotesDetail: String, Sendable {
	/// Regions, named, with a silhouette of their notes.
	case regions
	/// Notes as bars on the lane's rows.
	case notes
	/// Notes with their names, and a key strip.
	case named

	/// Narrower than this a sixteenth is not worth drawing as a note: a bar's
	/// notes would run together, and the region is what can be read.
	public static let sixteenthPoints: Double = 2
	/// A row shorter than this has no room for a name in it.
	public static let namedRowPoints: Double = 9
	/// Nor has a sixteenth narrower than this, at the size names are drawn.
	public static let namedSixteenthPoints: Double = 14

	/// - Parameter sixteenth: how wide a sixteenth note is, in points.
	/// - Parameter row: how tall a row of the lane is, in points.
	public static func chosen(sixteenth: Double, row: Double) -> SongNotesDetail {
		guard sixteenth >= sixteenthPoints else { return .regions }
		guard row >= namedRowPoints, sixteenth >= namedSixteenthPoints else { return .notes }
		return .named
	}
}

/// The rows a lane's notes are drawn on: one per pitch over the lane's range,
/// and one per drum sound.
///
/// Worked out over the whole song, not the window, so panning does not move a
/// pitch to another row under the reader's eyes.
public struct SongNoteRows: Equatable, Sendable {
	/// Drum sounds by their MIDI note, lowest first: the bottom rows.
	public var drums: [String]
	/// The pitched rows, lowest to highest; empty when the lane is all drums.
	public var pitches: ClosedRange<Int>?

	/// How far the range reaches past the lane's lowest and highest note.
	public static let padding = 2

	public init(tracks: [SongArrangement.Track]) {
		var drumNotes: [String: Double] = [:]
		var low = Int.max
		var high = Int.min
		for track in tracks {
			for note in track.notes {
				if let drum = note.drum {
					drumNotes[drum] = min(drumNotes[drum] ?? .infinity, note.midi)
				} else {
					low = min(low, Int(note.midi.rounded()))
					high = max(high, Int(note.midi.rounded()))
				}
			}
		}
		drums = drumNotes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }.map(\.key)
		pitches = low <= high ? (low - Self.padding)...(high + Self.padding) : nil
	}

	public var count: Int { drums.count + (pitches?.count ?? 0) }

	/// A note's row, counted from the bottom.
	public func row(of note: SongArrangement.Note) -> Int? {
		if let drum = note.drum { return drums.firstIndex(of: drum) }
		guard let pitches else { return nil }
		let midi = Int(note.midi.rounded())
		guard pitches.contains(midi) else { return nil }
		return drums.count + midi - pitches.lowerBound
	}
}

/// How tall each lane of a song is: a header each, and what is left shared out
/// by how many strips a lane draws — so a lane opened into its tracks gives
/// each of them the room a closed lane has, and the closed ones give way.
public enum SongLaneHeights {
	/// - Parameter strips: how many strips each lane draws; a lane with none
	///   still counts as one.
	public static func shared(strips: [Int], header: Double, in height: Double) -> [Double] {
		let weights = strips.map { Double(max(1, $0)) }
		let total = weights.reduce(0, +)
		guard total > 0 else { return [] }
		let unit = max(0, height - header * Double(strips.count)) / total
		return weights.map { header + unit * $0 }
	}
}
