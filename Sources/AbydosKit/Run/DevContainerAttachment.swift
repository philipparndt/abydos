import Foundation

/// A project's devcontainer and what it turned out to carry — one fact.
///
/// **Why these are one value and not two tables.** They used to be two, keyed
/// the same way and filled at the same moment, and 0438 is what that cost. The
/// session was kept when a project's servers were stopped — deliberately, for
/// 0424's reason: switching away and back has to be instant and there may be
/// somebody's shell in the container — while the list of what the container
/// carries was dropped on the same path. Coming back then found the session, so
/// the start that fills the list never ran, so the list was empty, so every
/// language in the project was reported as having no server in the container.
/// A sentence that was false, above a file a server in that very container was
/// perfectly able to answer about, with a hint telling somebody to edit a
/// Dockerfile that was already correct.
///
/// Keeping the session and dropping its capabilities is the one combination
/// that produces a confident wrong answer, and the way to make it unreachable is
/// to make it unspellable.
public struct DevContainerAttachment: Equatable, Sendable {
	/// The container that is up, and everything needed to run something in it.
	public let session: DevContainers.Session

	/// Which of the language servers this app knows about the image actually
	/// has, asked once when the container came up.
	///
	/// The question nobody can answer by reading: an image carries what it
	/// carries. Without it every language the project touches starts a server
	/// that fails its handshake ten seconds later with the runtime's own
	/// `executable file not found`, which says nothing about the project.
	public let servers: Set<String>

	public init(session: DevContainers.Session, servers: Set<String>) {
		self.session = session
		self.servers = servers
	}

	/// Whether this container can run a language server, by the command it is
	/// started with.
	///
	/// **False means the image does not have it**, and never "nobody has asked
	/// yet" — that state is the absence of the whole attachment, which is a
	/// different question with a different answer above the file.
	public func carries(_ command: String) -> Bool { servers.contains(command) }
}

/// Which projects have a devcontainer up for their language servers, and what
/// each of those containers can run.
///
/// A value rather than an actor: it is bookkeeping owned by whoever starts the
/// servers, and every one of them is on the main thread already.
public struct DevContainerAttachments: Sendable {
	/// Keyed by the canonical project path, because `/var` is a symlink to
	/// `/private/var` and a project reached both ways is one project — 0430's
	/// fault, in a table one along.
	private var attached: [String: DevContainerAttachment] = [:]

	/// Which languages asked for a container that is still coming up, so that
	/// ten files opened at once bring up one container and every one of them
	/// gets its server when it lands.
	private var waiting: [String: Set<String>] = [:]

	public init() {}

	private func key(_ project: URL) -> String { FilePath.canonical(project) }

	// MARK: - The container a project's servers are in

	public subscript(project: URL) -> DevContainerAttachment? {
		attached[key(project)]
	}

	/// A container came up for this project, and this is what it has in it.
	public mutating func attach(
		_ session: DevContainers.Session, providing servers: Set<String>, to project: URL
	) {
		attached[key(project)] = DevContainerAttachment(session: session, servers: servers)
	}

	/// Whether this project's container can run a language server: nil when
	/// there is no container of this project's up at all, which is the state
	/// that starts one rather than the state that reports it missing.
	public func carries(_ command: String, for project: URL) -> Bool? {
		attached[key(project)]?.carries(command)
	}

	// MARK: - Waiting for one to come up

	/// This language wants a server as soon as the container lands.
	public mutating func wait(for languageId: String, in project: URL) {
		waiting[key(project), default: []].insert(languageId)
	}

	/// Everything that was waiting, taken off the list because the container has
	/// either landed or been given up on.
	public mutating func takeWaiting(for project: URL) -> Set<String> {
		waiting.removeValue(forKey: key(project)) ?? []
	}

	// MARK: - Letting go

	/// The project's language servers were stopped — it was closed, or its
	/// toolchain was moved onto this machine.
	///
	/// **What is dropped is what was about to happen; what is kept is the
	/// container and what it carries.** The container itself is deliberately
	/// left running (0424: coming back has to be instant, and there may be a
	/// terminal in it), and an attachment is a fact about that container rather
	/// than about the servers that happened to be using it. Dropping half of it
	/// here is 0438's second fault, and there is a test named after it.
	///
	/// - Returns: the languages that were waiting for a container, so their
	///   caller can stop telling somebody a server is on its way.
	@discardableResult
	public mutating func letGo(_ project: URL) -> Set<String> {
		takeWaiting(for: project)
	}

	/// The container itself has gone — stopped by hand from the list of running
	/// tools, or swept up on the way out.
	///
	/// The only thing that takes an attachment away. Everything known about a
	/// container goes at the moment the container does, together, for the same
	/// reason it arrived together.
	public mutating func containersStopped(keeping alive: Set<String>) {
		attached = attached.filter { alive.contains($0.value.session.name) }
	}

	public mutating func removeAll() {
		attached.removeAll()
		waiting.removeAll()
	}

	/// Which projects have a container, for a test and for the log.
	public var projects: [String] { attached.keys.sorted() }
}
