import Foundation
import Testing
@testable import AbydosKit

/// Where a file stands for git: which repository owns it, and what that
/// repository calls it. The compare verbs ask this of a URL, and used to ask
/// the superproject about a file it holds only as a gitlink.
struct GitEstatePlaceTests {
	@Test func aFileInASubmoduleIsPlacedInThatSubmodule() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "place")
		defer { estate.remove() }
		let read = await GitEstate.read(from: estate.root)

		let inside = read.place(of: estate.root.appendingPathComponent("svc-1/src/Main.java"))
		#expect(inside?.root.standardizedFileURL.path
			== estate.root.appendingPathComponent("svc-1").standardizedFileURL.path)
		#expect(inside?.path == "src/Main.java")
		#expect(inside?.estatePath == "svc-1/src/Main.java")

		// A file of the superproject's own is the superproject's, under the
		// same name either way.
		let own = read.place(of: estate.root.appendingPathComponent("README.md"))
		#expect(own?.root.standardizedFileURL.path == estate.root.standardizedFileURL.path)
		#expect(own?.path == "README.md")
		#expect(own?.estatePath == "README.md")

		// Outside the estate there is nothing to compare against.
		#expect(read.place(of: URL(fileURLWithPath: "/somewhere/else/README.md")) == nil)
	}

	/// `/tmp` and `/private/tmp` are one place: a URL under either name finds
	/// its repository.
	@Test func aPathThroughASymlinkIsStillInside() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "placelink")
		defer { estate.remove() }
		let read = await GitEstate.read(from: estate.root)

		let resolved = estate.root.resolvingSymlinksInPath()
		let place = read.place(of: resolved.appendingPathComponent("svc-1/src/Main.java"))
		#expect(place?.path == "src/Main.java")
		#expect(place?.estatePath == "svc-1/src/Main.java")
	}

	/// The estate before its first read has no root, and must place nothing
	/// rather than place everything at `/`.
	@Test func anUnreadEstatePlacesNothing() {
		let unread = GitEstate(root: URL(fileURLWithPath: "/"))
		#expect(unread.place(of: URL(fileURLWithPath: "/Users/me/dev/thing/README.md")) == nil)
	}

	/// **The mechanism the compare verbs fell to.** The superproject answers a
	/// diff for a file inside a submodule with nothing and exit 0 — it tracks
	/// the gitlink, not the file — while the submodule has the hunk.
	@Test func theSuperprojectAnswersNothingForAFileInsideASubmodule() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "placediff")
		defer { estate.remove() }
		try estate.dirty("svc-1")
		let read = await GitEstate.read(from: estate.root)
		let file = estate.root.appendingPathComponent("svc-1/src/Main.java")

		let asked = await GitWorkingCopy.diffAgainstHead(for: "svc-1/src/Main.java", in: estate.root)
		#expect(asked?.isEmpty ?? true, "the superproject knows no file inside a gitlink")

		let place = try #require(read.place(of: file))
		let answer = await GitWorkingCopy.diffAgainstHead(for: place.path, in: place.root)
		#expect(answer?.contains("-one") == true)
		#expect(answer?.contains("+changed") == true)
	}
}
