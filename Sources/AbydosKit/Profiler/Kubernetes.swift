import Foundation

/// A pod worth profiling.
public struct PodTarget: Equatable, Sendable, Identifiable {
	public let namespace: String
	public let name: String
	/// `Running`, `Pending`, and the rest of what kubectl reports.
	public let phase: String
	public let containers: [String]
	/// Where its pprof handlers are, as far as can be told from the spec.
	public let port: Int
	/// Why that port: an annotation, a named port, or the usual one.
	public let portSource: PortSource
	public let age: String

	public enum PortSource: String, Sendable {
		/// The pod said so itself.
		case annotation
		/// A container port called `pprof`, or 6060 by number.
		case containerPort
		/// Nothing said, so the one Go programs use.
		case convention
	}

	public var id: String { "\(namespace)/\(name)" }
	public var isRunning: Bool { phase == "Running" }

	public init(
		namespace: String,
		name: String,
		phase: String,
		containers: [String],
		port: Int,
		portSource: PortSource,
		age: String = ""
	) {
		self.namespace = namespace
		self.name = name
		self.phase = phase
		self.containers = containers
		self.port = port
		self.portSource = portSource
		self.age = age
	}
}

/// Talking to a cluster.
///
/// Through `kubectl` rather than the API directly: it already knows the
/// kubeconfig, the contexts, the certificates, whatever exec plugin the
/// cluster needs for authentication, and the proxy in front of it. Every one
/// of those is a project on its own, and the user has already solved them all
/// for the tool sitting on their PATH.
public enum Kubernetes {
	/// The pprof port a pod can declare when its spec cannot show one — a
	/// host-network pod, say, where a container port would claim the port on
	/// the node itself. goprofiler's annotation, so pods already marked for it
	/// need no second one.
	public static let portAnnotation = "goprofiler.io/port"
	/// What Go programs serve pprof on when nobody chose.
	public static let conventionalPort = 6060

	public static var isAvailable: Bool { executable != nil }

	/// `kubectl`, wherever it is.
	///
	/// A GUI app's PATH is not a shell's, so the usual places are checked as
	/// well — including Rancher Desktop's, which is where a Mac often has it.
	public static var executable: String? {
		let candidates = [
			"/opt/homebrew/bin/kubectl",
			"/usr/local/bin/kubectl",
			"/usr/bin/kubectl",
			NSHomeDirectory() + "/.rd/bin/kubectl",
			NSHomeDirectory() + "/.docker/bin/kubectl",
		]
		let manager = FileManager.default
		if let onPath = which("kubectl") { return onPath }
		return candidates.first { manager.isExecutableFile(atPath: $0) }
	}

	private static func which(_ name: String) -> String? {
		let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
		let manager = FileManager.default
		for directory in path.split(separator: ":") {
			let candidate = String(directory) + "/" + name
			if manager.isExecutableFile(atPath: candidate) { return candidate }
		}
		return nil
	}

	// MARK: - Discovery

