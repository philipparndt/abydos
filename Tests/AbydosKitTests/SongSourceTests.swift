import Foundation
import Testing
@testable import AbydosKit

/// What the song pane reads out of a `.song` file's text: where the tracks
/// and patterns are, which layer each track renders into, and which stems a
/// caret should light.
struct SongSourceTests {
	/// The shape of `examples/drunken-sailor.song`, shortened.
	private let song = """
	title "Drunken Sailor"
	tempo 132          # quarter notes per minute
	meter 4/4

	instrument strings synth
	  osc saw voices=3

	pattern beat grid=1/16
	  kick  X.....x.X.....x.
	  snare ....X.......X...

	pattern verse
	  A4:q A4:e A4 A4:q A4:e A4 | A4:q D4 F4 A4 |

	track low_strings
	  instrument strings
	  play verse x2
	  play verse transpose=2

	track pad
	  instrument strings
	  layer chords
	  mute
	  play verse

	track drums
	  instrument kit
	  play beat x4

	master
	  gain 3
	"""

	@Test func theTracksAndPatternsAreFoundWithTheirLines() {
		let source = SongSource.parse(song)
		#expect(source.title == "Drunken Sailor")
		#expect(source.patterns.map(\.name) == ["beat", "verse"])
		#expect(source.tracks.map(\.name) == ["low_strings", "pad", "drums"])
		#expect(source.pattern(atLine: 8)?.name == "beat")
		#expect(source.pattern(atLine: 10)?.name == "beat")
		#expect(source.track(atLine: 15)?.name == "low_strings")
		// The blank line after a block belongs to it: the caret on it is
		// still nearer that block than the next.
		#expect(source.track(atLine: 19)?.name == "low_strings")
		#expect(source.track(atLine: 20)?.name == "pad")
		#expect(source.track(atLine: 30) == nil)
	}

	/// A track's layer is its own name unless it says `layer`; `mute` is read
	/// so a silent stem can be said to be silent on purpose.
	@Test func aLayerIsTheTracksNameUnlessItSaysOtherwise() {
		let source = SongSource.parse(song)
		#expect(source.tracks[0].layer == "low_strings")
		#expect(source.tracks[1].layer == "chords")
		#expect(source.tracks[1].isMuted)
		#expect(!source.tracks[0].isMuted)
		#expect(source.tracks(inLayer: "chords").map(\.name) == ["pad"])
	}

	/// `play verse x2 transpose=2` names `verse`; `play all` and `play bars=…`
	/// are an audio track's and name nothing.
	@Test func thePatternsATrackPlaysAreRead() {
		let source = SongSource.parse(song)
		#expect(source.tracks[0].patterns == ["verse", "verse"])
		#expect(source.tracks[2].patterns == ["beat"])
		let audio = SongSource.parse("track vocals\n  audio \"v.wav\"\n  play all\n  play bars=1-8\n")
		#expect(audio.tracks[0].patterns == [])
	}

	/// The caret in a track lights that track's layer; in a pattern, every
	/// layer whose tracks play it; anywhere else, nothing.
	@Test func whatTheCaretLights() {
		let source = SongSource.parse(song)
		#expect(source.layers(litByCaretAt: 16) == ["low_strings"])
		#expect(source.layers(litByCaretAt: 22) == ["chords"])
		#expect(source.layers(litByCaretAt: 12) == ["low_strings", "chords"])
		#expect(source.layers(litByCaretAt: 9) == ["drums"])
		#expect(source.layers(litByCaretAt: 2) == [])
		#expect(source.layers(litByCaretAt: 30) == [])
	}

	/// `#` starts a comment, except inside a note name like `C#4`.
	@Test func aCommentIsNotASetting() {
		#expect(SongSource.stripped("  layer x # layer y") == "  layer x ")
		#expect(SongSource.stripped("  C#4:q D#4 # the hook") == "  C#4:q D#4 ")
		let source = SongSource.parse("track a\n  # layer b\n  play x\n")
		#expect(source.tracks[0].layer == "a")
	}

	/// Half-typed: a `track` with no name yet, and a file that ends inside a
	/// block, still parse.
	@Test func aFileBeingTypedStillParses() {
		let source = SongSource.parse("track\n  instrument x\ntrack b")
		#expect(source.tracks.count == 2)
		#expect(source.tracks[0].name == "")
		#expect(source.tracks[1].lines == 3...3)
		#expect(SongSource.parse("").tracks.isEmpty)
	}
}
