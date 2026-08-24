import Testing
import Foundation
@testable import AbydosKit

/// How the run list is arranged so that a hundred-module build fits in it.
///
/// The scenario every test here is a version of: a reactor offers each goal in
/// each of its modules, so what the menu used to show was goals × modules
/// printed flat — three goals across a hundred modules is three hundred rows,
/// two hundred and ninety-seven of which say the same three words.
struct RunPickerTests {
	private func maven(_ goal: String, in module: String?) -> RunConfiguration {
		RunConfiguration(
			name: module.map { "mvn \(goal) (\($0))" } ?? "mvn \(goal)",
			source: .maven,
			executable: "mvn",
			arguments: [goal],
			workingDirectory: "/p/" + (module ?? ""),
			module: module
		)
	}

	private func saved(_ name: String) -> RunConfiguration {
		RunConfiguration(name: name, source: .vscode, executable: "java", workingDirectory: "/p")
	}

	private let modules = ["client", "client/ui", "common", "common/api-core", "server"]

	private func reactor(goals: [String] = ["clean", "test", "package"]) -> [RunConfiguration] {
		// Root first, then the modules — the order discovery walks them in, and
		// the order that broke the first version of `arrange`.
		goals.flatMap { goal in [maven(goal, in: nil)] + modules.map { maven(goal, in: $0) } }
	}

	// MARK: - The arithmetic

	@Test func aGoalIsOneRowHoweverManyModulesItRunsIn() {
		let arranged = RunPicker.arrange(reactor())

		#expect(arranged.goals.count == 3)
		#expect(arranged.goals.map(\.name) == ["mvn clean", "mvn test", "mvn package"])
		#expect(arranged.rowCount == 3, "\(arranged.rowCount) rows")
		#expect(arranged.flatCount == 18, "3 goals × (root + 5 modules)")
	}

	/// The root is discovered before its modules, and the first version of this
	/// put it in one section and its modules in another.
	@Test func theRootIsPartOfItsGoalRatherThanARowOfItsOwn() throws {
		let arranged = RunPicker.arrange(reactor(goals: ["clean"]))

		#expect(arranged.singles.isEmpty, "\(arranged.singles.map(\.name))")
		let goal = try #require(arranged.goals.first)
		#expect(goal.atRoot?.module == nil)
		#expect(goal.inModules.count == 5)
		#expect(goal.places == 6)
	}

	/// Return on the goal row runs it where `mvn clean` in a terminal would.
	@Test func choosingAGoalRunsItAtTheReactorRoot() {
		let arranged = RunPicker.arrange(reactor(goals: ["clean"]))
		#expect(arranged.goals.first?.whenChosen?.module == nil)
	}

	/// A reactor whose root declares no goals still has to run somewhere.
	@Test func aGoalWithNoRootRunsInItsFirstModule() {
		let arranged = RunPicker.arrange(modules.map { maven("verify", in: $0) })
		#expect(arranged.goals.first?.whenChosen?.module == "client")
	}

	/// One place is not a goal with modules behind it — it is a row, and a
	/// `1 place ›` chip on it would be a lie.
	@Test func aGoalFoundInOnePlaceStaysARow() {
		let arranged = RunPicker.arrange([maven("clean", in: nil)])
		#expect(arranged.goals.isEmpty)
		#expect(arranged.singles.map(\.name) == ["mvn clean"])
	}

	/// Folding is for lists long enough to hide their neighbours. Two rows are
	/// not, and showing both is what tells two `run Main`s apart — which the
	/// flat menu could not do at all.
	@Test func aFewPlacesAreShownRatherThanFolded() {
		let two = [maven("verify", in: "client"), maven("verify", in: "server")]
		let arranged = RunPicker.arrange(two)

		#expect(arranged.goals.isEmpty)
		#expect(arranged.singles.map(\.module) == ["client", "server"])
	}

	@Test func enoughPlacesAreFolded() {
		let many = ["a", "b", "c", "d"].map { maven("verify", in: $0) }
		#expect(RunPicker.arrange(many).goals.first?.places == 4)
		// And the threshold is where it says it is.
		#expect(RunPicker.arrange(many, foldFrom: 5).goals.isEmpty)
	}