	public static func contexts(kubeconfig: String? = nil) async -> [String] {
		let result = await run(["config", "get-contexts", "-o", "name"], kubeconfig: kubeconfig)
		guard result.exitCode == 0 else { return [] }
		return result.stdout
			.split(separator: "\n")
			.map { String($0).trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}

	public static func currentContext(kubeconfig: String? = nil) async -> String? {
		let result = await run(["config", "current-context"], kubeconfig: kubeconfig)
		let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return result.exitCode == 0 && !name.isEmpty ? name : nil
	}

	public static func namespaces(context: String?) async -> [String] {
		let result = await run(
			["get", "namespaces", "-o", "jsonpath={.items[*].metadata.name}"], context: context
		)
		guard result.exitCode == 0 else { return [] }
		return result.stdout.split(separator: " ").map(String.init).filter { !$0.isEmpty }
	}

	/// The pods in a namespace, or in all of them.
	public static func pods(
		context: String?,
		namespace: String?,
		kubeconfig: String? = nil
	) async -> [PodTarget] {
		var arguments = ["get", "pods", "-o", "json"]
		if let namespace, !namespace.isEmpty {
			arguments += ["-n", namespace]
		} else {
			arguments.append("--all-namespaces")
		}

		let result = await run(arguments, context: context, kubeconfig: kubeconfig)
		guard result.exitCode == 0 else { return [] }
		return parsePods(result.stdout)
	}

	/// Reads `kubectl get pods -o json`.
	///
	/// Internal rather than private so the port rules can be tested against
	/// real cluster output without a cluster.
	static func parsePods(_ json: String) -> [PodTarget] {
		guard let data = json.data(using: .utf8),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let items = object["items"] as? [[String: Any]]
		else { return [] }

		return items.compactMap { item -> PodTarget? in
			guard let metadata = item["metadata"] as? [String: Any],
			      let name = metadata["name"] as? String
			else { return nil }

			let namespace = metadata["namespace"] as? String ?? "default"
			let annotations = metadata["annotations"] as? [String: String] ?? [:]
			let labels = metadata["labels"] as? [String: String] ?? [:]
			let spec = item["spec"] as? [String: Any] ?? [:]
			let containers = spec["containers"] as? [[String: Any]] ?? []
			let status = item["status"] as? [String: Any] ?? [:]

			let (port, source) = profilingPort(annotations: annotations, labels: labels, containers: containers)

			return PodTarget(
				namespace: namespace,
				name: name,
				phase: status["phase"] as? String ?? "Unknown",
				containers: containers.compactMap { $0["name"] as? String },
				port: port,
				portSource: source,
				age: age(since: metadata["creationTimestamp"] as? String)
			)
		}
	}

	/// Where a pod's pprof handlers are.
	///
	/// The pod's own word first, then a port that says what it is, then the
	/// convention. Guessing last, and saying that it guessed, because a
	/// forward to the wrong port fails in a way that looks like the profiler
	/// is broken.
	static func profilingPort(
		annotations: [String: String],
		labels: [String: String],
		containers: [[String: Any]]
	) -> (Int, PodTarget.PortSource) {
		if let declared = annotations[portAnnotation] ?? labels[portAnnotation],
		   let port = Int(declared), (1...65535).contains(port) {
			return (port, .annotation)
		}

		for container in containers {
			for entry in container["ports"] as? [[String: Any]] ?? [] {
				let number = (entry["containerPort"] as? Int)
					?? Int((entry["containerPort"] as? NSNumber)?.intValue ?? 0)
				let named = (entry["name"] as? String ?? "").lowercased()
				if named.contains("pprof") || named.contains("profil") || number == conventionalPort {
					return (number > 0 ? number : conventionalPort, .containerPort)
				}
			}
		}
		return (conventionalPort, .convention)
	}

	/// `2d`, `4h`, `35m` — how kubectl writes it.
	static func age(since timestamp: String?, now: Date = Date()) -> String {
		guard let timestamp else { return "" }
		let formatter = ISO8601DateFormatter()
		guard let created = formatter.date(from: timestamp) else { return "" }

		let seconds = now.timeIntervalSince(created)
		guard seconds > 0 else { return "0s" }
		switch seconds {
		case ..<60: return "\(Int(seconds))s"
		case ..<3600: return "\(Int(seconds / 60))m"
		case ..<86_400: return "\(Int(seconds / 3600))h"
		default: return "\(Int(seconds / 86_400))d"
		}
	}

	// MARK: - Running kubectl

	public struct Result: Sendable {
		public let exitCode: Int32
		public let stdout: String
		public let stderr: String
	}

	/// Runs kubectl. Public because putting a container into development mode
	/// is a patch, and the app is where that decision is made.
	public static func run(
		_ arguments: [String],
		context: String? = nil,
		kubeconfig: String? = nil
	) async -> Result {
		guard let executable else {
			return Result(exitCode: 127, stdout: "", stderr: "kubectl is not installed")
		}
		var full = arguments
		if let context, !context.isEmpty { full = ["--context", context] + full }
		// A cluster that lives in a file of its own — a k3d cluster on a remote
		// machine, a customer's kubeconfig — rather than in the merged default.
		if let kubeconfig, !kubeconfig.isEmpty {
			full = ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath] + full
		}

		return await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: executable)
				process.arguments = full

