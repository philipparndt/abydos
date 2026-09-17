import Foundation

/// Rendering a `.song` with `mat`, and reading what the run said.
///
/// A song is text that makes sound the way a `.scad` is text that makes a
/// shape, and it is rendered the same way: a program is run and the pane shows
/// what it wrote. `mat render <song> -o <dir>/mix.wav --stems <dir>/stems`
/// writes the whole mix, one file per *layer* — a stem group a track names
/// with `layer`, or the track's own name — and `manifest.json`, which is what
/// says which file is which layer and which tracks are in it.
///
/// Kept apart from the pane so the parts that read output are tested against
/// real output: the manifest is `mat`'s own JSON, and a failed render is
/// `error: …` with a `-->` line naming the place in the file.
public enum SongRender {
	/// The tool. `mat` is a Rust binary somebody has `cargo install`ed, so it
	/// is looked for the way every tool is — the process's own `PATH`, the
	/// login shell's, then the well-known directories, of which `~/.cargo/bin`
	/// is one.
	public static let tool = "mat"

	public static func executable() -> String? { Executables.locate(tool) }

	/// What to say when the tool is not there, with the way to get it.
	public static let missingMessage =
		"mat is not installed. In a checkout of musik-as-text, run:\n"
		+ "cargo install --path crates/mat-cli"

	// MARK: - Where a render goes

	/// The directory a pane renders into: under the temporary directory, named
	/// for the song and for this process.
	///
	/// **The process is in the name so what a crash leaves can be told from
	/// what is in use.** A pane deletes its directory when it goes, and a
	/// process that was killed — a driven run, a crash — never gets to. Six
	/// stems of a three-minute song are a hundred megabytes; the first
	/// afternoon's driven runs left a gigabyte. The song's hash keeps two
	/// panes on two files apart, and the pid keeps two panes on one file in
	/// two processes apart; two panes on one file in one process share it,
	/// which is the case where they also share the tab.
	public static func outputRoot(
		for song: URL, under temporary: URL = FileManager.default.temporaryDirectory,
		pid: Int32 = ProcessInfo.processInfo.processIdentifier
	) -> URL {
		temporary.appendingPathComponent("abydos-song", isDirectory: true)
			.appendingPathComponent("\(songDigest(song))-\(pid)", isDirectory: true)
	}

