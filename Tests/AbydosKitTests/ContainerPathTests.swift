import Foundation
import Testing
@testable import AbydosKit

/// Translating between the paths a container sees and the ones this side has.
///
/// The part worth getting exactly right: a mapping that is subtly wrong does
/// not fail, it opens the wrong file or reports a problem against nothing, and
/// both look like the language server being unreliable.
struct ContainerPathTests {
	private let paths = ContainerPaths(host: "/Users/me/project")

	@Test func aFileInsideTheProjectCrossesBothWays() {
		#expect(paths.toContainer(path: "/Users/me/project/src/main.go")
			== "/workspace/src/main.go")
		#expect(paths.toHost(path: "/workspace/src/main.go")
			== "/Users/me/project/src/main.go")
	}

	/// The project root itself, which is what a server is told to open.
	@Test func theRootItselfCrosses() {
		#expect(paths.toContainer(path: "/Users/me/project") == "/workspace")
		#expect(paths.toHost(path: "/workspace") == "/Users/me/project")
	}

	/// Outside the project there is nothing to map to. Inventing a path inside
	/// would point the server at the wrong file rather than at none.
	@Test func anythingOutsideIsRefused() {
		#expect(paths.toContainer(path: "/Users/me/elsewhere/x.go") == nil)
		#expect(paths.toContainer(path: "/etc/passwd") == nil)
		#expect(paths.toHost(path: "/usr/lib/go/src/fmt/print.go") == nil)
	}

	/// A sibling whose name merely starts the same way is outside it. This is
	/// the prefix bug every path mapping has once.
	@Test func aSiblingWithTheSameBeginningIsOutside() {
		#expect(paths.toContainer(path: "/Users/me/project-notes/x.go") == nil)
		let deeper = ContainerPaths(host: "/Users/me/project", container: "/work")
		#expect(deeper.toHost(path: "/workspace/x.go") == nil)
		#expect(deeper.toHost(path: "/work/x.go") == "/Users/me/project/x.go")
	}

	/// A trailing slash on either side is the same mapping, not a different one.
	@Test func trailingSlashesAreNotPartOfTheAnswer() {
		let slashed = ContainerPaths(host: "/Users/me/project/", container: "/workspace/")
		#expect(slashed.toContainer(path: "/Users/me/project/a.go") == "/workspace/a.go")
		#expect(slashed.toHost(path: "/workspace/a.go") == "/Users/me/project/a.go")
	}

	// MARK: - URIs

	@Test func fileURIsCrossToo() {
		#expect(paths.toContainer(uri: "file:///Users/me/project/src/main.go")
			== "file:///workspace/src/main.go")
		#expect(paths.toHost(uri: "file:///workspace/src/main.go")
			== "file:///Users/me/project/src/main.go")
	}

	/// A space in a directory name must not end the URI.
	@Test func aSpaceSurvivesTheRoundTrip() {
		let spaced = ContainerPaths(host: "/Users/me/my project")
		let uri = spaced.toContainer(uri: "file:///Users/me/my%20project/a%20file.go")
		#expect(uri == "file:///workspace/a%20file.go")
		#expect(spaced.toHost(uri: "file:///workspace/a%20file.go")
			== "file:///Users/me/my%20project/a%20file.go")
	}

	/// Schemes that name something with no path on either side are left alone.
	@Test func onlyFileURIsAreRewritten() {
		#expect(paths.toContainer(uri: "untitled:Untitled-1") == nil)
		#expect(paths.toContainer(uri: "jdt://contents/rt.jar/java.lang/String.class") == nil)
		#expect(paths.toHost(uri: "not a uri at all") == nil)
	}

	/// The mount it implies is the project, writable — a language server writes
	/// nothing but a formatter does, and one rule is fewer to get wrong.
	@Test func theMountIsTheProject() {
		#expect(paths.mount == ContainerMount(
			host: "/Users/me/project", container: "/workspace", isReadOnly: false
		))
	}
}
