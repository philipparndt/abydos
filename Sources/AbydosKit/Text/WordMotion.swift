import Foundation

/// Where the next word begins and the previous one ends.
///
/// Offsets are UTF-16, as everywhere the editor deals in positions. The rules
/// are macOS's rather than vi's: ⌥→ goes to the *end* of the word ahead and
/// ⌥← to the *start* of the word behind, which is why holding one and then the
/// other does not return you to where you began. That asymmetry is what every
/// other Mac text field does, and an editor that improved on it would just feel
/// broken.
public enum WordMotion {
	/// What a character counts as when deciding where a word stops.
	enum Class {
		case word        // letters, digits, underscore — the body of an identifier
		case whitespace
		case punctuation
	}

	static func classify(_ unit: UInt16) -> Class {
		if unit == 0x5F { return .word }  // underscore belongs to the identifier
		guard let scalar = Unicode.Scalar(unit) else { return .word }
		if CharacterSet.whitespacesAndNewlines.contains(scalar) { return .whitespace }
		if CharacterSet.alphanumerics.contains(scalar) { return .word }
		return .punctuation
	}

	/// The offset ⌥→ lands on: past the whitespace, then to the end of the run
	/// that follows it.
	public static func endOfWord(after offset: Int, in text: [UInt16]) -> Int {
		var index = max(0, min(offset, text.count))
		guard index < text.count else { return text.count }

		// Skip whatever separates here from the next word.
		while index < text.count, classify(text[index]) == .whitespace { index += 1 }
		guard index < text.count else { return text.count }

		// Then the run of one kind: letters stop at punctuation, and a row of
		// punctuation is crossed in one go rather than one character at a time.
		let kind = classify(text[index])
		while index < text.count, classify(text[index]) == kind { index += 1 }
		return index
	}

	/// The offset ⌥← lands on: back over the whitespace, then to the start of
	/// the run before it.
	public static func startOfWord(before offset: Int, in text: [UInt16]) -> Int {
		var index = max(0, min(offset, text.count))
		guard index > 0 else { return 0 }

		while index > 0, classify(text[index - 1]) == .whitespace { index -= 1 }
		guard index > 0 else { return 0 }

		let kind = classify(text[index - 1])
		while index > 0, classify(text[index - 1]) == kind { index -= 1 }
		return index
	}

	/// The word around an offset, for selecting it by double-click or for
	/// deciding what a completion is trying to finish.
	public static func wordRange(at offset: Int, in text: [UInt16]) -> Range<Int>? {
		let index = max(0, min(offset, text.count))

		// A caret just after a word belongs to that word: that is where it is
		// when somebody has finished typing one.
		var start = index
		while start > 0, classify(text[start - 1]) == .word { start -= 1 }
		var end = index
		while end < text.count, classify(text[end]) == .word { end += 1 }

		return end > start ? start..<end : nil
	}

	/// The identifier being typed immediately before an offset.
	///
	/// What a completion list is filtered by: everything back to the start of
	/// the current word, and empty when the caret is not in one.
	public static func prefix(before offset: Int, in text: [UInt16]) -> String {
		let index = max(0, min(offset, text.count))
		var start = index
		while start > 0, classify(text[start - 1]) == .word { start -= 1 }
		guard start < index else { return "" }
		return String(decoding: text[start..<index], as: UTF16.self)
	}
}
