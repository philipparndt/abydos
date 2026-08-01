import Foundation

/// Where you have been, so you can get back.
///
/// One list with a cursor in it, the way a browser works: going back walks
/// towards older places, and jumping somewhere new from the middle throws away
/// the forward tail. Anything else — a stack of "back" entries and a separate
/// stack of "forward" ones — ends up disagreeing with itself the first time
/// somebody goes back three times and then follows a definition.
public struct NavigationHistory: Equatable, Sendable {
	public struct Place: Equatable, Sendable {
		public let file: URL
		public let line: Int

		public init(file: URL, line: Int) {
			self.file = file.standardizedFileURL
			self.line = max(1, line)
		}
	}

	/// Enough to get back through an afternoon's wandering, not enough to keep
	/// a file alive in memory forever.
	public static let limit = 60

	/// How far apart two lines in the same file have to be to count as two
	/// places. Scrolling a few lines while reading is not navigation.
	public static let sameNeighbourhood = 8

	private(set) var places: [Place] = []
	/// Index of where we are now, or nil when nothing has been recorded.
	private(set) var cursor: Int?

	public init() {}

	public var current: Place? {
		guard let cursor, places.indices.contains(cursor) else { return nil }
		return places[cursor]
	}

	public var canGoBack: Bool { (cursor ?? 0) > 0 }
	public var canGoForward: Bool {
		guard let cursor else { return false }
		return cursor + 1 < places.count
	}

	/// Records arriving somewhere.
	///
	/// Returning to where you already are records nothing: opening the same
	/// file twice, or clicking a line you are already on, should not make the
	/// back button take two presses.
	public mutating func record(_ place: Place) {
		if let current, Self.isSamePlace(current, place) {
			// Keep the newer line: reading down a file and then jumping away
			// should bring you back to where you were reading, not to where
			// you entered.
			places[cursor!] = place
			return
		}

		if let cursor, cursor + 1 < places.count {
			// A new jump from the middle of the history ends the future that
			// was there.
			places.removeSubrange((cursor + 1)...)
		}

		places.append(place)
		if places.count > Self.limit { places.removeFirst(places.count - Self.limit) }
		cursor = places.count - 1
	}

	@discardableResult
	public mutating func back() -> Place? {
		guard canGoBack, let cursor else { return nil }
		self.cursor = cursor - 1
		return places[cursor - 1]
	}

	@discardableResult
	public mutating func forward() -> Place? {
		guard canGoForward, let cursor else { return nil }
		self.cursor = cursor + 1
		return places[cursor + 1]
	}

	/// Drops everywhere in a file, for one that was deleted or renamed.
	public mutating func forget(file: URL) {
		let target = file.standardizedFileURL
		let remaining = places.filter { $0.file != target }
		guard remaining.count != places.count else { return }
		places = remaining
		cursor = places.isEmpty ? nil : min(cursor ?? 0, places.count - 1)
	}

	static func isSamePlace(_ one: Place, _ other: Place) -> Bool {
		one.file == other.file && abs(one.line - other.line) < sameNeighbourhood
	}
}
