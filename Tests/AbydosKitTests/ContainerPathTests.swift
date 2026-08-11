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

	// MARK: - A workspace edit crossing

	/// **The message this rewriting was built for and had never carried.**
	///
	/// `spec/tool-images.md` has required since the containers were built that
	/// URIs cross "for the ones that are values and for the ones that are keys,
	/// so that a workspace edit's map of changes crosses too" — written for a
	/// message this program did not send until 0453. A `changes` map is the only
	/// place in the whole protocol where a URI is a dictionary *key*, so a walk
	/// that looked at values only would bring every edit home and leave the file
	/// each one belongs to on the container's side: the edits would be applied
	/// to `/workspace/…`, which is a path this machine does not have.
	///
	/// Driven rather than assumed, because nothing had ever driven it.
	@Test func aWorkspaceEditsMapOfChangesCrossesByItsKeys() {
		let reply: [String: Any] = [
			"jsonrpc": "2.0",
			"id": 7,
			"result": [
				"changes": [
					"file:///workspace/src/main.go": [[
						"range": [
							"start": ["line": 4, "character": 5],
							"end": ["line": 4, "character": 13],
						],
						"newText": "greeting",
					]],
					"file:///workspace/src/other.go": [],
				],
			],
		]

		let home = paths.hostSide(of: reply)
		let edit = WorkspaceEdit(json: (home["result"] as? [String: Any]))

		#expect(edit?.changes.map(\.uri) == [
			"file:///Users/me/project/src/main.go",
			"file:///Users/me/project/src/other.go",
		])
		// And the file each one names is a file on this machine.
		#expect(WorkspaceEditPlan.fileURL(edit?.changes.first?.uri ?? "")?.path
			== "/Users/me/project/src/main.go")
	}

	/// The same for `documentChanges`, where the URI is a value inside a nested
	/// object and a file operation names two of them.
	@Test func documentChangesAndAFileThatMovesCrossToo() {
		let reply: [String: Any] = [
			"result": [
				"documentChanges": [
					[
						"textDocument": ["uri": "file:///workspace/src/Foo.java", "version": 2],
						"edits": [[
							"range": [
								"start": ["line": 0, "character": 6],
								"end": ["line": 0, "character": 9],
							],
							"newText": "Bar",
						]],
					],
					[
						"kind": "rename",
						"oldUri": "file:///workspace/src/Foo.java",
						"newUri": "file:///workspace/src/Bar.java",
					],
				],
			],
		]

		let edit = WorkspaceEdit(json: paths.hostSide(of: reply)["result"] as? [String: Any])
		#expect(edit?.changes.last == .rename(
			from: "file:///Users/me/project/src/Foo.java",
			to: "file:///Users/me/project/src/Bar.java",
			overwrite: false, ignoreIfExists: false
		))
	}

	/// And the way out. A rename is asked at a URI, and a server that was given
	/// this machine's name for the file would answer about no such document.
	@Test func theQuestionGoesOutUnderTheContainersName() {
		let request: [String: Any] = [
			"method": "textDocument/rename",
			"params": [
				"textDocument": ["uri": "file:///Users/me/project/src/main.go"],
				"position": ["line": 4, "character": 5],
				"newName": "greeting",
			],
		]

		let outgoing = paths.containerSide(of: request)
		let document = (outgoing["params"] as? [String: Any])?["textDocument"] as? [String: Any]
		#expect(document?["uri"] as? String == "file:///workspace/src/main.go")
	}
}
