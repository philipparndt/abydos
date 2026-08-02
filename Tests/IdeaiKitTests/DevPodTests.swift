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

	@Test func ignoresSomethingThatIsNotThere() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(DevPodFiles.plan(files: ["/nowhere/config.json"], arguments: [], root: root)
			.transfers.isEmpty)
	}
}
