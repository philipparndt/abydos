import Foundation

/// The environment a project asks for, and whether it is applied.
///
/// **Environment variables are code.** `SOPS_AGE_KEY_CMD` is a command sops
/// runs to fetch a key; `GIT_SSH_COMMAND` and `GIT_EXTERNAL_DIFF` are commands
/// git runs; `DYLD_INSERT_LIBRARIES` and `LD_PRELOAD` choose what is loaded
/// into a process that was never asked. A project's `env` block, its
/// devcontainer's `containerEnv` and its `.envrc` are arbitrary execution
/// wearing the clothes of configuration — which is why an untrusted project's
/// variables reach nothing at all.
///
/// **Dropped, not filtered.** An allow-list of safe names is a list somebody
/// has to keep correct forever, and the dangerous ones do not look dangerous:
/// `SOPS_AGE_KEY_CMD` reads like configuration and is a command. So the rule is
/// the blunt one, which is the only kind that stays true.
///
/// This is the one place that decides, so that a new caller assembling a
/// project's environment has one function to go through rather than a rule to
/// remember. It takes the answer rather than asking, because the store is the
/// window's and this is the engine.
public enum ProjectEnvironment {
	/// What of a project's own environment may be applied.
	///
	/// - Parameter supplied: the variables the project asked for — a
	///   `launch.json` `env`, a run configuration's own, a devcontainer's.
	/// - Parameter trusted: whether the project may run its own code at all.
	public static func allowed(
		_ supplied: [String: String],
		trusted: Bool
	) -> [String: String] {
		trusted ? supplied : [:]
	}

	/// What is said when a project's variables were dropped, for a caller that
	/// has somewhere to say it. Nil when there was nothing to drop, so a
	/// trusted project and a project with no variables both stay quiet.
	public static func dropped(
		_ supplied: [String: String],
		trusted: Bool
	) -> String? {
		guard !trusted, !supplied.isEmpty else { return nil }
		let names = supplied.keys.sorted().joined(separator: ", ")
		return "\(names) came from the project and were not applied: it is not trusted, "
			+ "and a variable is a command in every case that matters."
	}
}
