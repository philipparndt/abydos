import Foundation
import Testing
@testable import AbydosKit

/// The backlog as a directory: what counts as an item, what a number is, and
/// what moving one does.
struct BacklogTests {
	private func makeProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("backlog-\(UUID().uuidString)")
			.appendingPathComponent("project")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func cleanUp(_ root: URL) {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}

	// MARK: - Names and numbers

	@Test func aSlugIsCutAtAWord() {
		#expect(Backlog.slug(from: "The capsule is clipped") == "the-capsule-is-clipped")
		#expect(Backlog.slug(from: "A `code` span, and — punctuation!") == "a-code-span-and-punctuation")

		// The old rule cut at sixty characters wherever that fell, which is
		// where `…-past-about-one-and-a-half-t` came from.
		let long = Backlog.slug(from: "a system control cannot be drawn past about one and a half times its size")
		#expect(long.count <= 60)
		#expect(!long.hasSuffix("-"))
		#expect(long == "a-system-control-cannot-be-drawn-past-about-one-and-a-half")
	}

	@Test func aTitleWithNothingUsableInItStillMakesAName() {
		#expect(Backlog.slug(from: "???") == "item")
	}

	@Test func numbersCarryOnFromTheHighestInUse() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		#expect(backlog.nextNumber() == 1)
		let first = try backlog.create(title: "One")
		#expect(first.number == 1)

