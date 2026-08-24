import Foundation
import Testing
@testable import AbydosKit

/// Running a project's own chart, rather than one of ours.
struct HelmReleaseTests {
	private let root = URL(fileURLWithPath: "/tmp/project")

	@Test func theCommandReadsTheStagesValuesInOrder() {
		let settings = LaunchConfiguration.HelmSettings(
			chart: "deploy/chart",
			release: "smarthome",
			valueFiles: ["deploy/values.yaml", "deploy/values-dev.yaml"],
			container: "app"
		)
		let arguments = HelmRelease.upgradeArguments(
			settings, root: root, namespace: "dev", context: "k3c-demo1", kubeconfig: nil
		)

		#expect(arguments.starts(with: ["upgrade", "--install", "smarthome", "/tmp/project/deploy/chart"]))
		#expect(arguments.contains("--namespace"))
		// Not --wait: the container being replaced is the one it would wait for.
		#expect(!arguments.contains("--wait"))
		// The field this app patches is one the cluster records an owner for,
		// and helm reasserting the chart's image over it is what should happen.
		#expect(arguments.contains("--force-conflicts"))
		let values = zip(arguments, arguments.dropFirst())
			.filter { $0.0 == "--values" }
			.map(\.1)
		#expect(values == ["/tmp/project/deploy/values.yaml", "/tmp/project/deploy/values-dev.yaml"])
		#expect(arguments.contains("k3c-demo1"))
	}

	/// The plugin wraps the command, so it has to come first.
	@Test func encryptedValuesGoThroughTheSecretsPlugin() {
		let settings = LaunchConfiguration.HelmSettings(
			chart: "chart", release: "app", valueFiles: ["secrets.yaml"], usesSecrets: true
		)
		let arguments = HelmRelease.upgradeArguments(
			settings, root: root, namespace: "dev", context: nil, kubeconfig: nil
		)
		#expect(arguments.first == "secrets")
		#expect(arguments.dropFirst().first == "upgrade")
	}

	@Test func pathsMayBeAbsoluteOrInTheProject() {
		#expect(HelmRelease.expand("/opt/chart", root: root) == "/opt/chart")
		#expect(HelmRelease.expand("chart", root: root) == "/tmp/project/chart")
		#expect(HelmRelease.expand("${workspaceFolder}/chart", root: root).hasSuffix("/chart"))
	}

	@Test func theDeploymentHoldingAContainerIsTheOneToPatch() {
		let json = """
		{"items": [
		  {"metadata": {"name": "smarthome-web"},
		   "spec": {"template": {"spec": {"containers": [{"name": "web"}]}}}},
		  {"metadata": {"name": "smarthome-app"},
		   "spec": {"template": {"spec": {"containers": [{"name": "app"}, {"name": "sidecar"}]}}}}
		]}
		"""
		let deployments = HelmRelease.parseDeployments(json)
		#expect(deployments.count == 2)
		#expect(HelmRelease.deployment(holding: "app", in: deployments) == "smarthome-app")
		#expect(HelmRelease.deployment(holding: "web", in: deployments) == "smarthome-web")
		// Nothing named: the first one, which is the only sensible guess for a
		// release with one deployment in it.
		#expect(HelmRelease.deployment(holding: "", in: deployments) == "smarthome-web")
		#expect(HelmRelease.deployment(holding: "valkey", in: deployments) == nil)
	}

	@Test func theSettingsSurviveBeingWrittenDown() throws {
		var configuration = LaunchConfiguration(name: "app in dev", type: "go")
		configuration.helm = LaunchConfiguration.HelmSettings(
			chart: "deploy/chart",
			release: "smarthome",
			valueFiles: ["deploy/values-dev.yaml"],
			usesSecrets: true,
			sets: ["image.tag=dev"],
			container: "app",
			install: false
		)
		let read = try #require(LaunchConfiguration(json: configuration.json))
		#expect(read.helm == configuration.helm)
	}
}

/// Swapping one container of a real workload for the supervisor.
struct DevContainerPatchTests {
	private var patched: [String: Any] {
		let json = DevContainerPatch.json(container: "app", image: "pharndt/abydos-devpod:dev")
		let data = json.data(using: .utf8) ?? Data()
		return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
	}

	private var container: [String: Any] {
		let spec = patched["spec"] as? [String: Any]
		let template = spec?["template"] as? [String: Any]
		let podSpec = template?["spec"] as? [String: Any]
		return (podSpec?["containers"] as? [[String: Any]])?.first ?? [:]
	}

	/// Merged by name, so everything else the chart gave the container — its
	/// environment, its mounted secrets, its neighbours — stays.
	@Test func thePatchNamesTheContainerItReplaces() {
		#expect(container["name"] as? String == "app")
		#expect(container["image"] as? String == "pharndt/abydos-devpod:dev")
		#expect(container["command"] as? [String] == ["/usr/local/bin/abydos-supervisor"])
	}

	/// A container restarted every ten seconds is one nothing can be pushed
	/// into: the probes test an application that has not arrived yet.
	@Test func theProbesAreTakenOff() {
		for probe in ["livenessProbe", "readinessProbe", "startupProbe"] {
			#expect(container[probe] is NSNull, "\(probe) should be cleared")
		}
		#expect(container["args"] is NSNull)
	}

	@Test func theControlAndDebugPortsAreNamedAsThePodsAre() {
		let ports = container["ports"] as? [[String: Any]] ?? []
		#expect(ports.contains { $0["name"] as? String == "control" && $0["containerPort"] as? Int == 7999 })
		#expect(ports.contains { $0["name"] as? String == "debug" && $0["containerPort"] as? Int == 2345 })
	}

	/// The same label the chart puts on its own pods, so one way of finding a
	/// development pod finds both kinds.
	@Test func thePodIsLabelledAsADevelopmentPod() {
		let spec = patched["spec"] as? [String: Any]
		let template = spec?["template"] as? [String: Any]
		let metadata = template?["metadata"] as? [String: Any]
		let labels = metadata?["labels"] as? [String: String]
		#expect(labels?["abydos.dev/devpod"] == "true")
		#expect(DevPods.label == "abydos.dev/devpod=true")
	}

	@Test func theSupervisorIsToldWhereEverythingIs() {
		let env = container["env"] as? [[String: String]] ?? []
		#expect(env.contains { $0["name"] == "ABYDOS_BINARY" && $0["value"] == "/app/current" })
		#expect(env.contains { $0["name"] == "ABYDOS_DLV" })
	}
}