	/// Two sources that happen to agree on a word are not two halves of one
	/// thing.
	@Test func aMakefileGoalIsNotFoldedIntoAMavenOne() {
		let make = RunConfiguration(
			name: "make test", source: .make, executable: "make",
			arguments: ["test"], workingDirectory: "/p"
		)
		let arranged = RunPicker.arrange([make] + reactor(goals: ["test"]))

		#expect(arranged.singles.map(\.name) == ["make test"])
		#expect(arranged.goals.map(\.name) == ["mvn test"])
	}

	// MARK: - Pinned

	@Test func savedConfigurationsStayAboveWhatWasMerelyDiscovered() {
		let all = [saved("Server"), saved("Client")] + reactor(goals: ["clean"])
		let arranged = RunPicker.arrange(all, pinned: ["Server", "Client"])

		#expect(arranged.pinned.map(\.name) == ["Server", "Client"])
		#expect(arranged.goals.map(\.name) == ["mvn clean"])
	}

	// MARK: - Filtering

	/// Filtering flattens the folding: somebody who has typed a module name has
	/// already said which one they mean.
	@Test func typingAModuleReachesItWithoutOpeningTheGoal() {
		let arranged = RunPicker.arrange(reactor())
		let found = RunPicker.matches(for: "client/ui", in: arranged)

		#expect(found.count == 3, "\(found.map(\.configuration.name))")
		#expect(found.allSatisfy { $0.configuration.module == "client/ui" })
		// The row says which goal it came out of, since its own name no longer
		// carries the module.
		#expect(found.allSatisfy { $0.goal != nil })
	}

	/// A hit in the thing's own name beats a hit in the module beside it — the
	/// same rule the file search stands on.
	@Test func aHitInTheNameOutranksAHitInTheModule() {
		let all = reactor(goals: ["clean"]) + [maven("verify", in: "cleanup-tools")]
		let arranged = RunPicker.arrange(all)

		let found = RunPicker.matches(for: "clean", in: arranged)
		#expect(found.first?.configuration.goalName == "mvn clean", "\(found.map(\.configuration.name))")
	}

	/// Saved configurations come first, because they were written down on
	/// purpose.
	@Test func aSavedConfigurationOutranksADiscoveredOne() {
		let all = [saved("clean deploy")] + reactor(goals: ["clean"])
		let arranged = RunPicker.arrange(all, pinned: ["clean deploy"])

		#expect(RunPicker.matches(for: "clean", in: arranged).first?.configuration.name == "clean deploy")
	}

	@Test func nothingMatchesAnEmptyQuery() {
		let arranged = RunPicker.arrange(reactor())
		#expect(RunPicker.matches(for: "", in: arranged).isEmpty)
		#expect(RunPicker.matches(for: "  ", in: arranged).isEmpty)
	}

	/// The cap exists for the reason the palette's does: without it the sections
	/// underneath are pushed off the end.
	@Test func onlyAsManyAsAskedForAreReturned() {
		let arranged = RunPicker.arrange(reactor())
		#expect(RunPicker.matches(for: "mvn", in: arranged, limit: 5).count == 5)
		#expect(RunPicker.matches(for: "mvn", in: arranged, limit: 0).isEmpty)
	}

	/// A list that reshuffled between two keystrokes would be one nobody could
	/// click.
	@Test func theSameQueryGivesTheSameOrderTwice() {
		let arranged = RunPicker.arrange(reactor())
		#expect(
			RunPicker.matches(for: "co", in: arranged) == RunPicker.matches(for: "co", in: arranged)
		)
	}

	// MARK: - The name

	/// `goalName` takes off exactly the suffix `moduleSuffix` put on, and leaves
	/// a name that merely mentions a module alone.
	@Test func theModuleComesOffTheNameAndNothingElseDoes() {
		#expect(maven("clean", in: "client/ui").goalName == "mvn clean")
		#expect(maven("clean", in: nil).goalName == "mvn clean")
		#expect(saved("Run (client) tests").goalName == "Run (client) tests")
	}
}
