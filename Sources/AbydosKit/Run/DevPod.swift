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
		arguments: [String] = [],
		environment: [String: String] = [:],
		compress: Bool = true
	) async throws -> DevPodStatus {
		let data = try Data(contentsOf: binary)

		// The chart's values are the default; these are what the developer is
		// working with, and the program has to be started with them.
		var query = [URLQueryItem(name: "mode", value: mode)]
		query += arguments.map { URLQueryItem(name: "arg", value: $0) }
		query += environment.sorted { $0.key < $1.key }
			.map { URLQueryItem(name: "env", value: "\($0.key)=\($0.value)") }

		var request = URLRequest(
			url: base.appendingPathComponent("binary").appending(queryItems: query)
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

	/// Sends something the program reads.
	@discardableResult
	public func push(file: URL, to path: String) async throws -> String {
		let data = try Data(contentsOf: file)
		var request = URLRequest(
			url: base.appendingPathComponent("file")
				.appending(queryItems: [URLQueryItem(name: "path", value: path)])
		)
		request.httpMethod = "POST"
		if let packed = Gzip.compress(data) {
			request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
			request.httpBody = packed
		} else {
			request.httpBody = data
		}

		let (body, response) = try await send(request)
		guard response.statusCode == 200 else {
			throw Failure.refused(response.statusCode, String(decoding: body, as: UTF8.self))
		}
		return path
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

/// Why a cluster was refused.
public enum ContextRefusal: Error, Equatable, Sendable {
	case noCurrentContext
	case notAllowed(context: String, patterns: String)

	/// What to say, in the words of the person who set the rule.
	public var message: String {
		switch self {
		case .noCurrentContext:
			return "kubectl has no current context, and this configuration follows it."
		case let .notAllowed(context, patterns):
			return "The current context is “\(context)”, and this configuration only runs on "
				+ "\(patterns). Switch context, or change what it allows."
		}
	}
}

/// Matching context names against what a configuration allows.
public enum ContextPattern {
	/// `*-local, k3c-*` — a list, because a team has more than one kind of
	/// cluster it is safe to run on.
	public static func list(_ text: String) -> [String] {
		text
			.split(whereSeparator: { $0 == "," || $0 == " " })
			.map { String($0).trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}

	/// Glob matching: `*` for any run of characters, `?` for one.
	///
	/// Not a regular expression: a pattern in a configuration file is written
	/// by somebody thinking about shell globs, and `*-local` should mean what
	/// it looks like rather than "anything at all".
	public static func matches(_ name: String, _ pattern: String) -> Bool {
		matches(Array(name.lowercased()), Array(pattern.lowercased()))
	}

	private static func matches(_ name: [Character], _ pattern: [Character]) -> Bool {
		var nameIndex = 0
		var patternIndex = 0
		// Where to resume after the last `*`, so backtracking costs nothing.
		var starPattern = -1
		var starName = 0

		while nameIndex < name.count {
			if patternIndex < pattern.count,
			   pattern[patternIndex] == "?" || pattern[patternIndex] == name[nameIndex] {
				nameIndex += 1
				patternIndex += 1
			} else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
				starPattern = patternIndex
				starName = nameIndex
				patternIndex += 1
			} else if starPattern >= 0 {
				patternIndex = starPattern + 1
				starName += 1
				nameIndex = starName
			} else {
				return false
			}
		}
		while patternIndex < pattern.count, pattern[patternIndex] == "*" { patternIndex += 1 }
		return patternIndex == pattern.count
	}
}

/// Finding development pods.
public enum DevPods {
	/// The label the chart puts on every pod it makes.
	public static let label = "abydos.dev/devpod=true"

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

/// Which image a development pod runs.
///
/// The image carries a debugger, and a pod only ever debugs one language, so
/// there are three of them: Delve for Go, gdbserver for a native binary, and
/// one with both for when this cannot tell. Choosing the right one halves what
/// the cluster pulls — 13 MB against 32 — without anybody having to know that
/// the tags exist.
public enum DevPodImage {
	public static let repository = "pharndt/abydos-devpod"
	public static let version = "dev"

	/// The full image: both debuggers, and what an unrecognised project gets.
	public static var `default`: String { "\(repository):\(version)" }

	/// The image for a project, unless the configuration names one itself.
	///
	/// What somebody typed always wins. A cluster that mirrors one tag, or a
	/// pod image built in-house, is not something to be clever about — and the
	/// field is only empty when nobody has expressed a preference at all.
	public static func resolved(
		_ chosen: String,
		for configuration: LaunchConfiguration,
		root: URL
	) -> String {
		let named = chosen.trimmingCharacters(in: .whitespaces)
		guard named.isEmpty else { return named }

		switch DevPodBuild.debugger(for: configuration, root: root) {
		case .delve: return "\(repository):\(version)-go"
		case .gdbserver: return "\(repository):\(version)-native"
		// The one variant that is bigger rather than smaller: a JRE and its
		// libraries are 167 MB, and no other language's pod has a use for them.
		case .jdwp: return "\(repository):\(version)-jvm"
		case nil: return `default`
		}
	}

	/// An image reference split into the chart's two values.
	///
	/// The chart writes `{{ .Values.image.repository }}:{{ .Values.image.tag }}`,
	/// so setting the repository to something with a tag on it produces
	/// `repo:tag:dev` — an image nothing can pull, and a pod stuck on
	/// ImagePullBackOff for a reason nobody can see from the outside.
	public static func values(for reference: String) -> [String] {
		guard !reference.isEmpty else { return [] }
		let (repository, tag) = split(reference)
		var values = ["image.repository=" + repository]
		if let tag { values.append("image.tag=" + tag) }
		return values
	}

	/// The repository and the tag, if there is one.
	///
	/// The last colon, but only after the last slash: `localhost:5000/thing` is
	/// a registry with a port and no tag at all.
	public static func split(_ reference: String) -> (repository: String, tag: String?) {
		let afterSlash = reference.lastIndex(of: "/").map(reference.index(after:))
			?? reference.startIndex
		guard let colon = reference[afterSlash...].lastIndex(of: ":") else {
			return (reference, nil)
		}
		return (String(reference[..<colon]), String(reference[reference.index(after: colon)...]))
	}
}
