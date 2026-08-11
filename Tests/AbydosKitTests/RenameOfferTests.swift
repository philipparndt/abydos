import Foundation
import Testing
@testable import AbydosKit

/// The sentences a rename says when it does not happen.
///
/// All of them live on `RenameOffer`, `RenameSubject` and `RenameAnswer` rather
/// than at the window that shows them, which is what lets a test read them
/// without one. 0453 wrote the first two and nothing tested them; 0469 found
/// that out while adding the third.
struct RenameOfferTests {
	private let anywhere = LSPRange(
		start: LSPPosition(line: 0, character: 0),
		end: LSPPosition(line: 0, character: 8)
	)

	// MARK: - Before the field opens

	@Test func aServerThatDoesNotRenameIsNamed() {
		#expect(RenameOffer.serverCannot(server: "kotlin-language-server").refusal
			== "kotlin-language-server does not rename.")
	}

	/// Two of the four say nothing, and which two is the whole design: no
	/// server is most files in most projects, and a server's own "nothing
	/// here" is what the caret on a bracket looks like every time.
	@Test func theTwoSilentRefusalsSayNothing() {
		#expect(RenameOffer.noServer.refusal == nil)
		#expect(RenameOffer.notHere.refusal == nil)
		#expect(RenameOffer.offered(RenameSubject(name: "Greeting", range: anywhere)).refusal == nil)
	}

	// MARK: - The caveat under the field

	@Test func aSyntacticServersRenameSaysSoAndNamesTheSymbol() {
		let subject = RenameSubject(name: "Greeting", range: anywhere, isSyntactic: true)
		let caveat = try? #require(subject.caveat)
		#expect(caveat?.contains("matches names rather than types") == true)
		#expect(caveat?.contains("Greeting") == true)
	}

	@Test func aServerThatReadsTypesHasNothingToWarnAbout() {
		#expect(RenameSubject(name: "Greeting", range: anywhere).caveat == nil)
	}

	/// The one server in the table that reads text rather than types. If a
	/// second one is added this test is where it is noticed.
	@Test func kmpLspIsTheSyntacticServerAndJdtlsIsNot() {
		let syntactic = LanguageServers.known.filter(\.isSyntactic).map(\.name)
		#expect(syntactic == ["kmp-lsp"])
	}

	// MARK: - After the name is typed

	/// 0469: kmp-lsp advertised rename, answered `prepareRename` with a range,
	/// and then answered the rename itself with `null`. "Nothing to change" is
	/// also what a caret on a comma means, and by this point the caret was not
	/// on one — so the server's name is the whole of what there is to say.
	@Test func aServerThatDeclinesAfterOfferingIsNamed() {
		let answer = RenameAnswer.nothingToChange(server: "kmp-lsp")
		let refusal = try? #require(answer.refusal)
		#expect(refusal?.title == "Nothing was renamed")
		#expect(refusal?.detail == "kmp-lsp offered this rename and then found nothing to change.")
		// Information, not an error: nothing changed and nothing is wrong.
		#expect(refusal?.isFailure == false)
		#expect(answer.edit == nil)
	}

	@Test func aServersOwnWordsAreWhatAFailureSays() {
		let answer = RenameAnswer.failed(
			LSPClient.ClientError.failed(code: -32600, message: "identity is ambiguous")
		)
		let refusal = try? #require(answer.refusal)
		#expect(refusal?.detail.contains("identity is ambiguous") == true)
		#expect(refusal?.isFailure == true)
	}

	/// An edit says nothing at all. The files changing on screen is the whole
	/// of what was asked for.
	@Test func anEditIsSilent() {
		let edit = WorkspaceEdit(json: [
			"changes": ["file:///a.java": [[
				"range": [
					"start": ["line": 0, "character": 0],
					"end": ["line": 0, "character": 8],
				],
				"newText": "Salutation",
			]]],
		])
		let answer = RenameAnswer.edit(try! #require(edit))
		#expect(answer.refusal == nil)
		#expect(answer.edit?.changes.count == 1)
	}
}
