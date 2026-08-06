import Foundation
import Testing
@testable import AbydosKit

/// What the Makefile reader makes of every Makefile on this machine.
///
/// Not an assertion about any one project — a survey, printed, so the answer
/// to "does this work generally or only for one file" is measured rather than
/// asserted. Runs only when asked, since it reads the user's home directory.
struct MakeSurveyTests {
	@Test func surveysEveryMakefileAround() throws {
		guard ProcessInfo.processInfo.environment["ABYDOS_MAKE_SURVEY"] != nil else { return }

		let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("dev")
		let manager = FileManager.default
		guard let walker = manager.enumerator(
			at: home, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		) else { return }

		var files: [URL] = []
		for case let url as URL in walker {
			guard url.lastPathComponent == "Makefile" else { continue }
			let path = url.path
			guard !path.contains("/node_modules/"), !path.contains("/vendor/"),
			      !path.contains("/.build/"), !path.contains("/cmake-build")
			else { continue }
			files.append(url)
			if files.count >= 60 { break }
		}

		var withTargets = 0
		var withPlans = 0
		for url in files.sorted(by: { $0.path < $1.path }) {
			guard let makefile = Makefile.read(at: url) else { continue }
			let goals = makefile.targets.filter { MakeLaunch.plan(for: $0.name, in: makefile) != nil }
			if !makefile.targets.isEmpty { withTargets += 1 }
			if !goals.isEmpty { withPlans += 1 }

			let short = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
			print("SURVEY \(makefile.targets.count) targets, \(goals.count) debuggable — \(short)")
			for goal in goals {
				guard let plan = MakeLaunch.plan(for: goal.name, in: makefile) else { continue }
				print("   → \(goal.name): build=\(plan.buildTargets) pkg=\(plan.package) "
					+ "args=\(plan.arguments.count) env=\(plan.environment.count)+\(plan.environmentCommands.count)")
			}
		}
		print("SURVEY TOTAL files=\(files.count) parsed=\(withTargets) debuggable=\(withPlans)")
	}
}
