import Foundation

/// What a `.vboard` on disk is, decided before anything is sent anywhere.
///
/// Three files must not be uploaded: one that is not a board file at all, one
/// already encrypted with some other board's key — vboard needs that board's
/// link key to import it, and the tab has no such key — and one larger than
/// the server takes. Each would fail on the server anyway, but only after the
/// whole file had travelled there, and a 700 MB upload that ends in a 400 is a
/// bad way to learn the file was the wrong kind.
///
/// Decided from the head of the file, never the whole of it: a board with a
/// recorded workshop on it is hundreds of megabytes of base64, and the answer
/// is in the first few dozen bytes.
public enum VboardFile: Equatable {
	case board
	/// Nothing in it yet: somebody made `my.vboard` to start a board. It opens
	/// as a new blank board named after the file, and the first save is what
	/// gives the file its contents.
	case empty
	case encrypted
	case notABoard
	case tooLarge(bytes: Int)

	/// vboard's own limit on an import, in its documentation and its code.
	public static let largestImport = 700 * 1024 * 1024
	/// How much of the head is read. vboard itself looks for the encrypted
	/// format's name in the first 4 KB of a file it is given.
	static let headLength = 4096

	public static func inspect(_ url: URL) -> VboardFile {
		let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		if size > largestImport { return .tooLarge(bytes: size) }
		guard let handle = try? FileHandle(forReadingFrom: url) else { return .notABoard }
		defer { try? handle.close() }
		let head = (try? handle.read(upToCount: headLength)) ?? Data()
		return inspect(head: head, isWhole: size <= headLength)
	}

	/// The decision on the head alone, where a test can reach it.
	///
	/// `format` is looked for as a key with one of vboard's two values, not as
	/// a phrase. Inside a JSON string every quote is escaped, so a sticky that
	/// says `"format":"vboard"` cannot match; and the one nested `format` key
	/// vboard writes — an item's text format, `"md"` — has neither value.
	/// Anywhere in the head rather than first, so a file somebody re-indented
	/// with sorted keys is still a board, as long as the key is near the top.
	///
	/// Empty means nothing but whitespace, and only when the head is the whole
	/// file: a touched file and one an editor saved with a newline are both a
	/// new board.
	static func inspect(head: Data, isWhole: Bool = false) -> VboardFile {
		if isWhole, head.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return .empty }
		// A head cut through the middle of a multi-byte character is not
		// UTF-8; up to three bytes off its end make it so again.
		let text = (0...3).lazy.compactMap { String(data: head.dropLast($0), encoding: .utf8) }.first
		guard let text, text.drop(while: \.isWhitespace).first == "{" else { return .notABoard }
		guard let regex = try? NSRegularExpression(pattern: #""format"\s*:\s*"(vboard|vboard-encrypted)""#),
		      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
		      let range = Range(match.range(at: 1), in: text)
		else { return .notABoard }
		return text[range] == "vboard" ? .board : .encrypted
	}
}
