import Foundation

/// A song and every file it reads, in one zip beside it: `mat pack`.
///
/// Asked for 2026-09-21: "export everything (samples + text model to one zip
/// file)", and "the sample locations need to be updated in that case as well in
/// the text. It should get one self contianing archive". Which files a song
/// reads, and which words in it are their paths, is `mat`'s knowledge — the same
/// reading its render makes — so the pack is `mat`'s to make, and this is the
/// command line for it and what to make of what it says.
public enum SongPack {
	/// Where the pack goes: `neon.zip` beside `neon.song`.
	public static func destination(for song: URL) -> URL {
		song.deletingPathExtension().appendingPathExtension("zip")
	}

	public static func command(executable: String, song: URL, output: URL) -> String {
		[executable, "pack", song.path, "-o", output.path].map(SongRender.quoted).joined(separator: " ")
	}

	/// Whether a `mat` packs, from what `mat --help` says: a `mat` from before
	/// faece3d has no such command, and the menu says so rather than failing.
	public static func isSupported(help: String) -> Bool {
		help.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("pack ") }
	}

	/// What `mat pack` said it did: its files and size, and what the song needs
	/// installed where it is played, which the pack does not carry.
	public struct Report: Equatable, Sendable {
		public var files: Int?
		public var megabytes: Double?
		public var needs: [String]
	}

	public static func report(from output: String) -> Report {
		var report = Report(files: nil, megabytes: nil, needs: [])
		var listing = false
		for line in output.split(whereSeparator: \.isNewline).map(String.init) {
			if line.hasPrefix("packed ") {
				// `packed 11 files, 0.8 MB, into …`
				let words = line.split(separator: " ")
				report.files = words.count > 1 ? Int(words[1]) : nil
				report.megabytes = words.count > 3 ? Double(words[3]) : nil
			} else if line.hasPrefix("needs") {
				listing = true
			} else if listing, line.hasPrefix("  - ") {
				report.needs.append(String(line.dropFirst(4)))
			} else {
				listing = false
			}
		}
		return report
	}
}
