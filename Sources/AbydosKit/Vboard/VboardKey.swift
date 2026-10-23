import Foundation
import Security

/// The link key of a private vboard board: what encrypts it on the server and
/// what opens it for whoever holds the link.
///
/// One is made for every board tab and never for anything else. vboard's
/// private boards are encrypted at rest with a content key the server keeps
/// only wrapped by this one, so a key that outlived its tab — written into the
/// settings, a log line, a crash report — would be a way into a board that was
/// supposed to have ended. That is why this is not `Codable`, and why its
/// `description` says nothing: a stray `"\(key)"` in a log message is the
/// likeliest way for it to leave memory, and it would do so silently.
///
/// The format is vboard's: 32 random bytes as base64url without padding,
/// 43 characters. A malformed key counts on the server as no key at all, and
/// the answer to no key is the same 404 as a board that does not exist, so a
/// wrong format would look exactly like a deleted board.
public struct VboardKey: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
	/// The key as it goes into `X-Board-Key` and a link's fragment.
	public let encoded: String

	/// A new key from the system's random source.
	///
	/// `SecRandomCopyBytes` rather than `SystemRandomNumberGenerator` only so
	/// that the source is the one the platform documents for key material; both
	/// read the same generator today.
	public static func make() -> VboardKey {
		var bytes = [UInt8](repeating: 0, count: 32)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		precondition(status == errSecSuccess, "the system's random source refused: \(status)")
		return VboardKey(bytes: bytes)
	}

	init(bytes: [UInt8]) {
		encoded = Data(bytes).base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	public var description: String { "VboardKey(…)" }
	public var debugDescription: String { description }
}

/// A board id of vboard's own shape, made here so the file's item ids survive.
///
/// The import that takes a board id is the one that keeps the ids in the file;
/// without one, every item was given a new id on every open. vboard wants `b_`
/// and sixteen lowercase hex digits and answers 400 to anything else.
public enum VboardBoardID {
	public static func make() -> String {
		var bytes = [UInt8](repeating: 0, count: 8)
		_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		return "b_" + bytes.map { String(format: "%02x", $0) }.joined()
	}

	public static func isValid(_ id: String) -> Bool {
		id.count == 18 && id.hasPrefix("b_")
			&& id.dropFirst(2).allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
	}
}

/// Where a board is, for the web view and for colleagues.
public enum VboardLink {
	/// The page for a board, with the key in the fragment.
	///
	/// The fragment because a browser never sends it: the key reaches the server
	/// only in the `X-Board-Key` header the page sends itself, and never lands in
	/// a request line or an access log. vboard refuses a key in a query string.
	public static func board(server: URL, id: String, key: VboardKey) -> URL {
		var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
		components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path)
			+ "/b/" + id
		components.query = nil
		components.fragment = "k=" + key.encoded
		return components.url!
	}
}
