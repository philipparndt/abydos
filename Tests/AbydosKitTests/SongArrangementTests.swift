import Foundation
import Testing
@testable import AbydosKit

/// What the pane draws as *Notes*, read from `mat export` — against the real
/// output of `mat` c036a81 for a small song, cut to the fields the pane reads.
struct SongArrangementTests {
	/// `chords` plays `stab` four times from bar 3, `pad` plays it once an
	/// octave up into the same layer, and `drums` plays `beat` twice. At 120
	/// a bar is two seconds.
	static let small = """
		tempo 120
		meter 4/4
		instrument keys synth
		instrument kit drums
		pattern stab
		  [C4 Eb4 G4]:q r:q r:h |
		pattern beat grid=1/16
		  kick  X.......X.......
		  snare ....X.......X...
		track chords
		  instrument keys
		  at 3
		  play stab x4
		track pad
		  instrument keys
		  layer chords
		  play stab transpose=12
		track drums
		  instrument kit
		  play beat x2
		"""

	static let exported = """
		{"tempo":120.0,"meter":[4,4],"bar_seconds":2.0,"tracks":[
		{"name":"chords","layer":"chords","regions":[
		{"kind":"pattern","name":"stab","start":4.0,"end":12.0,"pass":2.0,"repeat":4,"transpose":0.0,"file":"small.song","line":13,"pattern_file":"small.song","pattern_line":5}],"notes":[
		{"start":4.0,"duration":0.5,"pitch":{"Note":60.0},"midi":60.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":4.0,"duration":0.5,"pitch":{"Note":63.0},"midi":63.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":4.0,"duration":0.5,"pitch":{"Note":67.0},"midi":67.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":6.0,"duration":0.5,"pitch":{"Note":60.0},"midi":60.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":6.0,"duration":0.5,"pitch":{"Note":63.0},"midi":63.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":6.0,"duration":0.5,"pitch":{"Note":67.0},"midi":67.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":8.0,"duration":0.5,"pitch":{"Note":60.0},"midi":60.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":8.0,"duration":0.5,"pitch":{"Note":63.0},"midi":63.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":8.0,"duration":0.5,"pitch":{"Note":67.0},"midi":67.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":10.0,"duration":0.5,"pitch":{"Note":60.0},"midi":60.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":10.0,"duration":0.5,"pitch":{"Note":63.0},"midi":63.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":10.0,"duration":0.5,"pitch":{"Note":67.0},"midi":67.0,"velocity":0.78740156,"accent":false,"region":0}]},
		{"name":"pad","layer":"chords","regions":[
		{"kind":"pattern","name":"stab","start":0.0,"end":2.0,"pass":2.0,"repeat":1,"transpose":12.0,"file":"small.song","line":17,"pattern_file":"small.song","pattern_line":5}],"notes":[
		{"start":0.0,"duration":0.5,"pitch":{"Note":72.0},"midi":72.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":0.0,"duration":0.5,"pitch":{"Note":75.0},"midi":75.0,"velocity":0.78740156,"accent":false,"region":0},
		{"start":0.0,"duration":0.5,"pitch":{"Note":79.0},"midi":79.0,"velocity":0.78740156,"accent":false,"region":0}]},
		{"name":"drums","layer":"drums","regions":[
		{"kind":"pattern","name":"beat","start":0.0,"end":4.0,"pass":2.0,"repeat":2,"transpose":0.0,"file":"small.song","line":20,"pattern_file":"small.song","pattern_line":7}],"notes":[
		{"start":0.0,"duration":0.125,"pitch":{"Drum":"kick"},"midi":36.0,"velocity":1.0,"accent":true,"region":0},
		{"start":0.5,"duration":0.125,"pitch":{"Drum":"snare"},"midi":38.0,"velocity":1.0,"accent":true,"region":0},
		{"start":1.0,"duration":0.125,"pitch":{"Drum":"kick"},"midi":36.0,"velocity":1.0,"accent":true,"region":0},
		{"start":1.5,"duration":0.125,"pitch":{"Drum":"snare"},"midi":38.0,"velocity":1.0,"accent":true,"region":0},
		{"start":2.0,"duration":0.125,"pitch":{"Drum":"kick"},"midi":36.0,"velocity":1.0,"accent":true,"region":0},
		{"start":2.5,"duration":0.125,"pitch":{"Drum":"snare"},"midi":38.0,"velocity":1.0,"accent":true,"region":0},
		{"start":3.0,"duration":0.125,"pitch":{"Drum":"kick"},"midi":36.0,"velocity":1.0,"accent":true,"region":0},
		{"start":3.5,"duration":0.125,"pitch":{"Drum":"snare"},"midi":38.0,"velocity":1.0,"accent":true,"region":0}]}]}
		"""

	static var arrangement: SongArrangement {
		get throws { try SongArrangement.decode(Data(exported.utf8)) }
	}

	@Test func thePlaysAreRegionsWhereTheSongPutsThem() throws {
		let chords = try #require(try Self.arrangement.tracks.first { $0.name == "chords" })
		let stab = try #require(chords.regions.first)
		#expect(chords.regions.count == 1)
		#expect(stab.name == "stab" && stab.start == 4 && stab.end == 12 && stab.pass == 2 && stab.repeatCount == 4)
		#expect(stab.file == "small.song" && stab.line == 13 && stab.patternLine == 5)
		#expect(chords.notes.count == 12 && chords.notes.allSatisfy { $0.region == 0 })
	}

