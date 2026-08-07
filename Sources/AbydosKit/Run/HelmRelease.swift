import Foundation

/// Running a project's own chart, and putting one container of it into
/// development mode.
///
/// The development pod's chart is right for a service that has none of its
/// own. A real project usually does have one: values files per stage, secrets
/// through `helm-secrets`, a pod with an application and a web front end in it,
/// a cache beside them. Reproducing that with a chart of ours would be
/// reproducing it badly, and the parts that matter — what the containers are
/// given, what they can reach — are exactly the parts that would drift.
///
/// So the chart is installed as it is, and then one container is swapped for
/// the supervisor: same pod, same environment, same secrets, same neighbours,
/// with the binary from this machine running in it. Everything else in the
/// release goes on being what the chart says it is.
public enum HelmRelease {
	public struct Failure: Error, Equatable {
		public let message: String
		public init(_ message: String) { self.message = message }
	}

	/// The arguments for installing or upgrading a project's chart.
	///
	/// Pure, so what gets run is something that can be looked at and tested
	/// rather than something to be found out by running it.
	public static func upgradeArguments(
		_ settings: LaunchConfiguration.HelmSettings,
		root: URL,
		namespace: String,
		context: String?,
		kubeconfig: String?,
		timeout: Int = 300,
		forcesConflicts: Bool = true
	) -> [String] {
		var arguments: [String] = []
		// The plugin wraps the command rather than adding a flag: `helm secrets
		// upgrade` decrypts the values files on the way past.
		if settings.usesSecrets { arguments.append("secrets") }

		// No `--wait`: the container this configuration is for is about to be
		// replaced, and waiting for the image it is being replaced with to
		// become ready is waiting for something nobody wants. What is waited on
		// is the patched deployment, afterwards.
		arguments += [
			"upgrade", "--install", settings.release,
			expand(settings.chart, root: root),
			"--namespace", namespace, "--create-namespace",
			"--timeout", "\(timeout)s",
		]
		// The container this app puts into development mode is a field the
		// cluster now records somebody else as owning, and a server-side apply
		// refuses to overwrite what it does not own. Helm reasserting the
		// chart's own image over ours is exactly what should happen here: it is
		// undone again a second later by the patch.
		if forcesConflicts { arguments.append("--force-conflicts") }
		for file in settings.valueFiles where !file.isEmpty {
			arguments += ["--values", expand(file, root: root)]
		}
		for setting in settings.sets where !setting.isEmpty {
			arguments += ["--set", setting]
		}
		if let context, !context.isEmpty { arguments += ["--kube-context", context] }
		if let kubeconfig, !kubeconfig.isEmpty {
			arguments += ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath]
		}
		return arguments
	}

	/// A path in the configuration, as a path on this machine.
	public static func expand(_ path: String, root: URL) -> String {
		var text = path.replacingOccurrences(
			of: "${workspaceFolder}", with: FilePath.canonical(root)
		)
		text = (text as NSString).expandingTildeInPath
		guard !text.hasPrefix("/") else { return text }
		return root.appendingPathComponent(text).path
	}

	/// Whether the release is there at all.
	public static func exists(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?
	) async -> Bool {
		guard let helm = DevPodInstall.helm else { return false }
		var arguments = ["status", release, "--namespace", namespace]
		if let context, !context.isEmpty { arguments += ["--kube-context", context] }
		if let kubeconfig, !kubeconfig.isEmpty {
			arguments += ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath]
		}
		return await Process.runQuietly(helm, arguments) == 0
	}

	/// Runs helm, reporting its output as it arrives.
	public static func upgrade(
		_ settings: LaunchConfiguration.HelmSettings,
		root: URL,
		namespace: String,
		context: String?,
		kubeconfig: String?,
		progress: (@Sendable (String) -> Void)? = nil
	) async throws {
		guard let helm = DevPodInstall.helm else { throw Failure("helm is not installed.") }

		let arguments = upgradeArguments(
			settings, root: root, namespace: namespace, context: context, kubeconfig: kubeconfig
		)
		progress?("$ helm " + arguments.joined(separator: " "))

		let result = await Process.run(helm, arguments, progress: progress)
		guard result.exitCode == 0 else {
			let output = (result.error.isEmpty ? result.output : result.error)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			// The one failure worth naming: the plugin is how a project's
			// encrypted values are read, and without it helm reads ciphertext.
			if settings.usesSecrets, output.contains("secrets") , output.contains("unknown command") {
				throw Failure(
					"""
					helm has no `secrets` command.

					This configuration reads encrypted values files, which needs \
					the helm-secrets plugin:
					    helm plugin install https://github.com/jkroepke/helm-secrets

					\(output)
					"""
				)
			}
			// A release left half-done refuses every later attempt. For the
			// development pod's own chart this app clears it; for a project's
			// chart it says what to do instead — removing a release somebody
			// else owns is not this app's decision to make.
			if DevPodInstall.isPendingOperation(output) {
				throw Failure(
					"""
					A previous helm operation on \(settings.release) never finished, so this one \
					was refused.

					Put it back to the last working revision, or take it away:
					    helm rollback \(settings.release) --namespace \(namespace)
					    helm uninstall \(settings.release) --namespace \(namespace)

					\(output)
					"""
				)
			}
			throw Failure(output.isEmpty ? "helm failed." : output)
		}
	}

	/// The deployments a release made, with the containers in each.
	public static func deployments(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?
	) async -> [(name: String, containers: [String])] {
		let result = await Kubernetes.run(
			[
				"get", "deployments", "--namespace", namespace,
				"--selector", "app.kubernetes.io/instance=" + release,
				"-o", "json",
			],
			context: context,
			kubeconfig: kubeconfig
		)
		return parseDeployments(result.stdout)
	}

	static func parseDeployments(_ json: String) -> [(name: String, containers: [String])] {
		guard let data = json.data(using: .utf8),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let items = object["items"] as? [[String: Any]]
		else { return [] }

		return items.compactMap { item in
			guard let metadata = item["metadata"] as? [String: Any],
			      let name = metadata["name"] as? String
			else { return nil }

			let spec = item["spec"] as? [String: Any]
			let template = spec?["template"] as? [String: Any]
			let podSpec = template?["spec"] as? [String: Any]
			let containers = (podSpec?["containers"] as? [[String: Any]] ?? [])
				.compactMap { $0["name"] as? String }
			return (name, containers)
		}
	}

	/// Which deployment holds a container, when the configuration names one.
	public static func deployment(
		holding container: String,
		in deployments: [(name: String, containers: [String])]
	) -> String? {
		if container.isEmpty { return deployments.first?.name }
		return deployments.first { $0.containers.contains(container) }?.name
	}
}

