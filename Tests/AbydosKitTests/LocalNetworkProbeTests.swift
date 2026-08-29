import Foundation
import Testing
@testable import AbydosKit

/// The probe exists to tell a permission apart from an outage, so what it must
/// never do is answer "unreachable" about something that was merely closed —
/// that reading sends somebody to System Settings for a broker that is simply
/// not running. Loopback is the one address macOS does not gate, which makes it
/// the place to check the mapping without the answer depending on the machine's
/// permissions or on anything being on the network.
struct LocalNetworkProbeTests {
	@Test func aClosedPortIsRefusedRatherThanUnreachable() async throws {
		let port = try closedLoopbackPort()

		// **The timeout is a hang detector here too.** A closed loopback port is
		// refused immediately, so a *timeout* is never the right answer — and
		// two seconds is short enough that a loaded machine can miss it, at
		// which point the probe answers `unreachable` and the test reads a busy
		// machine as a permissions fault. That is precisely the confusion this
		// probe exists to prevent, so the number must not be able to cause it.
		let timeout: TimeInterval = 30

		let socket = LocalNetworkProbe.checkWithSocket(
			host: "127.0.0.1", port: port, timeout: timeout
		)
		#expect(socket == .refused, "a closed port read as \(socket)")

		let framework = await withCheckedContinuation { continuation in
			LocalNetworkProbe.check(host: "127.0.0.1", port: port, timeout: timeout) { result in
				continuation.resume(returning: result)
			}
		}
		// The two paths are asked the same question in the same run precisely
		// because they are compared against each other in the diagnostic: the
		// app answers through Network.framework, a program it launches answers
		// through a socket, and a difference between them is meant to mean a
		// difference in permission rather than in how the question was asked.
		#expect(framework == socket, "the app said \(framework), a child said \(socket)")
	}

	@Test func summariesSayWhatToDoOnlyWhenThereIsSomethingToDo() {
		// Refused is a working permission, and must not mention Settings.
		#expect(!LocalNetworkProbe.Result.refused.summary.contains("System Settings"))
		#expect(!LocalNetworkProbe.Result.reachable.summary.contains("System Settings"))
		#expect(LocalNetworkProbe.Result.unreachable("EHOSTUNREACH").summary.contains("System Settings"))
	}

	@Test func hostAndPortAreReadTheWaySomebodyWouldTypeThem() {
		#expect(LocalNetworkProbe.parse("10.10.1.3:1883")?.host == "10.10.1.3")
		#expect(LocalNetworkProbe.parse("10.10.1.3:1883")?.port == 1883)
		// A bare host is not a target: there is no port to try, and guessing
		// one would produce an answer about a port nobody asked about.
		#expect(LocalNetworkProbe.parse("10.10.1.3") == nil)
		#expect(LocalNetworkProbe.parse(":1883") == nil)
		#expect(LocalNetworkProbe.parse("10.10.1.3:nope") == nil)
	}

	/// A port nothing is listening on: bound, read back, then given up.
	private func closedLoopbackPort() throws -> UInt16 {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		try #require(descriptor >= 0)
		defer { close(descriptor) }

		var address = sockaddr_in()
		address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		address.sin_family = sa_family_t(AF_INET)
		address.sin_port = 0
		address.sin_addr.s_addr = inet_addr("127.0.0.1")

		let bound = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		try #require(bound == 0)

		var assigned = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		let named = withUnsafeMutablePointer(to: &assigned) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				getsockname(descriptor, $0, &length)
			}
		}
		try #require(named == 0)
		return UInt16(bigEndian: assigned.sin_port)
	}
}
