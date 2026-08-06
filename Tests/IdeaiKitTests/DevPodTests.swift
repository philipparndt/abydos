import Foundation
import Testing
@testable import IdeaiKit

/// Finding development pods and reading what they say.
struct DevPodTests {
	@Test func readsAPodAndItsPorts() {
		let json = """
		{"items":[{"metadata":{"name":"dev-ideai-devpod-abc","namespace":"devpod",
		   "creationTimestamp":"2026-08-01T12:00:00Z"},
		 "spec":{"containers":[{"name":"devpod","ports":[
		   {"name":"control","containerPort":7999},
		   {"name":"debug","containerPort":2345},
		   {"name":"http","containerPort":8080}]}]},
		 "status":{"phase":"Running"}}]}
		"""
		let pods = DevPods.parse(json)
		#expect(pods.count == 1)
		#expect(pods.first?.namespace == "devpod")
		#expect(pods.first?.controlPort == 7999)
		#expect(pods.first?.debugPort == 2345)
		#expect(pods.first?.isRunning == true)
	}

	/// Somebody will move the ports; the chart names them, so they are read
	/// rather than assumed.
	@Test func takesThePortsFromTheContainer() {
		let json = """
		{"items":[{"metadata":{"name":"p","namespace":"n"},
		 "spec":{"containers":[{"name":"devpod","ports":[
		   {"name":"control","containerPort":9100},
		   {"name":"debug","containerPort":9200}]}]},
		 "status":{"phase":"Running"}}]}
		"""
		let pod = DevPods.parse(json).first
		#expect(pod?.controlPort == 9100)
		#expect(pod?.debugPort == 9200)
	}

	@Test func survivesRubbish() {
		#expect(DevPods.parse("not json").isEmpty)
		#expect(DevPods.parse("{\"items\":[{}]}").isEmpty)
	}

	@Test func readsTheStatusAPodReports() throws {
		let json = Data("""
		{"state":"running","mode":"debug","pid":15,"hasBinary":true,
		 "binarySize":2233099,"debugAddress":":2345","arch":"arm64"}
		""".utf8)
		let status = try #require(DevPodStatus(json: json))
		#expect(status.state == "running")
		#expect(status.mode == "debug")
		#expect(status.hasBinary)
		#expect(status.binarySize == 2233099)
		#expect(status.architecture == "arm64")
		#expect(status.exitCode == nil)
	}

	@Test func readsAnExit() throws {
		let status = try #require(DevPodStatus(json: Data(
			"{\"state\":\"exited\",\"exitCode\":3,\"hasBinary\":true,\"arch\":\"amd64\"}".utf8
		)))
		#expect(status.exitCode == 3)
		#expect(status.state == "exited")
	}

	@Test func refusesSomethingThatIsNotAStatus() {
		#expect(DevPodStatus(json: Data("nonsense".utf8)) == nil)
	}
}

/// The gzip the pod's supervisor expects.
struct GzipTests {
	/// Round-tripped through the same decoder the supervisor uses — Apple's
	/// raw DEFLATE plus a header we write ourselves, which is the part that
	/// can be wrong.
	@Test func producesSomethingGunzipUnderstands() async throws {
		let original = Data((0..<40_000).map { UInt8($0 % 251) })
		let packed = try #require(Gzip.compress(original))

		#expect(packed[0] == 0x1F)
		#expect(packed[1] == 0x8B)
		#expect(packed.count < original.count)

		// Through the system's own gunzip: if it reads it, so will Go's.
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("gzip-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let file = directory.appendingPathComponent("payload.gz")
		try packed.write(to: file)

		let result = await ShellEnvironment.run("gunzip -c payload.gz | wc -c", in: directory)
		#expect(result.exitCode == 0)
		#expect(Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) == original.count)
	}

	@Test func hasNothingToSayAboutNothing() {
		#expect(Gzip.compress(Data()) == nil)
	}

	/// The checksum gzip carries, against a value everybody agrees on.
	@Test func computesTheChecksum() {
		#expect(Gzip.crc32(Data("The quick brown fox jumps over the lazy dog".utf8)) == 0x414F_A339)
	}
}

/// Which cluster a shared configuration is allowed to run on.
struct ContextPatternTests {
	@Test func matchesTheWayAShellWould() {
		#expect(ContextPattern.matches("philipp-local", "*-local"))
		#expect(ContextPattern.matches("k3c-demo1", "k3c-*"))
		#expect(ContextPattern.matches("anything", "*"))
		#expect(!ContextPattern.matches("prod-eu", "*-local"))
		#expect(!ContextPattern.matches("local-prod", "*-local"))
	}

