import Foundation

/// Completed lines, kept in a ring.
///
/// A terminal only ever appends here and reads a window back out. Held in a
/// plain array, every line of output past the limit shifted the whole buffer
/// down by one — five thousand lines moved for each line printed, which cost
/// more than parsing the line did. A ring overwrites the oldest entry instead,
/// which costs nothing.
///
/// Presented as a collection so the places that read it — indexing, counting,
/// the last line, mapping over all of them — did not have to change.
public struct ScrollbackBuffer: RandomAccessCollection, Sendable {
	private var storage: [TerminalLine] = []
	/// Where the oldest line sits in `storage`.
	private var start = 0
	public private(set) var count = 0
	public private(set) var capacity: Int

	public init(capacity: Int) {
		self.capacity = Swift.max(0, capacity)
	}

	public var startIndex: Int { 0 }
	public var endIndex: Int { count }

	public subscript(index: Int) -> TerminalLine {
		get {
			precondition(index >= 0 && index < count, "scrollback index out of range")
			return storage[(start + index) % storage.count]
		}
		set {
			precondition(index >= 0 && index < count, "scrollback index out of range")
			storage[(start + index) % storage.count] = newValue
		}
	}

	/// Adds a line, returning the one it displaced once the buffer is full.
	///
	/// The displaced line is handed back rather than dropped so the caller can
	/// reuse its storage; a scroll needs a blank line at the bottom anyway, and
	/// this one is exactly the right size and no longer referenced.
	@discardableResult
	public mutating func append(_ line: TerminalLine) -> TerminalLine? {
		guard capacity > 0 else { return line }

		// A gap left by popLast is filled before anything is displaced: shrinking
		// the window and growing it again must not cost history.
		if count < storage.count {
			storage[(start + count) % storage.count] = line
			count += 1
			return nil
		}

		// Room to grow. The ring cannot have wrapped yet, so the logical end is
		// the end of the storage.
		if storage.count < capacity {
			storage.append(line)
			count += 1
			return nil
		}

		let evicted = storage[start]
		storage[start] = line
		start = (start + 1) % storage.count
		return evicted
	}

	public mutating func popLast() -> TerminalLine? {
		guard count > 0 else { return nil }
		let line = self[count - 1]
		count -= 1
		return line
	}

	public mutating func removeAll() {
		storage.removeAll(keepingCapacity: true)
		start = 0
		count = 0
	}

	/// Changes how much history is kept, dropping the oldest lines if it shrinks.
	public mutating func setCapacity(_ newCapacity: Int) {
		let newCapacity = Swift.max(0, newCapacity)
		guard newCapacity != capacity else { return }

		// Straightened out rather than rotated in place: this happens when a
		// setting changes, not while output is arriving.
		var kept = [TerminalLine]()
		let dropped = Swift.max(0, count - newCapacity)
		kept.reserveCapacity(count - dropped)
		for index in dropped..<count { kept.append(self[index]) }

		capacity = newCapacity
		storage = kept
		start = 0
		count = kept.count
	}
}
