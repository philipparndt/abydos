import Foundation
import Testing
@testable import AbydosKit

/// Against a real endpoint, when there is one.
///
/// Skipped unless `ABYDOS_PPROF_ENDPOINT` names a running program, so the
/// suite stays hermetic; run it by hand against anything that serves pprof.
struct PprofLiveTests {
	private var endpoint: PprofEndpoint? {
		ProcessInfo.processInfo.environment["ABYDOS_PPROF_ENDPOINT"]
			.flatMap(PprofEndpoint.init(text:))
	}

	@Test func listsWhatAProgramOffers() async throws {
		guard let endpoint else { return }
		let kinds = try await PprofClient().kinds(at: endpoint)
		#expect(kinds.map(\.name).contains("heap"))
		#expect(kinds.map(\.name).contains("goroutine"))
	}

	@Test func fetchesAHeapProfile() async throws {
		guard let endpoint else { return }
		let profile = try await PprofClient().profile("heap", from: endpoint)
		let graph = FlameGraph.build(from: profile)

		#expect(graph.total > 0)
		#expect(graph.unit == "bytes")
		#expect(graph.functions.contains { $0.name.hasPrefix("main.") })
	}

	@Test func fetchesACPUProfile() async throws {
		guard let endpoint else { return }
		let profile = try await PprofClient().profile("profile", from: endpoint, seconds: 2)
		let graph = FlameGraph.build(from: profile)

		#expect(graph.unit == "nanoseconds")
		#expect(graph.total > 0)
		print("LIVE CPU top: \(graph.functions.prefix(4).map(\.name))")
		#expect(graph.functions.contains { $0.name.hasPrefix("main.") })
	}

	@Test func reportsAnEndpointThatIsNotThere() async {
		let dead = try! #require(PprofEndpoint(text: "127.0.0.1:1"))
		await #expect(throws: (any Error).self) {
			try await PprofClient(timeout: 2).kinds(at: dead)
		}
	}
}
