import Foundation

/// Whether a project's own code may be run.
///
/// **Opening a folder in this app runs code from it.** Not on a press — on the
/// open: the run configurations are discovered by reading a `Makefile`, a
/// `launch.json` and a devcontainer definition; a language server is started
/// from what the project's tree provides; a terminal comes up in its
/// directory; a commit runs `.git/hooks`. A repository cloned to read — a bug
/// report's reproduction, a dependency somebody linked — was handed the trust
/// its owner's code gets.
///
/// The sharpest edge is that **environment variables are code**:
/// `SOPS_AGE_KEY_CMD` is a command sops runs, `GIT_SSH_COMMAND` and
/// `GIT_EXTERNAL_DIFF` are commands git runs, and the dynamic loader's
/// variables choose what is loaded into a process that was never asked. So a
/// project's variables are dropped while it is untrusted rather than filtered
/// against a list of dangerous names — the dangerous ones do not look
/// dangerous, and such a list is one somebody has to keep correct forever.
///
/// This is not a sandbox: it decides what *starts*, not what a trusted
/// project's build may then do. And it is not a scanner: no heuristic reads a
/// project and decides it looks safe.
public struct TrustedFolder: Codable, Equatable, Sendable {
	/// The folder's resolved path — symlinks and `/tmp` settled, since
	/// `/tmp/x` and `/private/tmp/x` are the same folder and only one of them
	/// would otherwise be trusted.
	public var path: String
	public var trusted: Date
	/// Whether the gesture was this folder alone or everything under it.
	public var coversChildren: Bool

	public init(path: String, trusted: Date = Date(), coversChildren: Bool = false) {
		self.path = path
		self.trusted = trusted
		self.coversChildren = coversChildren
	}
}

/// A git host every clone from which is trusted.
///
/// **For an enterprise server**, where a hundred repositories arrive from one
/// place and a folder entry per clone is the dialog people learn to dismiss.
///
/// It is weaker than a folder, and the page that offers it says so: a
/// repository's remote is what its own `.git/config` claims, so a folder that
/// arrived with a `.git` directory somebody else wrote can name any host it
/// likes. It is trust in what the folder says about itself, which is worth
/// having for a host nobody outside a company can even reach, and worth
/// knowing about before it is granted.
public struct TrustedRemote: Codable, Equatable, Sendable {
	/// The host as git spells it — `github.company.com`, without a scheme, a
	/// user or a port, and lower-cased so that one spelling answers for all.
	public var host: String
	/// The owner under it — `my-org` — or nil for the whole host.
	///
	/// **Because a host is the right unit for one server and the wrong one for
	/// github.com.** An enterprise server nobody outside a company can reach is
	/// a place; `github.com` is the world, and trusting the world is not what
	/// anybody means. So the same entry says both, and the sheet offers the
	/// owner first where there is one.
	public var owner: String?
	public var trusted: Date

	public init(host: String, owner: String? = nil, trusted: Date = Date()) {
		self.host = TrustedRemote.normalised(host)
		self.owner = owner.map { $0.lowercased() }
		self.trusted = trusted
	}

	/// How it reads in a sheet and in the settings: `github.com/my-org`, or
	/// `github.company.com` for a whole host.
	public var said: String {
		owner.map { "\(host)/\($0)" } ?? host
	}

	public func matches(host: String, owner: String?) -> Bool {
		guard self.host == TrustedRemote.normalised(host) else { return false }
		guard let mine = self.owner else { return true }
		return mine == owner?.lowercased()
	}

	public static func normalised(_ host: String) -> String {
		host.lowercased().components(separatedBy: "@").last ?? host.lowercased()
	}
}

/// What a call site may do with a project, and why.
///
/// A decision rather than a `Bool` because the answer is a sentence somebody
/// reads: every refusal in the window says the same thing in the same words and
/// offers the same gesture, and that is easier to keep true when the reason
/// travels with the answer.
public enum TrustDecision: Equatable, Sendable {
	case trusted
	/// Nothing of the project's runs, and this is what to say about it.
	case untrusted(project: String)

	public var isTrusted: Bool { self == .trusted }

	/// One sentence, in one place: a refusal that reads differently in the
	/// terminal and in the run control teaches somebody that they are two
	/// different problems.
	public var said: String? {
		switch self {
		case .trusted: return nil
		case .untrusted(let project):
			return "\(project) is not trusted, so nothing in it runs. "
				+ "Trust it in the window's banner to run, debug, open a terminal "
				+ "and start language servers."
		}
	}
}

@MainActor
public final class ProjectTrust {
	public static let shared = ProjectTrust()

	private let storeURL: URL
	/// Whether what happens here outlives the process.
	///
	/// `RecentProjects`' rule, for its reason: a driven run trusting a
	/// temporary directory must not leave that in somebody's real list — the
	/// list is a record of decisions a person made, and a capture run adding to
	/// it is that record being wrong.
	private let persists: Bool

	public private(set) var folders: [TrustedFolder] = []
	public private(set) var remotes: [TrustedRemote] = []