	@Test func matchesOneCharacterWithAQuestionMark() {
		#expect(ContextPattern.matches("dev1", "dev?"))
		#expect(!ContextPattern.matches("dev12", "dev?"))
	}

	/// Case is not what anybody means by a different cluster.
	@Test func ignoresCase() {
		#expect(ContextPattern.matches("My-Local", "*-local"))
	}

	@Test func readsAListOfPatterns() {
		#expect(ContextPattern.list("*-local, k3c-*") == ["*-local", "k3c-*"])
		#expect(ContextPattern.list("  ").isEmpty)
	}
}

/// Following the current context, but only so far.
struct DevPodContextTests {
	@Test func followsWhicheverContextIsCurrent() {
		let settings = LaunchConfiguration.DevPodSettings(allowedContexts: "*-local")
		#expect(try! settings.resolve(current: "philipp-local").get() == "philipp-local")
	}

	/// The whole point: a configuration everybody shares must not follow one
	/// of them onto production.
	@Test func refusesAContextThatIsNotAllowed() {
		let settings = LaunchConfiguration.DevPodSettings(allowedContexts: "*-local")
		guard case let .failure(refusal) = settings.resolve(current: "prod-eu") else {
			Issue.record("ran on production")
			return
		}
		#expect(refusal.message.contains("prod-eu"))
		#expect(refusal.message.contains("*-local"))
	}

	@Test func allowsAnythingWhenNothingIsSaid() {
		let settings = LaunchConfiguration.DevPodSettings()
		#expect(try! settings.resolve(current: "prod-eu").get() == "prod-eu")
	}

	/// A context named outright is still checked: writing one down is not a
	/// way around the rule.
	@Test func checksAContextThatWasNamed() {
		let settings = LaunchConfiguration.DevPodSettings(
			context: "prod-eu", allowedContexts: "*-local"
		)
		guard case .failure = settings.resolve(current: "mine-local") else {
			Issue.record("ran on production")
			return
		}
	}

	@Test func saysWhenThereIsNoCurrentContext() {
		let settings = LaunchConfiguration.DevPodSettings()
		guard case let .failure(refusal) = settings.resolve(current: nil) else {
			Issue.record("resolved to nothing")
			return
		}
		#expect(refusal == .noCurrentContext)
	}

	/// `${currentContext}` says out loud what an empty field means.
	@Test func acceptsTheVariableSpelling() {
		let settings = LaunchConfiguration.DevPodSettings(
			context: "${currentContext}", allowedContexts: "*-local"
		)
		#expect(settings.followsCurrentContext)
		#expect(try! settings.resolve(current: "mine-local").get() == "mine-local")
	}
}

/// What travels into the pod beside the binary.
struct DevPodFileTests {
	private func project() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("files-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("config"), withIntermediateDirectories: true
		)
		try "{}".write(
			to: root.appendingPathComponent("config/config.json"), atomically: true, encoding: .utf8
		)
		return root
	}

