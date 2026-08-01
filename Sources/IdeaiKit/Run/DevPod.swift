import Foundation

/// A development pod: one waiting in a cluster for something to run.
public struct DevPodTarget: Equatable, Sendable, Identifiable {
	public let namespace: String
	public let name: String
	public let phase: String
	public let controlPort: Int
	public let debugPort: Int
	public let age: String

	public var id: String { "\(namespace)/\(name)" }
	public var isRunning: Bool { phase == "Running" }

	public init(
		namespace: String,
		name: String,
		phase: String,
		controlPort: Int = 7999,
		debugPort: Int = 2345,
		age: String = ""
	) {
		self.namespace = namespace
		self.name = name
		self.phase = phase
		self.controlPort = controlPort
		self.debugPort = debugPort
		self.age = age
	}
}

/// What a development pod says about itself.
public struct DevPodStatus: Equatable, Sendable {
	public let state: String
	public let mode: String
	public let hasBinary: Bool
	public let binarySize: Int
	public let exitCode: Int?
	/// What the pod's node is, so a binary built for something else can be
	/// refused before it produces `exec format error`.
	public let architecture: String

	public init(
		state: String,
		mode: String = "",
		hasBinary: Bool = false,
		binarySize: Int = 0,
		exitCode: Int? = nil,
		architecture: String = ""
	) {
		self.state = state
		self.mode = mode
		self.hasBinary = hasBinary
		self.binarySize = binarySize
		self.exitCode = exitCode
		self.architecture = architecture
	}

	public init?(json: Data) {
		guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
			return nil
		}
		state = object["state"] as? String ?? "unknown"
		mode = object["mode"] as? String ?? ""
		hasBinary = object["hasBinary"] as? Bool ?? false
		binarySize = object["binarySize"] as? Int ?? 0
		exitCode = object["exitCode"] as? Int
		architecture = object["arch"] as? String ?? ""
	}
}

/// Talking to the supervisor inside a development pod.
///
/// Over a port-forward, so it works the same for a cluster on this machine and
/// one in a data centre: the editor never needs a route into the cluster, only
/// the credentials it already has.
public actor DevPodClient {
	public enum Failure: Error, Equatable {
		case unreachable(String)
		case refused(Int, String)
		/// The binary was built for something the node cannot run.
		case wrongArchitecture(binary: String, pod: String)
	}

	private let session: URLSession
	private let base: URL

	public init(localPort: Int, timeout: TimeInterval = 60) {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = timeout
		configuration.timeoutIntervalForResource = max(timeout, 300)
		session = URLSession(configuration: configuration)
		base = URL(string: "http://127.0.0.1:\(localPort)")!
	}

	public func status() async throws -> DevPodStatus {
		let (data, response) = try await get(base.appendingPathComponent("status"))
		guard response.statusCode == 200 else {
			throw Failure.refused(response.statusCode, String(decoding: data, as: UTF8.self))
		}
		guard let status = DevPodStatus(json: data) else {
			throw Failure.unreachable("that is not a development pod")
		}
		return status
	}

	/// Sends a binary and starts it.
	///
	/// Compressed only when it is worth it: a Go binary halves, which pays for
	/// itself over anything slower than a LAN and costs a sixth of a second on
	/// the machine the cluster is running on.
	@discardableResult
	public func push(
		binary: URL,
		mode: String,
		compress: Bool = true
	) async throws -> DevPodStatus {
		let data = try Data(contentsOf: binary)
		var request = URLRequest(
			url: base.appendingPathComponent("binary")
				.appending(queryItems: [URLQueryItem(name: "mode", value: mode)])
		)
		request.httpMethod = "POST"
		request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

		if compress, let packed = Gzip.compress(data) {
			request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
			request.httpBody = packed
		} else {
			request.httpBody = data
		}

		let (body, response) = try await send(request)
		guard response.statusCode == 200 else {
			throw Failure.refused(response.statusCode, String(decoding: body, as: UTF8.self))
		}
		guard let status = DevPodStatus(json: body) else {
			throw Failure.unreachable("the pod answered something unexpected")
		}
		return status
	}

	public func stop() async throws {
		var request = URLRequest(url: base.appendingPathComponent("stop"))
		request.httpMethod = "POST"
		_ = try await send(request)
	}

	public func logs(tail: Int = 200) async throws -> String {
		let url = base.appendingPathComponent("logs")
			.appending(queryItems: [URLQueryItem(name: "tail", value: "\(tail)")])
		let (data, _) = try await get(url)
		return String(decoding: data, as: UTF8.self)
	}

	private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
		try await send(URLRequest(url: url))
	}

	private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
		do {
			let (data, response) = try await session.data(for: request)
			guard let http = response as? HTTPURLResponse else {
				throw Failure.unreachable("no answer from the pod")
			}
			return (data, http)
		} catch let failure as Failure {
			throw failure
		} catch {
			throw Failure.unreachable(error.localizedDescription)
		}
	}
}

/// Finding development pods.
public enum DevPods {
	/// The label the chart puts on every pod it makes.
	public static let label = "ideai.dev/devpod=true"

	public static func list(
		context: String?,
		namespace: String? = nil,
		kubeconfig: String? = nil
	) async -> [DevPodTarget] {
		var arguments = ["get", "pods", "-l", label, "-o", "json"]
		if let namespace, !namespace.isEmpty {
			arguments += ["-n", namespace]
		} else {
			arguments.append("--all-namespaces")
		}

		let result = await Kubernetes.run(arguments, context: context, kubeconfig: kubeconfig)
		guard result.exitCode == 0 else { return [] }
		return parse(result.stdout)
	}