	/// A layer is its tracks, in the song's order: the chords lane holds both.
	@Test func aLayerHoldsEveryTrackRenderedIntoIt() throws {
		let arrangement = try Self.arrangement
		#expect(arrangement.tracks(inLayer: "chords").map(\.name) == ["chords", "pad"])
		#expect(arrangement.tracks(inLayer: "chords")[1].regions.first?.transpose == 12)
	}

	@Test func drumsAreNamedAndPitchesSpelledWithFlats() throws {
		let arrangement = try Self.arrangement
		let drums = try #require(arrangement.tracks.first { $0.name == "drums" })
		#expect(drums.notes.prefix(2).map(\.name) == ["kick", "snare"])
		#expect(arrangement.tracks[0].notes.prefix(3).map(\.name) == ["C4", "E♭4", "G4"])
		#expect(SongArrangement.name(ofMidi: 70) == "B♭4" && SongArrangement.name(ofMidi: 21) == "A0")
		#expect(SongArrangement.name(ofMidi: 0) == "C-1")
	}

	/// The rows are the lane's range over the whole song, padded, with the
	/// drums under the pitches — so a note keeps its row wherever the window is.
	@Test func aLanesRowsAreItsRangeOverTheWholeSong() throws {
		let arrangement = try Self.arrangement
		let chords = SongNoteRows(tracks: arrangement.tracks(inLayer: "chords"))
		// C4 of chords to G5 of pad, two semitones either side.
		#expect(chords.pitches == 58...81)
		#expect(chords.drums.isEmpty && chords.count == 24)
		let c4 = try #require(arrangement.tracks[0].notes.first)
		#expect(chords.row(of: c4) == 2)

		let drums = SongNoteRows(tracks: arrangement.tracks(inLayer: "drums"))
		#expect(drums.drums == ["kick", "snare"] && drums.pitches == nil && drums.count == 2)
	}

	/// A track whose `at` goes back has its regions written out of order: they
	/// are sorted to be searched, and every note still names its own.
	@Test func aNoteKeepsItsRegionWhenTheRegionsAreSorted() throws {
		let backwards = """
			{"tempo":120.0,"meter":[4,4],"bar_seconds":2.0,"tracks":[{"name":"lead","layer":"lead","regions":[
			{"kind":"pattern","name":"late","start":8.0,"end":10.0,"pass":2.0,"repeat":1,"transpose":0.0,"file":"s.song","line":9},
			{"kind":"pattern","name":"early","start":0.0,"end":2.0,"pass":2.0,"repeat":1,"transpose":0.0,"file":"s.song","line":11}],"notes":[
			{"start":0.0,"duration":0.5,"pitch":{"Note":60.0},"midi":60.0,"velocity":0.8,"accent":false,"region":1},
			{"start":8.0,"duration":0.5,"pitch":{"Note":62.0},"midi":62.0,"velocity":0.8,"accent":false,"region":0}]}]}
			"""
		let track = try SongArrangement.decode(Data(backwards.utf8)).tracks[0]
		#expect(track.regions.map(\.name) == ["early", "late"])
		#expect(track.notes.map { track.regions[$0.region ?? -1].name } == ["early", "late"])
	}

	/// A `mat` from before regions still gives notes, with none around them.
	@Test func anExportWithoutRegionsStillHasItsNotes() throws {
		let old = """
			{"tempo":120.0,"meter":[4,4],"bar_seconds":2.0,"tracks":[{"name":"lead","layer":"lead","notes":[
			{"start":0.5,"duration":0.25,"pitch":{"Note":64.0},"midi":64.0,"velocity":0.8,"accent":false,"slide":false,"seed":1}]}]}
			"""
		let arrangement = try SongArrangement.decode(Data(old.utf8))
		#expect(arrangement.tracks[0].regions.isEmpty)
		#expect(arrangement.tracks[0].notes.map(\.name) == ["E4"] && arrangement.tracks[0].notes[0].region == nil)
	}

	/// The detail from points: the whole of a four-minute song in a pane is
	/// regions, four bars is notes, and a bar in a tall lane is named notes.
	@Test func theDetailFollowsTheZoom() {
		let width = 900.0
		let sixteenth = 15.0 / 128  // seconds, at neon's tempo
		func points(showing seconds: Double) -> Double { sixteenth / seconds * width }
		#expect(SongNotesDetail.chosen(sixteenth: points(showing: 232), row: 3) == .regions)
		#expect(SongNotesDetail.chosen(sixteenth: points(showing: 4 * 1.875), row: 3) == .notes)
		#expect(SongNotesDetail.chosen(sixteenth: points(showing: 1.875), row: 3) == .notes)
		#expect(SongNotesDetail.chosen(sixteenth: points(showing: 1.875), row: 12) == .named)
	}

	@Test func theCommandIsAnExportOfTheSong() {
		let arguments = SongArrangement.arguments(
			song: URL(fileURLWithPath: "/songs/my song.song"), output: URL(fileURLWithPath: "/tmp/a.json")
		)
		#expect(arguments == ["export", "/songs/my song.song", "-o", "/tmp/a.json"])
	}
}
