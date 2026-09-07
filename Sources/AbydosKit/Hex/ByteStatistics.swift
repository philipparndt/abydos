import Foundation

/// What each block of a file is made of, from one pass over it.
///
/// The minimap, the entropy curve and the "likely compressed or encrypted"
/// note all want the same thing — for each stretch of the file, how random its
/// bytes are and what kind they are — and a strip two hundred pixels tall
/// cannot show a million rows anyway. So the file is cut into about four
/// thousand blocks whatever its size, sixteen bytes for a small file and a
/// quarter of a megabyte for a gigabyte, and one sequential read produces a
/// table a few hundred kilobytes long that everything else draws from. Nothing
/// is computed twice, and nothing is computed on the main thread.
public struct ByteStatistics: Sendable, Equatable {
	/// One block's numbers.
	public struct Block: Sendable, Equatable {
		/// Shannon entropy, in bits a byte, from 0 to 8.
		public let entropy: Double
		public let zero: Int
		public let printable: Int
		public let control: Int
		public let high: Int

		public var length: Int { zero + printable + control + high }

		/// The block's numbers from its bytes. A pure function, so a block is
		/// recomputed by calling it again over the bytes an edit changed.
		public init(of bytes: Data) {
			var histogram = Histogram()
			histogram.add(bytes)
			self.init(histogram)
		}

		init(_ histogram: Histogram) {
			entropy = histogram.entropy
			zero = histogram.counts[0]
			printable = histogram.counts[0x20..<0x7F].reduce(0, +)
			high = histogram.counts[0x80...].reduce(0, +)
			control = histogram.total - zero - printable - high
		}
	}

	/// How often each byte value occurred. Kept only while a block or a
	/// group is open: a table of four thousand of these would be eight
	/// megabytes, and the numbers the views want fit in a `Block`.
	struct Histogram {
		var counts = [Int](repeating: 0, count: 256)
		var total = 0

		mutating func add(_ bytes: Data) {
			bytes.withUnsafeBytes { buffer in
				for byte in buffer { counts[Int(byte)] += 1 }
			}
			total += bytes.count
		}

		/// Shannon entropy in bits a byte. Sixteen bytes cannot reach eight
		/// — with fewer samples than values the estimate is low however
		/// random the bytes — which is why the note reads groups, not blocks.
		var entropy: Double {
			guard total > 0 else { return 0 }
			let scale = 1.0 / Double(total)
			var entropy = 0.0
			for count in counts where count > 0 {
				let probability = Double(count) * scale
				entropy -= probability * log2(probability)
			}
			return min(8, max(0, entropy))
		}
	}

	/// A run of blocks that is almost certainly not plain data.
	public struct Note: Sendable, Equatable {
		public let range: Range<Int>
		public let entropy: Double

		public var said: String {
			String(
				format: "0x%llX–0x%llX is likely compressed or encrypted (%.2f bits a byte)",
				range.lowerBound, range.upperBound - 1, entropy
			)
		}
	}

	/// About this many blocks, however large the file.
	public static let aimedBlocks = 4096
	/// Above this a block is named as compressed or encrypted. Text is under
	/// five, code under seven, and DEFLATE and every cipher sit above 7.9;
	/// 7.5 is inside the gap.
	public static let highEntropy = 7.5

	/// A group is the smallest stretch an entropy is trusted over. Four
	/// thousand samples over two hundred and fifty-six values reads noise as
	/// 7.95 and text as under five; sixteen samples read everything as under
	/// four. The curve and the minimap show blocks, which may be that small;
	/// the note reads groups, which never are.
	public static let groupBytes = 4096

	/// The window the curve is drawn from. A block may be sixteen bytes, and
	/// sixteen samples over two hundred and fifty-six values read as under
	/// four bits however random they are — a curve of those sat at 3.9 over
	/// a file the note called 7.86. A kilobyte reads noise as about 7.8 and
	/// text as about 4.5, which is the difference the curve is for.
	public static let windowBytes = 1024

	public let blockSize: Int
	public let count: Int
	/// Nil until the pass has reached it.
	public private(set) var blocks: [Block?]
	/// Entropy per group of `blocksPerGroup` blocks, nil until reached.
	public private(set) var groups: [Double?]
	/// Entropy over the window ending at each block, nil until reached: what
	/// the curve, the minimap's entropy mode and the hover read.
	public private(set) var windows: [Double?]

