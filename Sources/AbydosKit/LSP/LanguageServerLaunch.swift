import Foundation

/// How a language server is going to be started: from this machine, or from an
/// image.
///
/// The difference is smaller than it looks — both end as an executable and a
/// list of arguments, which is all `LSPClient.start` wants — and the part that
/// is not small is the paths. A server in a container knows the project by the
/// name it is mounted under and by no other, so a launch carries the mapping
/// with it rather than leaving each caller to remember there is one.
public enum LanguageServerLaunch: Equatable, Sendable {
	/// The copy installed here, at this path, with the arguments its definition
	/// asks for.
	case installed(executable: String, arguments: [String])
	/// An image, run by whichever runtime is here, with the project mounted.
	case image(container: ToolContainer, runtime: ContainerRuntime, paths: ContainerPaths)
	/// The project's own devcontainer, which is already running: the server is
	/// `exec`'d into it rather than started beside it.
	///
	/// The distinction from `.image` is not how it starts but *whose container
	/// it is*. An image is started for this server and removed with it; a
	/// devcontainer belongs to the project, holds somebody's terminal, and was
	/// brought up before any of this. One container with the project's own
	/// toolchain in it is the thing a devcontainer exists to provide, and a
	/// second container beside it running a language server would be a second
	/// answer to what `go` means here.
	///
	/// - Parameters:
	///   - command: what to run *inside*, as the container's PATH will resolve
	///     it. Not a path from this machine — nothing here is on that machine.
	///   - root: where to run it, in the container's own names.
	case devcontainer(
		session: DevContainers.Session,
		command: String,
		arguments: [String],
		root: String
	)

	/// The command line to start it with.
	public var invocation: (executable: String, arguments: [String]) {
		switch self {
		case let .installed(executable, arguments):
			return (executable, arguments)
		case let .image(container, runtime, _):
			// Nothing added. The contract an image is held to puts the server on
			// the entry point with whatever flags it needs — `--stdio` and the
			// rest — so an argument from this side would arrive after those and
			// be read by the server as a file to open.
			return container.invocation(using: runtime)
		case let .devcontainer(session, command, arguments, root):
			return DevContainers.execCommand(
				session, arguments: [command] + arguments, workingDirectory: root
			)
		}
	}

	/// The project's two names, or nil when there is only one.
	public var paths: ContainerPaths? {
		switch self {
		case .installed: return nil
		case let .image(_, _, paths): return paths
		// The devcontainer's own mapping, which is the file's rather than
		// `/workspace`: a devcontainer.json says where the checkout goes, and a
		// server told anything else names files that do not exist on either side.
		case let .devcontainer(session, _, _, _): return session.configuration.paths
		}
	}

	/// The image and the runtime that has to fetch it, when one is used.
	public var image: (name: String, runtime: ContainerRuntime)? {
		switch self {
		case .installed: return nil
		case let .image(container, runtime, _): return (container.image, runtime)
		// Nothing to fetch here: whatever the devcontainer came from was pulled
		// or built when it came up, which is `DevContainers`' business.
		case .devcontainer: return nil
		}
	}

	/// The container this will run in: what it is called, and what to ask to
	/// remove it.
	///
	/// A server is the longest-lived thing this app starts, so it is also the
	/// container most worth being able to end: stopping the `run` process leaves
	/// it up, holding the project's mount, until something removes it by name.
	public var container: (name: String, runtime: ContainerRuntime)? {
		switch self {
		case .installed: return nil
		case let .image(container, runtime, _):
			guard let name = container.name else { return nil }
			return (name, runtime)
		// Nil, and this is the one place the two container cases must not agree.
		// A devcontainer is the project's, not this server's: removing it when
		// the server stops would take somebody's terminal, their build and their
		// whole session with it. What stopping the server has to end is the
		// server, and the protocol's own `exit` does that from inside.
		case .devcontainer: return nil
		}
	}

	/// The container the server runs *inside*, whoever owns it.
	///
	/// Deliberately a different question from `container` above, and the
	/// devcontainer case is where the two answers part company: that one asks
	/// what to remove when this server stops, and the answer there has to be
	/// nothing. This one asks where the server actually is, which the list of
	/// what is running needs for a reason of its own — a server in a container
	/// has a few megabytes of runtime client out here and the whole of itself in
	/// there, so a row that measured the process on this machine would be
	/// reporting a hundredth of the truth and calling it the cost.
	public var hostContainerName: String? {
		switch self {
		case .installed: return nil
		case let .image(container, _, _): return container.name
		case let .devcontainer(session, _, _, _): return session.name
		}
	}

	/// What to call it in a log line somebody is reading to find out why a
	/// server did not answer.
	public var description: String {
		switch self {
		case let .installed(executable, _):
			return executable
		case let .image(container, runtime, paths):
			return "\(runtime.name) run \(container.image) [\(paths.host) as \(paths.container)]"
		case let .devcontainer(session, command, _, root):
			let paths = session.configuration.paths
			return "\(session.runtime.name) exec \(session.name) \(command) at \(root) "
				+ "[\(paths.host) as \(paths.container)]"
		}
	}
}
