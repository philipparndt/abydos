import Foundation
import Testing
@testable import AbydosKit

/// What a `mat render` run is asked and what is read back from it, against
/// output measured from the real tool on 2026-09-13.
struct SongRenderTests {
	@Test func theCommandRendersTheMixAndTheStemsIntoTheOutputDirectory() {
		let command = SongRender.command(
			executable: "/Users/me/.cargo/bin/mat",
			song: URL(fileURLWithPath: "/Users/me/my songs/neon.song"),
			output: URL(fileURLWithPath: "/tmp/abydos-song/1234/run-3")
		)
		#expect(command == "/Users/me/.cargo/bin/mat render '/Users/me/my songs/neon.song' "
			+ "-o /tmp/abydos-song/1234/run-3/mix.wav --stems /tmp/abydos-song/1234/run-3/stems")
	}

	/// The render is streamed, so the song can be played while the rest of it
	/// renders: one render, not a preview and then the whole of it.
	@Test func theCommandStreamsTheMixAsItIsWritten() {
		let command = SongRender.command(
			executable: "mat", song: URL(fileURLWithPath: "/songs/drive.song"),
			output: URL(fileURLWithPath: "/tmp/run-3"), cache: URL(fileURLWithPath: "/tmp/c"),
			streaming: true
		)
		#expect(command == "mat render /songs/drive.song -o /tmp/run-3/mix.wav "
			+ "--stems /tmp/run-3/stems --stream --cache /tmp/c")
		#expect(SongRender.streamStatus(beside: URL(fileURLWithPath: "/tmp/run-3/mix.wav")).path
			== "/tmp/run-3/mix.stream.json")
	}

	/// What an installed `mat` said on 2026-09-16 when it could not find its
	/// sample library: warnings, and a render that went on and succeeded with
	/// the kit missing. The pane has to be able to say so.
	@Test func whatMatWarnedAboutIsReadOutOfARenderThatWorked() {
		let said = """
		warning: track 'drums': cannot open assets/samples/sonic-pi/bd_tek.wav: No such file or directory (os error 2)
		warning: track 'perc': cannot open assets/samples/sonic-pi/elec_wood.wav: No such file or directory (os error 2)
		  drums.wav: peak -23.3 dBFS
		rendered 4:37.9 in 6.20s (44x realtime), peak -1.0 dBFS, rms -15.9 dBFS
		"""
		let warnings = SongRender.warnings(in: said)
		#expect(warnings.count == 2)
		#expect(warnings.first == "track 'drums': cannot open assets/samples/sonic-pi/bd_tek.wav: No such file or directory (os error 2)")
		// Nothing in it is an error: the render worked, as far as mat is concerned.
		#expect(SongRender.diagnostics(in: said).isEmpty)
		#expect(SongRender.warnings(in: "rendered 0:08.0 in 0.4s\n").isEmpty)
	}

	/// A `mat` from before a5f7d05 refuses `--stream` and the render with it, so
	/// the help is read before the flag is passed. Both texts are `mat render
	/// --help` as it stands, with and without the option.
	@Test func aMatThatDoesNotStreamIsToldApartByItsHelp() {
		let streams = """
		      --stems <STEMS>
		          Also write one file per layer
		      --stream
		          Render the song in order of time and write it as it goes
		"""
		#expect(SongRender.supportsStreaming(help: streams))
		let older = """
		      --stems <STEMS>
		          Also write one file per layer
		      --cache <CACHE>
		          Keep each layer here between renders
		"""
		#expect(!SongRender.supportsStreaming(help: older))
	}

	/// `mat render --stream` beside the mix, caught while the drive example was
	/// rendering on 2026-09-16 and again when it was done.
	@Test func theStreamSaysHowMuchOfTheMixCanBePlayed() throws {
		let going = Data("""
		{
		  "bar_seconds": 1.8045112781954886,
		  "bars_total": 120,
		  "bars_written": 0,
		  "bits": 24,
		  "bytes_per_frame": 6,
		  "channels": 2,
		  "data_offset": 68,
		  "file": "mix.wav",
		  "finished": false,
		  "frames_written": 48913,
		  "sample_rate": 48000,
		  "seconds_total": 216.54135338345864,
		  "seconds_written": 1.0190208333333333,
		  "tempo": 133.0
		}
		""".utf8)
		let first = try #require(SongRender.stream(from: going))
		#expect(first.frames == 48913)
		#expect(first.sampleRate == 48000)
		#expect(abs(first.seconds - 1.019) < 0.001)
		#expect(!first.finished)
		// Enough of the song to open a pane on: its tempo, its bars, and how
		// long the whole of it is — so the timeline is laid out once rather
		// than growing under the playhead.
		#expect(first.totalBars == 120)
		let manifest = SongRender.manifest(ofStream: first)
		#expect(manifest.tempo == 133)
		#expect(abs(manifest.barSeconds - 1.8045) < 0.001)
		#expect(abs(manifest.seconds - 216.541) < 0.001)
		#expect(manifest.layers.isEmpty)

		let done = Data(String(data: going, encoding: .utf8)!
			.replacingOccurrences(of: "\"seconds_written\": 1.0190208333333333", with: "\"seconds_written\": 221.55720833333334")
			.replacingOccurrences(of: "\"finished\": false", with: "\"finished\": true")
			.replacingOccurrences(of: "\"frames_written\": 48913", with: "\"frames_written\": 10634746").utf8)
		let whole = try #require(SongRender.stream(from: done))
		#expect(whole.finished)
		#expect(whole.frames == 10634746)
		#expect(whole != first)
		// A reverb rings past the last bar, so the file outlives the song: the
		// pane shows what is there, not what the tempo says.
		#expect(whole.seconds > whole.totalSeconds ?? 0)
		#expect(abs(SongRender.manifest(ofStream: whole).seconds - 221.557) < 0.001)

		// A mat that says neither leaves the length to what has been written.
		let older = Data(String(data: going, encoding: .utf8)!
			.replacingOccurrences(of: "\"bars_total\": 120,", with: "")
			.replacingOccurrences(of: "\"seconds_total\": 216.54135338345864,", with: "").utf8)
		let quiet = try #require(SongRender.stream(from: older))
		#expect(quiet.totalSeconds == nil)
		#expect(abs(SongRender.manifest(ofStream: quiet).seconds - 1.019) < 0.001)
	}

	/// Half a file, or none: the reader says nothing rather than a length.
	@Test func anUnreadableStreamIsNoStream() {
		#expect(SongRender.stream(from: Data("{ \"frames_wri".utf8)) == nil)
		#expect(SongRender.stream(from: Data("{}".utf8)) == nil)
	}

	/// The pane keeps the layers in a directory named for the song and not
	/// for the process, so a relaunch finds them — and the sweep of what dead
	/// processes left does not take it.
	@Test func theCacheOutlivesTheProcessAndIsNotSwept() throws {
		let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("song-cache-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: temporary) }
		let song = URL(fileURLWithPath: "/songs/neon.song")
		let cache = SongRender.cacheDirectory(for: song, under: temporary)
		#expect(cache.lastPathComponent.hasSuffix("-cache"))
		#expect(cache.deletingLastPathComponent() == SongRender.outputRoot(for: song, under: temporary, pid: 1).deletingLastPathComponent())
		try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
		#expect(SongRender.staleRenderDirectories(under: temporary) { _ in false }.isEmpty)

		let command = SongRender.command(
			executable: "mat", song: song, output: URL(fileURLWithPath: "/tmp/out"), cache: URL(fileURLWithPath: "/tmp/c")
		)
		#expect(command.hasSuffix("--stems /tmp/out/stems --cache /tmp/c"))
	}

	/// An export writes beside the song, the stems in a folder of its name, in
	/// the format the extension names.
	@Test func anExportWritesBesideTheSongInTheChosenFormat() {
		let song = URL(fileURLWithPath: "/Users/me/songs/neon.song")
		let mix = SongRender.export(of: song, as: .flac, withStems: false)
		#expect(mix.mix.path == "/Users/me/songs/neon.flac")
		#expect(mix.stems == nil)
		let both = SongRender.export(of: song, as: .m4a, withStems: true)
		#expect(both.stems?.path == "/Users/me/songs/neon stems")
		let command = SongRender.exportCommand(
			executable: "mat", song: song, export: both, cache: URL(fileURLWithPath: "/tmp/c")
		)
		#expect(command == "mat render /Users/me/songs/neon.song -o /Users/me/songs/neon.m4a "
			+ "--stems '/Users/me/songs/neon stems' --cache /tmp/c")
	}

	/// What would be replaced is found before anything runs.
	@Test func anExportSaysWhatItWouldReplace() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("export-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let song = directory.appendingPathComponent("neon.song")
		let export = SongRender.export(of: song, as: .wav, withStems: true)
		#expect(export.replaces.isEmpty)
		try Data().write(to: export.mix)
		#expect(export.replaces == [export.mix])
	}

	/// A `mat` from before formats writes WAV under any name; its help has no
	/// `--bitrate`, which is how it is told apart.
	@Test func aMatWithoutFormatsIsToldApartByItsHelp() {
		#expect(SongRender.supportsFormats(help: "      --bitrate <BITRATE>  Bit rate of .m4a files in kbit/s"))
		#expect(!SongRender.supportsFormats(help: "      --bits <BITS>  [default: 24] [possible values: 16, 24, 32f]"))
	}

	/// What `mat` 23c5b97 writes for a layer with a cache.
	@Test func aLayerSaysWhatItWasKeyedByAndWhetherItWasCached() throws {
		let json = """
		{ "tempo": 128, "meter": [4, 4], "bar_seconds": 1.875, "seconds": 228.4,
		  "layers": [
		    { "layer": "drums", "file": "drums.wav", "tracks": ["drums"], "key": "8a0c5e1f3b2d4c6e", "cached": true },
		    { "layer": "hook", "file": "hook.wav", "tracks": ["hook"], "key": "0123456789abcdef", "cached": false }
		  ] }
		"""
		let read = try SongRender.manifest(from: Data(json.utf8))
		#expect(read.layers.map(\.key) == ["8a0c5e1f3b2d4c6e", "0123456789abcdef"])
		#expect(read.layers.map(\.cached) == [true, false])
		// An older manifest has neither.
		let older = try SongRender.manifest(from: Data(manifest.utf8))
		#expect(older.layers.allSatisfy { $0.key == nil && !$0.cached })
	}

	/// `mat`'s own manifest, as written for `examples/drunken-sailor.song`.
	private let manifest = """
	{
	  "bar_seconds": 1.8181818181818181,
	  "bars": 37.0,
	  "layers": [
	    { "file": "low_strings.wav", "layer": "low_strings", "tracks": ["low_strings"] },
	    { "file": "chords.wav", "layer": "chords", "tracks": ["pad", "keys"] }
	  ],
	  "loop": false,
	  "meter": [4, 4],
	  "sample_rate": 48000,
	  "seconds": 67.27272727272727,
	  "sections": [{ "name": "chorus", "start": 29.09, "end": 58.18 }],
	  "tempo": 132.0,
	  "title": "Drunken Sailor (epic synth arrangement)"
	}
	"""

	@Test func theManifestSaysWhichFileIsWhichLayer() throws {
		let read = try SongRender.manifest(from: Data(manifest.utf8))
		#expect(read.title == "Drunken Sailor (epic synth arrangement)")
		#expect(read.tempo == 132)
		#expect(read.meter == [4, 4])
		#expect(read.layers.map(\.name) == ["low_strings", "chords"])
		#expect(read.layers[1].file == "chords.wav")
		#expect(read.layers[1].tracks == ["pad", "keys"])
		#expect(read.sections == [.init(name: "chorus", start: 29.09, end: 58.18)])
		#expect(abs(read.seconds - 67.2727) < 0.001)
	}

	/// Bar 1 starts at 0; at 132 bpm in 4/4 a bar is 1.818 s, so 2 s is in
	/// bar 2, a tenth of the way in.
	@Test func aMomentHasABarAndABeat() throws {
		let read = try SongRender.manifest(from: Data(manifest.utf8))
		#expect(read.bar(at: 0).bar == 1)
		let (bar, beat) = read.bar(at: 2.0)
		#expect(bar == 2)
		#expect(abs(beat - 0.4) < 0.001)
	}

	/// The stems sum to the mix before its limiter, and the manifest says how
	/// loud that sum peaks; a player turns them down to the ceiling.
	@Test func theStemsAreTurnedDownToTheLimitersCeiling() throws {
		let newer = """
		{ "tempo": 120, "meter": [4, 4], "bar_seconds": 2, "seconds": 8, "layers": [],
		  "mixing": { "stems_sum_to": "the mix before saturation, compressor, clip and limiter",
		              "applied": ["gain"], "skipped": ["limiter"], "sum_peak_db": 1.34 },
		  "master": { "gain_db": 3.0, "limiter": { "enabled": true, "ceiling_db": -1.0, "release_ms": 80.0 } } }
		"""
		let read = try SongRender.manifest(from: Data(newer.utf8))
		#expect(read.stemsPeakDb == 1.34)
		#expect(read.limiterCeilingDb == -1)
		// 2.34 dB down: 10^(-2.34/20).
		#expect(abs(read.stemGain - 0.7639) < 0.001)

		// A quiet song is left alone rather than turned up.
		let quiet = newer.replacingOccurrences(of: "\"sum_peak_db\": 1.34", with: "\"sum_peak_db\": -6.0")
		#expect(try SongRender.manifest(from: Data(quiet.utf8)).stemGain == 1)

		// The limiter off: the ceiling is taken as -1 dBFS, the limiter's own default.
		let unlimited = newer.replacingOccurrences(of: "\"enabled\": true", with: "\"enabled\": false")
		let readUnlimited = try SongRender.manifest(from: Data(unlimited.utf8))
		#expect(readUnlimited.limiterCeilingDb == nil)
		#expect(abs(readUnlimited.stemGain - 0.7639) < 0.001)

		// An older mat says nothing, and nothing is changed.
		#expect(try SongRender.manifest(from: Data(manifest.utf8)).stemGain == 1)
	}

	/// Stems that are the mix are played as they were written.
	///
	/// Reported 2026-09-16: "the mix and the combined stems still have a
	/// different volume/dynamic". `mat` f2063b3 writes each stem through the
	/// master's own gain curve, so they sum to the mix sample for sample and
	/// there is nothing left for the pane to take off. The `mixing` block is
	/// the drunken sailor's, rendered with that `mat`.
	@Test func stemsWrittenThroughTheMasterArePlayedAsTheyAre() throws {
		let through = """
		{ "tempo": 120, "meter": [4, 4], "bar_seconds": 2, "seconds": 8, "layers": [],
		  "mixing": { "stems_sum_to": "the mix, sample for sample",
		              "applied": ["gain", "eq", "width", "saturation", "comp", "clip", "limiter"],
		              "skipped": [], "stems_through_master": true,
		              "master_curve_key": "f6fb47d3b0cb0cbd",
		              "pre_master_peak_db": 0.6670909523963928,
		              "sum_peak_db": -1.0000003576278687 },
		  "master": { "gain_db": 4.0, "limiter": { "enabled": true, "ceiling_db": -1.0, "release_ms": 80.0 } } }
		"""
		let read = try SongRender.manifest(from: Data(through.utf8))
		#expect(read.stemsThroughMaster)
		#expect(read.stemGain == 1)

		// A looped render's sum can sit a hundredth of a decibel over the
		// ceiling, which the old arithmetic would have taken off.
		let looped = through.replacingOccurrences(
			of: "\"sum_peak_db\": -1.0000003576278687", with: "\"sum_peak_db\": -0.991"
		)
		#expect(try SongRender.manifest(from: Data(looped.utf8)).stemGain == 1)

		// And a mat that cuts them before the master still has them turned down.
		let before = through
			.replacingOccurrences(of: "\"stems_through_master\": true", with: "\"stems_through_master\": false")
			.replacingOccurrences(of: "\"sum_peak_db\": -1.0000003576278687", with: "\"sum_peak_db\": 0.667")
		#expect(abs(try SongRender.manifest(from: Data(before.utf8)).stemGain - 0.8254) < 0.001)
	}

	@Test func aManifestThatIsNotOneIsRefusedInWords() {
		#expect(throws: SongRender.Failure.self) { try SongRender.manifest(from: Data("[]".utf8)) }
		#expect(throws: SongRender.Failure.self) { try SongRender.manifest(from: Data("not json".utf8)) }
	}

	/// The exact shape `mat` prints for a misspelt instrument, twice.
	private let failed = """
	error: unknown instrument 'brasss'
	   --> /tmp/scratch/broken.song:137:14
	    |
	137 |   instrument brasss
	    |              ^^^^^^
	    = hint: did you mean 'brass'?
	error: unknown instrument 'brasss'
	   --> /tmp/scratch/broken.song:149:14
	    |
	149 |   instrument brasss
	    |              ^^^^^^
	    = hint: did you mean 'brass'?
	2 error(s) in /tmp/scratch/broken.song
	"""

	@Test func anErrorNamesItsLineAndKeepsItsHint() {
		let diagnostics = SongRender.diagnostics(in: failed)
		#expect(diagnostics.count == 2)
		#expect(diagnostics[0].line == 137)
		#expect(diagnostics[0].column == 14)
		#expect(diagnostics[0].message == "unknown instrument 'brasss' — did you mean 'brass'?")
		#expect(diagnostics[1].line == 149)
		#expect(SongRender.complaint(in: failed).hasPrefix("137:14: unknown instrument 'brasss'"))
	}

	/// An error with no place in the file — a sample that could not be
	/// opened — is still an error, without a line.
	@Test func anErrorWithNoPlaceIsKept() {
		let diagnostics = SongRender.diagnostics(in: "error: cannot open stems/Vocals.wav\n")
		#expect(diagnostics == [.init(message: "cannot open stems/Vocals.wav")])
		#expect(SongRender.complaint(in: "error: cannot open stems/Vocals.wav\n") == "cannot open stems/Vocals.wav")
	}

	/// A run that said nothing `mat`-shaped — a shell that could not find it —
	/// shows its tail rather than nothing.
	@Test func aSilentFailureShowsItsTail() {
		#expect(SongRender.complaint(in: "zsh: command not found: mat\n") == "zsh: command not found: mat")
		#expect(SongRender.complaint(in: "") == "The render said nothing and wrote no sound.")
	}

	/// A render directory is named for the song and the process, so what a
	/// killed process left can be told from what a live one is playing.
	@Test func whatAKilledProcessLeftIsStaleAndWhatALiveOneHasIsNot() throws {
		let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("song-render-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: temporary) }
		let song = URL(fileURLWithPath: "/songs/neon.song")
		let other = URL(fileURLWithPath: "/songs/undertow.song")

		let mine = SongRender.outputRoot(for: song, under: temporary, pid: 100)
		let dead = SongRender.outputRoot(for: song, under: temporary, pid: 200)
		let theirs = SongRender.outputRoot(for: other, under: temporary, pid: 300)
		for directory in [mine, dead, theirs] {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		#expect(mine.lastPathComponent.hasSuffix("-100"))
		#expect(mine.deletingLastPathComponent().lastPathComponent == "abydos-song")
		#expect(mine.lastPathComponent != theirs.lastPathComponent.replacingOccurrences(of: "-300", with: "-100"))

		let stale = SongRender.staleRenderDirectories(under: temporary) { $0 == 100 }
		#expect(Set(stale.map(\.lastPathComponent)) == [dead.lastPathComponent, theirs.lastPathComponent])
	}

	@Test func theRenderedLineIsFound() {
		let said = "rendered 1:10.6 in 0.83s (85x realtime), peak -1.0 dBFS, rms -16.0 dBFS\nwrote /tmp/x/mix.wav\n"
		#expect(SongRender.renderedLine(in: said) == "rendered 1:10.6 in 0.83s (85x realtime), peak -1.0 dBFS, rms -16.0 dBFS")
		#expect(SongRender.renderedLine(in: "wrote /tmp/x/mix.wav") == nil)
	}

	/// mat e72d7e5 on: every file the song was read from, the song first.
	@Test func theManifestSaysWhichFilesTheSongWasReadFrom() throws {
		let json = """
		{ "bar_seconds": 1.935, "seconds": 30.97, "tempo": 124, "layers": [],
		  "sources": ["/songs/include/song.song", "/songs/include/kit.song", "/songs/include/parts/bass.song"] }
		"""
		let read = try SongRender.manifest(from: Data(json.utf8))
		#expect(read.sources == ["/songs/include/song.song", "/songs/include/kit.song", "/songs/include/parts/bass.song"])
		#expect(try SongRender.manifest(from: Data(manifest.utf8)).sources.isEmpty, "an older mat says none")
	}
}
