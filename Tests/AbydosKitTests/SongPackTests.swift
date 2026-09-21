import Foundation
import Testing
@testable import AbydosKit

struct SongPackTests {
	@Test func thePackIsBesideTheSong() {
		let song = URL(fileURLWithPath: "/songs/my song.song")
		#expect(SongPack.destination(for: song).path == "/songs/my song.zip")
		#expect(
			SongPack.command(executable: "/bin/mat", song: song, output: SongPack.destination(for: song))
				== "/bin/mat pack '/songs/my song.song' -o '/songs/my song.zip'"
		)
	}

	@Test func aMatThatPacksSaysSoInItsHelp() {
		let help = """
			Commands:
			  export         Export the arranged timeline as JSON (input for external renderers)
			  pack           Pack a song and every file it reads into one zip
			  translate      Measure, and hear, how a mix carries to other devices
			"""
		#expect(SongPack.isSupported(help: help))
		#expect(!SongPack.isSupported(help: help.replacingOccurrences(of: "  pack  ", with: "")))
		// A word in a description is not the command.
		#expect(!SongPack.isSupported(help: "  export   Export it, then pack it yourself"))
	}

	@Test func whatThePackSaid() {
		let said = """
			packed 11 files, 0.8 MB, into /songs/neon.zip; 10 path(s) rewritten to point into it
			needs, installed where it is played (listed in its README.txt):
			  - logic:01 Acoustic Pianos/Steinway Grand Piano 2.exs (preset steinway)
			  - the CLAP plugin Surge XT (instrument bass)
			"""
		let report = SongPack.report(from: said)
		#expect(report.files == 11 && report.megabytes == 0.8)
		#expect(report.needs == [
			"logic:01 Acoustic Pianos/Steinway Grand Piano 2.exs (preset steinway)", "the CLAP plugin Surge XT (instrument bass)",
		])
		#expect(SongPack.report(from: "packed 1 files, 0.0 MB, into /a.zip; 0 path(s) rewritten").needs.isEmpty)
	}
}
