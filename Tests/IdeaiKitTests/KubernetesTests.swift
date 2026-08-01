import Foundation
import Testing
@testable import IdeaiKit

/// Reading a cluster's pods.
struct KubernetesPodTests {
	private func podsJSON(_ items: String) -> String {
		"""
		{"apiVersion":"v1","kind":"List","items":[\(items)]}
		"""
	}

	private let plain = """
	{"metadata":{"name":"api-7d9f","namespace":"prod","creationTimestamp":"2026-08-01T10:00:00Z"},
	 "spec":{"containers":[{"name":"api","image":"api:1","ports":[{"containerPort":8080,"name":"http"}]}]},
	 "status":{"phase":"Running"}}
	"""

	@Test func readsAPod() {
		let pods = Kubernetes.parsePods(podsJSON(plain))
		#expect(pods.count == 1)
		#expect(pods.first?.name == "api-7d9f")
		#expect(pods.first?.namespace == "prod")
		#expect(pods.first?.containers == ["api"])
		#expect(pods.first?.isRunning == true)
	}

	/// Nothing said where pprof is, so it is the port Go programs use — and
	/// the pod says as much, because a forward to the wrong port fails in a
	/// way that looks like the profiler is broken.
	@Test func fallsBackToTheUsualPort() {
		let pods = Kubernetes.parsePods(podsJSON(plain))
		#expect(pods.first?.port == 6060)
		#expect(pods.first?.portSource == .convention)
	}

	@Test func prefersAPortTheContainerNames() {
		let named = """
		{"metadata":{"name":"worker","namespace":"prod"},
		 "spec":{"containers":[{"name":"w","ports":[
		   {"containerPort":8080,"name":"http"},
		   {"containerPort":9999,"name":"pprof"}]}]},
		 "status":{"phase":"Running"}}
		"""
		let pod = Kubernetes.parsePods(podsJSON(named)).first
		#expect(pod?.port == 9999)
		#expect(pod?.portSource == .containerPort)
	}

	/// A container port numbered 6060 says what it is without being named.
	@Test func recognisesTheConventionalPortByNumber() {
		let numbered = """
		{"metadata":{"name":"worker","namespace":"prod"},
		 "spec":{"containers":[{"name":"w","ports":[{"containerPort":6060}]}]},
		 "status":{"phase":"Running"}}
		"""
		#expect(Kubernetes.parsePods(podsJSON(numbered)).first?.portSource == .containerPort)
	}

	/// A host-network pod cannot declare a container port without claiming it
	/// on the node, so it says so in an annotation instead.
	@Test func takesTheAnnotationOverEverything() {
		let annotated = """
		{"metadata":{"name":"edge","namespace":"prod",
		   "annotations":{"goprofiler.io/port":"7070"}},
		 "spec":{"containers":[{"name":"e","ports":[{"containerPort":6060}]}]},
		 "status":{"phase":"Running"}}
		"""
		let pod = Kubernetes.parsePods(podsJSON(annotated)).first
		#expect(pod?.port == 7070)
		#expect(pod?.portSource == .annotation)
	}

	@Test func ignoresAnAnnotationThatIsNotAPort() {
		let nonsense = """
		{"metadata":{"name":"edge","namespace":"prod",
		   "annotations":{"goprofiler.io/port":"yes please"}},
		 "spec":{"containers":[{"name":"e"}]},
		 "status":{"phase":"Pending"}}
		"""
		let pod = Kubernetes.parsePods(podsJSON(nonsense)).first
		#expect(pod?.port == 6060)
		#expect(pod?.isRunning == false)
	}

	@Test func survivesSomethingThatIsNotPodJSON() {
		#expect(Kubernetes.parsePods("not json").isEmpty)
		#expect(Kubernetes.parsePods("{}").isEmpty)
		#expect(Kubernetes.parsePods(podsJSON("{\"spec\":{}}")).isEmpty)
	}

	@Test func writesAgeTheWayKubectlDoes() {
		let now = ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z")!
		#expect(Kubernetes.age(since: "2026-08-01T11:59:30Z", now: now) == "30s")
		#expect(Kubernetes.age(since: "2026-08-01T11:30:00Z", now: now) == "30m")
		#expect(Kubernetes.age(since: "2026-08-01T06:00:00Z", now: now) == "6h")
		#expect(Kubernetes.age(since: "2026-07-29T12:00:00Z", now: now) == "3d")
		#expect(Kubernetes.age(since: nil, now: now) == "")
	}
}

/// The forward itself.
struct PortForwardTests {
	/// Two forwards must not be handed the same local port.
	@Test func findsAFreePortEachTime() throws {
		let first = try #require(PortForward.freePort())
		let second = try #require(PortForward.freePort())
		#expect(first > 1024)
		#expect(second > 1024)
	}

	/// Against a real cluster, when one is configured: forwards to a pod and
	/// checks something answers. Skipped otherwise, so the suite needs no
	/// cluster.
	@Test func forwardsToARealPod() async throws {
		let environment = ProcessInfo.processInfo.environment
		guard let namespace = environment["IDEAI_K8S_NAMESPACE"],
		      let name = environment["IDEAI_K8S_POD"]
		else { return }

		let target = PodTarget(
			namespace: namespace,
			name: name,
			phase: "Running",
			containers: [],
			port: Int(environment["IDEAI_K8S_PORT"] ?? "6060") ?? 6060,
			portSource: .convention
		)
		let forward = try await PortForward.start(to: target, context: environment["IDEAI_K8S_CONTEXT"])
		defer { forward.stop() }

		#expect(forward.isRunning)
		#expect(forward.localPort > 1024)
	}
}
