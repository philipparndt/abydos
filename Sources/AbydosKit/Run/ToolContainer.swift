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
	/// Docker first when nothing was asked for. Apple's used to be first, because
	/// it is the one that needs no daemon running before it will answer — the
	/// difference between a feature that works after a restart and one that says
	/// "cannot connect" — and *that reasoning is still sound*, which is why this
	/// is worth reading before it is either undone or left alone.
	///
	/// What put docker first was that a container had to be removable and the
	/// removal verb could not be proven against Apple's CLI while its service was
	/// wedged. **That reason is gone**: `container rm --force` is proven now, end
	/// to end, against `container` 1.2.2 — as are the sweep, the image pull,
	/// bind mounts, `exec -it` onto a pty, and a container kept detached with a
	/// keep-alive. Every one of those has a live test beside its docker twin.
	///
	/// What keeps docker first is one thing and it is not about cleanup:
	/// **nothing here can talk to one of Apple's containers over the network.**
	/// A published port is listened on and every connection to it is accepted and
	/// reset, because the runtime's own forwarder cannot reach the container it
	/// forwards to — `No route to host`, in its log. A container's own address on
	/// `bridge100` is the same story from this side: `connect(2)` from a freshly
	/// built binary returns `EHOSTUNREACH` while `curl` from an approved terminal
	/// fetches a picture from it in the same second. One cause, macOS's
	/// local-network privacy, and the runtime's helper is subject to it as much
	/// as this app is.
	///
	/// Two features want that and get refused for it: the kept PlantUML server
	/// (0422) and a devcontainer's `forwardPorts` (0424). Preferring a runtime
	/// two features quietly degrade on is worse than saying so, so this line
	/// stays as it is — and the day something on this machine may reach
	/// `192.168.64.0/24`, it is the one line to change, because everything else
	/// is proven there.
	///
	/// Apple's is found first when it is the only one here, and everything that
	/// does not go over the network works on it — the removal, the sweep, the
	/// image pull, bind mounts, a shell. `caveat` is what it says about the rest.
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
			return dockerLike(locate)
		case .automatic:
			if let docker = dockerLike(locate) { return docker }
			if let apple = locate("container") { return .apple(apple) }
			return nil
		}
	}

	private static func dockerLike(_ locate: (String) -> String?) -> ContainerRuntime? {
		for name in ["docker", "nerdctl", "podman"] {
			if let found = locate(name) { return .docker(found) }
		}
		return nil
	}

	/// What this app cannot promise about this runtime, or nil when it can
	/// promise everything.
	///
	/// One sentence, and only for Apple's. It used to be about removing a
	/// container by name, which is proven now and no longer worth warning anybody
	/// about. What is left is that nothing here can reach one of its containers
	/// over the network — which is what a kept PlantUML and a forwarded port both
	/// need, and what a pipe, a mount and a shell all do not.
	public var caveat: String? {
		switch self {
		case .docker: return nil
		case .apple:
			return "Apple's container runtime does everything here except be talked to over "
				+ "the network: its published ports are accepted and then reset, and its "
				+ "containers' own addresses are refused to this app. So diagrams are drawn "
				+ "the slow way, one container each, and a devcontainer that forwards a port "
				+ "will not open. Allowing local network access to `container` in Privacy & "
				+ "Security is what is worth trying."
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
	/// What the container is called, so it can be removed again.
	///
	/// Nil only where nothing will ever have to find it — a command line being
	/// shown to somebody, a test comparing arguments. Everything this app
	/// actually starts is named, because `--rm` is not the promise it looks
	/// like: killing the `run` that started a container leaves the container up
	/// and `--rm` never fires, so the only way back to it is the name.
	public let name: String?

	public init(
		image: String,
		command: [String] = [],
		mounts: [ContainerMount] = [],
		workingDirectory: String? = nil,
		name: String? = nil
	) {
		self.image = image
		self.command = command
		self.mounts = mounts
		self.workingDirectory = workingDirectory
		self.name = name
	}

	/// The same container, called this.
	public func named(_ name: String?) -> ToolContainer {
		ToolContainer(
			image: image, command: command, mounts: mounts,
			workingDirectory: workingDirectory, name: name
		)
	}

	/// The command line that runs it.
	///
	/// `--rm` because a container per render would otherwise pile up until
	/// somebody notices — though it only fires for a container that ends of its
	/// own accord, which is why there is a name as well; `-i` because the tools
	/// worth running this way read their input on standard input; and no tty,
	/// because a tty turns the output into something meant for a terminal rather
	/// than for a pipe.
	public func invocation(
		using runtime: ContainerRuntime,
		arguments: [String] = []
	) -> (executable: String, arguments: [String]) {
		var line = ["run", "--rm", "-i"]
		if let name { line += ["--name", name] }
		for mount in mounts { line += ["-v", mount.flag] }
		if let workingDirectory { line += ["-w", workingDirectory] }
		line.append(image)
		line += command
		line += arguments
		return (runtime.path, line)
	}
}
