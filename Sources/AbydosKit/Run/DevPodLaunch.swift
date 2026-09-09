import Foundation

/// A launch configuration that runs in a cluster.
///
/// The same `launch.json` entry as any other, with one extra key: where the
/// pod is. Everything else — the package, the arguments, the environment — is
/// what it already was, because the program does not change when the machine
/// it runs on does.
public extension LaunchConfiguration {
	struct DevPodSettings: Equatable, Sendable {
		/// The kube context, or empty for whichever is current.
		public var context: String
		public var namespace: String
		/// The pod, or empty to take whichever development pod is there.
		public var pod: String
		/// A kubeconfig other than the default, for a cluster that lives in a
		/// file of its own.
		public var kubeconfig: String
		/// A hostname to publish the service on, or empty for none.
		///
		/// A microservice with no chart of its own still has to be reachable to
		/// be tested. The development pod's chart can publish one — through
		/// whichever of Gateway API, Traefik or a plain Ingress the cluster
		/// has — and this is the name it answers to.
		public var ingressHost: String
		/// The port the program listens on, or 0 for the chart's default.
		public var port: Int
		/// The image the pod runs, for a cluster that has to pull one.
		///
		/// Empty means the chart's own default, which is the image imported by
		/// hand into a local cluster. A cluster somewhere else has no way to be
		/// handed a tarball, so it is given a published image instead.
		public var image: String
		/// Files the program needs beside it, as `local` or `local:/in/the/pod`.
		///
		/// A service started with a path to its configuration cannot run in a
		/// pod that has never seen that file, and the failure — "no such file"
		/// — says nothing about the pod being empty.
		public var files: [String]
		/// Whether a missing development pod may be installed.
		///
		/// True by default: this is a development cluster, the chart is small,
		/// and stopping to say "install this first" helps nobody. A team that
		/// installs its own with a pipeline turns it off.
		public var allowInstall: Bool
		/// Which contexts this may run on, as patterns: `*-local`, `k3c-*`.
		///
		/// The point is a configuration that is shared. Everybody's cluster is
		/// called something different, so the context cannot be written down —
		/// but "anything ending in -local" can, and then the configuration
		/// follows whoever runs it without following them onto production.
		public var allowedContexts: String

		public init(
			context: String = "",
			namespace: String = "",
			pod: String = "",
			kubeconfig: String = "",
			allowedContexts: String = "",
			allowInstall: Bool = true,
			files: [String] = [],
			image: String = "",
			ingressHost: String = "",
			port: Int = 0
		) {
			self.context = context
			self.namespace = namespace
			self.pod = pod
			self.kubeconfig = kubeconfig
			self.allowedContexts = allowedContexts
			self.allowInstall = allowInstall
			self.files = files
			self.image = image
			self.ingressHost = ingressHost
			self.port = port
		}

		/// What `context` means when it is not a name.
		public static let currentContext = "${currentContext}"

		/// Whether this runs on whichever context kubectl is pointed at.
		public var followsCurrentContext: Bool {
			context.isEmpty || context == Self.currentContext
		}

		/// The context to use, and whether it is allowed.
		///
		/// Refusing is the whole point: a shared configuration that follows
		/// the current context follows it everywhere, and everybody has a
		/// production cluster in their kubeconfig.
		public func resolve(current: String?) -> Result<String, ContextRefusal> {
			let chosen = followsCurrentContext ? (current ?? "") : context
			guard !chosen.isEmpty else { return .failure(.noCurrentContext) }

			let patterns = ContextPattern.list(allowedContexts)
			guard patterns.isEmpty || patterns.contains(where: { ContextPattern.matches(chosen, $0) })
			else {
				return .failure(.notAllowed(context: chosen, patterns: allowedContexts))
			}
			return .success(chosen)
		}

		public var json: JSONValue {
			var fields: [String: JSONValue] = [:]
			if !context.isEmpty { fields["context"] = .string(context) }
			if !namespace.isEmpty { fields["namespace"] = .string(namespace) }
			if !pod.isEmpty { fields["pod"] = .string(pod) }
			if !kubeconfig.isEmpty { fields["kubeconfig"] = .string(kubeconfig) }
			if !allowedContexts.isEmpty { fields["allowedContexts"] = .string(allowedContexts) }
			// Written only when it is off: the default is what nearly every
			// configuration wants, and a file full of defaults is noise.
			if !allowInstall { fields["allowInstall"] = .bool(false) }
			if !files.isEmpty { fields["files"] = .array(files.map(JSONValue.string)) }
			if !image.isEmpty { fields["image"] = .string(image) }
			if !ingressHost.isEmpty { fields["ingressHost"] = .string(ingressHost) }
			if port > 0 { fields["port"] = .number(Double(port)) }
			return .object(fields)
		}

