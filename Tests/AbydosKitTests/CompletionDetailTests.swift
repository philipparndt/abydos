import Foundation
import Testing
@testable import AbydosKit

/// What a server says about a completion, and what the editor is allowed to
/// conclude from a handshake.
///
/// Every dictionary here was copied from a real exchange rather than invented:
/// `openscad-lsp` and `sourcekit-lsp` were both driven over stdio from this
/// machine while the change was being written, and what they answered is in
/// the change's `design.md`.
struct CompletionDetailTests {
	/// openscad-lsp labels `cube` with its whole signature and asks to be
	/// matched on `cube`. The editor matched on the label, which for this item
	/// happens to work and for a Swift one does not.
	@Test func anItemIsMatchedByItsFilterTextRatherThanItsLabel() {
		let cube = LSPCompletion(json: [
			"label": "cube(size, center=false)",
			"filterText": "cube",
			"insertText": "cube(size = ${1:size}, center = false);$0",
			"insertTextFormat": 2,
			"kind": 9,
		])

		#expect(cube?.matchText == "cube")
		#expect(cube?.label == "cube(size, center=false)")
		#expect(cube?.isSnippet == true)
	}

	/// The Swift shape, where the label is a whole signature and its first
	/// characters are not the name of anything.
	@Test func aLabelThatIsAWholeSignatureIsNotWhatIsTypedAt() {
		let item = LSPCompletion(json: [
			"label": "withUnsafeCurrentTask(body: (UnsafeCurrentTask?) throws -> T) rethrows",
			"filterText": "withUnsafeCurrentTask(body:)",
			"detail": "T",
			"kind": 3,
		])

		#expect(item?.matchText == "withUnsafeCurrentTask(body:)")
		#expect(item?.matchText.hasPrefix("withUnsafe") == true)
	}

	@Test func anItemWithNoFilterTextIsMatchedOnItsLabel() {
		let item = LSPCompletion(json: ["label": "union"])
		#expect(item?.matchText == "union")
	}