				let out = Pipe(), err = Pipe()
				process.standardOutput = out
				process.standardError = err

				do {
					try process.run()
				} catch {
					continuation.resume(returning: Result(
						exitCode: 127, stdout: "", stderr: error.localizedDescription
					))
					return
				}

				let captured = ProcessPipes.drainText(process, out: out, err: err)

				continuation.resume(returning: Result(
					exitCode: process.terminationStatus,
					stdout: captured.stdout,
					stderr: captured.stderr
				))
			}
		}
	}
}

/// A `kubectl port-forward` that is running.
///
/// Held onto for as long as the profiler is pointed at the pod, and stopped
/// when it is not: a forward that outlives its use is a socket listening on
/// localhost that nobody remembers opening.
public final class PortForward: @unchecked Sendable {
	public enum Failure: Error, Equatable {
		case noKubectl
		case noFreePort
		case failed(String)
		case timedOut
	}

	public let target: PodTarget
	public let localPort: Int
	private let process: Process

	private init(target: PodTarget, localPort: Int, process: Process) {
		self.target = target
		self.localPort = localPort
		self.process = process
	}

	public var isRunning: Bool { process.isRunning }

	public func stop() {
		guard process.isRunning else { return }
		process.terminate()
	}

	deinit { stop() }

	/// Starts the forward and waits until it is actually listening.
	///
	/// Waiting matters: kubectl prints "Forwarding from" only once the tunnel
	/// is up, and a fetch sent before that fails with a connection refused
	/// that looks like the program is not serving pprof at all.
	public static func start(
		to target: PodTarget,
		context: String?,
		remotePort: Int? = nil,
		kubeconfig: String? = nil,
		timeout: TimeInterval = 15
	) async throws -> PortForward {
		guard let executable = Kubernetes.executable else { throw Failure.noKubectl }
		guard let localPort = freePort() else { throw Failure.noFreePort }
		// A pod may be reached on more than one port at once — a control port
		// and a debugger's — so the caller can say which rather than the
		// target's one.
		let port = remotePort ?? target.port

		var arguments: [String] = []
		if let kubeconfig, !kubeconfig.isEmpty {
			arguments += ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath]
		}
		if let context, !context.isEmpty { arguments += ["--context", context] }
		arguments += [
			"port-forward",
			"-n", target.namespace,
			"pod/\(target.name)",
			"\(localPort):\(port)",
		]

		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments

		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err

		do {
			try process.run()
		} catch {
			throw Failure.failed(error.localizedDescription)
		}

		let forward = PortForward(target: target, localPort: localPort, process: process)
		do {
			try await waitUntilReady(out: out, err: err, process: process, timeout: timeout)
		} catch {
			forward.stop()
			throw error
		}
		return forward
	}

	private static func waitUntilReady(
		out: Pipe,
		err: Pipe,
		process: Process,
		timeout: TimeInterval
	) async throws {
		let deadline = Date().addingTimeInterval(timeout)
		var errorText = ""

		while Date() < deadline {
			if !process.isRunning {
				let remaining = String(
					decoding: err.fileHandleForReading.availableData, as: UTF8.self
				)
				throw Failure.failed(
					(errorText + remaining).trimmingCharacters(in: .whitespacesAndNewlines)
				)
			}

			// availableData blocks until there is something, which is exactly
			// the wait wanted here — with the deadline as the escape.
			let data = out.fileHandleForReading.availableData
			let text = String(decoding: data, as: UTF8.self)
			if text.contains("Forwarding from") { return }

			let problem = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
			if !problem.isEmpty { errorText += problem }
			try? await Task.sleep(nanoseconds: 50_000_000)
		}
		throw errorText.isEmpty ? Failure.timedOut : Failure.failed(errorText)
	}

	/// A port nobody is using.
	///
	/// The socket dance moved to `DebugPort` when a second caller wanted it — a
	/// JVM started by a wrapper script waits on a port on this machine, with no
	/// pod and no forward in it. Kept as a name here because this is where the
	/// forwards ask.
	static func freePort() -> Int? { DebugPort.free() }
}