	public var blocksPerGroup: Int { max(1, Self.groupBytes / blockSize) }
	public var blocksPerWindow: Int { max(1, Self.windowBytes / blockSize) }

	public init(count: Int, blockSize: Int? = nil) {
		self.count = count
		let size = blockSize ?? Self.blockSize(for: count)
		self.blockSize = size
		let blockCount = count == 0 ? 0 : (count + size - 1) / size
		blocks = Array(repeating: nil, count: blockCount)
		let perGroup = max(1, Self.groupBytes / size)
		groups = Array(repeating: nil, count: (blockCount + perGroup - 1) / perGroup)
		windows = Array(repeating: nil, count: blockCount)
	}

	/// The entropy to draw for a block: its window's, or its own until the
	/// window has been delivered.
	public func curve(at index: Int) -> Double? {
		guard blocks.indices.contains(index) else { return nil }
		return windows[index] ?? blocks[index]?.entropy
	}

	/// The bytes a block's window covers: the window ends at the block and
	/// reaches back `blocksPerWindow` blocks, or to the start of the file.
	public func windowRange(ofBlock index: Int) -> Range<Int> {
		let first = max(0, index - blocksPerWindow + 1)
		return range(ofBlock: first).lowerBound..<range(ofBlock: index).upperBound
	}

	public func range(ofGroup index: Int) -> Range<Int> {
		let start = index * blocksPerGroup * blockSize
		return start..<min(count, start + blocksPerGroup * blockSize)
	}

	/// A power of two, at least sixteen, giving about `aimedBlocks` blocks.
	public static func blockSize(for count: Int, aiming blocks: Int = aimedBlocks) -> Int {
		var size = 16
		while count / size > blocks { size *= 2 }
		return size
	}

	public var isComplete: Bool { !blocks.contains { $0 == nil } }
	public var completedBlocks: Int { blocks.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }

	public func range(ofBlock index: Int) -> Range<Int> {
		let start = index * blockSize
		return start..<min(count, start + blockSize)
	}

	/// The blocks touching a byte range.
	public func blockIndices(touching range: Range<Int>) -> Range<Int> {
		guard !blocks.isEmpty else { return 0..<0 }
		let first = max(0, min(blocks.count - 1, range.lowerBound / blockSize))
		let last = max(first, min(blocks.count - 1, max(range.lowerBound, range.upperBound - 1) / blockSize))
		return first..<(last + 1)
	}

	public mutating func set(_ block: Block, at index: Int) {
		guard blocks.indices.contains(index) else { return }
		blocks[index] = block
	}

	public mutating func set(_ delivery: Delivery) {
		set(delivery.block, at: delivery.index)
		if windows.indices.contains(delivery.index) { windows[delivery.index] = delivery.window }
		if let group = delivery.group, groups.indices.contains(group.index) {
			groups[group.index] = group.entropy
		}
	}

	/// What an edit makes stale. A same-size edit is the blocks it touched;
	/// an edit that moved the bytes after it is everything from there on,
	/// since every later block now holds different bytes.
	public mutating func invalidate(_ range: Range<Int>, delta: Int) -> Range<Int> {
		let stale: Range<Int>
		if delta == 0 {
			stale = blockIndices(touching: range)
		} else {
			let from = blockIndices(touching: range).lowerBound
			stale = from..<blocks.count
		}
		for index in stale { blocks[index] = nil }
		// A stale block is a stale group, and the pass recomputes a group
		// from its first block, so what goes back is widened to group edges.
		let firstGroup = stale.lowerBound / blocksPerGroup
		let lastGroup = min(groups.count, (max(stale.lowerBound, stale.upperBound - 1)) / blocksPerGroup + 1)
		for index in firstGroup..<lastGroup { groups[index] = nil }
		let widened = (firstGroup * blocksPerGroup)..<min(blocks.count, lastGroup * blocksPerGroup)
		for index in widened {
			blocks[index] = nil
			windows[index] = nil
		}
		return widened
	}