	/// Empty is nothing, not an empty document: a panel opened for it would read
	/// as "there is nothing to know about this".
	@Test func aCompletionWithNoProseHasNoDocumentation() {
		#expect(LSPCompletion(json: ["label": "union"])?.documentation == nil)
		#expect(LSPCompletion(json: [
			"label": "cube",
			"documentation": ["kind": "markdown", "value": "a cube"],
		])?.documentation == "a cube")
	}

	// MARK: - What a handshake means

	/// sourcekit-lsp's answer, verbatim.
	private let swiftCapabilities: [String: Any] = [
		"completionProvider": ["resolveProvider": true, "triggerCharacters": [".", "("]],
		"signatureHelpProvider": [
			"triggerCharacters": ["(", "["],
			"retriggerCharacters": [",", ":"],
		],
	]

	/// openscad-lsp's, also verbatim — an empty `completionProvider` and no
	/// mention of signature help at all.
	private let openSCADCapabilities: [String: Any] = [
		"completionProvider": [:],
		"definitionProvider": true,
		"hoverProvider": true,
		"renameProvider": ["prepareProvider": true],
		"textDocumentSync": 2,
	]

	@Test func aServerThatNamesTriggerCharactersIsAskedOnThem() {
		#expect(LSPClient.completionTriggerCharacters(in: swiftCapabilities) == [".", "("])
	}

	/// The other half, and the one that keeps a `.scad` behaving exactly as it
	/// did: openscad-lsp names none, so nothing changes for it.
	@Test func aServerThatNamesNoTriggerCharactersIsAskedOnWordsOnly() {
		#expect(LSPClient.completionTriggerCharacters(in: openSCADCapabilities).isEmpty)
	}

	@Test func theCallIsAskedAboutOnOpeningAndOnEveryComma() {
		#expect(LSPClient.signatureHelpTriggerCharacters(in: swiftCapabilities) == ["(", "[", ",", ":"])
	}

	/// **The request is never sent to a server that did not claim it.** Driven
	/// anyway, openscad-lsp sends no reply of any kind — not even an error — and
	/// the client is left holding a continuation until its timeout.
	@Test func aServerWithNoSignatureHelpIsNeverAsked() {
		#expect(LSPClient.offersSignatureHelp(in: openSCADCapabilities) == false)
		#expect(LSPClient.signatureHelpTriggerCharacters(in: openSCADCapabilities).isEmpty)
		#expect(LSPClient.offersSignatureHelp(in: swiftCapabilities) == true)
	}

	// MARK: - Signature help

	/// sourcekit-lsp's answer inside `.extruded(height: height, `, as it
	/// arrived.
	private var extrudedHelp: Any {
		[
			"signatures": [[
				"label": "extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D",
				"documentation": ["value": "See ``extruded(height:topEdge:bottomEdge:)``", "kind": "markdown"],
				"activeParameter": 1,
				"parameters": [["label": [9, 23]], ["label": [25, 45]]],
			]],
		]
	}

	@Test func theParameterBeingFilledInIsTheOneTheServerPointsAt() throws {
		let help = try #require(LSPSignatureHelp(json: extrudedHelp))
		let active = try #require(help.active)

		#expect(active.signature.label == "extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D")
		let range = try #require(active.parameter?.range)
		let label = Array(active.signature.label.utf16)
		#expect(String(decoding: label[range], as: UTF16.self) == "topEdge: EdgeProfile")
	}

	/// The per-signature number wins over the reply's, which is what the
	/// protocol says and what sourcekit-lsp relies on: it sends several
	/// overloads at once, each with its own, and nothing at the top level.
	@Test func aSignatureSaysWhichOfItsOwnParametersIsActive() throws {
		let help = try #require(LSPSignatureHelp(json: [
			"activeParameter": 0,
			"signatures": [[
				"label": "f(a: Int, b: Int)",
				"activeParameter": 1,
				"parameters": [["label": [2, 8]], ["label": [10, 16]]],
			]],
		]))
		let range = try #require(help.active?.parameter?.range)
		#expect(range == 10..<16)
	}

	/// A server that names its parameters with strings rather than offsets, which
	/// the protocol still allows.
	@Test func aParameterNamedByStringIsFoundInTheLabel() throws {
		let help = try #require(LSPSignatureHelp(json: [
			"activeParameter": 1,
			"signatures": [[
				"label": "f(alpha: Int, beta: Int)",
				"parameters": [["label": "alpha: Int"], ["label": "beta: Int"]],
			]],
		]))
		let range = try #require(help.active?.parameter?.range)
		let label = Array("f(alpha: Int, beta: Int)".utf16)
		#expect(String(decoding: label[range], as: UTF16.self) == "beta: Int")
	}

	@Test func aReplyWithNoSignaturesIsNothing() {
		#expect(LSPSignatureHelp(json: ["signatures": []]) == nil)
		#expect(LSPSignatureHelp(json: NSNull()) == nil)
	}

	// MARK: - What a parameter takes, for a server with no signature help

	private func cubeDocumentation() throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: "openscad-cube-documentation", withExtension: "md", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	/// The whole point of the change, from the one server that cannot answer
	/// `signatureHelp` at all.
	@Test func theStopNamesTheParameterAndTheProseDescribesIt() throws {
		let description = try #require(
			ServerDocumentation.description(ofParameter: "size", in: try cubeDocumentation())
		)

		#expect(description.contains("single value, cube with all sides this length"))
		#expect(description.contains("3 value array [x,y,z]"))
		// And stops where the next parameter starts.
		#expect(!description.contains("1st (positive) octant"))
	}

	@Test func eachParameterGetsItsOwnDescription() throws {
		let centre = try #require(
			ServerDocumentation.description(ofParameter: "center", in: try cubeDocumentation())
		)
		#expect(centre.contains("1st (positive) octant"))
		#expect(!centre.contains("all sides this length"))
	}

	/// **The same server writes this two ways**, and a rule that reads one of
	/// them looks right until the second is tried: `cube` puts `**size**` on a
	/// line of its own, and `cylinder` writes `**h** : height of the cylinder or
	/// cone` all on one. Driven against the app, the second shape produced no
	/// hint at all until this was noticed.
	@Test func aParameterDescribedOnItsOwnLineIsFoundToo() {
		let cylinder = """
		**Parameters**

		**h**\u{a0}: height of the cylinder or cone

		**r** \u{a0}: radius of cylinder. r1 = r2 = r.

		**r1**\u{a0}: radius, bottom of cone.
		"""

		#expect(ServerDocumentation.description(ofParameter: "h", in: cylinder)
			== "height of the cylinder or cone")
		#expect(ServerDocumentation.description(ofParameter: "r", in: cylinder)
			== "radius of cylinder. r1 = r2 = r.")
	}

	/// A bold run that is not a parameter name. `**false** (default), …` is part
	/// of what `center` takes, and reading it as a new entry would leave
	/// `center` with nothing said about it at all.
	@Test func aBoldWordInProseDoesNotEndTheDescription() throws {
		let centre = try #require(
			ServerDocumentation.description(ofParameter: "center", in: try cubeDocumentation())
		)
		#expect(centre.contains("false (default)"))
		#expect(centre.contains("true, cube is centered"))
	}

	/// Exact, or nothing. A near match would put a neighbouring parameter's type
	/// under the caret, which is worse than saying nothing because it would be
	/// believed.
	@Test func aStopTheProseDoesNotDescribeGetsNoHint() throws {
		#expect(ServerDocumentation.description(ofParameter: "radius", in: try cubeDocumentation()) == nil)
		#expect(ServerDocumentation.description(ofParameter: "siz", in: try cubeDocumentation()) == nil)
		#expect(ServerDocumentation.description(ofParameter: "", in: try cubeDocumentation()) == nil)
	}
}
