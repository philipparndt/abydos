import Foundation

/// What a `.song` file says about itself, read from its text: the tracks and
/// the patterns, and where each one is.
///
/// A [musik-as-text](https://github.com/rnd7/musik-as-text) song is plain
/// text made of blocks — a keyword at the start of a line, its settings
/// indented under it. The song pane needs three things out of it and none of
/// them needs the real parser: **which block the caret is in**, so the stem
/// that block makes can be lit; **which layer a track renders into**, since
/// `mat render --stems` writes one file per layer and a track's layer is its
/// name unless it says otherwise; and **which tracks play a pattern**, so a
/// caret in the pattern lights every stem that carries it.
///
/// A line scan, then, and a forgiving one: the file is being typed, so half of
/// the time it is not a song `mat` would accept, and the caret still has to
/// land somewhere. Whether the song is *valid* is `mat`'s answer, read off its
/// render — see `SongRender`.
public struct SongSource: Equatable, Sendable {
	/// A `track` block.
	public struct Track: Equatable, Sendable {
		public var name: String
		/// The stem group `mat render --stems` puts this track in: `layer`
		/// when the block says one, the track's own name otherwise.
		public var layer: String
		/// The patterns its `play` lines name.
		public var patterns: [String]
		public var isMuted: Bool
		/// Its lines, 1-based, from the `track` line to the line before the
		/// next block.
		public var lines: ClosedRange<Int>
	}

	/// A `pattern` block.
	public struct Pattern: Equatable, Sendable {
		public var name: String
		public var lines: ClosedRange<Int>
	}

	public var title: String?
	public var tracks: [Track]
	public var patterns: [Pattern]

	/// The keywords that start a block. Anything else at column one is a
	/// setting of the song — `tempo`, `meter`, `swing`, `section`.
	static let blockKeywords: Set<String> = ["instrument", "pattern", "track", "master"]

	public static func parse(_ text: String) -> SongSource {
		var title: String?
		var tracks: [Track] = []
		var patterns: [Pattern] = []

		/// The block being read, closed by the next keyword at column one.
		enum Open {
			case track(Track)
			case pattern(Pattern)
			case other
		}
		var open: Open = .other

		func close(at line: Int) {
			switch open {
			case .track(var track):
				track.lines = track.lines.lowerBound...max(track.lines.lowerBound, line)
				tracks.append(track)
			case .pattern(var pattern):
				pattern.lines = pattern.lines.lowerBound...max(pattern.lines.lowerBound, line)
				patterns.append(pattern)
			case .other:
				break
			}
			open = .other
		}

		var number = 0
		for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
			number += 1
			let line = Self.stripped(raw)
			let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
			guard let first = words.first else { continue }

			// A keyword at column one starts a block; the same word indented is
			// a setting of the block above, which is how `track foo` and its
			// `  instrument foo` line are told apart.
			let isTopLevel = !(raw.first?.isWhitespace ?? true)
			if isTopLevel {
				switch first {
				case "track":
					close(at: number - 1)
					let name = words.count > 1 ? words[1] : ""
					open = .track(Track(
						name: name, layer: name, patterns: [], isMuted: false, lines: number...number
					))
					continue
				case "pattern":
					close(at: number - 1)
					open = .pattern(Pattern(name: words.count > 1 ? words[1] : "", lines: number...number))
					continue
				case "title":
					title = Self.unquoted(String(line.dropFirst("title".count)).trimmingCharacters(in: .whitespaces))
					continue
				default:
					if Self.blockKeywords.contains(first) { close(at: number - 1) }
					continue
				}
			}

			guard case .track(var track) = open else { continue }
			switch first {
			case "layer":
				if words.count > 1 { track.layer = words[1] }
			case "mute":
				track.isMuted = true
			case "play":
				// `play verse x2 transpose=2` — the pattern is the word after
				// `play`; `play all` and `play bars=…` are an audio track's and
				// name no pattern.
				if words.count > 1, words[1] != "all", !words[1].contains("=") {
					track.patterns.append(words[1])
				}
			default:
				break
			}
			open = .track(track)
		}
		close(at: number)

		return SongSource(title: title, tracks: tracks, patterns: patterns)
	}

	/// The line without its comment: `#` starts one, except inside a note
	/// name like `C#4`, where it follows a letter.
	static func stripped(_ line: Substring) -> String {
		var result = ""
		var previous: Character?
		for character in line {
			if character == "#", !(previous?.isLetter ?? false) { break }
			result.append(character)
			previous = character
		}
		return result
	}

	private static func unquoted(_ text: String) -> String? {
		var value = text
		if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
			value = String(value.dropFirst().dropLast())
		}
		return value.isEmpty ? nil : value
	}

	// MARK: - What the caret is in

	public func track(atLine line: Int) -> Track? {
		tracks.first { $0.lines.contains(line) }
	}

	public func pattern(atLine line: Int) -> Pattern? {
		patterns.first { $0.lines.contains(line) }
	}

	/// The layers a caret on `line` should light: the track's own when it is
	/// in a track, and every track's that plays the pattern when it is in a
	/// pattern. Nothing anywhere else — the caret in an instrument or the
	/// master lights no stem in particular.
	public func layers(litByCaretAt line: Int) -> Set<String> {
		if let track = track(atLine: line) { return [track.layer] }
		if let pattern = pattern(atLine: line) {
			return Set(tracks.filter { $0.patterns.contains(pattern.name) }.map(\.layer))
		}
		return []
	}

	/// The tracks that render into a layer, in file order.
	public func tracks(inLayer layer: String) -> [Track] {
		tracks.filter { $0.layer == layer }
	}
}
