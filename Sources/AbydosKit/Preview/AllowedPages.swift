import Foundation

/// The HTML documents somebody has let reach the network.
///
/// The preview refuses every remote reference, which is right for a file
/// nobody has read and wrong for the one case somebody asked about: a page they
/// wrote themselves, whose typeface lives at `fonts.googleapis.com`. Pressing
/// the pane's offer puts the file here, and this is what makes that survive
/// closing it.
///
/// `ProjectTrust`'s arrangement, deliberately, down to the driven-run rule:
///
///  * **Outside the project.** Kept in this application's support directory and
///    keyed by the file's resolved path. In the project it would be *committed*,
///    and everyone who cloned the repository would inherit permission for their
///    machine to reach that server — which is the shape of thing the pane's
///    default exists to prevent — besides putting a line in `git status` for
///    reading a file.
///  * **A path is the key, and a weak one.** A file renamed or moved loses its
///    allow and is asked about again, which is the safe direction to fail in.
///    Nothing is stored about the contents, so a document that changes entirely
///    under a path it kept is still allowed. `ProjectTrust` makes the same trade
///    for a folder.
///  * **A driven run writes nothing.** A capture that added to somebody's real
///    list would be a record of a decision no person made.
@MainActor
public final class AllowedPages {
	public static let shared = AllowedPages()

	private let storeURL: URL
	private let persists: Bool

	/// The resolved paths that may fetch.
	public private(set) var paths: [String] = []

	public init(storeURL: URL? = nil, driven: Bool = DrivenRun.isActive) {
		let support = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("Abydos", isDirectory: true)
		try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
		self.storeURL = storeURL ?? support.appendingPathComponent("allowed-pages.json")
		self.persists = !driven
		load()
	}

	// MARK: - Asking

	/// Whether the list says this document may fetch.
	///
	/// What somebody decided, which is not the same question as what happens
	/// now — see `isAllowed`. The pane needs both: one decides whether the
	/// blocking list goes on the web view, the other decides what the line says,
	/// and a pane that had only the first would describe a page somebody allowed
	/// as though they never had.
	public func isRemembered(_ file: URL) -> Bool {
		paths.contains(Self.resolved(file))
	}

	/// Whether this document may reach the network *now*.
	///
	/// **A driven run never may**, whatever is remembered. A capture that
	/// fetched somebody else's server would be a picture that differs by network
	/// and a suite that fails on an aeroplane, which is why `LinkOpener` refuses
	/// to open a browser on one. The pane says that is the reason, rather than
	/// rendering a page as though the allow had not been read.
	public func isAllowed(_ file: URL) -> Bool {
		persists && isRemembered(file)
	}

	/// Whether a driven run is what is standing in the way, so the pane can say
	/// so rather than offering a button that would do nothing.
	public var isHeldBackByDrivenRun: Bool { !persists }

	// MARK: - Answering

	public func allow(_ file: URL) {
		let path = Self.resolved(file)
		guard !paths.contains(path) else { return }
		paths.append(path)
		save()
	}

	public func forget(_ file: URL) {
		let path = Self.resolved(file)
		guard paths.contains(path) else { return }
		paths.removeAll { $0 == path }
		save()
	}

	/// Symlinks and `/tmp` settled, the same standardising `ProjectTrust` does
	/// and for its reason: a file under `/tmp` is really under `/private/tmp`,
	/// and an answer that depends on which spelling arrived is one nobody can
	/// predict.
	///
	/// **It settles them only for a file that is there.**
	/// `resolvingSymlinksInPath` stats the path, so a name that does not exist
	/// keeps whichever spelling it arrived in. That costs nothing here — the
	/// pane asks only about the document it is showing — and it is the same
	/// reason a file that is moved loses its allow rather than keeping it under
	/// a path nothing is at.
	static func resolved(_ url: URL) -> String {
		url.standardizedFileURL.resolvingSymlinksInPath().path
	}

	/// The same standardising for a caller outside this file that has to key
	/// something by the same string.
	public static func resolvedForTesting(_ url: URL) -> String { resolved(url) }

	// MARK: - Persistence

	/// A record rather than a bare array, so this can gain a field — when it was
	/// allowed, say — without the older file becoming unreadable. A store that
	/// cannot be added to is a store that gets replaced.
	private struct Stored: Codable {
		var paths: [String] = []
	}

	private func load() {
		guard let data = try? Data(contentsOf: storeURL),
		      let decoded = try? JSONDecoder().decode(Stored.self, from: data)
		else { return }
		paths = decoded.paths
	}

	private func save() {
		guard persists else { return }
		guard let data = try? JSONEncoder().encode(Stored(paths: paths)) else { return }
		try? data.write(to: storeURL, options: .atomic)
	}
}
