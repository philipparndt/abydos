import Foundation

/// Tags, and the one thing they are routinely used for that git makes awkward.
///
/// A release tag is written once and never touched. A *moving* tag — `v1`,
/// pointing at whatever the latest `v1.x` is — is what every GitHub Action
/// expects, and moving one means deleting and rewriting it in two places: here,
/// and on the remote where the workflow reads it from.
public enum GitTags {
	/// Makes a tag that does not exist yet.
	///
	/// **The half that was missing, and not for want of git.** `recreate` below
	/// has always been able to move a tag onto anything git can resolve, so it
	/// could point `v1` at `main` from the first day — but every verb in this
	/// app hangs off the menu of a row, and a tag that does not exist yet has no
	/// row to open a menu on. So the app could move a tag and could not make
	/// one.
	///
	/// - Parameter message: annotated when given, lightweight when not. A
	///   release tag people read carries a message; a marker somebody drops on a
	///   commit for their own use does not, and forcing one on them would put an
	///   editor in the way of a one-second job.
	public static func create(
		_ name: String,
		at source: String = "HEAD",
		message: String? = nil,
		in root: URL
	) async -> GitRepository.ProcessResult {
		var arguments = ["tag"]
		if let message, !message.isEmpty {
			arguments += ["--annotate", "--message", message]
		}
		arguments += [name, source]
		return await GitRepository.run(arguments, in: root)
	}

	/// Removes a tag from this repository.
	///
	/// Local only. Deleting it where a workflow reads it from is a separate ask
	/// with a separate consequence, which is `deleteOnRemote`.
	public static func delete(
		_ name: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(["tag", "--delete", name], in: root)
	}

	/// Removes a tag from the remote.
	///
	/// The fully-qualified ref, for the reason `push` gives below: `git push
	/// origin :v1` is ambiguous when a branch of the same name exists, and the
	/// thing being deleted is not the thing somebody meant.
	public static func deleteOnRemote(
		_ name: String,
		in root: URL,
		remote: String = "origin"
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(
			["push", "--delete", remote, "refs/tags/\(name)"],
			in: root,
			environment: [
				"GIT_TERMINAL_PROMPT": "0",
				"GIT_ASKPASS": "/usr/bin/false",
				"SSH_ASKPASS": "/usr/bin/false",
			]
		)
	}

	/// Points a tag at something else, making it if it does not exist.
	///
	/// - Parameter source: anything git can resolve — a commit, a branch, a
	///   tag. `v1.4.2` is the usual answer; `HEAD` is the other one.
	public static func recreate(
		_ name: String,
		at source: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(["tag", "--force", name, source], in: root)
	}

	/// Sends the tag to the remote, over whatever is there.
	///
	/// Force, because moving a tag is exactly the case git refuses without it,
	/// and the fully-qualified ref, because `git push origin v1` is ambiguous
	/// when a branch of the same name exists.
	public static func push(
		_ name: String,
		in root: URL,
		remote: String = "origin"
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(
			["push", "--force", remote, "refs/tags/\(name)"],
			in: root,
			environment: [
				"GIT_TERMINAL_PROMPT": "0",
				"GIT_ASKPASS": "/usr/bin/false",
				"SSH_ASKPASS": "/usr/bin/false",
			]
		)
	}

	/// What a tag points at now, as a short commit and its subject.
	public static func describe(_ name: String, in root: URL) async -> String? {
		let result = await GitRepository.run(
			["log", "-1", "--format=%h %s", name], in: root
		)
		guard result.exitCode == 0 else { return nil }
		let line = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return line.isEmpty ? nil : line
	}

	/// The tag a moving one most likely wants to point at.
	///
	/// `v1` is kept at the newest `v1.something`, which is the whole convention
	/// — so that is what the dialog offers, and `HEAD` when there is no such
	/// tag to be found.
	public static func likelySource(for name: String, in root: URL) async -> String {
		let result = await GitRepository.run(
			[
				"for-each-ref",
				"--format=%(refname:short)",
				// Newest first by the version numbers in the name, so v1.10
				// beats v1.9 — which sorting by text does not.
				"--sort=-version:refname",
				"refs/tags/\(name).*",
			],
			in: root
		)
		guard result.exitCode == 0 else { return "HEAD" }

		let candidate = result.stdout
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.first { !$0.isEmpty && $0 != name }
		return candidate ?? "HEAD"
	}
}
