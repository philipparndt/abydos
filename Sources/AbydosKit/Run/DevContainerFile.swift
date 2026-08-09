import Foundation

/// What a project's `devcontainer.json` says it needs, in the part of that file
/// this app can honestly honour.
///
/// Everything here is already resolved: the substitutions are done, the paths
/// are absolute, and `paths` is the same `ContainerPaths` a language server
/// uses — because a workspace folder and a mounted tool are the same problem
/// and there is no reason for two answers to it.
public struct DevContainerConfiguration: Equatable, Sendable {
	/// The file this was read from.
	public let file: URL
	/// The project it belongs to, on this machine.
	public let project: URL
	/// What the file calls itself, if it says.
	public let name: String?
	/// The image to run, when the file names one.
	public let image: String?
	/// The Dockerfile to build, when it names one instead.
	public let build: Build?
	/// The project on this machine, and where it is mounted in the container.
	public let paths: ContainerPaths
	/// Where a shell starts, which is the mount or a directory inside it.
	public let workspaceFolder: String
	/// Who the container runs as, if the file says.
	public let containerUser: String?
	/// Who a shell or a tool inside it runs as, if the file says.
	public let remoteUser: String?
	/// Environment for the container itself.
	public let containerEnv: [String: String]
	/// Environment for what is started inside it afterwards — a terminal, a
	/// language server. Not the same thing, and the spec is right that it is
	/// not: `containerEnv` is baked in at `run`, `remoteEnv` is added at `exec`.
	public let remoteEnv: [String: String]
	/// Ports to publish, on the loopback address.
	public let forwardPorts: [Int]
	/// Anything else the file wants mounted, as `--mount` already takes it.
	public let extraMounts: [String]
	/// Arguments handed to the runtime verbatim.
	public let runArgs: [String]
	/// What the file asks to be run, and when — `postCreateCommand` and the
	/// five others. `DevContainers` is what runs them; this is what they are.
	public let lifecycle: DevContainerLifecycle

	/// An image built from the project rather than pulled.
	public struct Build: Equatable, Sendable {
		/// The Dockerfile, absolute, on this machine.
		public let dockerfile: String
		/// What to build it in, absolute, on this machine.
		public let context: String
		public let args: [String: String]
		public let target: String?
	}

	/// What to call the image built for this project.
	///
	/// One repository for all of them and the project's name in the tag, so a
	/// machine with several devcontainers on it does not rebuild one over
	/// another, and so `docker images` says whose they are.
	public var builtImageName: String {
		let stem = project.lastPathComponent.lowercased().map { character -> Character in
			character.isLetter || character.isNumber ? character : "-"
		}
		let name = String(stem).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		return "abydos-devcontainer:\(name.isEmpty ? "project" : name)"
	}

	/// The image this container comes from, whichever way it is obtained.
	public var imageReference: String { image ?? builtImageName }
}

/// Reading a `devcontainer.json`, and saying plainly what it cannot read.
///
/// A subset, deliberately, and the subset is stated rather than implied: an
/// image or a Dockerfile, a workspace folder, a user, some environment, some
/// ports, some mounts. `features` is a package manager and `dockerComposeFile`
/// is a second orchestrator, and a container started while quietly ignoring
/// either would be missing exactly the tools somebody opened the project for —
/// which does not look like an unsupported file, it looks like a broken editor.
/// So those refuse, by name, in one sentence somebody can act on.
///
/// Whether the reference CLI should do this instead is open, and 0424 says why
/// it is open. Nothing here forecloses it: this reads the *file*, which the app
/// needs to have read whoever builds the container.
public enum DevContainerFile {
	/// Understood, or refused with the reason.
	public enum Reading: Equatable, Sendable {
		case understood(DevContainerConfiguration)
		/// One sentence, in the register of `ContainerImages.explain`: what was
		/// in the file, and what to do about it.
		case refused(String)

		public var configuration: DevContainerConfiguration? {
			if case let .understood(configuration) = self { return configuration }
			return nil
		}

		public var refusal: String? {
			if case let .refused(reason) = self { return reason }
			return nil
		}
	}

