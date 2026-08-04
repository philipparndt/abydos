import Foundation

/// Which thing the play button is pointed at.
///
/// There are two lists it can come from — the launch configurations a project
/// has, and a Makefile goal somebody picked that is not one of them — and one
/// name saying which is chosen. Working that out in two places is how the strip
/// came to say one thing while the button did another: the display fell back to
/// "the first configuration" whenever the chosen name was not among them, which
/// is exactly the case where a make goal had been chosen.
public enum RunSelection {
	public enum Target: Equatable, Sendable {
		/// One of the project's launch configurations, by name.
		case configuration(String)
		/// A Makefile goal, run as make runs it.
		case make(String)
		/// Nothing to run, and nothing to say.
		case none
	}

	/// Resolves the selection from what there is and what was chosen.
	///
	/// - Parameters:
	///   - configurations: the names of the project's launch configurations,
	///     in the order they are offered.
	///   - makeRun: the name of the Makefile goal chosen from the menu, if one
	///     was.
	///   - selected: the name last chosen, from either list.
	public static func resolve(
		configurations: [String],
		makeRun: String?,
		selected: String?
	) -> Target {
		if let selected {
			if configurations.contains(selected) { return .configuration(selected) }
			// A goal only counts while it is the one that was chosen: a stale
			// make run must not win over a configuration somebody has since
			// picked.
			if let makeRun, makeRun == selected { return .make(makeRun) }
		}
		if let first = configurations.first { return .configuration(first) }
		if let makeRun { return .make(makeRun) }
		return .none
	}

	/// What the run control should show.
	public static func displayName(
		configurations: [String],
		makeRun: String?,
		selected: String?
	) -> String? {
		switch resolve(configurations: configurations, makeRun: makeRun, selected: selected) {
		case let .configuration(name): return name
		case let .make(name):          return name
		case .none:                    return nil
		}
	}
}
