import Foundation

/// Where a repository lives on the web.
///
/// A remote is written for git, not for a browser: `git@github.com:me/x.git`
/// is not an address anything can open. This turns one into the other, for
/// GitHub and for the Enterprise installations that share its layout — which
/// is the same layout Gitea and Forgejo use, so those work by accident rather
/// than by claim.
public enum GitForge {
	/// A remote, taken apart.
	public struct Repository: Equatable, Sendable {
		public let host: String
		public let owner: String
		public let name: String

		public init(host: String, owner: String, name: String) {
			self.host = host
			self.owner = owner
			self.name = name
		}

		public var webURL: URL? { URL(string: "https://\(host)/\(owner)/\(name)") }

		/// The branch's own page.
		public func url(forBranch branch: String) -> URL? {
			guard let escaped = branch.addingPercentEncoding(
				withAllowedCharacters: .urlPathAllowed
			) else { return nil }
			return URL(string: "https://\(host)/\(owner)/\(name)/tree/\(escaped)")
		}

		/// What to call the place, for a menu: the name of the host, unless it
		/// is GitHub itself.
		public var displayName: String {
			host == "github.com" ? "GitHub" : host
		}
	}

	/// Reads a remote address, in any of the forms git accepts.
	///
	/// - `git@github.com:owner/name.git`  — scp-like, the usual ssh form
	/// - `ssh://git@ghe.example.com:22/owner/name.git`
	/// - `https://github.com/owner/name.git`
	/// - `https://user@ghe.example.com/owner/name`
	public static func repository(fromRemote remote: String) -> Repository? {
		let text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return nil }

		// The scp-like form is not a URL and URLComponents will not read it:
		// there is a colon where a scheme would be and no slashes after it.
		if !text.contains("://"), let colon = text.firstIndex(of: ":") {
			let host = String(text[text.startIndex..<colon])
			let path = String(text[text.index(after: colon)...])
			return repository(host: host.components(separatedBy: "@").last ?? host, path: path)
		}

		guard let components = URLComponents(string: text), let host = components.host else {
			return nil
		}
		return repository(host: host, path: components.path)
	}

	private static func repository(host: String, path: String) -> Repository? {
		// A repository is the last two parts of the path; anything in front is
		// a group, a team or a subgroup, and belongs to the owner.
		var parts = path.split(separator: "/").map(String.init)
		guard parts.count >= 2 else { return nil }

		var name = parts.removeLast()
		if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
		guard !name.isEmpty, !host.isEmpty else { return nil }

		return Repository(host: host, owner: parts.joined(separator: "/"), name: name)
	}

	/// The address a remote points at, or nil when there is no such remote.
	public static func remoteURL(in root: URL, remote: String = "origin") async -> String? {
		let result = await GitRepository.run(["remote", "get-url", remote], in: root)
		guard result.exitCode == 0 else { return nil }
		let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return text.isEmpty ? nil : text
	}

	/// Points a remote somewhere, adding it if the repository has none.
	///
	/// One call for both cases: a repository cloned without a remote and one
	/// pointed at the wrong place are the same problem to whoever is looking at
	/// it, and `add` versus `set-url` is git's distinction, not theirs.
	public static func setRemote(
		_ url: String,
		named remote: String = "origin",
		in root: URL
	) async -> GitRepository.ProcessResult {
		let existing = await GitRepository.run(["remote", "get-url", remote], in: root)
		let arguments = existing.exitCode == 0
			? ["remote", "set-url", remote, url]
			: ["remote", "add", remote, url]
		return await GitRepository.run(arguments, in: root)
	}

	/// Where a repository's remote points, ready to be opened.
	///
	/// - Parameter remote: which remote to ask about; the branch's own, when it
	///   has one, and `origin` otherwise.
	public static func repository(in root: URL, remote: String = "origin") async -> Repository? {
		let result = await GitRepository.run(["remote", "get-url", remote], in: root)
		guard result.exitCode == 0 else { return nil }
		return repository(fromRemote: result.stdout)
	}
}
