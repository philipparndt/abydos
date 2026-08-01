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
