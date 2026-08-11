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
}
