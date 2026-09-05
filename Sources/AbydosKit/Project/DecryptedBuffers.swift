import Foundation

/// A decrypted buffer as it was left: its text, whether it was edited, and
/// where the caret was.
public struct DecryptedBuffer: Equatable {
	public var text: String
	public var isEdited: Bool
	public var caretLine: Int

	public init(text: String, isEdited: Bool, caretLine: Int) {
		self.text = text
		self.isEdited = isEdited
		self.caretLine = caretLine
	}
}

/// Decrypted buffers parked while their project is not in the window.
///
/// A project switch closes every tab. A decrypted buffer closed that way has
/// nowhere to go: the session file must not have its text — that is the one
/// place plaintext must not land — and a dialog on every switch would make
/// switching to work on something else, which is the ordinary case, a
/// question. So the buffer is parked here, in memory, by root and file,
/// beside `ProjectSessions` and `DraftInbox`, which are the same idea for the
/// same reason, and put back into its tab when the session reopens the file.
/// Kept for the life of the app and not beyond; quitting is where it asks.
public final class DecryptedBuffers {
	private var parked: [String: DecryptedBuffer] = [:]

	public init() {}

	private static func key(root: URL, file: URL) -> String {
		root.standardizedFileURL.path + "\u{0}" + file.standardizedFileURL.path
	}

	/// Parks a buffer for a file under a root. A later park replaces.
	public func park(_ buffer: DecryptedBuffer, root: URL, file: URL) {
		parked[Self.key(root: root, file: file)] = buffer
	}

	/// The buffer parked for a file, taken.
	public func take(root: URL, file: URL) -> DecryptedBuffer? {
		parked.removeValue(forKey: Self.key(root: root, file: file))
	}

	public func discard(root: URL, file: URL) {
		parked.removeValue(forKey: Self.key(root: root, file: file))
	}

	/// Every edited buffer, with its root and file — what quitting has to ask
	/// about. An unedited one needs no answer: the ciphertext is on disk.
	public func edited() -> [(root: URL, file: URL, buffer: DecryptedBuffer)] {
		parked.compactMap { key, buffer in
			guard buffer.isEdited else { return nil }
			let parts = key.split(separator: "\u{0}", maxSplits: 1).map(String.init)
			guard parts.count == 2 else { return nil }
			return (URL(fileURLWithPath: parts[0]), URL(fileURLWithPath: parts[1]), buffer)
		}
		.sorted { $0.file.path < $1.file.path }
	}

	public var isEmpty: Bool { parked.isEmpty }
}
