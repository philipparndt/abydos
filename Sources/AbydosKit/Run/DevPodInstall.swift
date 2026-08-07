import Foundation

/// Putting a development pod in a cluster that has none.
///
/// Pressing run should not stop to say that a chart is missing. A cluster with
/// nowhere to run this project's code gets somewhere, named after the project
/// so two projects do not share one pod and overwrite each other's binary.
public enum DevPodInstall {
	public enum Failure: Error, Equatable {
		case noHelm
		case noChart
		case failed(String)
	}

	/// `helm`, wherever it is.
	///
	/// The same search as kubectl's: a GUI application's PATH is not a
	/// shell's, and Rancher Desktop and Homebrew both put it somewhere the
	/// Finder has never heard of.
	public static var helm: String? {
		let candidates = [
			"/opt/homebrew/bin/helm",
			"/usr/local/bin/helm",
			"/usr/bin/helm",
			NSHomeDirectory() + "/.rd/bin/helm",
		]
		if let path = ProcessInfo.processInfo.environment["PATH"] {
			for directory in path.split(separator: ":") {
				let candidate = String(directory) + "/helm"
				if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
			}
		}
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
	}

	/// A release name for a project.
	///
	/// From the project's own name, because a developer looking at
	/// `helm list` should recognise what they are looking at, and because two
	/// projects in one cluster must not be the same pod.
	public static func releaseName(for project: URL) -> String {
		let cleaned = project.lastPathComponent.map { character -> Character in
			character.isLetter || character.isNumber ? character : "-"
		}
		var name = String(cleaned).lowercased()
		while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
		name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		return "ideai-" + (name.isEmpty ? "project" : String(name.prefix(40)))
	}

	/// Installs or upgrades the chart, and waits for the pod to be ready.
	///
	/// `--wait`, because the next thing that happens is a binary being pushed
	/// into it: returning before there is anywhere to push it would only move
	/// the failure one step later.
	public static func install(
		chart: URL,
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?,
		image: String? = nil,
		values: [String] = [],
		timeout: TimeInterval = 120,
		progress: (@Sendable (String) -> Void)? = nil,
		recovering: Bool = false
	) async throws {
		guard let helm else { throw Failure.noHelm }
		guard FileManager.default.fileExists(atPath: chart.appendingPathComponent("Chart.yaml").path)
		else { throw Failure.noChart }

		var arguments = [
			"upgrade", "--install", release, chart.path,
			"--namespace", namespace, "--create-namespace",
			"--wait", "--timeout", "\(Int(timeout))s",
		]
		if let context, !context.isEmpty { arguments += ["--kube-context", context] }
		if let kubeconfig, !kubeconfig.isEmpty {
			arguments += ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath]
		}
		for value in DevPodImage.values(for: image ?? "") {
			arguments += ["--set", value]
		}
		for value in values {
			arguments += ["--set", value]
		}