/// Turning one container of a real workload into a development container.
///
/// A strategic merge patch, because that is the one that merges a container
/// into the container of the same name rather than replacing the whole list:
/// everything the chart gave it — the environment, the secrets it mounts, the
/// service it is behind — stays exactly as it was. What changes is what runs.
public enum DevContainerPatch {
	/// What the supervisor needs to know, wherever it is running.
	public static let environment: [(String, String)] = [
		("ABYDOS_BINARY", "/app/current"),
		("ABYDOS_WORKDIR", "/app"),
		("ABYDOS_CONTROL_ADDR", ":7999"),
		("ABYDOS_DEBUG_ADDR", ":2345"),
		("ABYDOS_DLV", "/usr/local/bin/dlv"),
	]

	/// The patch that puts the supervisor in a container's place.
	///
	/// The probes go: they test an application that is not there yet, and a
	/// container restarted every ten seconds is one nothing can be pushed into.
	/// The label goes on so the pod is found the same way any other development
	/// pod is.
	public static func patch(container: String, image: String) -> [String: Any] {
		[
			"spec": [
				"template": [
					"metadata": ["labels": ["ideai.dev/devpod": "true"]],
					"spec": [
						"containers": [[
							"name": container,
							"image": image,
							"command": ["/usr/local/bin/ideai-supervisor"],
							"args": NSNull(),
							"ports": [
								["name": "control", "containerPort": 7999],
								["name": "debug", "containerPort": 2345],
							],
							"env": environment.map { ["name": $0.0, "value": $0.1] },
							"livenessProbe": NSNull(),
							"readinessProbe": NSNull(),
							"startupProbe": NSNull(),
						]],
					],
				],
			],
		]
	}

	public static func json(container: String, image: String) -> String {
		let data = try? JSONSerialization.data(
			withJSONObject: patch(container: container, image: image),
			options: [.sortedKeys, .withoutEscapingSlashes]
		)
		return String(decoding: data ?? Data(), as: UTF8.self)
	}
}

extension Process {
	/// Runs a command and hands back what it said, line by line as it says it.
	static func run(
		_ executable: String,
		_ arguments: [String],
		progress: (@Sendable (String) -> Void)? = nil
	) async -> (exitCode: Int32, output: String, error: String) {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: executable)
				process.arguments = arguments

				let out = Pipe(), err = Pipe()
				process.standardOutput = out
				process.standardError = err

				do {
					try process.run()
				} catch {
					continuation.resume(returning: (127, "", error.localizedDescription))
					return
				}
				let captured = ProcessPipes.drainText(process, out: out, err: err)
				let output = captured.stdout
				let error = captured.stderr
				for line in (output + error).split(separator: "\n") where !line.isEmpty {
					progress?(String(line))
				}
				continuation.resume(returning: (process.terminationStatus, output, error))
			}
		}
	}

	/// Just the exit code, for a question with a yes-or-no answer.
	static func runQuietly(_ executable: String, _ arguments: [String]) async -> Int32 {
		await run(executable, arguments).exitCode
	}
}