		public init?(json: JSONValue) {
			guard case let .object(fields) = json else { return nil }
			func string(_ key: String) -> String {
				guard case let .string(value)? = fields[key] else { return "" }
				return value
			}
			var allowInstall = true
			if case let .bool(value)? = fields["allowInstall"] { allowInstall = value }

			var files: [String] = []
			if case let .array(values)? = fields["files"] {
				files = values.compactMap { value in
					guard case let .string(text) = value else { return nil }
					return text
				}
			}

			self.init(
				context: string("context"),
				namespace: string("namespace"),
				pod: string("pod"),
				kubeconfig: string("kubeconfig"),
				allowedContexts: string("allowedContexts"),
				allowInstall: allowInstall,
				files: files,
				image: string("image"),
				ingressHost: string("ingressHost"),
				port: {
					guard case let .number(value)? = fields["port"] else { return 0 }
					return Int(value)
				}()
			)
		}

		/// How a person would describe where this runs.
		public var summary: String {
			let place = [followsCurrentContext ? "current context" : context, namespace]
				.filter { !$0.isEmpty }
				.joined(separator: "/")
			return pod.isEmpty ? place : place + " · " + pod
		}
	}

	/// Where this runs, when it does not run here.
	var devPod: DevPodSettings? {
		get {
			guard let value = extra("devPod") else { return nil }
			return DevPodSettings(json: value)
		}
		set {
			guard let newValue else {
				setExtra("devPod", nil)
				return
			}
			setExtra("devPod", newValue.json)
		}
	}

	/// A project's own chart, and which container of it this replaces.
	struct HelmSettings: Equatable, Sendable {
		/// Where the chart is, relative to the project or absolute.
		public var chart: String
		/// The release name. A project's chart is somebody else's too, and the
		/// release is what says whose copy this is.
		public var release: String
		/// Values files, in the order helm should read them — the stage's, then
		/// whatever this developer overrides.
		public var valueFiles: [String]
		/// Whether the values are encrypted, and helm needs its secrets plugin.
		public var usesSecrets: Bool
		/// `--set` values, for the one or two things that are not worth a file.
		public var sets: [String]
		/// The container this configuration replaces with the supervisor. A pod
		/// with an application and a web front end in it is two configurations,
		/// one for each.
		public var container: String
		/// Whether the chart may be installed when the release is not there.
		public var install: Bool

		public init(
			chart: String = "",
			release: String = "",
			valueFiles: [String] = [],
			usesSecrets: Bool = false,
			sets: [String] = [],
			container: String = "",
			install: Bool = true
		) {
			self.chart = chart
			self.release = release
			self.valueFiles = valueFiles
			self.usesSecrets = usesSecrets
			self.sets = sets
			self.container = container
			self.install = install
		}

		public var json: JSONValue {
			var fields: [String: JSONValue] = [:]
			if !chart.isEmpty { fields["chart"] = .string(chart) }
			if !release.isEmpty { fields["release"] = .string(release) }
			if !valueFiles.isEmpty { fields["values"] = .array(valueFiles.map(JSONValue.string)) }
			if usesSecrets { fields["secrets"] = .bool(true) }
			if !sets.isEmpty { fields["set"] = .array(sets.map(JSONValue.string)) }
			if !container.isEmpty { fields["container"] = .string(container) }
			if !install { fields["install"] = .bool(false) }
			return .object(fields)
		}

		public init?(json: JSONValue) {
			guard case let .object(fields) = json else { return nil }
			func string(_ key: String) -> String {
				guard case let .string(value)? = fields[key] else { return "" }
				return value
			}
			func list(_ key: String) -> [String] {
				guard case let .array(values)? = fields[key] else { return [] }
				return values.compactMap { value in
					guard case let .string(text) = value else { return nil }
					return text
				}
			}
			var install = true
			if case let .bool(value)? = fields["install"] { install = value }
			var secrets = false
			if case let .bool(value)? = fields["secrets"] { secrets = value }

			self.init(
				chart: string("chart"),
				release: string("release"),
				valueFiles: list("values"),
				usesSecrets: secrets,
				sets: list("set"),
				container: string("container"),
				install: install
			)
		}
	}

	/// The project's own chart, when this configuration runs inside one.
	var helm: HelmSettings? {
		get {
			guard let value = extra("helm") else { return nil }
			return HelmSettings(json: value)
		}
		set {
			guard let newValue else {
				setExtra("helm", nil)
				return
			}
			setExtra("helm", newValue.json)
		}
	}

	/// What kind of thing this configuration starts, in the terms the editor
	/// offers rather than the ones the file uses.
	enum Kind: String, CaseIterable, Sendable {
		case go = "Go package"
		case executable = "Executable"
		case devPod = "In a cluster"
		case helmDevPod = "In a cluster, with this project's chart"

		/// Whether this runs somewhere else.
		public var runsInCluster: Bool { self == .devPod || self == .helmDevPod }

		public var explanation: String {
			switch self {
			case .go: return "Built and run here, with Delve for debugging."
			case .executable: return "A binary that already exists, run with LLDB."
			case .devPod:
				return "Built here, pushed into a development pod, and debugged there. "
					+ "For a service with no chart of its own."
			case .helmDevPod:
				return "The project's chart is installed as it is, and one container of it "
					+ "runs the build from this machine — same environment, same secrets, "
					+ "same neighbours."
			}
		}
	}