	/// The usual shape: a service told where its configuration is. The path is
	/// this machine's and means nothing in a pod, so the file goes too and the
	/// argument is rewritten to where it lands.
	@Test func sendsWhatTheArgumentsName() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let plan = DevPodFiles.plan(
			files: [],
			arguments: ["${workspaceFolder}/config/config.json"],
			root: root
		)
		#expect(plan.transfers.count == 1)
		#expect(plan.transfers.first?.remote == "/app/files/config.json")
		#expect(plan.arguments == ["/app/files/config.json"])
	}

	@Test func sendsWhatTheConfigurationLists() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let plan = DevPodFiles.plan(
			files: ["${workspaceFolder}/config/config.json:/etc/app/config.json"],
			arguments: [],
			root: root
		)
		#expect(plan.transfers.first?.remote == "/etc/app/config.json")
	}

	/// A file named in both places is sent once, and the argument follows what
	/// the configuration said rather than the default.
	@Test func sendsAFileOnce() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let plan = DevPodFiles.plan(
			files: ["${workspaceFolder}/config/config.json:/etc/app/config.json"],
			arguments: ["${workspaceFolder}/config/config.json"],
			root: root
		)
		#expect(plan.transfers.count == 1)
		#expect(plan.arguments == ["/etc/app/config.json"])
	}

	/// Arguments that are not files are left exactly as they were: a flag
	/// rewritten into a path would be a fine way to ruin a launch.
	@Test func leavesOrdinaryArgumentsAlone() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let plan = DevPodFiles.plan(
			files: [],
			arguments: ["--verbose", "8080", "/does/not/exist", "${workspaceFolder}"],
			root: root
		)
		#expect(plan.transfers.isEmpty)
		#expect(plan.arguments == ["--verbose", "8080", "/does/not/exist", "${workspaceFolder}"])
	}

	/// The form this app writes itself. `entry(for:in:)` stores anything inside
	/// the project relative to it, so the configuration can be committed and
	/// shared, and every other test here spells its entries out in full — which
	/// is why reading the relative form back against the wrong directory went
	/// unnoticed. Nothing about the failure points here: the file is listed, the
	/// pod has no configuration, and the program says an argument is missing.
	@Test func sendsAFileListedRelativeToTheProject() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let plan = DevPodFiles.plan(
			files: ["config/config.json"],
			arguments: [],
			root: root
		)
		#expect(plan.transfers.count == 1)
		#expect(plan.transfers.first?.remote == "/app/files/config.json")
		#expect(plan.transfers.first?.local.path.hasSuffix("/config/config.json") == true)
	}

	/// A relative entry with a destination still gets one, and a relative entry
	/// naming nothing is still ignored rather than sent as an empty file.
	@Test func readsRelativeEntriesTheSameWayAsAbsoluteOnes() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(DevPodFiles.plan(
			files: ["config/config.json:/etc/app/config.json"],
			arguments: [],
			root: root
		).transfers.first?.remote == "/etc/app/config.json")

		#expect(DevPodFiles.plan(files: ["config/missing.json"], arguments: [], root: root)
			.transfers.isEmpty)

		// Listed relative and named in full is one file, not two: the shape a
		// configuration takes when the program is told where its configuration
		// is and the configuration also says to send it.
		let both = DevPodFiles.plan(
			files: ["config/config.json"],
			arguments: ["${workspaceFolder}/config/config.json"],
			root: root
		)
		#expect(both.transfers.count == 1)
		#expect(both.arguments == ["/app/files/config.json"])
	}

	@Test func ignoresSomethingThatIsNotThere() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(DevPodFiles.plan(files: ["/nowhere/config.json"], arguments: [], root: root)
			.transfers.isEmpty)
	}
}

/// Watching an install, so a launch that will never work says why.
struct DevPodWatchTests {
	private let stuck = """
	{"items": [{
	  "metadata": {"name": "ideai-thing-ideai-devpod-59cd-2cmr2"},
	  "status": {
	    "phase": "Pending",
	    "containerStatuses": [{
	      "state": {"waiting": {
	        "reason": "ImagePullBackOff",
	        "message": "Back-off pulling image \\"ideai-devpod:dev\\""
	      }}
	    }]
	  }
	}]}
	"""

	@Test func readsWhyAPodIsNotRunning() {
		let states = DevPodWatch.parse(stuck)
		#expect(states.count == 1)
		#expect(states[0].pod == "ideai-thing-ideai-devpod-59cd-2cmr2")
		#expect(states[0].phase == "Pending")
		#expect(states[0].reason == "ImagePullBackOff")
		#expect(states[0].isHopeless)
	}

