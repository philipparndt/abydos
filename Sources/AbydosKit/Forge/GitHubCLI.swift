import Foundation

/// Running `gh`, which is the only way this program talks to GitHub.
///
/// **A process, like `git`.** `GitRepository.runSync` is already the shape —
/// a `Process`, both pipes drained, an exit code and two strings — and this is
/// the same thing pointed at a different binary. It costs no dependency and no
/// HTTP client.
///
/// **And no credential.** The alternative was the REST API with a token in the
/// Keychain: a secret this program would then own, a refresh to implement, and
/// an SSO dance per Enterprise host. `gh` is authenticated once, per machine, by
/// the person whose account it is; it knows about Enterprise hosts and token
/// refresh; and a token kept here would be a second place for one to leak from
/// and a second thing to expire without saying so.
///
/// The cost of that choice is real and is stated rather than hidden: `gh` must
/// be installed and logged in, and this program can fix neither. So both are
/// first-class answers — `ForgeAbsence` — rather than errors, and neither ever
/// renders as an empty list.
public enum GitHubCLI {
	/// Where `gh` is, or nil when it is not installed.
	///
	/// Through `Executables`, for the reason that type exists: an app launched
	/// from the Finder has `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and `gh` is in
	/// none of the four on any machine. A hard-coded `/opt/homebrew/bin/gh`
	/// would work here and be missing for whoever installed it elsewhere.
	public static func locate() -> String? { Executables.locate("gh") }

	/// Runs `gh` and answers with what it said.
	///
	/// - Parameter root: the work tree to run in. `gh` reads the repository from
	///   the directory it is started in, the same way `git` does, which is why
	///   nothing here passes `--repo` for the ordinary calls.
	public static func run(
		_ arguments: [String],
		in root: URL,
		input: Data? = nil
	) async -> GitRepository.ProcessResult {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: runSync(arguments, in: root, input: input))
			}
		}
	}

	static func runSync(
		_ arguments: [String],
		in root: URL,
		input: Data? = nil
	) -> GitRepository.ProcessResult {
		guard let tool = locate() else {
			return GitRepository.ProcessResult(stdout: "", stderr: "gh is not installed", exitCode: -1)
		}

		let process = Process()
		process.executableURL = URL(fileURLWithPath: tool)
		process.arguments = arguments
		process.currentDirectoryURL = root

		// **Never a prompt.** `gh` asks on a terminal when it wants a login or a
		// confirmation, and this one has no terminal to ask on — so it would
		// wait for an answer nobody can give and the call would hang rather than
		// fail. `GH_PROMPT_DISABLED` makes it say so and exit instead, which is
		// an answer this can turn into a sentence.
		var environment = ProcessInfo.processInfo.environment
		environment["GH_PROMPT_DISABLED"] = "1"
		environment["GH_NO_UPDATE_NOTIFIER"] = "1"
		// Colour in JSON is not JSON.
		environment["NO_COLOR"] = "1"
		environment["CLICOLOR"] = "0"
		process.environment = environment

		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		let stdin = Pipe()
		process.standardInput = stdin

		do {
			try process.run()
		} catch {
			return GitRepository.ProcessResult(stdout: "", stderr: "\(error)", exitCode: -1)
		}

		// Both pipes drained at once and stdin written on a thread of its own —
		// see `ProcessPipes`, and the afternoons the other way round cost.
		let captured = ProcessPipes.drainText(
			process, out: out, err: err, input: input, stdin: stdin
		)
		return GitRepository.ProcessResult(
			stdout: captured.stdout,
			stderr: captured.stderr,
			exitCode: process.terminationStatus
		)
	}

	/// Which `gh` this is, for a driven run to print.
	///
	/// The JSON `gh` answers with is a contract this program does not own, so a
	/// run that decodes something unexpected should be able to say which version
	/// produced it. Without this, a change in `gh`'s output is a mystery rather
	/// than a diagnosis.
	public static func version(in root: URL) async -> String? {
		guard locate() != nil else { return nil }
		let result = await run(["--version"], in: root)
		guard result.exitCode == 0 else { return nil }
		// `gh version 2.62.0 (2024-11-14)` and a second line about upgrades.
		return result.stdout
			.split(separator: "\n")
			.first
			.map { $0.trimmingCharacters(in: .whitespaces) }
	}

	/// Whether a question can be asked here at all, and what stops it if not.
	///
	/// Three checks in the order that makes the answer useful: a `gh` that is
	/// not installed cannot be logged in, and a repository with no GitHub remote
	/// has nothing to ask about however well `gh` is set up.
	public static func availability(in root: URL) async -> ForgeAbsence? {
		guard locate() != nil else { return .cliNotInstalled }

		guard let repository = await GitForge.repository(in: root) else {
			return .noGitHubRemote
		}

		let status = await run(["auth", "status", "--hostname", repository.host], in: root)
		guard status.exitCode == 0 else { return .cliNotLoggedIn(host: repository.host) }

		return nil
	}

	/// Who `gh` is logged in as on a host, which is what "waiting on me" means.
	public static func account(in root: URL, host: String) async -> String? {
		let result = await run(["api", "--hostname", host, "user", "--jq", ".login"], in: root)
		guard result.exitCode == 0 else { return nil }
		let login = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return login.isEmpty ? nil : login
	}
}

/// Why a forge question could not be asked — none of these an error.
///
/// **The one thing this must never look like is an empty list.** "No pull
/// requests are open" is a sentence about the repository; "the CLI is not logged
/// in" is a sentence about the machine. A reader cannot tell them apart, and
/// only one of them is something they can do anything about.
public enum ForgeAbsence: Equatable, Sendable {
	/// No `gh` anywhere on the search path.
	case cliNotInstalled
	/// `gh` is here and `gh auth status` says no.
	case cliNotLoggedIn(host: String)
	/// `origin` is a plain path, or a host this does not claim to understand.
	case noGitHubRemote

	/// What is the matter, in one line.
	public var summary: String {
		switch self {
		case .cliNotInstalled:
			return "The GitHub CLI is not installed."
		case .cliNotLoggedIn(let host):
			return "The GitHub CLI is not logged in to \(host)."
		case .noGitHubRemote:
			return "This repository has no GitHub remote."
		}
	}

	/// What to do about it — a command where there is one to run.
	///
	/// Each of the three says something different because each has a different
	/// remedy, and a single "something went wrong" would send somebody to look
	/// in the wrong place.
	public var remedy: String {
		switch self {
		case .cliNotInstalled:
			return "Install it with `brew install gh`."
		case .cliNotLoggedIn(let host):
			return "Log in with `gh auth login --hostname \(host)`."
		case .noGitHubRemote:
			return "Pull requests are read through GitHub, and `origin` does not point at one."
		}
	}
}

/// What came back from asking a forge a question.
///
/// Four cases and not two, because "could not ask" and "asked and it failed"
/// are different things to show somebody: the first three of them name
/// something they can fix, and the fourth is what the host said.
public enum ForgeReply<Value: Sendable>: Sendable {
	case answered(Value)
	/// The question could not be asked. See `ForgeAbsence`.
	case unavailable(ForgeAbsence)
	/// `gh` ran and refused; the text is what it said, trimmed.
	case failed(String)

	public var value: Value? {
		guard case .answered(let value) = self else { return nil }
		return value
	}

	/// What to put on screen when there is nothing to list.
	public var trouble: String? {
		switch self {
		case .answered: return nil
		case .unavailable(let absence): return absence.summary + " " + absence.remedy
		case .failed(let text): return text
		}
	}
}