		progress?("$ helm " + arguments.joined(separator: " "))
		let result = await run(helm, arguments, timeout: timeout + 30, progress: progress)
		if ProcessInfo.processInfo.environment["ABYDOS_HELM_DEBUG"] != nil {
			FileHandle.standardError.write(Data(
				"[helm] \(helm) \(arguments.joined(separator: " "))\n[helm] exit=\(result.exitCode) \(result.error)\n".utf8
			))
		}
		guard result.exitCode == 0 else {
			let output = (result.error.isEmpty ? result.output : result.error)
				.trimmingCharacters(in: .whitespacesAndNewlines)

			// A release left half-done — by a crash, a cancelled run, a laptop
			// closing — refuses every later attempt with "another operation is
			// in progress" and stays that way until somebody clears it by hand.
			// This is our own chart in a development cluster: nothing here is
			// worth keeping, so it is cleared and the install tried again.
			if isPendingOperation(output), !recovering {
				let recovered = await recoverPending(
					release: release,
					namespace: namespace,
					context: context,
					kubeconfig: kubeconfig,
					progress: progress
				)
				if recovered {
					try await install(
						chart: chart,
						release: release,
						namespace: namespace,
						context: context,
						kubeconfig: kubeconfig,
						image: image,
						values: values,
						timeout: timeout,
						progress: progress,
						recovering: true
					)
					return
				}
			}
			throw Failure.failed(output)
		}
	}

	/// Whether helm is refusing because a previous operation never finished.
	public static func isPendingOperation(_ output: String) -> Bool {
		output.contains("another operation (install/upgrade/rollback) is in progress")
	}

	/// What to do about a release stuck mid-operation.
	public enum Recovery: Equatable {
		/// Nothing was ever deployed, so there is nothing to go back to.
		case uninstall
		/// A working revision came before this one.
		case rollback
		/// Not stuck.
		case none
	}

	/// Read from what `helm status -o json` says the release is.
	public static func recovery(forStatus status: String) -> Recovery {
		switch status {
		case "pending-install": return .uninstall
		case "pending-upgrade", "pending-rollback": return .rollback
		default: return .none
		}
	}

	/// Clears a release that a previous run left half-done.
	static func recoverPending(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?,
		progress: (@Sendable (String) -> Void)?
	) async -> Bool {
		guard let helm else { return false }

		func arguments(_ command: [String]) -> [String] {
			var full = command + ["--namespace", namespace]
			if let context, !context.isEmpty { full += ["--kube-context", context] }
			if let kubeconfig, !kubeconfig.isEmpty {
				full += ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath]
			}
			return full
		}

		let status = await run(helm, arguments(["status", release, "-o", "json"]), timeout: 30)
		let state = statusName(fromJSON: status.output)
		progress?("the release is \(state.isEmpty ? "stuck" : state) from an earlier attempt")

		switch recovery(forStatus: state) {
		case .rollback:
			progress?("$ helm rollback \(release)")
			let rolled = await run(helm, arguments(["rollback", release]), timeout: 120, progress: progress)
			if rolled.exitCode == 0 { return true }
			// A rollback that cannot find a revision to go back to leaves the
			// same lock in place; removing the release does not.
			fallthrough
		case .uninstall:
			progress?("$ helm uninstall \(release)")
			let removed = await run(
				helm, arguments(["uninstall", release, "--wait"]), timeout: 120, progress: progress
			)
			return removed.exitCode == 0
		case .none:
			return false
		}
	}

	/// `helm status -o json` → `.info.status`.
	static func statusName(fromJSON json: String) -> String {
		guard let data = json.data(using: .utf8),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let info = object["info"] as? [String: Any],
		      let status = info["status"] as? String
		else { return "" }
		return status
	}

	/// What the release was installed with, as helm reports it.
	public static func deployedValues(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?
	) async -> String {
		guard let helm else { return "" }
		var arguments = ["get", "values", release, "--namespace", namespace, "-o", "json"]
		if let context, !context.isEmpty { arguments += ["--kube-context", context] }
		if let kubeconfig, !kubeconfig.isEmpty {
			arguments += ["--kubeconfig", (kubeconfig as NSString).expandingTildeInPath]
		}
		let result = await run(helm, arguments, timeout: 20)
		return result.exitCode == 0 ? result.output : ""
	}

	/// Whether what the configuration asks for is already what is deployed.
	///
	/// A pod that is running is not necessarily a pod that is published: the
	/// hostname, the port and the image are decided at install time, and a
	/// configuration that has since gained an ingress would otherwise be
	/// ignored until somebody deleted the release by hand.
	public static func upgradeNeeded(desired: [String], deployed json: String) -> Bool {
		guard !desired.isEmpty else { return false }
		guard let data = json.data(using: .utf8),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return true }

		for setting in desired {
			guard let (path, wanted) = split(setting) else { continue }
			guard let found = value(at: path, in: object) else { return true }
			guard describe(found) == wanted else { return true }
		}
		return false
	}

	/// `a.b[0].c=value` into its path and its value.
	private static func split(_ setting: String) -> (path: [String], value: String)? {
		guard let equals = setting.firstIndex(of: "=") else { return nil }
		let path = String(setting[setting.startIndex..<equals])
		let value = String(setting[setting.index(after: equals)...])

		var parts: [String] = []
		for piece in path.split(separator: ".") {
			// `ports[0]` is a key and an index, which is two steps.
			if let bracket = piece.firstIndex(of: "[") {
				parts.append(String(piece[piece.startIndex..<bracket]))
				let inside = piece[piece.index(after: bracket)...].dropLast()
				parts.append(String(inside))
			} else {
				parts.append(String(piece))
			}
		}
		return (parts, value)
	}

	private static func value(at path: [String], in object: Any) -> Any? {
		var current: Any? = object
		for step in path {
			if let dictionary = current as? [String: Any] {
				current = dictionary[step]
			} else if let array = current as? [Any], let index = Int(step), array.indices.contains(index) {
				current = array[index]
			} else {
				return nil
			}
			if current == nil { return nil }
		}
		return current
	}

	/// How helm would have written the value back.
	private static func describe(_ value: Any) -> String {
		switch value {
		case let text as String: return text
		case let flag as Bool: return flag ? "true" : "false"
		case let number as NSNumber:
			let double = number.doubleValue
			return double == double.rounded() ? String(Int(double)) : String(double)
		default: return String(describing: value)
		}
	}

	/// Whether the cluster can pull the image at all.
	///
	/// A local cluster is given the image by hand — `k3c image import`, `k3d
	/// image import` — and asking it to pull one that exists nowhere fails
	/// with `ImagePullBackOff`, which reads like a network problem rather than
	/// a missing step.
	public static func imagePresent(
		named image: String,
		context: String?,
		kubeconfig: String?
	) async -> Bool {
		let result = await Kubernetes.run(
			["get", "nodes", "-o", "jsonpath={.items[*].status.images[*].names[*]}"],
			context: context,
			kubeconfig: kubeconfig
		)
		return result.stdout.contains(image)
	}

	/// Runs a command, reporting its output as it arrives and stopping it if the
	/// task is cancelled.
	///
	/// Both matter here for the same reason: `helm --wait` can sit for two
	/// minutes on a deployment that will never become ready, and a person
	/// watching a spinner with no output and no stop button has no idea whether
	/// to keep waiting.
	private static func run(
		_ executable: String,
		_ arguments: [String],
		timeout: TimeInterval,
		progress: (@Sendable (String) -> Void)? = nil
	) async -> (exitCode: Int32, output: String, error: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments

		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				DispatchQueue.global(qos: .userInitiated).async {
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
		} onCancel: {
			// Terminating leaves the release as helm left it — which is what
			// `helm upgrade --install` is built to survive, and better than an
			// editor that cannot be told to stop.
			process.terminate()
		}
	}
}