	// MARK: - Where the file is

	/// The two fixed places, in the order VS Code looks in them.
	private static let fixedLocations = [".devcontainer/devcontainer.json", ".devcontainer.json"]

	/// Every `devcontainer.json` this project has, in the order they are
	/// preferred.
	///
	/// The third legal place is `.devcontainer/<anything>/devcontainer.json`,
	/// which is how a project offers a choice of containers. Sorted, so that
	/// which one comes first is a fact about the names rather than about the
	/// order the file system happened to answer in.
	public static func locations(in project: URL, fileManager: FileManager = .default) -> [URL] {
		var found: [URL] = []
		for relative in fixedLocations {
			let url = project.appendingPathComponent(relative)
			if fileManager.fileExists(atPath: url.path) { found.append(url) }
		}
		let folder = project.appendingPathComponent(".devcontainer")
		let inside = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
		for entry in inside.sorted() {
			let url = folder.appendingPathComponent(entry).appendingPathComponent("devcontainer.json")
			if fileManager.fileExists(atPath: url.path) { found.append(url) }
		}
		return found
	}

	/// Whether this project has one at all.
	public static func exists(in project: URL, fileManager: FileManager = .default) -> Bool {
		!locations(in: project, fileManager: fileManager).isEmpty
	}

	// MARK: - Which of them

	/// One of the devcontainers a project offers, named the way somebody has to
	/// be able to pick it out of a menu.
	///
	/// The file is what identifies it, because it is the only thing that
	/// distinguishes one from another: they share a project, a checkout and a
	/// mount, and differ in what is written in them.
	public struct Choice: Equatable, Sendable {
		/// The `devcontainer.json` this one is.
		public let file: URL
		/// What to call it on screen.
		public let name: String
	}

	/// Every devcontainer this project offers, in the order they are preferred,
	/// each named.
	///
	/// A project may have several — that is what the third legal location is
	/// *for*, and `.devcontainer/alpine` beside `.devcontainer/go` is a project
	/// offering a choice of toolchain rather than a project that is misconfigured.
	/// This app used to refuse the whole project for it, because a menu is the
	/// only honest way to ask which one somebody means and there was no menu to
	/// ask in. There is one now, so the answer is to offer them.
	public static func choices(
		in project: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		fileManager: FileManager = .default
	) -> [Choice] {
		locations(in: project, fileManager: fileManager).map { file in
			Choice(file: file, name: name(of: file, in: project, environment: environment))
		}
	}

