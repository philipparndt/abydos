import Foundation

/// A profile arranged for looking at.
///
/// Two views of the same samples, because they answer different questions.
/// The tree says where the time went — which call path, through which
/// middle — and the table says which functions are expensive wherever they
/// are called from. Neither is derivable from the other by eye.
public struct FlameGraph: Equatable, Sendable {
	public final class Node: @unchecked Sendable {
		public let name: String
		/// Everything spent in this frame and everything it called.
		public internal(set) var value: Int64
		/// Spent in this frame itself.
		public internal(set) var selfValue: Int64
		public internal(set) var children: [Node]

		init(name: String, value: Int64 = 0, selfValue: Int64 = 0, children: [Node] = []) {
			self.name = name
			self.value = value
			self.selfValue = selfValue
			self.children = children
		}

		/// How deep the tree goes from here, counting this node.
		public var depth: Int {
			1 + (children.map(\.depth).max() ?? 0)
		}
	}

	/// One function, wherever it was called from.
	public struct Function: Equatable, Sendable {
		public let name: String
		/// Time in this function itself.
		public let flat: Int64
		/// Time in it and everything it called, counted once per stack.
		public let cumulative: Int64

		public init(name: String, flat: Int64, cumulative: Int64) {
			self.name = name
			self.flat = flat
			self.cumulative = cumulative
		}
	}

	public let root: Node
	public let functions: [Function]
	/// What the numbers are: `nanoseconds`, `bytes`, `count`.
	public let unit: String
	public var total: Int64 { root.value }

	public static func == (one: FlameGraph, other: FlameGraph) -> Bool {
		one.unit == other.unit && one.functions == other.functions && one.total == other.total
	}

	/// Builds both views from a profile.
	public static func build(from profile: PprofProfile, valueIndex: Int? = nil) -> FlameGraph {
		let index = valueIndex ?? profile.defaultValueIndex
		let root = Node(name: "all")

		var flat: [String: Int64] = [:]
		var cumulative: [String: Int64] = [:]

		for sample in profile.samples {
			guard sample.values.indices.contains(index) else { continue }
			let value = sample.values[index]
			guard value != 0 else { continue }

			let stack = profile.stack(of: sample)
			guard !stack.isEmpty else { continue }

			root.value += value
			var node = root
			for name in stack {
				if let existing = node.children.first(where: { $0.name == name }) {
					existing.value += value
					node = existing
				} else {
					let child = Node(name: name, value: value)
					node.children.append(child)
					node = child
				}
			}
			node.selfValue += value

			// Flat belongs to the leaf; cumulative to every frame present, but
			// only once each — a recursive stack would otherwise count the
			// same time once per level.
			flat[stack[stack.count - 1], default: 0] += value
			for name in Set(stack) {
				cumulative[name, default: 0] += value
			}
		}

		sortByValue(root)

		let names = Set(flat.keys).union(cumulative.keys)
		let functions = names
			.map { Function(name: $0, flat: flat[$0] ?? 0, cumulative: cumulative[$0] ?? 0) }
			.sorted {
				// Heaviest first, and by name where two are equal so the table
				// does not reshuffle between identical profiles.
				($0.flat, $0.cumulative, $1.name) > ($1.flat, $1.cumulative, $0.name)
			}

		let unit = profile.valueTypes.indices.contains(index)
			? profile.valueTypes[index].unit
			: ""
		return FlameGraph(root: root, functions: functions, unit: unit)
	}

	/// Widest first, so the eye reads a flame graph left to right in order of
	/// cost rather than in the order samples happened to arrive.
	private static func sortByValue(_ node: Node) {
		node.children.sort { ($0.value, $1.name) > ($1.value, $0.name) }
		for child in node.children { sortByValue(child) }
	}
}

/// Numbers as a profiler shows them.
public enum ProfileValue {
	/// `1.25s`, `340ms`, `12.4MB` — the shortest form that is still exact
	/// enough to compare two rows by eye.
	public static func format(_ value: Int64, unit: String) -> String {
		switch unit {
		case "nanoseconds":
			return duration(nanoseconds: Double(value))
		case "bytes":
			return bytes(Double(value))
		case "count", "":
			return "\(value)"
		default:
			return "\(value) \(unit)"
		}
	}

	static func duration(nanoseconds: Double) -> String {
		let scales: [(Double, String)] = [
			(1_000_000_000, "s"), (1_000_000, "ms"), (1_000, "µs"),
		]
		for (divisor, suffix) in scales where nanoseconds >= divisor {
			return trimmed(nanoseconds / divisor) + suffix
		}
		return "\(Int(nanoseconds))ns"
	}

	static func bytes(_ value: Double) -> String {
		let scales: [(Double, String)] = [
			(1_073_741_824, "GB"), (1_048_576, "MB"), (1_024, "kB"),
		]
		for (divisor, suffix) in scales where value >= divisor {
			return trimmed(value / divisor) + suffix
		}
		return "\(Int(value))B"
	}

	/// Two significant decimals below ten, one below a hundred, none above:
	/// enough to tell rows apart without a column of noise.
	private static func trimmed(_ value: Double) -> String {
		let places = value < 10 ? 2 : (value < 100 ? 1 : 0)
		var text = String(format: "%.\(places)f", value)
		if text.contains(".") {
			while text.hasSuffix("0") { text.removeLast() }
			if text.hasSuffix(".") { text.removeLast() }
		}
		return text
	}

	/// A share of the whole, as a profiler writes it.
	public static func percentage(_ value: Int64, of total: Int64) -> String {
		guard total > 0 else { return "0%" }
		let share = Double(value) / Double(total) * 100
		if share >= 10 { return String(format: "%.0f%%", share) }
		if share >= 1 { return String(format: "%.1f%%", share) }
		return share > 0 ? "<1%" : "0%"
	}
}
