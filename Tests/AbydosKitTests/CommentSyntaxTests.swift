import Foundation
import Testing
@testable import AbydosKit

/// The table that says what commenting a line out means, and the one test that
/// makes it a table worth having rather than a list somebody remembered to add
/// to.
struct CommentSyntaxTests {
	/// **This is the point of the whole file.** The table is keyed on the same id
	/// space `languageId(for:)` and `languageId(forFenceInfo:)` produce, so a new
	/// extension added to `LanguageRegistry` without deciding what ⌘/ does in it
	/// fails here rather than reaching somebody's keyboard as a key that does
	/// nothing.
	@Test func everyLanguageIdHasAnAnswer() {
		for id in LanguageRegistry.shared.allLanguageIds {
			#expect(
				CommentSyntax.byLanguage[id] != nil,
				"“\(id)” has no line-comment decision in CommentSyntax.byLanguage"
			)
		}
	}

	/// Wider than the 25 grammars, which is the reason the token does not live on
	/// `LanguageDefinition`: `plantuml` has no grammar at all and still wants ⌘/.
	@Test func theIdSpaceIsWiderThanTheGrammars() {
		let ids = LanguageRegistry.shared.allLanguageIds
		#expect(ids.contains("plantuml"))
		#expect(ids.contains("markdown_inline"))
		#expect(ids.contains("objc"))
		#expect(LanguageRegistry.shared.configuration(for: "plantuml") == nil)
	}

	@Test func theCFamilyUsesTwoSlashes() {
		#expect(CommentSyntax.forLanguage("swift") == .line("//"))
		#expect(CommentSyntax.forLanguage("kotlin") == .line("//"))
		#expect(CommentSyntax.forLanguage("zig") == .line("//"))
	}

	@Test func theHashFamilyUsesAHash() {
		#expect(CommentSyntax.forLanguage("python") == .line("#"))
		#expect(CommentSyntax.forLanguage("yaml") == .line("#"))
		#expect(CommentSyntax.forLanguage("make") == .line("#"))
		#expect(CommentSyntax.forLanguage("toml") == .line("#"))
	}

	/// The five refusals, each with a sentence rather than a shrug. CSS and JSON
	/// were the two the item named; HTML, Markdown and Svelte turned out to be in
	/// the same position.
	@Test func theLanguagesWithNoLineCommentRefuseWithAReason() {
		for id in ["css", "json", "html", "markdown", "markdown_inline", "svelte"] {
			guard case let .unavailable(reason) = CommentSyntax.forLanguage(id) else {
				Issue.record("“\(id)” should have no line comment")
				continue
			}
			#expect(!reason.isEmpty)
			#expect(reason.hasSuffix("."))
		}
	}

	/// An id nothing is known about is a refusal and not a guess. `#` in a file
	/// that turns out to be C is a syntax error somebody then has to find.
	@Test func anUnknownLanguageRefusesRatherThanGuessing() {
		guard case let .unavailable(reason) = CommentSyntax.forLanguage("cobol") else {
			Issue.record("an id with no entry should refuse")
			return
		}
		#expect(reason.contains("cobol"))
	}

	@Test func aFileWithNoLanguageAtAllRefusesToo() {
		guard case let .unavailable(reason) = CommentSyntax.forLanguage(nil) else {
			Issue.record("no language should refuse")
			return
		}
		#expect(reason.contains("does not know what language"))
	}

	/// The same file has to resolve to the same answer however it was recognised
	/// — by extension, by name, or after a fence's alias — which is what keying
	/// the table on the registry's ids buys.
	@Test func aFileResolvesToOneAnswerWhicheverRoadItCameBy() {
		let registry = LanguageRegistry.shared
		let makefile = registry.languageId(for: URL(fileURLWithPath: "/p/Makefile"))
		let mk = registry.languageId(for: URL(fileURLWithPath: "/p/rules.mk"))
		#expect(CommentSyntax.forLanguage(makefile) == .line("#"))
		#expect(CommentSyntax.forLanguage(mk) == .line("#"))

		// `yml` is a fence alias and `.yaml` an extension; both are `yaml`.
		#expect(CommentSyntax.forLanguage(registry.languageId(forFenceInfo: "yml")) == .line("#"))
		#expect(
			CommentSyntax.forLanguage(registry.languageId(for: URL(fileURLWithPath: "/p/a.yaml")))
				== .line("#")
		)

		// A `.jsonc` file is JSON's id, and that is why the id refuses even
		// though JSONC allows comments — see the note in the table.
		guard case .unavailable = CommentSyntax.forLanguage(
			registry.languageId(for: URL(fileURLWithPath: "/p/tsconfig.jsonc"))
		) else {
			Issue.record("a .jsonc file lands on the json id, which refuses")
			return
		}
	}
}