	/// What one devcontainer is called.
	///
	/// The file's own `name` first, because that is the project saying what it
	/// calls this container and is what a menu entry should read. **The folder it
	/// sits in is the answer when it has none** — `.devcontainer/go` is "go" —
	/// which is the whole reason a project with several can be offered at all:
	/// two entries both reading "Container" would say less than the refusal they
	/// replaced.
	///
	/// A file this app *refuses* still has to be named, or the refusal cannot be
	/// attributed to anything on screen, so its `name` is read straight out of the
	/// JSON when the rest of it could not be honoured. The two fixed locations
	/// have no folder of their own to be named after, and fall back to the
	/// project — which is what a project with one devcontainer has always shown.
	public static func name(
		of file: URL,
		in project: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> String {
		switch read(file, project: project, environment: environment) {
		case let .understood(configuration):
			if let named = configuration.name, !named.trimmingCharacters(in: .whitespaces).isEmpty {
				return named
			}
		case .refused:
			if let declared = declaredName(of: file),
			   !declared.trimmingCharacters(in: .whitespaces).isEmpty {
				return declared
			}
		}
		return folderName(of: file, in: project)
	}

	/// The `name` field, without asking whether the rest of the file can be
	/// honoured.
	private static func declaredName(of file: URL) -> String? {
		guard let data = try? Data(contentsOf: file) else { return nil }
		let text = RunConfigurationDiscovery.stripJSONComments(String(decoding: data, as: UTF8.self))
		guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
		      let table = object as? [String: Any]
		else { return nil }
		return table["name"] as? String
	}

	/// The folder a file in `.devcontainer/<something>/` sits in, or the project
	/// for the two fixed locations, which have no folder of their own.
	private static func folderName(of file: URL, in project: URL) -> String {
		let folder = file.deletingLastPathComponent()
		if folder.deletingLastPathComponent().lastPathComponent == ".devcontainer" {
			return folder.lastPathComponent
		}
		return project.lastPathComponent
	}

	// MARK: - Reading it

	/// The project's preferred devcontainer, or nil when it has none.
	///
	/// **Preferred, not only.** A project may have several, and which one
	/// somebody means is a question rather than a fact — this used to refuse the
	/// whole project for asking it, because there was nowhere to ask. There is
	/// now: `choices(in:)` is what the menus offer, and every one of them names
	/// itself. This stays for the callers that have nowhere to ask and must still
	/// answer, and it answers with the first in `locations`' own order, which is
	/// the order VS Code prefers them in and is sorted rather than whatever the
	/// file system said.
	///
	/// A project with one — which is nearly all of them — cannot tell the
	/// difference, and that is deliberate.
	public static func read(
		project: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		fileManager: FileManager = .default
	) -> Reading? {
		guard let first = locations(in: project, fileManager: fileManager).first else { return nil }
		return read(first, project: project, environment: environment)
	}

	/// One file, read.
	public static func read(
		_ file: URL,
		project: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> Reading {
		let shown = relative(file, to: project)
		guard let data = try? Data(contentsOf: file) else {
			return .refused("\(shown) could not be read, so there is nothing to start the project in.")
		}
		return parse(data, named: shown, project: project, environment: environment)
	}

	/// The same, from the bytes — which is what every test of this works on.
	public static func parse(
		_ data: Data,
		named shown: String = ".devcontainer/devcontainer.json",
		project: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> Reading {
		// JSON with comments and trailing commas, which is what the spec calls
		// for and what `JSONSerialization` will not take. The stripper is the one
		// launch.json already goes through.
		let text = RunConfigurationDiscovery.stripJSONComments(String(decoding: data, as: UTF8.self))
		guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
		      let file = object as? [String: Any]
		else {
			return .refused("\(shown) is not valid JSON, so nothing in it could be read.")
		}

		// The two boundaries of the subset, first, because everything after them
		// would be describing a container that is not the one the file asks for.
		if let features = file["features"] as? [String: Any], !features.isEmpty {
			let named = features.keys.sorted().first ?? ""
			return .refused(
				"\(shown) installs devcontainer features (\(named)), which this app does not "
					+ "build — put what they provide into the image or the Dockerfile the file names.")
		}
		if file["dockerComposeFile"] != nil {
			let named = (file["dockerComposeFile"] as? String)
				?? (file["dockerComposeFile"] as? [String])?.first ?? "a compose file"
			return .refused(
				"\(shown) builds this project with Docker Compose (\(named)), which this app "
					+ "does not run — a single image or build.dockerfile is what it can start.")
		}
		let localFolder = FilePath.canonical(project)
		let localBasename = (localFolder as NSString).lastPathComponent

		// The workspace folder first, because `${containerWorkspaceFolder}` is
		// substituted into everything else and has to have a value by then.
		var resolve = Substitution(
			localWorkspaceFolder: localFolder,
			localWorkspaceFolderBasename: localBasename,
			containerWorkspaceFolder: nil,
			environment: environment
		)
		let declaredFolder = (file["workspaceFolder"] as? String).map { resolve($0) }
		if let unresolvable = resolve.unresolvable {
			return .refused(refusalForContainerEnv(unresolvable, in: shown))
		}

		// Where the project is mounted. `workspaceMount` overrides it, and is the
		// one place a file can put the checkout somewhere other than the folder
		// it works in.
		var mountTarget = declaredFolder ?? "/workspaces/\(localBasename)"
		if let declared = file["workspaceMount"] {
			guard let text = declared as? String else {
				return .refused("\(shown) has a workspaceMount that is not a string, so where the "
					+ "project would be mounted could not be read.")
			}
			let mount = MountSpecification(resolve(text))
			if let unresolvable = resolve.unresolvable {
				return .refused(refusalForContainerEnv(unresolvable, in: shown))
			}
			guard mount["type"] ?? "bind" == "bind" else {
				return .refused("\(shown) mounts the workspace as a \(mount["type"] ?? "") volume "
					+ "rather than binding the checkout, and this app only opens a project whose "
					+ "files stay on this machine.")
			}
			guard let source = mount["source"] ?? mount["src"], let target = mount["target"] ?? mount["dst"]
			else {
				return .refused("\(shown) has a workspaceMount with no source and target, so where "
					+ "the project would be mounted could not be read.")
			}
			guard FilePath.canonical(URL(fileURLWithPath: source)) == localFolder else {
				return .refused("\(shown) mounts \(source) as the workspace rather than this project, "
					+ "and this app opens the project it was given.")
			}
			mountTarget = target
		}

		let paths = ContainerPaths(host: localFolder, container: mountTarget)
		let workspaceFolder = declaredFolder ?? paths.container
		// `ContainerPaths` is the one that knows what "inside the project" means,
		// so it is the one asked. A folder outside the mount is a shell starting
		// in a directory the container has never heard of.
		guard paths.toHost(path: workspaceFolder) != nil else {
			return .refused("\(shown) mounts the project at \(paths.container) but works in "
				+ "\(workspaceFolder), which is not inside it, so a shell would start nowhere.")
		}

		resolve.containerWorkspaceFolder = paths.container

		// What the container comes from.
		//
		// Every relative path in a `build` is relative to the *file*, not to the
		// project: a `.devcontainer/Dockerfile` is written as `Dockerfile` and a
		// context of `..` is how such a file reaches the checkout above it.
		let here = URL(fileURLWithPath: fileURL(shown, project: project))
		let image = (file["image"] as? String).map { resolve($0) }
		var build: DevContainerConfiguration.Build?
		if let declared = file["build"] as? [String: Any] {
			let dockerfile = (declared["dockerfile"] as? String) ?? (declared["dockerFile"] as? String)
			guard let dockerfile else {
				return .refused("\(shown) has a build section with no dockerfile in it, so there is "
					+ "nothing to build the container from.")
			}
			build = DevContainerConfiguration.Build(
				dockerfile: absolute(resolve(dockerfile), from: here),
				context: absolute((declared["context"] as? String).map { resolve($0) } ?? ".", from: here),
				args: stringTable(declared["args"], resolve: { resolve($0) }),
				target: (declared["target"] as? String).map { resolve($0) }
			)
		} else if let dockerfile = file["dockerFile"] as? String {
			// The older spelling, which containers published years ago still use.
			build = DevContainerConfiguration.Build(
				dockerfile: absolute(resolve(dockerfile), from: here),
				context: absolute((file["context"] as? String).map { resolve($0) } ?? ".", from: here),
				args: [:],
				target: nil
			)
		}
		if let unresolvable = resolve.unresolvable {
			return .refused(refusalForContainerEnv(unresolvable, in: shown))
		}
		switch (image, build) {
		case (nil, nil):
			return .refused("\(shown) names neither an image nor a Dockerfile, so there is nothing "
				+ "to start this project in.")
		case (.some, .some):
			return .refused("\(shown) names both an image and a Dockerfile to build, and only one "
				+ "of them can be what the container comes from.")
		default:
			break
		}

		// The ports.
		var forwarded: [Int] = []
		for entry in file["forwardPorts"] as? [Any] ?? [] {
			if let port = entry as? Int { forwarded.append(port); continue }
			if let text = entry as? String, let port = Int(text) { forwarded.append(port); continue }
			return .refused("\(shown) forwards \(entry), which is not a port number this app can "
				+ "publish — a plain number is what it understands.")
		}

		// The extra mounts, in the form `--mount` already takes.
		var extra: [String] = []
		for entry in file["mounts"] as? [Any] ?? [] {
			if let text = entry as? String { extra.append(resolve(text)); continue }
			if let table = entry as? [String: Any] {
				let pairs = table.keys.sorted().compactMap { key -> String? in
					guard let value = table[key] as? String else { return nil }
					return "\(key)=\(resolve(value))"
				}
				extra.append(pairs.joined(separator: ","))
				continue
			}
			return .refused("\(shown) has a mount this app could not read, so something the project "
				+ "expects to see would be missing from the container.")
		}

		// The lifecycle commands, last of the parts because the substitutions in
		// them want `${containerWorkspaceFolder}`, which only has a value once the
		// mount above has been worked out.
		var commands: [DevContainerStage: DevContainerCommand] = [:]
		for stage in DevContainerStage.allCases {
			guard let declared = file[stage.rawValue] else { continue }
			guard let command = DevContainerCommand.read(declared) else {
				return .refused("\(shown) has a \(stage.rawValue) this app could not read — the spec "
					+ "allows a string, a list of arguments, or an object of named commands.")
			}
			commands[stage] = command.resolved { resolve($0) }
		}
		var waitFor: DevContainerStage?
		if let declared = file["waitFor"] {
			guard let text = declared as? String, let stage = DevContainerStage(rawValue: text),
			      stage != .initializeCommand
			else {
				return .refused("\(shown) waits for \(declared), which is not one of the lifecycle "
					+ "commands — waitFor names onCreateCommand, updateContentCommand, "
					+ "postCreateCommand, postStartCommand or postAttachCommand.")
			}
			waitFor = stage
		}

		let configuration = DevContainerConfiguration(
			file: here,
			project: URL(fileURLWithPath: localFolder, isDirectory: true),
			name: (file["name"] as? String).map { resolve($0) },
			image: image,
			build: build,
			paths: paths,
			workspaceFolder: workspaceFolder,
			containerUser: (file["containerUser"] as? String).map { resolve($0) },
			remoteUser: (file["remoteUser"] as? String).map { resolve($0) },
			containerEnv: stringTable(file["containerEnv"], resolve: { resolve($0) }),
			remoteEnv: stringTable(file["remoteEnv"], resolve: { resolve($0) }),
			forwardPorts: forwarded,
			extraMounts: extra,
			runArgs: (file["runArgs"] as? [String] ?? []).map { resolve($0) },
			lifecycle: DevContainerLifecycle(commands: commands, waitFor: waitFor)
		)
		if let unresolvable = resolve.unresolvable {
			return .refused(refusalForContainerEnv(unresolvable, in: shown))
		}
		return .understood(configuration)
	}

	// MARK: - The parts

	private static func refusalForContainerEnv(_ variable: String, in shown: String) -> String {
		"\(shown) uses ${containerEnv:\(variable)}, whose value only exists once the container is "
			+ "running, and this app cannot read it before starting one."
	}

	private static func stringTable(_ value: Any?, resolve: (String) -> String) -> [String: String] {
		guard let table = value as? [String: Any] else { return [:] }
		var result: [String: String] = [:]
		for (key, entry) in table {
			guard let text = entry as? String else { continue }
			result[key] = resolve(text)
		}
		return result
	}

	/// Where a file sits inside the project, as the file itself would be written
	/// in a message about it.
	///
	/// **Both sides through `realpath`, and the asymmetry was the bug.** The root
	/// was canonicalised and the file was not, so under `/tmp` — a symlink to
	/// `/private/tmp` on macOS, and where every scratch project this app's
	/// harness makes lives — the two never shared a prefix. This collapsed to
	/// `devcontainer.json` with no folder in front of it, which took a
	/// `build.dockerfile` with it (it resolves against *this*, so it became
	/// `<project>/Dockerfile`) and made two files in one project indistinguishable
	/// from each other. 0430.
	private static func relative(_ url: URL, to project: URL) -> String {
		let root = FilePath.canonical(project)
		let path = FilePath.canonical(url)
		guard path.hasPrefix(root + "/") else { return url.lastPathComponent }
		return String(path.dropFirst(root.count + 1))
	}

	private static func fileURL(_ shown: String, project: URL) -> String {
		FilePath.canonical(project) + "/" + shown
	}

	/// A path from the file, as this machine names it.
	///
	/// The `..` in a context of `..` is collapsed here rather than by
	/// `standardizedFileURL`, which has the special case `FilePath` warns about:
	/// it rewrites a leading `/private/var` back to `/var`, and the path is
	/// about to be handed to a runtime that knows the directory by its real
	/// name. Nothing here touches the file system, so a Dockerfile that has not
	/// been written yet still resolves.
	private static func absolute(_ path: String, from file: URL) -> String {
		let joined = path.hasPrefix("/")
			? path
			: file.deletingLastPathComponent().path + "/" + path
		var parts: [Substring] = []
		for component in joined.split(separator: "/") {
			switch component {
			case ".": continue
			case "..": if !parts.isEmpty { parts.removeLast() }
			default: parts.append(component)
			}
		}
		return "/" + parts.joined(separator: "/")
	}

	// MARK: - ${…}

	/// The substitutions the spec puts through every string in the file.
	///
	/// Only the ones that can be answered on this side of the container:
	/// `${localEnv:…}` from this process's environment, and the two workspace
	/// folders. `${containerEnv:…}` cannot be answered before the container is
	/// running, and is recorded rather than guessed at — a `PATH` silently
	/// resolved to the empty string is a container that comes up and finds
	/// nothing.
	///
	/// Anything else is left exactly as written, which is what VS Code does and
	/// is the only answer that does not corrupt a value it did not understand.
	struct Substitution {
		let localWorkspaceFolder: String
		let localWorkspaceFolderBasename: String
		var containerWorkspaceFolder: String?
		let environment: [String: String]
		/// The first `${containerEnv:…}` seen, if any.
		private(set) var unresolvable: String?

		mutating func callAsFunction(_ value: String) -> String {
			var result = ""
			var rest = Substring(value)
			while let opening = rest.range(of: "${") {
				result += rest[rest.startIndex..<opening.lowerBound]
				let after = opening.upperBound
				guard let closing = rest[after...].firstIndex(of: "}") else {
					result += rest[opening.lowerBound...]
					return result
				}
				let name = String(rest[after..<closing])
				result += replacement(for: name) ?? "${\(name)}"
				rest = rest[rest.index(after: closing)...]
			}
			result += rest
			return result
		}

		private mutating func replacement(for name: String) -> String? {
			switch name {
			case "localWorkspaceFolder": return localWorkspaceFolder
			case "localWorkspaceFolderBasename": return localWorkspaceFolderBasename
			case "containerWorkspaceFolder": return containerWorkspaceFolder
			case "containerWorkspaceFolderBasename":
				return containerWorkspaceFolder.map { ($0 as NSString).lastPathComponent }
			default: break
			}
			// `${localEnv:NAME}` and `${localEnv:NAME:fallback}`. A variable this
			// machine does not have becomes the empty string, which is what the
			// spec says and what a file expecting an optional setting relies on.
			if name.hasPrefix("localEnv:") {
				let rest = name.dropFirst("localEnv:".count)
				let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
				let variable = String(parts[0])
				let fallback = parts.count > 1 ? String(parts[1]) : ""
				let value = environment[variable] ?? ""
				return value.isEmpty ? fallback : value
			}
			if name.hasPrefix("containerEnv:") {
				if unresolvable == nil { unresolvable = String(name.dropFirst("containerEnv:".count)) }
				return nil
			}
			return nil
		}
	}

	/// A `source=…,target=…,type=bind` string, taken apart.
	struct MountSpecification {
		private let fields: [String: String]

		init(_ text: String) {
			var fields: [String: String] = [:]
			for part in text.split(separator: ",") {
				let pair = part.split(separator: "=", maxSplits: 1)
				guard pair.count == 2 else { continue }
				fields[String(pair[0]).trimmingCharacters(in: .whitespaces)] =
					String(pair[1]).trimmingCharacters(in: .whitespaces)
			}
			self.fields = fields
		}

		subscript(key: String) -> String? { fields[key] }
	}
}
