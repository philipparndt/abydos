import Foundation

/// Translating between the paths a container sees and the ones this side has.
///
/// A renderer needs none of this: a diagram goes in on standard input and a
/// picture comes back, and neither mentions a file. A language server is the
/// opposite — almost everything it says is about a file, by URI, and the URIs
/// it uses are the ones inside the container. Mount a project at `/workspace`
/// and the server reports a problem in `file:///workspace/src/main.go`, which
/// is a path that does not exist on this machine.
///
/// So every URI is rewritten on the way in and on the way back. This is the
/// part worth getting exactly right: a mapping that is subtly wrong does not
/// fail, it silently opens the wrong file or reports a diagnostic against
/// nothing, and both look like the language server being unreliable.
///
/// **Every path here is canonical, and the caller is what makes it so.** What
/// decides whether a file is inside the project is a prefix comparison against
/// `host`, and a comparison between two paths reached different ways answers
/// no: on macOS `/tmp` and `/var` are symlinks, so a `host` of `/tmp/x` shares
/// no prefix with the `/private/tmp/x/main.go` a tool reports, and the file is
/// refused as outside a project it is plainly in. Both construction sites pass
/// `FilePath.canonical` and both `toContainer(path:)` callers do too — see
/// `LanguageServers.resolve` and `DevContainerFile.parse`, which say so where
/// they do it.
///
/// Canonicalising in here instead would be wrong: this maps paths that need
/// not exist — a file about to be written, a diagnostic about one just deleted
/// — and `realpath` cannot answer for those. So the rule is at the edge, where
/// a path is turned into one of these, and it is stated at both ends.
public struct ContainerPaths: Equatable, Sendable {
	/// Where the project lives on this machine.
	public let host: String
	/// Where it is mounted inside the container.
	public let container: String
	/// Directories the container can see that are *not* in the project, each
	/// with the name it has on this machine and the name it has in there.
	///
	/// Empty for almost everything, and that is the point: the rule stays "one
	/// project, one mount, and everything else refused". What this adds is a
	/// short, named list of exceptions somebody wrote down — kmp-lsp's two
	/// dependency caches, 0434's scratch directory for OpenSCAD — rather than a
	/// mapping that will translate any path to any other. A path in none of
	/// them is still refused, which is the sentence at `toContainer(path:)`.
	public let beyond: [ContainerMount]

	/// - Parameters:
	///   - container: defaults to `/workspace`, which is what most images that
	///     expect a project use, and is short enough to read in a log.
	///   - beyond: directories outside the project this container is also given.
	///     They must not sit inside one another or inside the project: two
	///     mappings that could both answer for one path is a coin toss, and the
	///     one thing this type must never do is answer with a plausible name for
	///     the wrong file. Nothing here checks that, because the list comes from
	///     a table somebody maintains rather than from a running program.
	public init(host: String, container: String = "/workspace", beyond: [ContainerMount] = []) {
		self.host = Self.trimmed(host)
		self.container = Self.trimmed(container)
		self.beyond = beyond.map {
			ContainerMount(
				host: Self.trimmed($0.host),
				container: Self.trimmed($0.container),
				isReadOnly: $0.isReadOnly
			)
		}
	}

	/// Without a trailing slash, so joining is one rule rather than two.
	private static func trimmed(_ path: String) -> String {
		var value = path
		while value.count > 1, value.hasSuffix("/") { value.removeLast() }
		return value
	}

	/// The mount this implies, read-write: a language server writes nothing,
	/// but a formatter and a build tool both do, and a mount that has to be
	/// changed per tool is one more thing to get wrong.
	public var mount: ContainerMount {
		ContainerMount(host: host, container: container, isReadOnly: false)
	}

	/// Every directory this container is given: the project, and whatever else
	/// was named beyond it.
	///
	/// The project first, so a command line reads the way somebody would write
	/// it by hand and the important mount is the one that is easy to find.
	public var mounts: [ContainerMount] { [mount] + beyond }