	/// The point of watching: helm waits two minutes and then reports its own
	/// deadline, while the cluster said this in the fourth second.
	@Test func sayingWhatToDoAboutAnImageTheClusterCannotPull() {
		let explanation = DevPodWatch.explain(DevPodWatch.parse(stuck)[0], image: "")
		#expect(explanation.hasPrefix("The cluster cannot pull"))
		#expect(explanation.contains("import-k3d"))
		#expect(explanation.contains("devpod-publish"))
		#expect(explanation.contains("Back-off pulling image"))
	}

	@Test func aRunningPodIsNothingToGiveUpOn() {
		let json = """
		{"items": [{
		  "metadata": {"name": "pod-1"},
		  "status": {"phase": "Running", "containerStatuses": [{"state": {"running": {}}}]}
		}]}
		"""
		let states = DevPodWatch.parse(json)
		#expect(states[0].reason.isEmpty)
		#expect(!states[0].isHopeless)
		#expect(states[0].line == "pod-1: Running")
	}

	/// A container that is only starting is not a failure: pulling takes time,
	/// and giving up on it would be giving up on every first launch.
	@Test func waitingForAnImageIsNotHopeless() {
		let json = """
		{"items": [{
		  "metadata": {"name": "pod-1"},
		  "status": {"phase": "Pending", "containerStatuses": [
		    {"state": {"waiting": {"reason": "ContainerCreating"}}}
		  ]}
		}]}
		"""
		#expect(!DevPodWatch.parse(json)[0].isHopeless)
	}

	@Test func nonsenseIsNoPods() {
		#expect(DevPodWatch.parse("").isEmpty)
		#expect(DevPodWatch.parse("not json at all").isEmpty)
	}

	/// A cluster that has to pull needs to be told what to pull, so the image
	/// belongs to the configuration and has to survive being written down.
	@Test func theImageIsKeptInTheConfiguration() throws {
		var configuration = LaunchConfiguration(name: "in the cluster", type: "go")
		configuration.devPod = LaunchConfiguration.DevPodSettings(
			context: "k3c-demo1",
			namespace: "devpod",
			image: "pharndt/ideai-devpod:v1"
		)
		let json = configuration.json
		let read = try #require(LaunchConfiguration(json: json))
		#expect(read.devPod?.image == "pharndt/ideai-devpod:v1")
	}
}

/// The chart the app ships is a copy of the chart in the repository, and a
/// copy is a thing that drifts. This is the reminder: an edit to one that
/// never reached the other means the app installs the old chart, which shows
/// up in a cluster as a pod that runs the wrong image.
struct BundledChartTests {
	@Test func theShippedChartMatchesTheSource() throws {
		let repository = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let source = repository.appendingPathComponent("DevPod/chart/ideai-devpod")
		let shipped = repository.appendingPathComponent("Sources/ideai/Resources/devpod-chart")

		let manager = FileManager.default
		try #require(manager.fileExists(atPath: source.path))
		try #require(manager.fileExists(atPath: shipped.path))

		func contents(of directory: URL) throws -> [String: String] {
			var found: [String: String] = [:]
			let files = manager.enumerator(at: directory, includingPropertiesForKeys: nil)
			while let file = files?.nextObject() as? URL {
				guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
				else { continue }
				let relative = file.path.replacingOccurrences(of: directory.path + "/", with: "")
				found[relative] = try String(contentsOf: file, encoding: .utf8)
			}
			return found
		}

		let left = try contents(of: source)
		let right = try contents(of: shipped)
		#expect(Set(left.keys) == Set(right.keys), "the two charts hold different files")
		for (name, text) in left {
			#expect(right[name] == text, "\(name) differs — run: make devpod-chart")
		}
	}
}

/// Writing a dropped file down in a configuration.
struct DevPodFileEntryTests {
	@Test func aFileInTheProjectIsRelativeToIt() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("entry-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("config"), withIntermediateDirectories: true
		)
		defer { try? FileManager.default.removeItem(at: root) }

