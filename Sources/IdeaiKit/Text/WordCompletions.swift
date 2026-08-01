import Foundation

/// Completions taken from the words already in the file.
///
/// What an editor can offer for a language nobody wrote a server for, and what
/// it falls back to while a server is still starting. It knows nothing about
/// types or scope — every identifier in the file is a candidate — which sounds
/// useless until you notice how much of typing is repeating a name you wrote
/// forty lines ago and would otherwise have to spell exactly.
public enum WordCompletions {
	/// Words worth offering for a prefix, best first.
	///
	/// - `limit` keeps the list to what fits on screen and bounds the work.
	public static func candidates(
		matching prefix: String,
		in text: String,
		near offset: Int = 0,
		limit: Int = 12
	) -> [String] {
		guard prefix.count >= 1 else { return [] }
		let lowerPrefix = prefix.lowercased()

		// Where each word is, so the nearest use of it can be preferred: the
		// name you want is nearly always the one you last looked at.
		var best: [String: Int] = [:]
		for (word, position) in words(in: text) {
			guard word.count > prefix.count, word.lowercased().hasPrefix(lowerPrefix) else { continue }
			let distance = abs(position - offset)
			if let existing = best[word], existing <= distance { continue }
			best[word] = distance
		}

		// The word being typed is not a completion of itself.
		best.removeValue(forKey: prefix)

		return best
			.sorted { left, right in
				// An exact-case match first, then whichever is nearer.
				let leftExact = left.key.hasPrefix(prefix)
				let rightExact = right.key.hasPrefix(prefix)
				if leftExact != rightExact { return leftExact }
				if left.value != right.value { return left.value < right.value }
				return left.key < right.key
			}
			.prefix(limit)
			.map(\.key)
	}

	/// Every identifier in the text, with where it starts.
	///
	/// Deliberately naive — a word is letters, digits and underscores, and a
	/// comment is not told from code. Anything cleverer would be a parser, and
	/// where there is a parser there is a language server worth asking instead.
	static func words(in text: String) -> [(String, Int)] {
		var result: [(String, Int)] = []
		var current = ""
		var start = 0
		var index = 0

		for unit in text.utf16 {
			let isWord: Bool
			if unit == 0x5F {
				isWord = true
			} else if let scalar = Unicode.Scalar(unit) {
				isWord = CharacterSet.alphanumerics.contains(scalar)
			} else {
				isWord = false
			}

			if isWord {
				if current.isEmpty { start = index }
				current.append(Character(Unicode.Scalar(unit) ?? " "))
			} else if !current.isEmpty {
				// A run of digits is a number, not a name worth suggesting.
				if !current.allSatisfy(\.isNumber) { result.append((current, start)) }
				current = ""
			}
			index += 1
		}
		if !current.isEmpty, !current.allSatisfy(\.isNumber) { result.append((current, start)) }
		return result
	}
}