	/// A path on this machine, as the container would name it.
	///
	/// Returns nil for anything the container cannot see — inventing a path
	/// inside would point the server at the wrong file rather than at none.
	/// "Outside the project" was the whole of that rule until a server turned up
	/// that reads its dependencies from two directories in the home folder; it
	/// is now "outside the project and outside everything named beyond it",
	/// which is the same rule over a list somebody wrote down.
	///
	/// The project is asked first because it answers almost every question:
	/// `beyond` is empty for every server but one, and a message is walked URI
	/// by URI.
	public func toContainer(path: String) -> String? {
		if let inside = Self.moved(path, from: host, to: container) { return inside }
		for mount in beyond {
			if let inside = Self.moved(path, from: mount.host, to: mount.container) { return inside }
		}
		return nil
	}

	/// A path the container named, as this machine knows it.
	public func toHost(path: String) -> String? {
		if let here = Self.moved(path, from: container, to: host) { return here }
		for mount in beyond {
			if let here = Self.moved(path, from: mount.container, to: mount.host) { return here }
		}
		return nil
	}

	/// One mapping applied, or nil when the path is not under `from`.
	///
	/// The prefix has to be a whole path component: `/Users/me/project-notes`
	/// is not in `/Users/me/project`, and the mapping that thinks it is opens a
	/// file from a different checkout. This is the prefix bug every path
	/// mapping has once.
	private static func moved(_ path: String, from: String, to: String) -> String? {
		if path == from { return to }
		guard path.hasPrefix(from + "/") else { return nil }
		return to + String(path.dropFirst(from.count))
	}

	// MARK: - URIs

	/// The same, for the `file:` URIs a language server actually speaks.
	///
	/// Anything that is not a `file:` URI is left alone: `untitled:` and
	/// `jdt:` and the rest name things that have no path on either side.
	public func toContainer(uri: String) -> String? {
		rewrite(uri: uri) { toContainer(path: $0) }
	}

	public func toHost(uri: String) -> String? {
		rewrite(uri: uri) { toHost(path: $0) }
	}

	// MARK: - Whole messages

	/// A message on its way to the server, with every `file:` URI in it moved to
	/// the container's side.
	///
	/// Done here, over the whole message, rather than at each place that sends
	/// one: a URI turns up in more shapes than anybody can keep a list of —
	/// inside a location, inside an edit, inside a diagnostic's related
	/// information, as the *key* of a workspace edit's `changes` — and a list
	/// that misses one goes wrong silently. Walking the message needs no list.
	public func containerSide(of message: [String: Any]) -> [String: Any] {
		mapped(message) { toContainer(uri: $0) }
	}

	/// The same for a message coming back, moved home.
	public func hostSide(of message: [String: Any]) -> [String: Any] {
		mapped(message) { toHost(uri: $0) }
	}

	private func mapped(
		_ message: [String: Any], _ transform: (String) -> String?
	) -> [String: Any] {
		rewriting(message, transform) as? [String: Any] ?? message
	}

	/// Every `file:` URI in a JSON value, moved.
	///
	/// Anything that does not look like one is left exactly as it was, and so is
	/// one that does not map: a URI naming something the other side cannot see
	/// stays as it is rather than being moved to a path that is a different
	/// file. The server then says it cannot open that, which is the truth.
	private func rewriting(_ value: Any, _ transform: (String) -> String?) -> Any {
		switch value {
		case let text as String:
			guard text.hasPrefix("file:") else { return text }
			return transform(text) ?? text
		case let array as [Any]:
			return array.map { rewriting($0, transform) }
		case let table as [String: Any]:
			var rewritten: [String: Any] = [:]
			rewritten.reserveCapacity(table.count)
			for (key, inner) in table {
				// Keys as well as values. A workspace edit is keyed by URI —
				// `changes: {"file:///workspace/a.go": [...]}` — so a walk that
				// looked only at values would bring every edit home and leave
				// the file it belongs to on the container's side.
				let moved = key.hasPrefix("file:") ? (transform(key) ?? key) : key
				rewritten[moved] = rewriting(inner, transform)
			}
			return rewritten
		default:
			return value
		}
	}

	private func rewrite(uri: String, _ transform: (String) -> String?) -> String? {
		guard let components = URLComponents(string: uri), components.scheme == "file" else {
			return nil
		}
		// `path` is decoded, which is what the mapping works on; re-encoding on
		// the way out keeps a space in a directory name from ending the URI.
		guard let moved = transform(components.path) else { return nil }
		var rebuilt = URLComponents()
		rebuilt.scheme = "file"
		rebuilt.host = ""
		rebuilt.path = moved
		return rebuilt.string
	}
}
