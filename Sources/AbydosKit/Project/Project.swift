import Foundation

/// One open project: a root directory plus its version-control state.
public final class Project {
	public let root: URL
	public private(set) var git: GitRepository?

	public init(root: URL) {
		self.root = root.standardizedFileURL
	}

	public var name: String { root.lastPathComponent }

	/// Home-relative path, matching how IDEA shows it under the project name.
	public var displayPath: String { Project.abbreviate(root) }

	public static func abbreviate(_ url: URL) -> String {
		let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		if path == home { return "~" }
		if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
		return path
	}

	/// Finds the enclosing git work tree and loads its status.
	/// The part of the project being worked on, when it is not the whole of it.
	///
	/// Held here rather than passed in, so every refresh looks in the same
	/// place: a load started for the whole project and one started for a
	/// subproject can be in flight at once, and whichever finishes last must
	/// not be the one that decides which repository this is.
	public var scope: URL?

	/// The root everything scoped works against: the subproject when there is
	/// one, the whole checkout otherwise.
	///
	/// One property rather than `scope ?? root` written out at each call site,
	/// for the reason 0424 gave `devContainerRoot` one: a table keyed by "the
	/// project" and a table keyed by "the part being worked on" look identical
	/// until something is filed under one and looked for under the other. That
	/// is 0432 — a language server started for a subproject and asked for under
	/// the repository above it, which answered nothing and said so only in the
	/// log.
	public var scopeRoot: URL { scope ?? root }

	/// Finds the repository this project is in.
	///
	/// From the subproject when there is one, because a checkout of several
	/// repositories is the case subprojects exist for: the work tree git acts
	/// on is the one the part being worked on belongs to, which need not be the
	/// one the tree is rooted in.
	/// **On the main actor, and one at a time.**
	///
	/// This is a plain class with no isolation of its own, and `loadGit` was
	/// `nonisolated async` — so its body ran on the cooperative pool even when
	/// every caller was on the main actor, and two of them could be in it at
	/// once. The repository watcher calls it on *every* change inside `.git`,
	/// which during a build or a fetch is many a second, so two at once was not
	/// a rare interleaving. Two threads then wrote `git` and `gitRoot` on the
	/// same object, and the second release of the same `URL?` was a segfault:
	///
	///     EXC_BAD_ACCESS (SIGSEGV) ... objc_destructInstance
	///     _SwiftURL.__deallocating_deinit
	///     outlined assign with take of URL?
	///     Project.loadGit()
	///
	/// It is also what made the branch pill flicker on and off: two loads
	/// racing, and the pill drawn from whichever landed last.
	///
	/// `@MainActor` costs nothing here. Both awaits suspend rather than block,
	/// so the main thread is free for exactly as long as it was before; what it
	/// buys is that the two assignments happen in one place, in a known order.
	@MainActor
	public func loadGit() async {
		// Joined rather than started again. A second caller arriving while the
		// first is still out wants the same answer, and running `git status` on
		// a large work tree once per filesystem event — for an answer already on
		// its way — is most of what made switching projects feel slow.
		if let loading { return await loading.value }

		let task = Task { @MainActor [scope, root] () -> Void in
			let repo = await GitRepository.discover(from: scope ?? root)
			await repo?.refresh()
			self.git = repo
			self.gitRoot = repo?.root
			// Two git calls, 0.03 s over forty submodules and 0.01 s over two
			// hundred, so it is read here rather than on demand: everything that
			// wants it wants it while building a view, and a repository with no
			// submodules pays for an empty `ls-files --stage` filter.
			if let repo {
				self.estate = await GitEstate.read(from: repo.root)
			} else {
				self.estate = GitEstate(root: scope ?? root)
			}
		}
		loading = task
		await task.value
		loading = nil
	}

	/// The load in flight, so a second caller joins it instead of starting one.
	@MainActor private var loading: Task<Void, Never>?

	/// The repository *and the submodules it holds*, for the verbs that have to
	/// know which of them owns a path.
	///
	/// **`git` above is still the superproject, and deliberately.** Every caller
	/// that has ever asked for `Project.git` meant "the repository this project
	/// is", and in a checkout of two or three hundred microservices that is
	/// still a true and useful answer — it is the repository the branch pill
	/// names, the one the refs tree is rooted at, and the one a fetch of the
	/// whole estate starts from. What it is *not* is the repository that stages
	/// `svc-47/src/Main.java`, and this is what answers that.
	///
	/// So the two live side by side rather than one replacing the other. A
	/// rename that made every existing call site compile against the estate
	/// would have moved them all without anybody deciding that each was right,
	/// and the ones that are wrong are wrong silently — the compiler cannot tell
	/// "the repository" from "the repository that owns this path".
	///
	/// Empty until the first `loadGit`, and empty forever for a project with no
	/// submodules, which is the same code path and not a special case.
	@MainActor public private(set) var estate = GitEstate(root: URL(fileURLWithPath: "/"))

	/// Every file in the project, by path, for finding one by name.
	///
	/// Held here so two windows on the same project ask the same index: building
	/// it is a `git ls-files` over the whole repository, and doing that twice is
	/// the cost the index exists to avoid. It is an actor, so this is only a
	/// reference.
	public lazy var files = FileIndex(root: scope ?? root)

	/// Where the repository's work tree starts, once it has been found.
	///
	/// Kept here so it can be read without a hop onto the actor, because the
	/// callers that need it are building views: a pane is constructed
	/// synchronously and has to be told which directory to run git in before it
	/// can ask anything.
	///
	/// **This, and not `scopeRoot`, is the directory git commands belong in.**
	/// `git status` reports paths from the work tree root whatever directory it
	/// was run in, but `git add`, `restore`, `reset`, `clean` and `ls-files`
	/// resolve a pathspec against the *current* directory. Run one in a
	/// subproject and hand it a path that is already relative to the root and
	/// the two compose:
	///
	///     warning: could not open directory 'sub/sub/'
	///     fatal: pathspec 'sub/' did not match any files
	///
	/// which is staging that simply does not work while a subproject is open.
	public private(set) var gitRoot: URL?

	/// The project a file belongs to.
	///
	/// The repository around it, since that is what anybody means by "the
	/// project"; failing that, the directory the file sits in, which is at
	/// least something to show a tree of. What `ideai path/to/file.go` opens.
	public static func root(containing file: URL) -> URL {
		var directory = file.standardizedFileURL
		if !((try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
			directory = directory.deletingLastPathComponent()
		}
		return ProjectRoot.find(from: directory) ?? directory
	}

	/// Path relative to the git root, which is what `git status` output is keyed by.
	/// Note this is the *git* root, which may sit above the project root.
	public func gitRelativePath(for url: URL, gitRoot: URL) -> String {
		let base = gitRoot.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		guard path.hasPrefix(base + "/") else { return "" }
		return String(path.dropFirst(base.count + 1))
	}
}
