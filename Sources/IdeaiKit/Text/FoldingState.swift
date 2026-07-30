import Foundation

/// Tracks which fold regions are collapsed and maps between document lines and
/// the lines actually on screen.
///
/// The view only ever asks about the ~60 lines in the viewport, but those
/// queries happen on every scroll frame, so both directions are binary searches
/// over a prefix-summed table rather than walks over the fold list.
public struct FoldingState {
	/// Every foldable region in the document, keyed by start line.
	public private(set) var available: [Int: FoldRange] = [:]
	/// Start lines of the regions currently collapsed.
	public private(set) var collapsed: Set<Int> = []

	/// Merged, non-overlapping hidden line intervals, ascending.
	private var hidden: [(start: Int, end: Int)] = []
	/// hiddenBefore[i] = number of lines hidden before `hidden[i].start`.
	private var hiddenBefore: [Int] = []
	private var totalHidden = 0

	public init() {}

	public var hasCollapsedRegions: Bool { !collapsed.isEmpty }

	// MARK: - Regions

	/// Replaces the known fold regions, keeping collapse state for regions that
	/// still exist so editing does not silently unfold the document.
	public mutating func setAvailable(_ ranges: [FoldRange]) {
		available = Dictionary(ranges.map { ($0.startLine, $0) }, uniquingKeysWith: { a, b in
			a.endLine >= b.endLine ? a : b
		})
		collapsed = collapsed.filter { available[$0] != nil }
		rebuild()
	}

	public func foldRange(startingAt line: Int) -> FoldRange? { available[line] }

	public func isFoldable(line: Int) -> Bool { available[line] != nil }

	public func isCollapsed(line: Int) -> Bool { collapsed.contains(line) }

	// MARK: - Collapsing

	public mutating func toggle(line: Int) {
		guard available[line] != nil else { return }
		if collapsed.contains(line) {
			collapsed.remove(line)
		} else {
			collapsed.insert(line)
		}
		rebuild()
	}

	public mutating func collapseAll() {
		collapsed = Set(available.keys)
		rebuild()
	}

	public mutating func expandAll() {
		collapsed.removeAll()
		rebuild()
	}

	/// Expands whatever hides `line`, used when jumping to a folded location.
	public mutating func reveal(line: Int) {
		var changed = false
		for start in collapsed {
			guard let range = available[start], line > range.startLine, line <= range.endLine else { continue }
			collapsed.remove(start)
			changed = true
		}
		if changed { rebuild() }
	}

	// MARK: - Line mapping

	/// Merges collapsed regions into disjoint intervals and prefix-sums them.
	///
	/// Nested folds overlap, so intervals must be merged — counting each fold's
	/// lines separately would double-count the inner ones and skew every
	/// subsequent line lookup.
	private mutating func rebuild() {
		guard !collapsed.isEmpty else {
			hidden = []
			hiddenBefore = []
			totalHidden = 0
			return
		}

		// The fold's first line stays visible; the rest is hidden.
		let intervals = collapsed
			.compactMap { available[$0] }
			.map { (start: $0.startLine + 1, end: $0.endLine) }
			.filter { $0.start <= $0.end }
			.sorted { $0.start < $1.start }

		var merged: [(start: Int, end: Int)] = []
		for interval in intervals {
			if var last = merged.last, interval.start <= last.end + 1 {
				last.end = max(last.end, interval.end)
				merged[merged.count - 1] = last
			} else {
				merged.append(interval)
			}
		}

		hidden = merged
		hiddenBefore = []
		hiddenBefore.reserveCapacity(merged.count)
		var running = 0
		for interval in merged {
			hiddenBefore.append(running)
			running += interval.end - interval.start + 1
		}
		totalHidden = running
	}

	public func isHidden(line: Int) -> Bool {
		guard !hidden.isEmpty else { return false }
		var low = 0, high = hidden.count - 1
		while low <= high {
			let mid = (low + high) / 2
			if line < hidden[mid].start {
				high = mid - 1
			} else if line > hidden[mid].end {
				low = mid + 1
			} else {
				return true
			}
		}
		return false
	}

	public func visibleLineCount(documentLineCount: Int) -> Int {
		max(1, documentLineCount - totalHidden)
	}

	/// Document line shown at a given visual row.
	public func documentLine(forVisualLine visual: Int) -> Int {
		guard !hidden.isEmpty else { return visual }

		// Find the last interval that begins at or before the target once the
		// lines hidden ahead of it are accounted for.
		var low = 0
		var high = hidden.count - 1
		var result = visual
		while low <= high {
			let mid = (low + high) / 2
			let visualAtStart = hidden[mid].start - hiddenBefore[mid]
			if visualAtStart <= visual {
				result = visual + hiddenBefore[mid] + (hidden[mid].end - hidden[mid].start + 1)
				low = mid + 1
			} else {
				high = mid - 1
			}
		}
		return result
	}

	/// Visual row for a document line. A hidden line reports the row of the
	/// collapsed header that stands in for it.
	public func visualLine(forDocumentLine line: Int) -> Int {
		guard !hidden.isEmpty else { return line }

		var low = 0
		var high = hidden.count - 1
		var hiddenAhead = 0
		var clamped = line
		while low <= high {
			let mid = (low + high) / 2
			if hidden[mid].start <= line {
				if line <= hidden[mid].end {
					// Inside a collapsed region: report its header line.
					hiddenAhead = hiddenBefore[mid]
					clamped = hidden[mid].start - 1
					break
				}
				hiddenAhead = hiddenBefore[mid] + (hidden[mid].end - hidden[mid].start + 1)
				low = mid + 1
			} else {
				high = mid - 1
			}
		}
		return max(0, clamped - hiddenAhead)
	}
}
