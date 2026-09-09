import AppKit
import AbydosKit

/// The renderer asks for the tokens on each line in turn; scanning the whole
/// token array per line would be quadratic across the viewport.
struct TokenIndex {
	private let tokens: [HighlightToken]

	init(tokens: [HighlightToken]) {
		self.tokens = tokens.sorted { $0.range.lowerBound < $1.range.lowerBound }
	}

	func tokens(overlapping range: Range<Int>) -> ArraySlice<HighlightToken> {
		guard !tokens.isEmpty else { return [] }

		// First token that could reach into `range`.
		var low = 0
		var high = tokens.count
		while low < high {
			let mid = (low + high) / 2
			if tokens[mid].range.upperBound <= range.lowerBound {
				low = mid + 1
			} else {
				high = mid
			}
		}
		let start = low

		var end = start
		while end < tokens.count && tokens[end].range.lowerBound < range.upperBound {
			end += 1
		}
		return tokens[start..<end]
	}
}
