import Foundation

/// What the run dropdown offers, arranged so that a hundred-module build fits.
///
/// **The list is not long by accident; it is a multiplication table printed
/// flat.** Every Maven goal is offered against every module it could run in, so
/// what the menu shows is goals × modules: three goals across a hundred-module
/// reactor is three hundred rows, two hundred and ninety-seven of which say the
/// same three words. Measured on a real reactor the build section ran off the
/// bottom of the screen and under a scroll arrow, and an `NSMenu` cannot be
/// typed at, so there was nothing to do but scroll it.
///
/// So the goal is named once and the module is treated as the second choice it
/// is. `mvn clean` is one row with its modules behind it; Return runs it where
/// `mvn clean` in a terminal would run it, at the reactor root, and the modules
/// are reached by opening the row or by typing one.
///
/// Nothing about discovery changes. This is only what is done with what it
/// found — which is why it is a pure function over configurations and can be
/// asserted about without a window.
public enum RunPicker {
	/// One goal, and every module it was offered in.
	public struct Goal: Equatable, Sendable {
		/// `mvn clean` — the name with no module on it.
		public let name: String
		/// The one that runs at the root, where there is one. This is what
		/// Return on the goal row starts.
		public let atRoot: RunConfiguration?
		/// Every module it was offered in, in the order they were discovered.
		public let inModules: [RunConfiguration]

		/// How many places it can run, counting the root.
		public var places: Int { inModules.count + (atRoot == nil ? 0 : 1) }

		/// What Return on the goal row starts: the root where there is one, and
		/// otherwise the first module — a reactor whose root declares no goals
		/// still has to run somewhere, and refusing would be a row that does
		/// nothing.
		public var whenChosen: RunConfiguration? { atRoot ?? inModules.first }
	}

	/// The rows, in the order they are shown.
	public struct Arrangement: Equatable, Sendable {
		/// Saved configurations and schemes: what somebody wrote down on
		/// purpose, above everything that was merely discovered.
		public var pinned: [RunConfiguration] = []
		/// Discovered entries that exist once — a Makefile goal, a main class.
		public var singles: [RunConfiguration] = []
		/// Discovered entries that exist once per module.
		public var goals: [Goal] = []

		/// How many rows a flat menu would have needed for the same thing.
		public var flatCount: Int {
			pinned.count + singles.count + goals.reduce(0) { $0 + $1.places }
		}

		/// How many it needs now.
		public var rowCount: Int { pinned.count + singles.count + goals.count }
	}

	/// Arranges what discovery found.
	///
	/// - `pinned`: the ones that are not to be folded — launch.json entries,
	///   IntelliJ configurations, Xcode schemes. Passed in rather than decided
	///   here, because which sources count as saved is the window's business
	///   and it already knows.
	/// How many places a goal must have before it is worth folding.
	///
	/// **Folding is for lists long enough to hide their neighbours, and two is
	/// not.** A main class found in two modules folded to one row plus a
	/// keystroke, where two rows would have shown both — and showing both, each
	/// with its module beside it, is precisely the thing the flat menu could not
	/// do: it offered two rows called `run Main` and said nothing about which
	/// was which. At four, a goal never contributes more than three rows to the
	/// list it sits in.
	public static let foldFrom = 4

	public static func arrange(
		_ configurations: [RunConfiguration],
		pinned pinnedNames: Set<String> = [],
		foldFrom: Int = foldFrom
	) -> Arrangement {
		var result = Arrangement()

		// Grouped in two passes rather than one, because the root is discovered
		// *before* its modules: a single pass that decided "no module, so it
		// stands alone" put `mvn clean` in one section and its hundred modules
		// in another, which is the fault this whole type exists to fix, printed
		// twice.
		//
		// Insertion-ordered, because the order goals were discovered in is the
		// order the modules are laid out in and a dictionary would lose it.
		var order: [String] = []
		var groups: [String: [RunConfiguration]] = [:]

		for configuration in configurations {
			if pinnedNames.contains(configuration.name) {
				result.pinned.append(configuration)
				continue
			}
			// Keyed by source as well as name, so a Makefile's `test` and a
			// reactor's `test` are never folded into one another.
			let key = "\(configuration.source.rawValue)\u{0}\(configuration.goalName)"
			if groups[key] == nil { order.append(key) }
			groups[key, default: []].append(configuration)
		}

		for key in order {
			guard let found = groups[key] else { continue }
			// Few enough places to show outright — including the commonest case
			// of all, exactly one — stay rows. Each keeps its module, which is
			// what tells two of them apart.
			guard found.count >= foldFrom else {
				result.singles.append(contentsOf: found)
				continue
			}
			result.goals.append(Goal(
				name: found[0].goalName,
				atRoot: found.first { $0.module == nil },
				inModules: found.filter { $0.module != nil }
			))
		}
		return result
	}

	// MARK: - Filtering

	/// One row a query matched.
	public struct Match: Equatable, Sendable {
		public let configuration: RunConfiguration
		/// The goal it came out of, when it was reached by its module rather
		/// than by its own name — so the row can say `mvn clean` and put
		/// `client/ui` beside it.
		public let goal: String?
	}

	/// What a query finds, best first.
	///
	/// **Filtering flattens the folding**, exactly as the branch list flattens
	/// its folders. Somebody who has typed `client/ui` is looking at four rows
	/// and does not need one of them to be a goal that must be opened before it
	/// will say anything: they have already said which module they mean.
	public static func matches(
		for query: String, in arrangement: Arrangement, limit: Int = 20
	) -> [Match] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty, limit > 0 else { return [] }
		var scored: [(match: Match, rank: FileMatching.Rank, tier: Int)] = []

		func consider(_ configuration: RunConfiguration, goal: String?, tier: Int) {
			// Ranked on the name, then on the module — the same two-tier idea
			// the file search uses, where a hit in the thing's own name beats a
			// hit in the path above it.
			if let rank = FileMatching.rank(of: configuration.goalName, for: trimmed) {
				scored.append((Match(configuration: configuration, goal: goal), rank, tier))
				return
			}
			guard let module = configuration.module,
			      let rank = FileMatching.rank(of: module, for: trimmed)
			else { return }
			scored.append((Match(configuration: configuration, goal: goal), rank, tier + 1))
		}

		for configuration in arrangement.pinned { consider(configuration, goal: nil, tier: 0) }
		for configuration in arrangement.singles { consider(configuration, goal: nil, tier: 1) }
		for goal in arrangement.goals {
			if let root = goal.atRoot { consider(root, goal: nil, tier: 1) }
			for configuration in goal.inModules {
				consider(configuration, goal: goal.name, tier: 1)
			}
		}
		scored.sort { left, right in
			if left.tier != right.tier { return left.tier < right.tier }
			if left.rank != right.rank { return left.rank < right.rank }
			// Named order for the last tie, so the same query gives the same
			// list twice running and `module9` sorts before `module10`.
			return left.match.configuration.name
				.localizedStandardCompare(right.match.configuration.name) == .orderedAscending
		}
		return scored.prefix(limit).map(\.match)
	}
}