	/// Reads `kubectl get pods -o json`, taking the ports from the container
	/// rather than assuming the chart's defaults — somebody will move them.
	static func parse(_ json: String) -> [DevPodTarget] {
		guard let data = json.data(using: .utf8),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let items = object["items"] as? [[String: Any]]
		else { return [] }

		return items.compactMap { item -> DevPodTarget? in
			guard let metadata = item["metadata"] as? [String: Any],
			      let name = metadata["name"] as? String
			else { return nil }

			let spec = item["spec"] as? [String: Any] ?? [:]
			let containers = spec["containers"] as? [[String: Any]] ?? []
			var control = 7999
			var debug = 2345
			for container in containers {
				for port in container["ports"] as? [[String: Any]] ?? [] {
					let number = (port["containerPort"] as? Int)
						?? (port["containerPort"] as? NSNumber)?.intValue ?? 0
					switch port["name"] as? String {
					case "control": control = number
					case "debug": debug = number
					default: break
					}
				}
			}

			let status = item["status"] as? [String: Any] ?? [:]
			return DevPodTarget(
				namespace: metadata["namespace"] as? String ?? "default",
				name: name,
				phase: status["phase"] as? String ?? "Unknown",
				controlPort: control,
				debugPort: debug,
				age: Kubernetes.age(since: metadata["creationTimestamp"] as? String)
			)
		}
	}

	/// What the node runs, which is what the binary has to be built for.
	///
	/// A laptop is arm64 and a shared cluster usually is not; the difference
	/// shows up as `exec format error`, which explains nothing.
	public static func architecture(context: String?, kubeconfig: String? = nil) async -> String? {
		let result = await Kubernetes.run(
			["get", "nodes", "-o", "jsonpath={.items[0].status.nodeInfo.architecture}"],
			context: context,
			kubeconfig: kubeconfig
		)
		let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return result.exitCode == 0 && !value.isEmpty ? value : nil
	}
}

/// Building a Go package for a pod.
public enum DevPodBuild {
	public enum Failure: Error, Equatable {
		case noToolchain
		case failed(String)
	}

	/// Cross-compiles a package for the cluster, keeping what a debugger needs.
	///
	/// Static, because the image the pod runs has no libc in it; unoptimised
	/// and un-inlined, because otherwise a breakpoint lands on a line the
	/// compiler moved and a variable reads `<optimized out>`.
	public static func build(
		package: String,
		in directory: URL,
		architecture: String,
		output: URL
	) async throws -> URL {
		guard let go = GoTooling.findGoExecutable() else { throw Failure.noToolchain }

		let result = await ShellEnvironment.run(
			[
				shellQuoted(go), "build",
				"-gcflags", "'all=-N -l'",
				"-o", shellQuoted(output.path),
				shellQuoted(package),
			].joined(separator: " "),
			in: directory,
			environment: [
				"GOOS": "linux",
				"GOARCH": architecture,
				"CGO_ENABLED": "0",
			]
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(
				result.error.isEmpty ? result.output : result.error
			)
		}
		return output
	}

	private static func shellQuoted(_ word: String) -> String {
		guard word.contains(where: { !$0.isLetter && !$0.isNumber && !"-_./=:@".contains($0) })
		else { return word }
		return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}

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

		public init(context: String = "", namespace: String = "", pod: String = "", kubeconfig: String = "") {
			self.context = context
			self.namespace = namespace
			self.pod = pod
			self.kubeconfig = kubeconfig
		}

		public var json: JSONValue {
			var fields: [String: JSONValue] = [:]
			if !context.isEmpty { fields["context"] = .string(context) }
			if !namespace.isEmpty { fields["namespace"] = .string(namespace) }
			if !pod.isEmpty { fields["pod"] = .string(pod) }
			if !kubeconfig.isEmpty { fields["kubeconfig"] = .string(kubeconfig) }
			return .object(fields)
		}

		public init?(json: JSONValue) {
			guard case let .object(fields) = json else { return nil }
			func string(_ key: String) -> String {
				guard case let .string(value)? = fields[key] else { return "" }
				return value
			}
			self.init(
				context: string("context"),
				namespace: string("namespace"),
				pod: string("pod"),
				kubeconfig: string("kubeconfig")
			)
		}

		/// How a person would describe where this runs.
		public var summary: String {
			let place = [context.isEmpty ? "current context" : context, namespace]
				.filter { !$0.isEmpty }
				.joined(separator: "/")
			return pod.isEmpty ? place : place + " · " + pod
		}
	}

	/// Where this runs, when it does not run here.
	var devPod: DevPodSettings? {
		get {
			guard let value = extras["ideai.devPod"] else { return nil }
			return DevPodSettings(json: value)
		}
		set {
			guard let newValue else {
				extras.removeValue(forKey: "ideai.devPod")
				return
			}
			extras["ideai.devPod"] = newValue.json
		}
	}

	/// What kind of thing this configuration starts, in the terms the editor
	/// offers rather than the ones the file uses.
	enum Kind: String, CaseIterable, Sendable {
		case go = "Go package"
		case executable = "Executable"
		case devPod = "Dev pod in a cluster"

		public var explanation: String {
			switch self {
			case .go: return "Built and run here, with Delve for debugging."
			case .executable: return "A binary that already exists, run with LLDB."
			case .devPod: return "Built here, pushed into a pod, and debugged there."
			}
		}
	}

	var kind: Kind {
		get {
			if devPod != nil { return .devPod }
			return type == "go" ? .go : .executable
		}
		set {
			switch newValue {
			case .go:
				type = "go"
				devPod = nil
			case .executable:
				type = "lldb"
				devPod = nil
			case .devPod:
				type = "go"
				if devPod == nil { devPod = DevPodSettings() }
			}
		}
	}
}
