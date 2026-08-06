import Foundation
import Testing
@testable import AbydosKit

/// Against the Makefile this feature was built for.
///
/// Skipped where the file is not present, so the suite stays hermetic; it
/// exists because a parser that only reads its own fixtures proves nothing.
struct MakeRealProjectTests {
	private var url: URL? {
		let path = NSHomeDirectory() + "/dev/smarthome/projects/mqtt-unifi-network/app/Makefile"
		return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
	}

	@Test func readsTheGoals() throws {
		guard let url, let makefile = Makefile.read(at: url) else { return }
		let names = makefile.targets.map(\.name)
		#expect(names.contains("dev"))
		#expect(names.contains("build-backend"))
		#expect(makefile.target(named: "dev")?.summary.isEmpty == false)
	}

	/// The whole point: `make dev` becomes something a debugger can start.
	@Test func plansTheDevGoal() throws {
		guard let url, let makefile = Makefile.read(at: url) else { return }
		let plan = try #require(MakeLaunch.plan(for: "dev", in: makefile))

		print("PLAN targets=\(plan.buildTargets) package=\(plan.package)")
		print("PLAN args=\(plan.arguments)")
		print("PLAN env=\(plan.environment) commands=\(plan.environmentCommands.keys.sorted())")

		// The frontend is built by make; the Go binary is left to the debugger.
		#expect(plan.buildTargets.contains("build-frontend"))
		#expect(!plan.buildTargets.contains("build-backend"))
		#expect(plan.package == ".")
		#expect(plan.arguments.count == 1)
		#expect(plan.arguments.first?.hasSuffix("config.json") == true)
		#expect(plan.environmentCommands.keys.sorted() == ["UNIFI_PASSWORD", "UNIFI_USER"])
	}
}