		let file = root.appendingPathComponent("config/dev.json")
		try "{}".write(to: file, atomically: true, encoding: .utf8)

		// A shared configuration cannot hold one person's home directory.
		#expect(DevPodFiles.entry(for: file, in: root) == "config/dev.json")
	}

	@Test func aFileFromSomewhereElseKeepsItsPath() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("entry-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let elsewhere = FileManager.default.temporaryDirectory
			.appendingPathComponent("outside-\(UUID().uuidString).json")
		try "{}".write(to: elsewhere, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: elsewhere) }

		let entry = DevPodFiles.entry(for: elsewhere, in: root)
		#expect(entry.hasPrefix("/"))
		#expect(entry.hasSuffix(elsewhere.lastPathComponent))
	}

	/// The project root arrives as `/tmp/...` and the file as `/private/tmp/...`
	/// often enough that not resolving both is a bug that only shows up on a
	/// Mac.
	@Test func theSymlinkedTemporaryDirectoryIsStillTheProject() throws {
		let root = URL(fileURLWithPath: "/tmp/entry-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let file = URL(fileURLWithPath: "/private" + root.path + "/thing.json")
		try "{}".write(to: file, atomically: true, encoding: .utf8)

		#expect(DevPodFiles.entry(for: file, in: root) == "thing.json")
	}
}

/// Publishing a microservice that has no chart of its own.
struct DevPodIngressTests {
	@Test func theHostAndPortSurviveBeingWrittenDown() throws {
		var configuration = LaunchConfiguration(name: "lamarzocco", type: "go")
		configuration.devPod = LaunchConfiguration.DevPodSettings(
			context: "k3c-demo1",
			ingressHost: "lamarzocco.dev.example.com",
			port: 9000
		)
		let read = try #require(LaunchConfiguration(json: configuration.json))
		#expect(read.devPod?.ingressHost == "lamarzocco.dev.example.com")
		#expect(read.devPod?.port == 9000)
	}

	@Test func aHostTurnsTheChartsIngressOn() {
		let values = DevPodFiles.helmValues(for: .init(ingressHost: "thing.example.com"))
		#expect(values.contains("ingress.enabled=true"))
		#expect(values.contains("ingress.host=thing.example.com"))
	}

	/// The chart serves 8080 by default, which is not every service's port.
	@Test func aPortReplacesTheChartsFirstOne() {
		let values = DevPodFiles.helmValues(for: .init(port: 9000))
		#expect(values.contains("app.ports[0].containerPort=9000"))
		#expect(values.contains("app.ports[0].name=http"))
	}

	/// Nothing asked for, nothing set: a configuration that says none of this
	/// must not start publishing hostnames.
	@Test func sayingNothingSetsNothing() {
		#expect(DevPodFiles.helmValues(for: .init()).isEmpty)
	}

	/// The chart joins the repository and the tag, so a reference with a tag on
	/// it has to arrive as two values — otherwise the pod is asked to pull
	/// `pharndt/ideai-devpod:v2:dev`, which exists nowhere.
	@Test func theImageComesThroughAsARepositoryAndATag() {
		let values = DevPodFiles.helmValues(for: .init(image: "pharndt/ideai-devpod:v2"))
		#expect(values == ["image.repository=pharndt/ideai-devpod", "image.tag=v2"])
	}

	/// What the project needs, when nobody has said: the pod for a Zig project
	/// holds gdbserver and not Delve.
	@Test func anImageWorkedOutFromTheProjectWinsOverAnEmptyField() {
		let values = DevPodFiles.helmValues(
			for: .init(), image: "pharndt/ideai-devpod:dev-native"
		)
		#expect(values == ["image.repository=pharndt/ideai-devpod", "image.tag=dev-native"])
	}
}

/// Noticing that the pod in the cluster is not what the configuration asks for.
struct DevPodUpgradeTests {
	private let deployed = """
	{"image": {"repository": "pharndt/ideai-devpod"},
	 "ingress": {"enabled": true, "host": "thing.example.com"},
	 "app": {"ports": [{"name": "http", "containerPort": 9000}]}}
	"""

