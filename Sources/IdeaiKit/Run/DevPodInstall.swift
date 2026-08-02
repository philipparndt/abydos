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
		timeout: TimeInterval = 120
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

		let result = await run(helm, arguments, timeout: timeout + 30)
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

	private static func run(
		_ executable: String,
		_ arguments: [String],
		timeout: TimeInterval
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
				let outData = out.fileHandleForReading.readDataToEndOfFile()
				let errData = err.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()

				continuation.resume(returning: (
					process.terminationStatus,
					String(decoding: outData, as: UTF8.self),
					String(decoding: errData, as: UTF8.self)
				))
			}
		}
	}
}