	/// Which host each open project's `origin` names, resolved once when the
	/// project is loaded and kept for the life of the process.
	///
	/// **Because the gates are synchronous and git is not.** Asking
	/// `git remote get-url` at every gate would put a subprocess between a
	/// keypress and a refusal; asking it once, when the window takes the
	/// project, is one call for the answer everything else reads.
	private var remoteIdentities: [String: (host: String, owner: String?)] = [:]

	public init(storeURL: URL? = nil, driven: Bool = DrivenRun.isActive) {
		let support = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("Abydos", isDirectory: true)
		try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
		self.storeURL = storeURL ?? support.appendingPathComponent("trust.json")
		self.persists = !driven
		load()
	}

	// MARK: - Asking

	/// Whether this project's own code may be run.
	public func decision(for root: URL) -> TrustDecision {
		isTrusted(root)
			? .trusted
			: .untrusted(project: root.lastPathComponent)
	}

	public func isTrusted(_ root: URL) -> Bool {
		let path = Self.resolved(root)
		let byFolder = folders.contains { folder in
			if folder.path == path { return true }
			// **At a component boundary.** A prefix match alone trusts
			// `~/development` because `~/dev` was trusted, which is a name
			// looking like another name rather than a folder being inside one.
			return folder.coversChildren && path.hasPrefix(folder.path + "/")
		}
		if byFolder { return true }
		guard let identity = remoteIdentities[path] else { return false }
		return remotes.contains { $0.matches(host: identity.host, owner: identity.owner) }
	}

	/// Where this project's `origin` says it came from, told to the store by
	/// whoever asked git — the window, when it loads a project.
	public func noteRemote(host: String?, owner: String?, for root: URL) {
		let path = Self.resolved(root)
		guard let host else {
			remoteIdentities.removeValue(forKey: path)
			return
		}
		remoteIdentities[path] = (TrustedRemote.normalised(host), owner?.lowercased())
	}

	/// What this project's remote says, for the sheet that offers to trust
	/// where it came from.
	public func remote(of root: URL) -> (host: String, owner: String?)? {
		remoteIdentities[Self.resolved(root)]
	}

	// MARK: - Answering

	public func trust(_ root: URL, coveringChildren: Bool = false) {
		let path = Self.resolved(root)
		folders.removeAll { $0.path == path }
		folders.append(TrustedFolder(path: path, coversChildren: coveringChildren))
		save()
	}

	/// Trusts every clone that says it came from this host, or from this owner
	/// on it.
	public func trust(remoteHost host: String, owner: String? = nil) {
		let entry = TrustedRemote(host: host, owner: owner)
		remotes.removeAll { $0.host == entry.host && $0.owner == entry.owner }
		remotes.append(entry)
		save()
	}

	/// Takes it back, by the entry's own path — a project covered by a trusted
	/// parent is untrusted by removing the parent, which is what the settings
	/// page lists.
	public func withdraw(path: String) {
		folders.removeAll { $0.path == path }
		save()
	}

	public func withdraw(remoteHost host: String, owner: String? = nil) {
		let entry = TrustedRemote(host: host, owner: owner)
		remotes.removeAll { $0.host == entry.host && $0.owner == entry.owner }
		save()
	}

	/// The entry that trusts this project, for a page that has to say *why* a
	/// project is trusted before it offers to take it back.
	public func entry(covering root: URL) -> TrustedFolder? {
		let path = Self.resolved(root)
		return folders.first { folder in
			folder.path == path
				|| (folder.coversChildren && path.hasPrefix(folder.path + "/"))
		}
	}

	/// The folder above this one, which the sheet offers as the wider choice.
	/// Nil at the root of a volume, where "everything under it" is everything.
	public static func parent(of root: URL) -> URL? {
		let resolved = URL(fileURLWithPath: resolved(root))
		let parent = resolved.deletingLastPathComponent()
		guard parent.path != resolved.path, parent.path != "/" else { return nil }
		return parent
	}

	/// Symlinks and `/tmp` settled. The same standardising `SopsRules` and the
	/// git paths do, and for the same reason: a project under `/tmp` is really
	/// under `/private/tmp`, and an answer that depends on which spelling
	/// arrived is an answer nobody can predict.
	static func resolved(_ url: URL) -> String {
		url.standardizedFileURL.resolvingSymlinksInPath().path
	}

	// MARK: - Persistence

	/// Both lists in one file, and one that can gain a field without the older
	/// file becoming unreadable — a store that cannot be added to is a store
	/// that gets replaced.
	private struct Stored: Codable {
		var folders: [TrustedFolder] = []
		var remotes: [TrustedRemote] = []
	}

	private func load() {
		guard let data = try? Data(contentsOf: storeURL) else { return }
		if let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
			folders = decoded.folders
			remotes = decoded.remotes
			return
		}
		// The first shape this file had: a bare array of folders. Read rather
		// than discarded, so trusting a project again is not the price of an
		// update.
		if let decoded = try? JSONDecoder().decode([TrustedFolder].self, from: data) {
			folders = decoded
		}
	}

	private func save() {
		guard persists else { return }
		guard let data = try? JSONEncoder().encode(Stored(folders: folders, remotes: remotes))
		else { return }
		try? data.write(to: storeURL, options: .atomic)
	}
}