	@Test func nothingAskedForIsNothingToDo() {
		#expect(!DevPodInstall.upgradeNeeded(desired: [], deployed: deployed))
	}

	@Test func whatIsAlreadyDeployedNeedsNothing() {
		#expect(!DevPodInstall.upgradeNeeded(
			desired: ["ingress.enabled=true", "ingress.host=thing.example.com"],
			deployed: deployed
		))
	}

	/// The case this exists for: a configuration that has gained an ingress
	/// since the pod was installed.
	@Test func aNewHostNeedsAnUpgrade() {
		#expect(DevPodInstall.upgradeNeeded(
			desired: ["ingress.enabled=true", "ingress.host=other.example.com"],
			deployed: deployed
		))
	}

	@Test func anIndexedPathIsFollowedIntoTheList() {
		#expect(!DevPodInstall.upgradeNeeded(
			desired: ["app.ports[0].containerPort=9000"], deployed: deployed
		))
		#expect(DevPodInstall.upgradeNeeded(
			desired: ["app.ports[0].containerPort=8080"], deployed: deployed
		))
	}

	/// A release with no values at all, and one helm could not be asked about,
	/// both mean "install it".
	@Test func nothingDeployedMeansUpgrade() {
		#expect(DevPodInstall.upgradeNeeded(desired: ["ingress.enabled=true"], deployed: ""))
		#expect(DevPodInstall.upgradeNeeded(desired: ["ingress.enabled=true"], deployed: "null"))
		#expect(DevPodInstall.upgradeNeeded(desired: ["ingress.enabled=true"], deployed: "{}"))
	}
}

/// What an agent is allowed to do without stopping to ask.
struct AgentPermissionTests {
	@Test func acceptingEditsIsTheDefault() {
		#expect(AgentLauncher.permissionArguments("acceptEdits") == ["--permission-mode", "acceptEdits"])
		#expect(AgentLauncher.permissionArguments("anything else") == ["--permission-mode", "acceptEdits"])
	}

	/// An agent asked to fix one problem that stops to ask whether it may edit
	/// the file has not been asked anything.
	@Test func askingIsTheToolsOwnBehaviour() {
		#expect(AgentLauncher.permissionArguments("ask").isEmpty)
	}

	@Test func everythingSkipsThePromptsEntirely() {
		#expect(AgentLauncher.permissionArguments("full") == ["--dangerously-skip-permissions"])
	}
}

/// A release that a crash or a cancelled run left half-done.
struct HelmPendingTests {
	private let refusal = """
	Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
	"""

	@Test func theRefusalIsRecognised() {
		#expect(DevPodInstall.isPendingOperation(refusal))
		#expect(!DevPodInstall.isPendingOperation("Error: UPGRADE FAILED: timed out waiting"))
		#expect(!DevPodInstall.isPendingOperation(""))
	}

	/// Nothing was ever deployed by a pending install, so there is nothing to
	/// roll back to — it has to go.
	@Test func aPendingInstallIsRemoved() {
		#expect(DevPodInstall.recovery(forStatus: "pending-install") == .uninstall)
	}

	@Test func aPendingUpgradeGoesBackToWhatWorked() {
		#expect(DevPodInstall.recovery(forStatus: "pending-upgrade") == .rollback)
		#expect(DevPodInstall.recovery(forStatus: "pending-rollback") == .rollback)
	}

	@Test func aHealthyReleaseIsLeftAlone() {
		#expect(DevPodInstall.recovery(forStatus: "deployed") == .none)
		#expect(DevPodInstall.recovery(forStatus: "") == .none)
	}

	@Test func theStatusIsReadFromHelmsOwnJSON() {
		let json = """
		{"name":"ideai-thing","info":{"status":"pending-upgrade","description":"Preparing upgrade"}}
		"""
		#expect(DevPodInstall.statusName(fromJSON: json) == "pending-upgrade")
		#expect(DevPodInstall.statusName(fromJSON: "not json").isEmpty)
	}
}

