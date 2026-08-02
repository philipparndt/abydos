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
		progress: (@Sendable (String) -> Void)? = nil
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
		if let image, !image.isEmpty {
			arguments += ["--set", "image.repository=" + image]
		}
		for value in values {
			arguments += ["--set", value]
		}

		progress?("$ helm " + arguments.joined(separator: " "))
		let result = await run(helm, arguments, timeout: timeout + 30, progress: progress)
		if ProcessInfo.processInfo.environment["IDEAI_HELM_DEBUG"] != nil {
			FileHandle.standardError.write(Data(
				"[helm] \(helm) \(arguments.joined(separator: " "))\n[helm] exit=\(result.exitCode) \(result.error)\n".utf8
			))
		}
		guard result.exitCode == 0 else {
			throw Failure.failed(
				(result.error.isEmpty ? result.output : result.error)
					.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}
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
					let outData = out.fileHandleForReading.readDataToEndOfFile()
					let errData = err.fileHandleForReading.readDataToEndOfFile()
					process.waitUntilExit()

					let output = String(decoding: outData, as: UTF8.self)
					let error = String(decoding: errData, as: UTF8.self)
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
