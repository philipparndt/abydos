import Foundation
import Testing
@testable import AbydosKit

/// Which kinds of file a project is made of, for the shortcut past typing an
/// extension.
struct NewFileKindTests {
	@Test func offersWhatTheProjectIsMostlyMadeOf() {
		let kinds = NewFileKinds.choose(from: [
			"Sources/App/Main.swift", "Sources/App/View.swift", "Sources/App/Model.swift",
			"README.md", "docs/guide.md",
			"Package.swift",
		])
		#expect(kinds.map(\.name) == ["swift", "md"])
		#expect(kinds.first?.count == 4)
	}

	/// The example from the task: a directory of models offers what somebody
	/// writes there, not what the slicer wrote back.
	@Test func outputIsNotSomethingToCreate() {
		let kinds = NewFileKinds.choose(from: [
			"kamado.scad", "lid.scad",
			"out/kamado.stl", "out/lid.stl", "out/kamado.3mf", "out/lid.3mf", "out/plate.3mf",
			"README.md",
		])
		#expect(kinds.map(\.name) == ["scad", "md"])
	}

	/// A picture is an asset, and a new empty one is nothing. An SVG is a
	/// drawing written down, which is a reasonable thing to start.
	@Test func picturesAreDroppedExceptTheOneThatIsText() {
		let kinds = NewFileKinds.choose(from: [
			"a.png", "b.png", "c.png", "d.jpg", "e.gif",
			"icon.svg", "notes.md",
		])
		#expect(!kinds.map(\.name).contains("png"))
		#expect(kinds.map(\.name).sorted() == ["md", "svg"])
	}

	/// Lock files are text, are often among the biggest things in a project,
	/// and are never written by hand.
	@Test func whatIsGeneratedIsNotOffered() {
		let kinds = NewFileKinds.choose(from: [
			"package-lock.json", "yarn.lock", "Cargo.lock", "go.sum",
			"Package.resolved", "bundle.min.js", "app/main.ts", "app/view.ts",
		])
		#expect(kinds.map(\.name) == ["ts"])
	}

	/// The editor knowing a kind decides ties and nothing else: as a filter it
	/// would drop `.txt` and `.sql`, which are fine things to make.
	@Test func anUnknownKindIsStillOfferedWhenTheProjectUsesIt() {
		let kinds = NewFileKinds.choose(from: [
			"notes.txt", "more.txt", "third.txt", "schema.sql", "one.swift",
		])
		#expect(kinds.map(\.name).first == "txt")
		#expect(kinds.map(\.name).contains("sql"))
	}

	/// A dotfile is a whole name rather than a kind. `.env` is not "a file with
	/// the env extension" — there is nothing to put in front of it — and the
	/// shortcut only knows how to add an extension to what somebody types.
	@Test func aDotfileIsNotAKind() {
		let kinds = NewFileKinds.choose(from: [".env", ".gitignore", ".env.local", "a.swift"])
		#expect(kinds.map(\.name) == ["swift"])
	}

	@Test func neverMoreThanFive() {
		let paths = ["a.swift", "b.md", "c.json", "d.yml", "e.sh", "f.py", "g.rb"]
		#expect(NewFileKinds.choose(from: paths).count == 5)
	}

	/// An empty project offers nothing rather than a guess: a `.js` in a project
	/// with no JavaScript invites a file that does not belong.
	@Test func anEmptyProjectOffersNothing() {
		#expect(NewFileKinds.choose(from: []).isEmpty)
		#expect(NewFileKinds.choose(from: ["Makefile", "LICENSE"]).isEmpty)
	}

	/// The same list twice, whatever order the walk happened to be in.
	@Test func theOrderIsStableWhenCountsTie() {
		let first = NewFileKinds.choose(from: ["a.rb", "b.py", "c.sh"])
		let second = NewFileKinds.choose(from: ["c.sh", "b.py", "a.rb"])
		#expect(first.map(\.name) == second.map(\.name))
	}

	@Test func namesTheLanguageWhereItKnowsOne() {
		#expect(NewFileKinds.title(for: "swift") == "Swift (.swift)")
		#expect(NewFileKinds.title(for: "zzz") == ".zzz")
	}

	// MARK: - Against a directory

	/// The same rule over a real project, through the walker the search uses.
	///
	/// Worth having as well as the rules above: what reaches `choose` is
	/// whatever that walker decided to hand it, and a project's build output is
	/// exactly what it prunes.
	@Test func countsWhatIsActuallyInADirectory() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		for path in [
			"Sources/App/main.swift", "Sources/App/view.swift", "Sources/App/model.swift",
			"README.md", "docs/notes.md",
			"assets/logo.png",
			".git/config",
		] {
			try JavaTestDirectory.write("x", to: root.appendingPathComponent(path))
		}

		let kinds = NewFileKinds.inProject(root)
		#expect(kinds.map(\.name) == ["swift", "md"])
		#expect(kinds.first?.title == "Swift (.swift)")
		// Not the picture, and not anything from inside `.git`.
		#expect(!kinds.map(\.name).contains("png"))
		#expect(!kinds.map(\.name).contains("config"))
	}

	// MARK: - Naming the new file

	@Test func theExtensionIsAddedUnlessItIsAlreadyThere() {
		let kind = NewFileKind(name: "ts", count: 3, title: "TypeScript (.ts)")
		#expect(NewFileKinds.name("thing", endingIn: kind) == "thing.ts")
		#expect(NewFileKinds.name("thing.ts", endingIn: kind) == "thing.ts")
		// Typed in another case, and still not doubled.
		#expect(NewFileKinds.name("Thing.TS", endingIn: kind) == "Thing.TS")
		// A path is a name too: intermediate folders already work.
		#expect(NewFileKinds.name("src/new/thing", endingIn: kind) == "src/new/thing.ts")
		#expect(NewFileKinds.name("  ", endingIn: kind).isEmpty)
	}
}