	/// Runs of high-entropy groups. A group shorter than a kilobyte — the
	/// tail of a file, or a tiny file — is not judged: with too few samples
	/// the estimate says nothing either way.
	public var notes: [Note] {
		var notes: [Note] = []
		var runStart: Int?
		var runEntropy = 0.0
		var runGroups = 0
		func close(at end: Int) {
			defer { runStart = nil; runEntropy = 0; runGroups = 0 }
			guard let start = runStart, runGroups >= 1 else { return }
			notes.append(Note(
				range: range(ofGroup: start).lowerBound..<range(ofGroup: end - 1).upperBound,
				entropy: runEntropy / Double(runGroups)
			))
		}
		for (index, entropy) in groups.enumerated() {
			if let entropy, entropy >= Self.highEntropy, range(ofGroup: index).count >= 1024 {
				if runStart == nil { runStart = index }
				runEntropy += entropy
				runGroups += 1
			} else {
				close(at: index)
			}
		}
		close(at: groups.count)
		return notes
	}

	// MARK: - The pass

	/// One block computed and where it goes — and, when it was the last of
	/// its group, the group's entropy.
	public struct Delivery: Sendable, Equatable {
		public let index: Int
		public let block: Block
		/// Entropy over the window ending at this block.
		public let window: Double
		public let group: Group?

		public struct Group: Sendable, Equatable {
			public let index: Int
			public let entropy: Double
		}
	}

	/// Computes `indices` over the snapshot, in order, off the main thread,
	/// and ends when cancelled. The whole file is `0..<blocks.count`; after an
	/// edit it is what `invalidate` returned, which begins on a group edge.
	public static func pass(
		over snapshot: ByteDocument.Snapshot,
		blockSize: Int,
		indices: Range<Int>
	) -> AsyncStream<Delivery> {
		AsyncStream { continuation in
			let task = Task.detached(priority: .utility) {
				walk(snapshot, blockSize: blockSize, indices: indices) { delivery in
					continuation.yield(delivery)
					return !Task.isCancelled
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// The whole table at once, for a test and for a file small enough that
	/// waiting is invisible.
	public static func computed(over snapshot: ByteDocument.Snapshot, blockSize: Int? = nil) -> ByteStatistics {
		var table = ByteStatistics(count: snapshot.count, blockSize: blockSize)
		walk(snapshot, blockSize: table.blockSize, indices: table.blocks.indices) { delivery in
			table.set(delivery)
			return true
		}
		return table
	}

	/// The pass itself: one histogram per block, folded into one per group
	/// while the group is open. `deliver` returns false to stop.
	static func walk(
		_ snapshot: ByteDocument.Snapshot,
		blockSize: Int,
		indices: Range<Int>,
		deliver: (Delivery) -> Bool
	) {
		let perGroup = max(1, groupBytes / blockSize)
		let perWindow = max(1, windowBytes / blockSize)
		let lastBlock = snapshot.count == 0 ? -1 : (snapshot.count - 1) / blockSize
		var group = Histogram()

		// The window is a running sum of the last `perWindow` block
		// histograms; the ring holds them so the oldest can be taken out. A
		// pass that starts mid-file — after an edit — warms the ring with the
		// blocks before it, so its first windows are whole.
		var window = Histogram()
		var ring: [Histogram] = []
		func push(_ histogram: Histogram) {
			ring.append(histogram)
			for value in 0..<256 { window.counts[value] += histogram.counts[value] }
			window.total += histogram.total
			if ring.count > perWindow {
				let gone = ring.removeFirst()
				for value in 0..<256 { window.counts[value] -= gone.counts[value] }
				window.total -= gone.total
			}
		}
		for index in max(0, indices.lowerBound - perWindow + 1)..<indices.lowerBound {
			var histogram = Histogram()
			let start = index * blockSize
			histogram.add(snapshot.bytes(in: start..<min(snapshot.count, start + blockSize)))
			push(histogram)
		}

		for index in indices {
			let start = index * blockSize
			guard start < snapshot.count else { break }
			var histogram = Histogram()
			histogram.add(snapshot.bytes(in: start..<min(snapshot.count, start + blockSize)))
			for value in 0..<256 { group.counts[value] += histogram.counts[value] }
			group.total += histogram.total
			push(histogram)

			var finished: Delivery.Group?
			if (index + 1) % perGroup == 0 || index == lastBlock {
				finished = Delivery.Group(index: index / perGroup, entropy: group.entropy)
				group = Histogram()
			}
			guard deliver(Delivery(index: index, block: Block(histogram), window: window.entropy, group: finished)) else { return }
		}
	}
}