		// Including the states nothing new is ever written to: a project seeded
		// from its commit log has 396 of them, and handing out 1 next would put
		// two items on the same number for ever.
		let history = backlog.directory(for: .history)
		try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
		try "# 396. Something".write(
			to: history.appendingPathComponent("0396-something.md"),
			atomically: true,
			encoding: .utf8
		)
		#expect(backlog.nextNumber() == 397)
	}

	// MARK: - The two shapes

	@Test func anItemIsAFileOrAFolderWithATaskInIt() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let plain = try backlog.create(title: "Only words")
		#expect(plain.carriesFiles == false)
		#expect(plain.file.lastPathComponent == "0001-only-words.md")

		let carrying = try backlog.create(title: "With a picture", carriesFiles: true)
		#expect(carrying.carriesFiles)
		#expect(carrying.file.lastPathComponent == Backlog.taskFileName)
		#expect(carrying.folder?.lastPathComponent == "0002-with-a-picture")

		// Both read back the same way, which is the whole point of allowing two.
		let read = backlog.items(in: .open)
		#expect(read.map(\.number) == [1, 2])
		#expect(read.map(\.title) == ["Only words", "With a picture"])
	}

	@Test func aStrayFileIsNotAnItem() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])
		_ = try backlog.create(title: "Real")

		let open = backlog.directory(for: .open)
		try "notes".write(to: open.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
		try "notes".write(to: open.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
		try FileManager.default.createDirectory(
			at: open.appendingPathComponent("scratch"),
			withIntermediateDirectories: true
		)

		#expect(backlog.items(in: .open).map(\.number) == [1])
	}

	// MARK: - Finding one

	@Test func anItemIsFoundByItsNumberWhereverItIs() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		_ = try backlog.create(title: "Still open")
		let moved = try backlog.move(try backlog.create(title: "Finished"), to: .completed)
		let folder = try backlog.move(
			try backlog.create(title: "With a picture", carriesFiles: true), to: .waiting
		)

		#expect(backlog.item(number: 1)?.state == .open)
		#expect(backlog.item(number: 2)?.number == moved.number)
		#expect(backlog.item(number: 2)?.state == .completed)
		// Both shapes, since the folder form has no `.md` on the end of its name.
		#expect(backlog.item(number: 3)?.state == .waiting)
		#expect(backlog.item(number: 3)?.folder?.lastPathComponent == folder.folder?.lastPathComponent)
		#expect(backlog.item(number: 99) == nil)
	}

	@Test func theTitleComesFromTheHeadingWithoutItsNumber() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let open = backlog.directory(for: .open)
		try "# 12. Ligatures fade\n\nBody.\n".write(
			to: open.appendingPathComponent("0012-ligatures-fade-and-then-some.md"),
			atomically: true,
			encoding: .utf8
		)
		// No heading at all: the name has to do, rather than an empty card.
		try "Just some text.\n".write(
			to: open.appendingPathComponent("0013-no-heading-here.md"),
			atomically: true,
			encoding: .utf8
		)

		let items = backlog.items(in: .open)
		#expect(items[0].title == "Ligatures fade")
		#expect(items[1].title == "No heading here")
	}

	// MARK: - Moving

	@Test func movingTakesTheNumberAndEverythingWithIt() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "With a picture", carriesFiles: true)
		let shot = root.appendingPathComponent("shot.png")
		try Data("png".utf8).write(to: shot)
		let attached = try backlog.attach(shot, to: item)
		#expect(attached.item.images().count == 1)

		let moved = try backlog.move(attached.item, to: .ready)
		#expect(moved.state == .ready)
		#expect(moved.number == item.number)
		#expect(moved.images().count == 1)
		#expect(backlog.items(in: .open).isEmpty)
	}

	@Test func attachingTurnsAFileIntoAFolder() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "Only words")
		#expect(item.carriesFiles == false)
		let body = item.text()

		let shot = root.appendingPathComponent("shot.png")
		try Data("png".utf8).write(to: shot)
		let attached = try backlog.attach(shot, to: item)

		#expect(attached.item.carriesFiles)
		#expect(attached.item.number == item.number)
		// The words survive the conversion, which is the one thing that would
		// be unforgivable to get wrong.
		#expect(attached.item.text() == body)
		#expect(attached.attachment.lastPathComponent == "shot.png")
	}

	@Test func aSecondAttachmentOfTheSameNameKeepsTheFirst() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "Two shots", carriesFiles: true)
		var current = item
		for text in ["one", "two"] {
			let shot = root.appendingPathComponent("Screenshot.png")
			try Data(text.utf8).write(to: shot)
			current = try backlog.attach(shot, to: current).item
		}

		let images = current.images().map(\.lastPathComponent).sorted()
		#expect(images == ["Screenshot-2.png", "Screenshot.png"])
	}

	// MARK: - The checklist

	@Test func stepsAreCountedTickedAndUnticked() {
		let progress = BacklogItem.progress(in: """
		# 443. Something

		## Steps

		- [x] Find where the width comes from
		* [X] Ask tmux instead
		+ [ ] A test that fails with the old answer
		- [ ] `spec/terminal.md` says what the project now does
		""")

		#expect(progress?.done == 2)
		#expect(progress?.total == 4)
		#expect(progress?.summary == "2/4")
		#expect(progress?.isComplete == false)
	}

	@Test func anItemWithNoChecklistHasNoFraction() {
		// Different from `0/4`: a card should say nothing rather than claim
		// that nothing has been done.
		#expect(BacklogItem.progress(in: "# 1. A title\n\nJust prose.\n") == nil)
	}

	@Test func proseWithBracketsInItIsNotAStep() {
		// Markdown links and quoted `[x]` in a sentence are what would
		// otherwise make the number meaningless in the items with the most
		// words — which is most of them here.
		let progress = BacklogItem.progress(in: """
		See [the notes](notes.md) and the `[ ]` syntax.

		- A plain bullet
		- [x] A real one
		- [?] Not a checkbox
		""")
		#expect(progress?.summary == "1/1")
	}

	@Test func whatIsLeftIsNamedRatherThanCounted() {
		let remaining = BacklogItem.remainingSteps(in: """
		- [x] Done this
		- [ ] A test that fails with the old answer
		- [ ] Fold the spec
		""")
		#expect(remaining == ["A test that fails with the old answer", "Fold the spec"])
	}

	@Test func aNewItemComesWithAChecklistToTick() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "Fresh")
		let progress = item.progress()
		#expect(progress != nil)
		// Nothing pre-ticked: a template that arrives with work marked done is
		// a template that lies about the one thing it exists to say.
		#expect(progress?.done == 0)
		#expect(item.text().contains("## Steps"))
	}

	/// The default `create` is given, which is what both callers rely on.
	///
	/// `abydos-backlog new` passes no state unless `--state` is typed, and the
	/// "New item" button in the pane passes none at all — so this default is
	/// the whole of what keeps a button from making the promise `ready` is.
	/// Worth a test of its own because changing the default would break nothing
	/// that compiles.
	@Test func anItemMadeWithoutSayingWhereLandsInOpen() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "Filed from a button")
		#expect(item.state == .open)
		#expect(item.file.path.contains("/open/"))
		#expect(backlog.items(in: .ready).isEmpty)
	}

	// MARK: - How much longer

	@Test func anEstimateIsTheClaimAndTheTimeItWasMade() {
		let markdown = """
		# 1. A thing

		## Estimate

		2026-08-11 14:20 — about an hour left

		## Steps

		- [ ] Do it
		"""
		let estimate = BacklogItem.estimate(in: markdown)
		#expect(estimate?.text == "about an hour left")

		var components = DateComponents()
		components.year = 2026
		components.month = 8
		components.day = 11
		components.hour = 14
		components.minute = 20
		#expect(estimate?.saidAt == Calendar.current.date(from: components))
	}

	@Test func anEstimateSurvivesTheWaysSomebodyWouldWriteIt() {
		let hyphen = BacklogItem.parseEstimate("2026-08-11 09:05 - two more days")
		#expect(hyphen?.text == "two more days")
		#expect(BacklogItem.parseEstimate("- 2026-08-11 09:05 — a bullet")?.text == "a bullet")
		#expect(BacklogItem.parseEstimate("2026-08-11 09:05: a colon")?.text == "a colon")
		#expect(BacklogItem.parseEstimate("2026-08-11 09:05 nothing between")?.text == "nothing between")

		// A claim with no time on it is not an estimate. That is the whole rule:
		// "about an hour" that could have been judged this morning is the kind of
		// number somebody believes because it is on the screen.
		#expect(BacklogItem.parseEstimate("about an hour left") == nil)
		#expect(BacklogItem.parseEstimate("2026-08-11 14:20") == nil)
		#expect(BacklogItem.parseEstimate("2026-13-40 99:99 — not a time") == nil)
	}

	@Test func anItemNobodyHasEstimatedHasNoEstimate() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		// Straight off the template, which carries the heading and a line of
		// prose saying what to write under it. Absent, not a guess and not a
		// broken parse of the instructions.
		let item = try backlog.create(title: "Nobody has said")
		#expect(item.text().contains("## Estimate"))
		#expect(item.estimate() == nil)
	}

	@Test func anEstimateOutsideItsSectionIsNotOne() {
		let markdown = """
		# 1. A thing

		## Ruled out

		2026-08-11 14:20 — this is a note about what happened, not a claim

		## Steps

		- [ ] Do it
		"""
		#expect(BacklogItem.estimate(in: markdown) == nil)
	}

	@Test func anEstimateSaysWhenItWasSaidAndTheDayWhenItWasNotToday() throws {
		var components = DateComponents()
		components.year = 2026
		components.month = 8
		components.day = 11
		components.hour = 14
		components.minute = 20
		let saidAt = try #require(Calendar.current.date(from: components))
		let estimate = BacklogItem.Estimate(text: "about an hour left", saidAt: saidAt)

		let sameDay = try #require(Calendar.current.date(byAdding: .hour, value: 3, to: saidAt))
		#expect(estimate.summary(now: sameDay) == "about an hour left, as of 14:20")

		// Tomorrow, an estimate made at 14:20 must not read as if it were made
		// this afternoon.
		let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: saidAt))
		#expect(estimate.summary(now: nextDay) == "about an hour left, as of 11 Aug 14:20")
	}

	@Test func writingAnEstimateReplacesTheOneThatWasThere() {
		let markdown = """
		# 1. A thing

		## Estimate

		2026-08-11 09:00 — most of a day

		## Steps

		- [ ] Do it
		"""
		let written = BacklogItem.writingEstimate("2026-08-11 14:20 — about an hour left", into: markdown)
		#expect(BacklogItem.estimate(in: written)?.text == "about an hour left")
		#expect(!written.contains("most of a day"))
		#expect(written.contains("- [ ] Do it"))

		let cleared = BacklogItem.writingEstimate(nil, into: written)
		#expect(BacklogItem.estimate(in: cleared) == nil)
		// The heading goes with it: an empty section is a question nobody has
		// answered, and somebody who has just said they no longer know has.
		#expect(!cleared.contains("## Estimate"))
		#expect(cleared.contains("- [ ] Do it"))
	}

	@Test func anItemWithNoEstimateSectionGetsOneAboveItsSteps() {
		let markdown = """
		# 1. A thing

		What is wrong.

		## Steps

		- [ ] Do it
		"""
		let written = BacklogItem.writingEstimate("2026-08-11 14:20 — an hour", into: markdown)
		let headings = written.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }
		#expect(headings == ["## Estimate", "## Steps"])
		#expect(BacklogItem.estimate(in: written)?.text == "an hour")
	}

	@Test func aSpecDeltaIsNotAnAttachment() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "Changes behaviour", carriesFiles: true)
		let deltas = item.folder!.appendingPathComponent(Backlog.specDirectoryName, isDirectory: true)
		try FileManager.default.createDirectory(at: deltas, withIntermediateDirectories: true)
		try "## ADDED Requirement: A thing\n".write(
			to: deltas.appendingPathComponent("terminal.md"),
			atomically: true,
			encoding: .utf8
		)

		#expect(item.attachments().isEmpty)
		#expect(item.specDeltas().count == 1)
	}

	// MARK: - Ticking one step

	@Test func anOpenStepKnowsWhichLineItIsOn() {
		let steps = BacklogItem.openSteps(in: """
		## Steps

		- [x] Read the file
		- [ ] Write the test
		- [ ] Fold the spec
		""")
		#expect(steps.map(\.text) == ["Write the test", "Fold the spec"])
		// Counted from zero over the same split every other reader here uses.
		#expect(steps.map(\.line) == [3, 4])
	}

	@Test func tickingAStepChangesOneCharacter() throws {
		let before = "- [x] Done\n- [ ] Not done\n"
		let after = try #require(BacklogItem.ticking(line: 1, in: before))
		#expect(after == "- [x] Done\n- [x] Not done\n")
		#expect(after.count == before.count)
	}

	/// The bullet, the indentation, the prose under a step and a file that ends
	/// without a newline: all of it committed, all of it expected to survive a
	/// tick untouched.
	@Test func tickingKeepsTheContinuationLinesAndTheMissingFinalNewline() throws {
		let before = """
		  * [ ] 3.2 The list: a heading in the title weight,
		        a scrolling table of drawn rows, and the step's
		        first line cut to two.
		  * [ ] 3.3 Opening reads the file once.
		"""
		#expect(!before.hasSuffix("\n"))

		let after = try #require(BacklogItem.ticking(line: 0, in: before))
		#expect(after == """
		  * [x] 3.2 The list: a heading in the title weight,
		        a scrolling table of drawn rows, and the step's
		        first line cut to two.
		  * [ ] 3.3 Opening reads the file once.
		""")
		#expect(!after.hasSuffix("\n"))
	}

	/// The reason a step is a line number and not its words: ticking by text
	/// would find the first of these and tick the other section's box.
	@Test func theSecondOfTwoStepsWithTheSameWordsIsTheOneTicked() throws {
		let markdown = """
		## 1. Reading

		- [ ] Tests

		## 2. Writing

		- [ ] Tests
		"""
		let steps = BacklogItem.openSteps(in: markdown)
		#expect(steps.count == 2)
		#expect(steps.allSatisfy { $0.text == "Tests" })

		let after = try #require(BacklogItem.ticking(line: steps[1].line, in: markdown))
		#expect(after == """
		## 1. Reading

		- [ ] Tests

		## 2. Writing

		- [x] Tests
		""")
	}

	/// The way back from a tick: one character again, and only that one.
	@Test func untickingAStepIsTheTicksMirror() throws {
		let ticked = "- [x] Done\n- [x] Not done\n"
		let after = try #require(BacklogItem.unticking(line: 1, text: "Not done", in: ticked))
		#expect(after == "- [x] Done\n- [ ] Not done\n")
		#expect(after.count == ticked.count)
	}

	@Test func untickingKeepsTheContinuationLinesAndTheMissingFinalNewline() throws {
		let before = """
		  * [x] 3.2 The list: a heading in the title weight,
		        a scrolling table of drawn rows, and the step's
		        first line cut to two.
		  * [ ] 3.3 Opening reads the file once.
		"""
		let after = try #require(BacklogItem.unticking(
			line: 0, text: "3.2 The list: a heading in the title weight,", in: before
		))
		#expect(after.hasPrefix("  * [ ] 3.2 The list"))
		#expect(after.dropFirst(9) == before.dropFirst(9))
		#expect(!after.hasSuffix("\n"))
	}

	/// The safety of offering an undo at all: a line that no longer reads as
	/// the ticked step with those words is not the line that was ticked.
	@Test func anUntickIsRefusedWhenTheLineHasMovedOn() {
		#expect(BacklogItem.unticking(line: 0, text: "Open", in: "- [ ] Open\n") == nil)
		#expect(BacklogItem.unticking(line: 0, text: "Other words", in: "- [x] Open\n") == nil)
		#expect(BacklogItem.unticking(line: 0, text: "Open", in: "## A heading\n") == nil)
		#expect(BacklogItem.unticking(line: 3, text: "Open", in: "- [x] Open\n") == nil)
	}

	@Test func aLineThatIsNoLongerAnOpenStepIsRefused() {
		let markdown = "- [x] Already ticked\n## A heading\n- [ ] Open\n"
		// Ticked since the list was read.
		#expect(BacklogItem.ticking(line: 0, in: markdown) == nil)
		// Prose where a step used to be.
		#expect(BacklogItem.ticking(line: 1, in: markdown) == nil)
		// Past the end, which is a file that got shorter.
		#expect(BacklogItem.ticking(line: 99, in: markdown) == nil)
		// And the one line that is still what it was.
		#expect(BacklogItem.ticking(line: 2, in: markdown) != nil)
	}

	/// A refusal reaches the writing verb as `false` rather than as a throw:
	/// nothing went wrong, the file moved on under whoever was reading it.
	@Test func tickingAnItemWritesItsOwnFileAndRefusesAStaleLine() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		let backlog = Backlog(projectRoot: root)
		try BacklogSetup.run(projectRoot: root, assistants: [])

		let item = try backlog.create(title: "Tick me")
		try "## Steps\n\n- [ ] One\n- [ ] Two\n".write(
			to: item.file, atomically: true, encoding: .utf8
		)
		let steps = item.openSteps()
		#expect(steps.count == 2)

		#expect(try item.tick(line: steps[0].line) == true)
		#expect(item.progress()?.summary == "1/2")
		#expect(item.text() == "## Steps\n\n- [x] One\n- [ ] Two\n")

		// The same line again, now ticked: refused, and nothing else moves.
		#expect(try item.tick(line: steps[0].line) == false)
		#expect(item.progress()?.summary == "1/2")
	}

	@Test func aFileThatCannotBeWrittenIsSaidSoByName() {
		let missing = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("nothing-here-\(UUID().uuidString)", isDirectory: true)
			.appendingPathComponent("task.md")
		do {
			_ = try BacklogItem.tick(line: 0, in: missing)
			Issue.record("a file that is not there was ticked")
		} catch let error as BacklogItem.ChecklistWriteError {
			#expect(error.file == missing)
			#expect(error.localizedDescription.contains(missing.path))
		} catch {
			Issue.record("wrong error: \(error)")
		}
	}

	/// The fraction, the steps `done` prints and the rows a tip offers are one
	/// reader now, so a box with nothing written after it is open in all three
	/// or in none. They disagreed before: `progress` counted it and
	/// `remainingSteps` dropped it.
	@Test func aBoxWithNoWordsAfterItIsStillOneOfTheOpenSteps() {
		let markdown = "- [x] Done\n- [ ]\n"
		#expect(BacklogItem.progress(in: markdown)?.summary == "1/2")
		#expect(BacklogItem.openSteps(in: markdown).count == 1)
		#expect(BacklogItem.remainingSteps(in: markdown) == [""])
	}
}
