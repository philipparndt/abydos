import Foundation

/// A board on the server, as its board list gives it: enough to pick one.
public struct VboardBoardSummary: Equatable, Sendable {
	public let id: String
	public let name: String
	/// When anything on it last changed.
	public let updated: Date?

	public init(id: String, name: String, updated: Date?) {
		self.id = id
		self.name = name
		self.updated = updated
	}

	/// The boards in a `{"boards": [...]}` answer that can be opened without a
	/// key. A private board's name is sealed and its board needs the link key,
	/// so it is left out rather than shown as something that cannot be opened.
	static func listed(in json: [String: Any]) -> [VboardBoardSummary] {
		let boards = json["boards"] as? [[String: Any]] ?? []
		return boards.compactMap { board in
			guard let id = board["id"] as? String, board["private"] as? Bool != true else { return nil }
			let name = (board["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
			return VboardBoardSummary(id: id, name: name, updated: (board["updatedAt"] as? String).flatMap(date))
		}
	}

	/// RFC 3339 in UTC, with milliseconds the way vboard writes it, or without.
	private static func date(_ text: String) -> Date? {
		let precise = ISO8601DateFormatter()
		precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
	}
}