	static func songDigest(_ song: URL) -> String {
		// Not a cryptographic need: twelve hex characters of the path's hash
		// tell two songs apart, and the name has to stay short enough for a
		// directory listing to read.
		var hash: UInt64 = 0xcbf29ce484222325
		for byte in song.standardizedFileURL.path.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 0x100000001b3
		}
		return String(format: "%012llx", hash & 0xffffffffffff)
	}

	/// The render directories that belong to processes no longer running —
	/// what a crash, a kill or a quit left, of any song — so a pane can sweep
	/// them when it opens. Every song's and not only this one's, because a
	/// process keeps its last render of each song it showed until it quits,
	/// and the songs it showed are not the songs the next one will.
	public static func staleRenderDirectories(
		under temporary: URL = FileManager.default.temporaryDirectory,
		isRunning: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
	) -> [URL] {
		let parent = temporary.appendingPathComponent("abydos-song", isDirectory: true)
		guard let entries = try? FileManager.default.contentsOfDirectory(
			at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		) else { return [] }
		return entries.filter { entry in
			let name = entry.lastPathComponent
			guard let dash = name.lastIndex(of: "-"), let pid = Int32(name[name.index(after: dash)...]) else { return false }
			return !isRunning(pid)
		}
	}

	/// Where `mat` keeps this song's layers between renders: beside the render
	/// directories, named for the song and **not** for the process, so a
	/// relaunch finds them. `staleRenderDirectories` leaves it alone — its name
	/// does not end in a pid — and `mat` deletes what no render has used for
	/// half an hour.
	public static func cacheDirectory(for song: URL, under temporary: URL = FileManager.default.temporaryDirectory) -> URL {
		temporary.appendingPathComponent("abydos-song", isDirectory: true)
			.appendingPathComponent("\(songDigest(song))-cache", isDirectory: true)
	}

	/// The mix file's name in an output directory.
	public static let mixName = "mix.wav"
	public static let stemsDirectory = "stems"
	public static let manifestName = "manifest.json"

	/// The command line for rendering `song` into `output`: the mix beside a
	/// directory of stems, with the layers kept in `cache` so a render after an
	/// edit renders only the layers it touched. Quoted for the shell, since a
	/// song sits in a project and a project sits wherever somebody keeps them.
	/// - Parameter bars: only these bars of the song, 1-based and inclusive
	///   (`mat` f684cab), which is ten times faster than the whole of it and is
	///   how a pane has something to play while the song renders behind it.
	/// - Parameter streaming: write the mix as it renders (`mat` a5f7d05), a
	///   stretch at a time, with `mix.stream.json` beside it saying how much of
	///   it can be read. One render, not two: what it ends with is the file an
	///   ordinary render writes, to the byte.
	public static func command(
		executable: String, song: URL, output: URL, cache: URL? = nil, bars: ClosedRange<Int>? = nil,
		streaming: Bool = false
	) -> String {
		var arguments = [
			executable, "render", song.path,
			"-o", output.appendingPathComponent(mixName).path,
			"--stems", output.appendingPathComponent(stemsDirectory).path,
		]
		if streaming { arguments.append("--stream") }
		if let bars { arguments += ["--bars", "\(bars.lowerBound)-\(bars.upperBound)"] }
		if let cache { arguments += ["--cache", cache.path] }
		return arguments.map(quoted).joined(separator: " ")
	}

	// MARK: - The mix while it is being written

	/// The file `mat --stream` keeps beside a mix, saying how much of it is
	/// there: `mix.wav` has `mix.stream.json`.
	public static func streamStatus(beside mix: URL) -> URL {
		mix.deletingPathExtension().appendingPathExtension("stream.json")
	}

	/// How much of a streamed render can be played.
	///
	/// Written after the samples it counts and renamed into place, so what it
	/// says is always already in the file — never the other way round.
	public struct Stream: Equatable, Sendable {
		/// Frames readable now, at `sampleRate`.
		public let frames: Int64
		public let sampleRate: Double
		public let seconds: Double
		public let barSeconds: Double
		public let tempo: Double
		/// How long the whole song is, in seconds and in bars, from the first
		/// reading on (`mat` 357f7f5) — so a timeline is laid out once rather
		/// than growing under the playhead. Nil from a `mat` that does not say.
		///
		/// It is the *music's* length: the last bar, at the song's tempo. A
		/// reverb or a delay rings past it, so the file ends a little later —
		/// 228.4 s against 226.9 for neon — and what is written is what is
		/// played.
		public let totalSeconds: Double?
		public let totalBars: Int?
		/// The render is over: this is the whole song, and the file will not
		/// change again. It can be *shorter* than the last reading — the tail
		/// is trimmed and faded at the end — so what was scheduled past it is
		/// no longer there to play.
		public let finished: Bool
	}

	public static func stream(from data: Data) -> Stream? {
		guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let frames = (top["frames_written"] as? NSNumber)?.int64Value,
		      let rate = (top["sample_rate"] as? NSNumber)?.doubleValue, rate > 0
		else { return nil }
		return Stream(
			frames: frames,
			sampleRate: rate,
			seconds: (top["seconds_written"] as? NSNumber)?.doubleValue ?? Double(frames) / rate,
			barSeconds: (top["bar_seconds"] as? NSNumber)?.doubleValue ?? 0,
			tempo: (top["tempo"] as? NSNumber)?.doubleValue ?? 0,
			totalSeconds: (top["seconds_total"] as? NSNumber)?.doubleValue,
			totalBars: (top["bars_total"] as? NSNumber)?.intValue,
			finished: top["finished"] as? Bool ?? false
		)
	}

	/// What to read back out of a streamed mix: the manifest a pane shows while
	/// only the mix exists, with the tempo and bar length the stream knows.
	public static func manifest(ofStream stream: Stream) -> Manifest {
		Manifest(
			tempo: stream.tempo, meter: [4, 4], barSeconds: stream.barSeconds,
			seconds: max(stream.totalSeconds ?? 0, stream.seconds), layers: []
		)
	}

	// MARK: - Exporting

	/// What a song can be exported as. `mat` picks the format from the output's
	/// extension (4143e44), and writes stems in the same format.
	public enum ExportFormat: String, CaseIterable, Sendable {
		case wav, flac, m4a

		/// The item's name: what the file is, and what kind.
		public var title: String {
			switch self {
			case .wav: return "WAV (24-bit)"
			case .flac: return "FLAC (lossless)"
			case .m4a: return "M4A (AAC, 256 kbit/s)"
			}
		}
	}

	/// Where an export writes: beside the song, the mix under the song's name,
	/// and the stems in a folder of the song's name.
	public struct Export: Equatable, Sendable {
		public var mix: URL
		public var stems: URL?

		/// The files and folders already there that this export would replace.
		public var replaces: [URL] {
			[mix, stems].compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
		}
	}

	public static func export(of song: URL, as format: ExportFormat, withStems: Bool) -> Export {
		let base = song.deletingPathExtension()
		return Export(
			mix: base.appendingPathExtension(format.rawValue),
			stems: withStems ? base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent) stems", isDirectory: true) : nil
		)
	}

	/// The command line for an export: the same render, into the export's
	/// files, through the pane's cache — so exporting a song the pane has just
	/// rendered reads every layer back.
	public static func exportCommand(executable: String, song: URL, export: Export, cache: URL?) -> String {
		var arguments = [executable, "render", song.path, "-o", export.mix.path]
		if let stems = export.stems { arguments += ["--stems", stems.path] }
		if let cache { arguments += ["--cache", cache.path] }
		return arguments.map(quoted).joined(separator: " ")
	}

	/// Whether a `mat` writes anything but WAV, from its `render --help`.
	///
	/// **Asked, because the answer was a silent wrong file.** A `mat` from
	/// before 4143e44 takes `-o song.flac` and writes WAV data under that name:
	/// no error, and a file every player refuses. `--bitrate` came with the
	/// formats, so its presence is the question.
	public static func supportsFormats(help: String) -> Bool {
		help.contains("--bitrate")
	}

	/// Whether a `mat` writes the mix while it renders (a5f7d05), from its
	/// `render --help`. An older one takes no `--stream` and refuses the whole
	/// render over it, so the question is asked before it is passed.
	public static func supportsStreaming(help: String) -> Bool {
		help.contains("--stream\n") || help.contains("--stream ")
	}

	static func quoted(_ argument: String) -> String {
		if argument.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:".contains($0) }) { return argument }
		return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	// MARK: - The manifest

	/// What `mat render --stems` wrote beside the stems.
	public struct Manifest: Equatable, Sendable {
		public struct Layer: Equatable, Sendable {
			public var name: String
			/// The stem's file name, relative to the stems directory.
			public var file: String
			/// The tracks rendered into it, in the song's order.
			public var tracks: [String]
			/// What `mat` keyed the layer by in its cache: everything its samples
			/// are a function of. The same key is the same samples, so what was
			/// drawn of a stem with this key is still true of it. Nil from a
			/// render without a cache, or from an older `mat`.
			public var key: String? = nil
			/// Read back from the cache rather than rendered.
			public var cached: Bool = false
		}

		public struct Section: Equatable, Sendable {
			public var name: String
			public var start: Double
			public var end: Double
		}

		public var title: String?
		public var tempo: Double
		/// Beats per bar and the beat's note value: `[4, 4]`.
		public var meter: [Int]
		public var barSeconds: Double
		public var seconds: Double
		public var layers: [Layer]
		public var sections: [Section]
		/// The peak of the stems' sum, in dBFS, when the manifest says. Since
		/// 2026-09-13 `mat` cuts the stems from one render, so they sum to
		/// the mix as it was before the master's dynamics — which peaks above
		/// the limiter's ceiling, and a player summing them turns them down
		/// by the difference. Nil from an older `mat`, whose stems were solo
		/// renders through the limiter each.
		public var stemsPeakDb: Double?
		/// The master limiter's ceiling in dBFS, when the manifest carries the
		/// master; nil when the limiter is off or the manifest is older.
		public var limiterCeilingDb: Double?
		/// Whether every stem was written through the master's own gain curve,
		/// so the stems sum to the mix sample for sample (`mat` f2063b3).
		///
		/// Reported 2026-09-16: "the mix and the combined stems still have a
		/// different volume/dynamic" — the stems were cut before the master, so
		/// the compressor, the saturation and the limiter were the mix's alone
		/// and no fixed gain could stand in for them. Measured before the fix:
		/// the mix was 4.8 dB louder than the stems of neon, 3.7 dB of drive,
		/// and 6.5 dB *quieter* than harbour's. After it, 0.00 dB on all three.
		public var stemsThroughMaster = false
		/// Every file the song was read from, absolute, the song first: a save
		/// of any of them is a change to the sound. mat e72d7e5 on; empty
		/// before, and then the song is its only source.
		public var sources: [String] = []

		public init(
			title: String? = nil, tempo: Double, meter: [Int], barSeconds: Double,
			seconds: Double, layers: [Layer], sections: [Section] = [],
			stemsPeakDb: Double? = nil, limiterCeilingDb: Double? = nil,
			stemsThroughMaster: Bool = false
		) {
			self.title = title
			self.tempo = tempo
			self.meter = meter
			self.barSeconds = barSeconds
			self.seconds = seconds
			self.layers = layers
			self.sections = sections
			self.stemsPeakDb = stemsPeakDb
			self.limiterCeilingDb = limiterCeilingDb
			self.stemsThroughMaster = stemsThroughMaster
		}

		/// How much to turn every stem down so that their sum peaks where the
		/// mix's limiter would have held it: 1 when nothing is known, and
		/// never above 1 — a quiet song is not made louder.
		///
		/// Stems written through the master need none of it: they already are
		/// the mix, so they are played as they were written. The old sum is
		/// `pre_master_peak_db` in such a manifest, and the arithmetic below
		/// would come to 1 anyway — but not quite, for a looped render, whose
		/// sum can sit a hundredth of a decibel over the ceiling.
		public var stemGain: Double {
			if stemsThroughMaster { return 1 }
			guard let stemsPeakDb else { return 1 }
			let ceiling = limiterCeilingDb ?? -1
			return min(1, pow(10, (ceiling - stemsPeakDb) / 20))
		}

		/// The bar a moment is in, 1-based, and how far through it.
		public func bar(at seconds: Double) -> (bar: Int, beat: Double) {
			guard barSeconds > 0 else { return (1, 0) }
			let bars = seconds / barSeconds
			let beatsPerBar = Double(meter.first ?? 4)
			return (Int(bars.rounded(.down)) + 1, (bars - bars.rounded(.down)) * beatsPerBar)
		}
	}

	public enum Failure: Error, LocalizedError, Equatable {
		case unreadableManifest(String)

		public var errorDescription: String? {
			switch self {
			case .unreadableManifest(let why): return "The stems' manifest could not be read: \(why)"
			}
		}
	}

	/// Reads `manifest.json` as `mat` writes it — measured against a real one:
	///
	///     { "bar_seconds": 1.818, "bars": 37.0, "layers": [{ "file": "drums.wav",
	///       "layer": "drums", "tracks": ["drums"] }], "loop": false, "meter": [4, 4],
	///       "sample_rate": 48000, "seconds": 67.27, "sections": [], "tempo": 132.0,
	///       "title": "…" }
	public static func manifest(from data: Data) throws -> Manifest {
		let object: Any
		do {
			object = try JSONSerialization.jsonObject(with: data)
		} catch {
			throw Failure.unreadableManifest(error.localizedDescription)
		}
		guard let top = object as? [String: Any] else {
			throw Failure.unreadableManifest("it is not a JSON object")
		}
		let layers = (top["layers"] as? [[String: Any]] ?? []).compactMap { entry -> Manifest.Layer? in
			guard let name = entry["layer"] as? String, let file = entry["file"] as? String else { return nil }
			return Manifest.Layer(
				name: name, file: file, tracks: entry["tracks"] as? [String] ?? [],
				key: entry["key"] as? String, cached: entry["cached"] as? Bool ?? false
			)
		}
		let sections = (top["sections"] as? [[String: Any]] ?? []).compactMap { entry -> Manifest.Section? in
			guard let name = entry["name"] as? String,
			      let start = number(entry["start"]), let end = number(entry["end"]) else { return nil }
			return Manifest.Section(name: name, start: start, end: end)
		}
		let mixing = top["mixing"] as? [String: Any]
		let limiter = (top["master"] as? [String: Any])?["limiter"] as? [String: Any]
		let limiterOn = (limiter?["enabled"] as? Bool) ?? false
		var made = Manifest(
			title: top["title"] as? String,
			tempo: number(top["tempo"]) ?? 0,
			meter: (top["meter"] as? [Any])?.compactMap { number($0).map(Int.init) } ?? [4, 4],
			barSeconds: number(top["bar_seconds"]) ?? 0,
			seconds: number(top["seconds"]) ?? 0,
			layers: layers,
			sections: sections,
			stemsPeakDb: number(mixing?["sum_peak_db"]),
			limiterCeilingDb: limiterOn ? number(limiter?["ceiling_db"]) : nil,
			stemsThroughMaster: mixing?["stems_through_master"] as? Bool ?? false
		)
		made.sources = top["sources"] as? [String] ?? []
		return made
	}

	private static func number(_ value: Any?) -> Double? {
		if let double = value as? Double { return double }
		if let int = value as? Int { return Double(int) }
		return nil
	}

	// MARK: - What went wrong

	/// One thing `mat` refused, and where.
	public struct Diagnostic: Equatable, Sendable {
		public var message: String
		/// 1-based, when the error named a place in the song; nil for one
		/// that did not — a sample file it could not open, say.
		public var line: Int?
		public var column: Int?

		public init(message: String, line: Int? = nil, column: Int? = nil) {
			self.message = message
			self.line = line
			self.column = column
		}
	}

	/// The errors in a failed render's output, in order.
	///
	/// Measured, from a song with a misspelt instrument:
	///
	///     error: unknown instrument 'brasss'
	///        --> /…/broken.song:137:14
	///         |
	///     137 |   instrument brasss
	///         |              ^^^^^^
	///         = hint: did you mean 'brass'?
	///     2 error(s) in /…/broken.song
	///
	/// The `error:` line is the message, the `-->` under it the place, and the
	/// hint is worth keeping on the message since it is the one line somebody
	/// will act on.
	public static func diagnostics(in output: String) -> [Diagnostic] {
		var found: [Diagnostic] = []
		for raw in output.split(whereSeparator: \.isNewline) {
			let line = raw.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("error:") {
				let message = line.dropFirst("error:".count).trimmingCharacters(in: .whitespaces)
				found.append(Diagnostic(message: message))
			} else if line.hasPrefix("-->"), var last = found.popLast(), last.line == nil {
				let place = line.dropFirst("-->".count).trimmingCharacters(in: .whitespaces)
				// `path:line:col` — the path may hold colons of its own, so the
				// numbers are the last two pieces.
				let pieces = place.split(separator: ":")
				if pieces.count >= 3, let row = Int(pieces[pieces.count - 2]), let column = Int(pieces[pieces.count - 1]) {
					last.line = row
					last.column = column
				}
				found.append(last)
			} else if line.hasPrefix("= hint:"), var last = found.popLast() {
				last.message += " — " + line.dropFirst("= hint:".count).trimmingCharacters(in: .whitespaces)
				found.append(last)
			}
		}
		return found
	}

	/// What to show when a run wrote nothing: its errors when it said any,
	/// and the tail of what it said otherwise — a shell that could not find
	/// `mat`, a crash.
	public static func complaint(in output: String) -> String {
		let errors = diagnostics(in: output)
		if !errors.isEmpty {
			return errors.map { diagnostic in
				let place = diagnostic.line.map { line in
					diagnostic.column.map { "\(line):\($0): " } ?? "\(line): "
				} ?? ""
				return place + diagnostic.message
			}.joined(separator: "\n")
		}
		let tail = output.split(whereSeparator: \.isNewline).suffix(12).joined(separator: "\n")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return tail.isEmpty ? "The render said nothing and wrote no sound." : tail
	}

	/// What `mat` warned about while it rendered, one line each, without the
	/// `warning:` in front.
	///
	/// **A warning can be the whole story.** A sample `mat` cannot open is a
	/// warning, and the render goes on and succeeds without it: an installed
	/// `mat` that could not find its library wrote `examples/ember` with every
	/// voice of the kit missing and exited 0, and the pane showed that as an
	/// ordinary render. Reported 2026-09-16 as "Mix view loses the drums".
	public static func warnings(in output: String) -> [String] {
		output.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { $0.hasPrefix("warning:") }
			.map { $0.dropFirst("warning:".count).trimmingCharacters(in: .whitespaces) }
	}

	/// The line `mat` prints when it has rendered: `rendered 1:10.6 in 0.83s
	/// (85x realtime), peak -1.0 dBFS, rms -16.0 dBFS`. Shown in the strip
	/// once, since the peak is what somebody mastering a song wants to know.
	public static func renderedLine(in output: String) -> String? {
		output.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.last { $0.hasPrefix("rendered ") }
	}
}
