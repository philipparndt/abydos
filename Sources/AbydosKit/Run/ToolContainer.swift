import Foundation

/// Running a development tool from a container image rather than from the
/// machine it is being used on.
///
/// The problem this solves is the one every project has: a language server, a
/// build tool or a renderer that has to be installed before the project can be
/// worked on at all, in the version that project expects, on every machine
/// anybody uses. A checkout that names its own image needs none of that — the
/// tool arrives with the project, and the machine keeps whatever it already had.
///
/// Nothing here is a substitute for a tool that *is* installed: what is on the
/// machine is used first, because it starts faster and is what somebody chose.
/// The image is the answer for a machine where the tool is missing, and for a
/// project that would rather pin a version than trust whatever is on the PATH.
public enum ContainerRuntime: Equatable, Sendable {
	/// Apple's `container`, which runs each container in its own lightweight VM.
	case apple(String)
	/// `docker`, or something that speaks its command line — `nerdctl`,
	/// `podman` — since all of them take the same three flags this needs.
	case docker(String)

	/// The path of the command itself.
	public var path: String {
		switch self {
		case let .apple(path), let .docker(path): return path
		}
	}

	/// What to call it when saying which one is being used.
	public var name: String {
		switch self {
		case .apple:  return "container"
		case .docker: return "docker"
		}
	}

	/// What a person can ask for, rather than what happened to be found.
	public enum Preference: String, CaseIterable, Sendable {
		/// Whichever is installed, Apple's first.
		case automatic
		case apple
		case docker

		public var title: String {
			switch self {
			case .automatic: return "Whichever is installed"
			case .apple:     return "Apple container"
			case .docker:    return "Docker"
			}
		}
	}

	/// The runtimes to look for, in the order they are preferred.
	///
	/// Apple's first when nothing was asked for: it is the one that needs no
	/// daemon running before it will answer, which is the difference between a
	/// feature that works after a restart and one that says "cannot connect".
	///
	/// A stated preference is honoured exactly, including by finding nothing:
	/// somebody who says Docker and has none has a problem worth being told
	/// about, not a silent substitution of the other one.
	public static func discover(
		preference: Preference = .automatic,
		locate: (String) -> String? = { Executables.locate($0) }
	) -> ContainerRuntime? {
		switch preference {
		case .apple:
			return locate("container").map { .apple($0) }
		case .docker:
			for name in ["docker", "nerdctl", "podman"] {
				if let found = locate(name) { return .docker(found) }
			}
			return nil
		case .automatic:
			if let apple = locate("container") { return .apple(apple) }
			for name in ["docker", "nerdctl", "podman"] {
				if let found = locate(name) { return .docker(found) }
			}
			return nil
		}
	}
}

/// A directory the container can see.
public struct ContainerMount: Equatable, Sendable {
	public let host: String
	public let container: String
	public let isReadOnly: Bool

	public init(host: String, container: String, isReadOnly: Bool = false) {
		self.host = host
		self.container = container
		self.isReadOnly = isReadOnly
	}

	/// The `-v` argument both command lines take.
	public var flag: String {
		"\(host):\(container)" + (isReadOnly ? ":ro" : "")
	}
}

/// A tool that comes from an image.
public struct ToolContainer: Equatable, Sendable {
	/// The image, as `docker pull` would name it.
	public let image: String
	/// What to run inside it, when the image's own entry point is not enough.
	public let command: [String]
	/// Directories the tool needs to see. A renderer reading its diagram from
	/// standard input needs none; a language server needs the project.
	public let mounts: [ContainerMount]
	/// Where to start, inside the container.
	public let workingDirectory: String?

	public init(
		image: String,
		command: [String] = [],
		mounts: [ContainerMount] = [],
		workingDirectory: String? = nil
	) {
		self.image = image
		self.command = command
		self.mounts = mounts
		self.workingDirectory = workingDirectory
	}

	/// The command line that runs it.
	///
	/// `--rm` because a container per render would otherwise pile up until
	/// somebody notices; `-i` because the tools worth running this way read
	/// their input on standard input; and no tty, because a tty turns the
	/// output into something meant for a terminal rather than for a pipe.
	public func invocation(
		using runtime: ContainerRuntime,
		arguments: [String] = []
	) -> (executable: String, arguments: [String]) {
		var line = ["run", "--rm", "-i"]
		for mount in mounts { line += ["-v", mount.flag] }
		if let workingDirectory { line += ["-w", workingDirectory] }
		line.append(image)
		line += command
		line += arguments
		return (runtime.path, line)
	}
}
