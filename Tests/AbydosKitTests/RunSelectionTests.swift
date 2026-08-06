import Foundation
import Testing
@testable import AbydosKit

/// Which thing the play button is pointed at.
///
/// The case that broke: a project with launch configurations of its own, and a
/// Makefile goal chosen from the menu. The strip showed the first
/// configuration while the button ran the goal — and the earlier tests missed
/// it because the project they used had no configurations at all, so there was
/// nothing for the fallback to fall back to.
struct RunSelectionTests {
	private let configurations = ["make image", "Debug ideai", "Run tests"]

	@Test func aChosenMakeGoalWinsOverEveryConfiguration() {
		let target = RunSelection.resolve(
			configurations: configurations, makeRun: "make run", selected: "make run"
		)
		#expect(target == .make("make run"))
		#expect(RunSelection.displayName(
			configurations: configurations, makeRun: "make run", selected: "make run"
		) == "make run")
	}

	@Test func aChosenConfigurationIsTheOne() {
		#expect(RunSelection.resolve(
			configurations: configurations, makeRun: nil, selected: "Debug ideai"
		) == .configuration("Debug ideai"))
	}

	/// Picking a configuration after a make goal leaves the goal behind rather
	/// than letting it win from the past.
	@Test func aStaleMakeGoalDoesNotWin() {
		#expect(RunSelection.resolve(
			configurations: configurations, makeRun: "make run", selected: "Debug ideai"
		) == .configuration("Debug ideai"))
	}

	/// Nothing chosen: the first configuration, which is what the menu shows
	/// first as well.
	@Test func withNothingChosenTheFirstIsOffered() {
		#expect(RunSelection.resolve(
			configurations: configurations, makeRun: nil, selected: nil
		) == .configuration("make image"))
	}

	/// A project with no configurations at all — the case that used to be the
	/// only one tested.
	@Test func aProjectWithNoConfigurationsRunsTheGoal() {
		#expect(RunSelection.resolve(
			configurations: [], makeRun: "make dev", selected: "make dev"
		) == .make("make dev"))
		#expect(RunSelection.resolve(
			configurations: [], makeRun: "make dev", selected: nil
		) == .make("make dev"))
	}

	@Test func nothingAtAllIsNothingToRun() {
		#expect(RunSelection.resolve(configurations: [], makeRun: nil, selected: nil) == .none)
		#expect(RunSelection.displayName(configurations: [], makeRun: nil, selected: nil) == nil)
	}

	/// A name that belongs to neither list — a configuration deleted while it
	/// was selected — falls back rather than showing something that is gone.
	@Test func aNameThatIsGoneFallsBack() {
		#expect(RunSelection.resolve(
			configurations: configurations, makeRun: nil, selected: "Deleted"
		) == .configuration("make image"))
	}

	/// What the strip shows and what the button runs are the same answer, for
	/// every combination — that they were two answers is the whole bug.
	@Test func theStripAndTheButtonAgree() {
		for configurations in [[], ["A", "B"]] {
			for makeRun in [nil, "make run"] as [String?] {
				for selected in [nil, "A", "make run", "Gone"] as [String?] {
					let target = RunSelection.resolve(
						configurations: configurations, makeRun: makeRun, selected: selected
					)
					let shown = RunSelection.displayName(
						configurations: configurations, makeRun: makeRun, selected: selected
					)
					switch target {
					case let .configuration(name): #expect(shown == name)
					case let .make(name):          #expect(shown == name)
					case .none:                    #expect(shown == nil)
					}
				}
			}
		}
	}
}
