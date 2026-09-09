import Foundation

/// How to start a language server.
public struct LanguageServerDefinition: Equatable, Sendable {
	/// The languages it answers for, as the editor names them.
	///
	/// Not "the server for those languages": two servers may claim the same id,
	/// and which of them a project uses is `LanguageServerChoices`.
	public let languageIds: [String]
	/// The command, looked up on the path.
	public let command: String
	public let arguments: [String]
	/// Where to get it, said in the one sentence somebody needs when it is
	/// missing rather than left as "no language server found".
	public let installHint: String
	/// A file that marks the root of a project this server understands, so a
	/// Go server is not started for a repository with one `.go` file in a
	/// vendored directory.
	public let rootMarkers: [String]
	/// What this server is called — the name a person types to ask for it, and
	/// the name it is filed under everywhere: the choice of server for a
	/// language, the image chosen for it, the running server in the list.
	///
	/// Distinct from the command, and it has to be. Usually they are the same
	/// word, and twice they are not: Python's server ships a binary called
	/// `pyright-langserver` while the tool everybody means by it is `pyright`,
	/// and — the reason this is a name rather than a key — two servers for one
	/// language cannot both be "the Java one". A name nobody would think to
	/// type is a setting nothing reads.
	public let name: String
	/// Anything this server needs worked out per project rather than stated
	/// once here.
	public let setup: Setup
	/// Directories this server reads that are not in the project, for the case
	/// where it runs from an image and can see only what it is given.
	///
	/// Empty for all but one of them, and it is worth saying why rather than
	/// generalising: what a server needs beyond the project is a fact about
	/// that server, and the three that plausibly want something differ in
	/// whether it is the answer or a saving. kmp-lsp resolves a dependency's
	/// source out of `~/.m2` and `~/.gradle`, so without them it indexes the
	/// project perfectly and answers nothing at every dependency boundary —
	/// which is the state 0450's fork exists to end. gopls would like
	/// `~/go/pkg/mod`, but `ToolImages/gopls/Dockerfile` carries a module cache
	/// of its own and an empty one costs a download rather than an answer.
	/// jdtls builds its classpath by *running* Maven, which fetches what it is
	/// missing, and a read-only `~/.m2` would break that rather than help it.
	///
	/// So this is a list, in a table, one line per server, and the line is
	/// added when somebody has driven it — not a rule applied to all of them
	/// from one case that happened to be measured.
	public let outside: [OutsideDirectory]

	/// Whether what this server knows about the code is its text rather than its
	/// types.
	///
	/// It changes nothing about a question and everything about an *answer that
	/// changes files*. A go-to-definition from a syntactic server that lands in
	/// the wrong place costs a keystroke to undo; a rename from one is a
	/// substitution over what it indexed, so a method called `size()` on two
	/// unrelated classes is one name to it, and renaming one renames both — in
	/// forty files, some of which nobody had open.
	///
	/// So this is not a rating of servers. It is the one fact somebody needs
	/// before they accept a refactoring, and 0449 made it possible for a project
	/// to be pointed at such a server without the person at the editor knowing.
	public let isSyntactic: Bool

	/// What choosing this server costs and what it buys, in one line, for the
	/// page where somebody chooses.
	///
	/// Nil for every server that has no competition, because a language with one
	/// server offers no trade to describe — "gopls, the only one Abydos has" is
	/// already the whole answer. Set on the two that do, and 0449 asked for it in
	/// exactly those words: a menu offering two Java servers should say what the
	/// choice is between rather than two bare names.
	///
	/// 0449 left it to 0450, which knew what kmp-lsp trades away, and 0450 wrote
	/// it into its own entry rather than onto the screen. 0452 is what makes it a
	/// sentence somebody reads, and it is also what changed one of the two: the
	/// debugger no longer goes with the choice.
	public let trade: String?

