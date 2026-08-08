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
		}
	}

	/// The project's two names, or nil when there is only one.
	public var paths: ContainerPaths? {
		switch self {
		case .installed: return nil
		case let .image(_, _, paths): return paths
		}
	}

	/// The image and the runtime that has to fetch it, when one is used.
	public var image: (name: String, runtime: ContainerRuntime)? {
		switch self {
		case .installed: return nil
		case let .image(container, runtime, _): return (container.image, runtime)
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
		}
	}
}