	var kind: Kind {
		get {
			if helm != nil { return .helmDevPod }
			if devPod != nil { return .devPod }
			return type == "go" ? .go : .executable
		}
		set {
			switch newValue {
			case .go:
				type = "go"
				devPod = nil
				helm = nil
			case .executable:
				type = "lldb"
				devPod = nil
				helm = nil
			case .devPod:
				type = "go"
				if devPod == nil { devPod = DevPodSettings() }
				helm = nil
			case .helmDevPod:
				type = "go"
				if devPod == nil { devPod = DevPodSettings() }
				if helm == nil { helm = HelmSettings() }
			}
		}
	}
}

/// Working out what to send into a pod, and what the program should be told
/// about where it landed.
public enum DevPodFiles {
	/// One file on its way in.
	public struct Transfer: Equatable, Sendable {
		public let local: URL
		/// Where it lands in the pod.
		public let remote: String

		public init(local: URL, remote: String) {
			self.local = local
			self.remote = remote
		}
	}

	/// What the chart has to be told to publish this service.
	///
	/// Kept here rather than built where helm is called, so the one place that
	/// knows the chart's value names is the one place that has to change when
	/// the chart does.
	/// - Parameter image: the image the pod should run, when it has been worked
	///   out from the project rather than typed into the configuration.
	public static func helmValues(
		for settings: LaunchConfiguration.DevPodSettings,
		image: String? = nil
	) -> [String] {
		var values: [String] = []
		if !settings.ingressHost.isEmpty {
			values += ["ingress.enabled=true", "ingress.host=" + settings.ingressHost]
		}
		if settings.port > 0 {
			values += ["app.ports[0].name=http", "app.ports[0].containerPort=\(settings.port)"]
		}
		values += DevPodImage.values(for: image ?? settings.image)
		return values
	}

	/// How a file is written down in a configuration.
	///
	/// Relative to the project when it is in the project, because a
	/// configuration is shared and `/Users/somebody/...` is not; absolute
	/// otherwise, because that is the only thing that would find it.
	public static func entry(for file: URL, in root: URL?) -> String {
		let path = FilePath.canonical(file)
		guard let root else { return path }
		let base = FilePath.canonical(root)
		guard path.hasPrefix(base + "/") else { return path }
		return String(path.dropFirst(base.count + 1))
	}

	/// The default place for something sent along: beside the program.
	public static let directory = "/app/files"

	/// What a configuration says to send, plus whatever its arguments name.
	///
    /// The arguments are read too because that is how a service is usually
	/// told where its configuration is — `myservice /path/to/config.json` —
	/// and a path that exists on this machine means nothing in a pod. Those
	/// arguments are rewritten to where the file lands, so the program is told
	/// the truth.
	public static func plan(
		files: [String],
		arguments: [String],
		root: URL
	) -> (transfers: [Transfer], arguments: [String]) {
		var transfers: [Transfer] = []
		var seen: Set<String> = []

		func add(_ local: URL, _ remote: String) {
			guard seen.insert(local.path).inserted else { return }
			transfers.append(Transfer(local: local, remote: remote))
		}

		for entry in files {
			let expanded = LaunchConfiguration.expand(entry, root: root)
			let parts = expanded.split(separator: ":", maxSplits: 1).map(String.init)
			let localPath = parts[0]
			// Against the project, because that is what `entry(for:in:)` wrote:
			// anything inside the project is stored relative so the
			// configuration can be shared, and read back against this process's
			// own directory instead it names nothing. The transfer is then
			// dropped without a word and the pod starts with no configuration,
			// which the program reports as a missing argument — about a file
			// the configuration does list.
			//
			// Canonical, because the arguments below are expanded against the
			// canonical root and the two are compared by path to send a file
			// once. Resolved any other way, a file both listed and named is
			// sent twice.
			let local = localPath.hasPrefix("/")
				? URL(fileURLWithPath: localPath)
				: URL(fileURLWithPath: FilePath.canonical(root)).appendingPathComponent(localPath)
			guard FileManager.default.fileExists(atPath: local.path) else { continue }

			let remote = parts.count > 1 ? parts[1] : directory + "/" + local.lastPathComponent
			add(local, remote)
		}

		// An argument that names a file on this machine is a file the program
		// will try to open in the pod.
		var rewritten: [String] = []
		for argument in arguments {
			let expanded = LaunchConfiguration.expand(argument, root: root)
			var isDirectory: ObjCBool = false
			guard expanded.hasPrefix("/"),
			      FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
			      !isDirectory.boolValue
			else {
				rewritten.append(argument)
				continue
			}

			let local = URL(fileURLWithPath: expanded)
			let remote = transfers.first { $0.local.path == local.path }?.remote
				?? directory + "/" + local.lastPathComponent
			add(local, remote)
			rewritten.append(remote)
		}
		return (transfers, rewritten)
	}
}