	/// A directory outside the project that a server has to be able to read.
	///
	/// Named on both sides. The host side is relative to the home directory,
	/// because that is what these are — a person's caches, not a machine's —
	/// and an absolute path in a table would be one user's. The container side
	/// is written out rather than derived, because deriving it means guessing
	/// what `$HOME` is inside somebody's image, and a mount at the wrong place
	/// in there is not an error: the server starts, finds an empty cache and
	/// says nothing about it.
	public struct OutsideDirectory: Equatable, Sendable {
		/// Where it is on this machine, under the home directory.
		public let home: String
		/// Where the image must see it.
		public let container: String
		/// Read-only unless the server has to write there.
		///
		/// A language server has no business writing to a dependency cache: it
		/// reads jars out of it, and a mount that lets it do more than that is
		/// a mount that can corrupt somebody's build on a machine where the
		/// editor is the newcomer. The exception is a directory that is the
		/// server's *own* scratch, and even that is only writable because what
		/// it writes has to be readable from this side afterwards.
		public let isReadOnly: Bool

		public init(home: String, container: String, isReadOnly: Bool = true) {
			self.home = home
			self.container = container
			self.isReadOnly = isReadOnly
		}
	}

	/// Servers that cannot be started from a fixed command line.
	///
	/// Most can: the command takes no arguments, or the same two every time.
	/// One cannot, and pretending otherwise would mean either a stringly-typed
	/// escape hatch in the table or a special case at every call site.
	public enum Setup: String, Equatable, Sendable {
		case plain
		/// jdtls keeps a compiled index per project and will not share one
		/// between two, so each project is given a data directory of its own;
		/// and its debugger arrives as an Eclipse bundle that has to be named in
		/// the initialize request or it is never loaded.
		case java
		/// sourcekit-lsp builds the package to index it, and by default builds
		/// it into the package's own `.build` — the directory a terminal build
		/// uses. Two builds in one directory take turns holding its lock and
		/// invalidate each other's work, and where the toolchains differ they
		/// rebuild the world in turn: on this machine a nine-second incremental
		/// build took ten minutes while the indexer had it. It is given a
		/// directory of its own.
		case swift
	}

	/// Whether the debug adapter for this language can be loaded *into* this
	/// server.
	///
	/// `.java` is exactly that set, and it is the setup rather than the name for
	/// the reason 0449 gave: a name would go stale the day jdtls is packaged under
	/// another one. Named here rather than written as `setup == .java` at every
	/// call site, because since 0452 there are several and one of them asks the
	/// question of a server the project did *not* choose — which reads as a
	/// mistake unless the predicate says what it is for.
	public var hostsDebugAdapter: Bool { setup == .java }

	public init(
		languageIds: [String],
		command: String,
		arguments: [String] = [],
		installHint: String,
		rootMarkers: [String] = [],
		name: String? = nil,
		setup: Setup = .plain,
		outside: [OutsideDirectory] = [],
		isSyntactic: Bool = false,
		trade: String? = nil
	) {
		self.languageIds = languageIds
		self.command = command
		self.arguments = arguments
		self.installHint = installHint
		self.rootMarkers = rootMarkers
		self.name = name ?? command
		self.setup = setup
		self.outside = outside
		self.isSyntactic = isSyntactic
		self.trade = trade
	}

	/// The same server, run from this executable instead of from whatever the
	/// `PATH` calls it.
	///
	/// The `name` is carried over untouched, and that is the whole reason this is
	/// a method rather than a second table: the name is what a running server is
	/// filed under, what an image is chosen for and what a project names in
	/// `.abydos/tools.json`, and a definition whose name changed with its command
	/// would be a different server to every one of those. See
	/// `LanguageServerOverrides` for why a command has to be nameable at all.
	public func running(_ executable: String) -> LanguageServerDefinition {
		LanguageServerDefinition(
			languageIds: languageIds,
			command: executable,
			arguments: arguments,
			installHint: installHint,
			rootMarkers: rootMarkers,
			name: name,
			setup: setup,
			outside: outside,
			isSyntactic: isSyntactic,
			trade: trade
		)
	}
}
