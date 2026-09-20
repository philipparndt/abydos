import Foundation

/// Switching one `play` line of a song off and on again: `play beat x4 mute`.
///
/// Asked for 2026-09-20: "It should also be possible to enable and disable
/// individual blocks. This updates the source code, maybe we need a special
/// syntax for muted parts so that it is easy to toggle this without messing up
/// the code." Commenting the line out would do more than silence it: a `play`
/// takes its time on the track, so every block after it would move earlier.
/// `mute` is a word on the line that `mat` reads, and the block keeps its place.
///
/// So the edit is one word, at the end of what the line says and before what it
/// is commented with, and nothing else on the line is touched — not its
/// spacing, not its comment, not its line ending.
public enum SongBlockMute {
	public struct Edit: Equatable, Sendable {
		/// What to replace, in UTF-16 units of the whole text.
		public var range: Range<Int>
		public var text: String
		/// What the line says once it is made.
		public var muted: Bool
	}

	/// The edit that toggles `mute` on `line`, 1-based; nil when the line is
	/// not a `play` line.
	///
	/// Over UTF-16 units and not characters: that is what the range is in, and
	/// `\r\n` is one `Character`, which a search for `\n` walks straight past.
	public static func toggle(atLine line: Int, in text: String) -> Edit? {
		guard line >= 1 else { return nil }
		let units = Array(text.utf16)
		var start = 0
		for _ in 1..<line {
			guard let newline = units[start...].firstIndex(of: newlineUnit) else { return nil }
			start = newline + 1
		}
		let end = units[start...].firstIndex(of: newlineUnit) ?? units.count
		let code = start..<commentStart(in: units, of: start..<end)
		let words = words(in: units, of: code)
		func says(_ word: Range<Int>, _ expected: String) -> Bool { units[word].elementsEqual(expected.utf16) }
		guard let first = words.first, says(first, "play"), words.count >= 2 else { return nil }

		// The pattern is the word after `play`, so `mute` is an option from the
		// third word on: `play mute` plays a pattern of that name.
		if let word = words.dropFirst(2).first(where: { says($0, "mute") }) {
			// With the space before it, so the line is left as it was written.
			var from = word.lowerBound
			while from > code.lowerBound, isSpace(units[from - 1]) { from -= 1 }
			return Edit(range: from..<word.upperBound, text: "", muted: false)
		}
		let last = words[words.count - 1].upperBound
		return Edit(range: last..<last, text: " mute", muted: true)
	}

	private static let newlineUnit: UInt16 = 10

	private static func isSpace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == 13 }

	/// Where the line's comment starts: `#` starts one, except inside a note
	/// name like `C#4`, where it follows a letter — `SongSource.stripped`'s rule.
	private static func commentStart(in units: [UInt16], of line: Range<Int>) -> Int {
		for index in line where units[index] == 35 {
			let before = index > line.lowerBound ? Unicode.Scalar(units[index - 1]) : nil
			if !(before?.properties.isAlphabetic ?? false) { return index }
		}
		return line.upperBound
	}

	private static func words(in units: [UInt16], of code: Range<Int>) -> [Range<Int>] {
		var words: [Range<Int>] = []
		var from: Int?
		for index in code {
			if isSpace(units[index]) {
				if let began = from { words.append(began..<index) }
				from = nil
			} else if from == nil {
				from = index
			}
		}
		if let began = from { words.append(began..<code.upperBound) }
		return words
	}
}
