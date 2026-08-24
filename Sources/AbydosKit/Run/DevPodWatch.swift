import Foundation

/// Watching a pod that is being installed.
///
/// `helm --wait` says nothing at all until it gives up, which for a deployment
/// that will never become ready means two minutes of silence followed by
/// "context deadline exceeded" — a message about helm's patience rather than
/// about what went wrong. The cluster knows the answer within seconds and says
/// it plainly: the image cannot be pulled, the container will not start. This
/// reads that, so it can be shown while it is happening and given up on early
/// when there is nothing to wait for.
public enum DevPodWatch {
	/// One pod, as the cluster currently sees it.
	public struct State: Equatable, Sendable {
		public let pod: String
		public let phase: String
		/// Why the container is not running yet, if it says.
		public let reason: String
		public let message: String

		public init(pod: String, phase: String, reason: String = "", message: String = "") {
			self.pod = pod
			self.phase = phase
			self.reason = reason
			self.message = message
		}

		/// A line for the console.
		public var line: String {
			var text = "\(pod): \(phase)"
			if !reason.isEmpty { text += " — \(reason)" }
			if !message.isEmpty { text += ": \(message)" }
			return text
		}

		/// Whether waiting any longer is pointless.
		///
		/// These are the states a cluster does not recover from on its own: an
		/// image it cannot fetch stays unfetched however long helm waits.
		public var isHopeless: Bool {
			[
				"ImagePullBackOff", "ErrImagePull", "InvalidImageName",
				"CreateContainerConfigError", "CreateContainerError",
			].contains(reason)
		}
	}

	/// Reads `kubectl get pods -o json`.
	public static func parse(_ json: String) -> [State] {
		guard let data = json.data(using: .utf8),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let items = object["items"] as? [[String: Any]]
		else { return [] }

		return items.map { item in
			let metadata = item["metadata"] as? [String: Any]
			let status = item["status"] as? [String: Any]
			let containers = status?["containerStatuses"] as? [[String: Any]] ?? []

			// The first container that is waiting for something is the one with
			// the answer; a pod whose containers are all running is not stuck.
			var reason = "", message = ""
			for container in containers {
				guard let state = container["state"] as? [String: Any],
				      let waiting = state["waiting"] as? [String: Any],
				      let why = waiting["reason"] as? String
				else { continue }
				reason = why
				message = waiting["message"] as? String ?? ""
				break
			}

			return State(
				pod: metadata?["name"] as? String ?? "pod",
				phase: status?["phase"] as? String ?? "Unknown",
				reason: reason,
				message: message
			)
		}
	}

	/// What to tell somebody about a pod that is never going to start.
	///
	/// The cluster's own message says the image could not be pulled; what it
	/// cannot know is that this image is normally imported by hand into a local
	/// cluster, and that a cluster somewhere else needs a published one.
	public static func explain(_ state: State, image: String) -> String {
		let named = image.isEmpty ? "the development pod's image" : image
		switch state.reason {
		case "ImagePullBackOff", "ErrImagePull":
			return """
			The cluster cannot pull \(named).

			A local cluster is handed the image directly:
			    make -C DevPod import-k3d CLUSTER=<name>
			    make -C DevPod import-k3c CLUSTER=<name>

			A cluster anywhere else has to pull it, so publish one and name it \
			in this configuration's Image field:
			    make devpod-publish REPOSITORY=<user>/abydos-devpod VERSION=v1

			The cluster said: \(state.message.isEmpty ? state.reason : state.message)
			"""
		case "CreateContainerConfigError", "CreateContainerError", "InvalidImageName":
			return "The pod \(state.pod) cannot start: \(state.reason). "
				+ (state.message.isEmpty ? "" : state.message)
		default:
			return state.line
		}
	}

	/// Asks the cluster about a release's pods.
	public static func states(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?
	) async -> [State] {
		let result = await Kubernetes.run(
			[
				"get", "pods", "--namespace", namespace,
				"--selector", "app.kubernetes.io/instance=" + release,
				"-o", "json",
			],
			context: context,
			kubeconfig: kubeconfig
		)
		return parse(result.stdout)
	}
}
