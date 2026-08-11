import Foundation

/// What commenting a line out means in a language.
///
/// ## Why this is a table and not part of `LanguageDefinition`
///
/// A `LanguageDefinition` exists only where a *grammar* does, and there are 25
/// of those against far more ids than that: `extensionMap` resolves `.puml` to
/// `plantuml` and `.h` to `c` with nothing vendored for the first, and a `.go`
/// file whose query bundle failed to load still wants ⌘/. Hanging the token off
/// the definition would make the feature quietly depend on whether a grammar
/// happened to load, which is the one thing it must not depend on.
///
/// Nor can tree-sitter answer it where it *is* available. A grammar's
/// `highlights.scm` says where a comment **is**; nothing in any query says what
/// to **write**. So a table is unavoidable, and the only real decision is what
/// it is keyed on — which is the same id space `languageId(for:)` and
/// `languageId(forFenceInfo:)` produce, so that one file resolves to one answer
/// wherever the question is asked.
///
/// `CommentSyntaxTests.everyLanguageIdHasAnAnswer` walks
/// `LanguageRegistry.allLanguageIds` and fails if any of them is missing from
/// the table below, so adding an extension without deciding what ⌘/ does in it
/// is a red test rather than a keystroke that does nothing.
///
/// Block comments are deliberately absent: ⌘/ is line comments, and a separate
/// gesture for `/* */` is its own item.
public enum CommentSyntax: Equatable, Sendable {
	/// The token that turns the rest of a line into a comment.
	case line(String)
	/// The language has no line comment at all, and the sentence says so in
	/// words somebody can act on.
	///
	/// **This is not the same as doing nothing**, which is why it carries a
	/// reason rather than being an empty case: ⌘/ in a stylesheet has to say
	/// that CSS has only `/* */`, or the only thing the person learns is that
	/// the keyboard is broken.
	case unavailable(String)

	/// What ⌘/ does in a language, and what to say when it cannot.
	///
	/// An id nothing is known about — a plain-text file, a `.lock` that sniffed
	/// as nothing — is a refusal too rather than a guess: `#` in a file that
	/// turns out to be C is a syntax error somebody has to find.
	public static func forLanguage(_ languageId: String?) -> CommentSyntax {
		guard let languageId else {
			return .unavailable(
				"Abydos does not know what language this file is, so it cannot comment lines out."
			)
		}
		if let known = byLanguage[languageId] { return known }
		let name = LanguageRegistry.shared.displayName(for: languageId)
		return .unavailable("Abydos does not know how to comment a line out in \(name).")
	}

	/// Every language id this editor can resolve, and what a line comment is in
	/// it. Total on purpose — see the note on the type.
	static let byLanguage: [String: CommentSyntax] = [
		// The C family and everything that took its comment from it.
		"swift": .line("//"),
		"rust": .line("//"),
		"c": .line("//"),
		"cpp": .line("//"),
		"objc": .line("//"),
		"java": .line("//"),
		"kotlin": .line("//"),
		"groovy": .line("//"),
		"go": .line("//"),
		"javascript": .line("//"),
		"typescript": .line("//"),
		"tsx": .line("//"),
		"jsx": .line("//"),
		"zig": .line("//"),
		"odin": .line("//"),
		// OpenSCAD's language is C-shaped even though its output is a solid.
		"openscad": .line("//"),

		// The hash family. `make` is here and it matters that it is: a recipe
		// line begins with a tab and `#` still comments it, which is the case
		// the shallowest-common-indent rule was written for.
		"python": .line("#"),
		"bash": .line("#"),
		"yaml": .line("#"),
		"toml": .line("#"),
		"make": .line("#"),

		// PlantUML's line comment is an apostrophe; its block comment is
		// `/' … '/`, which is not this gesture.
		"plantuml": .line("'"),

		// ── The refusals, and why each one is a refusal ──────────────────────
		//
		// The item that asked for this named CSS and JSON as "the two here".
		// There are five: HTML, XML-through-HTML, Markdown and Svelte have no
		// line comment either, and finding that out is most of what deciding
		// this table consisted of.
		//
		// The shared argument: `/* */` and `<!-- -->` do not nest, so a line
		// already carrying one comes back mangled and unparseable rather than
		// merely uncommented. Wrapping each line in its own pair *would*
		// round-trip most of the time, and "most of the time" is not a property
		// an editing command may have — a mangling is worse than a refusal, and
		// the refusal is said out loud, which is what keeps it from being the
		// third and worst option of doing nothing quietly.
		"css": .unavailable(
			"CSS has no line comment — only /* … */, which cannot be nested."
		),
		// `.jsonc` and `.json5` collapse onto this same id, and comments are
		// legal in both. The strict answer wins anyway: the id also covers every
		// `package.json` and `Package.resolved`, where a `//` makes the file
		// unreadable to everything that parses it, and an editor that breaks a
		// manifest on one keystroke is worse than one that says JSON has no
		// comments.
		"json": .unavailable(
			"JSON has no comments, so there is nothing to comment these lines out with."
		),
		"html": .unavailable(
			"HTML has no line comment — only <!-- … -->, which cannot be nested."
		),
		// Markdown's only comment is an HTML one, and the inline grammar is the
		// same language seen through a second parser.
		"markdown": .unavailable(
			"Markdown has no line comment — only <!-- … -->, which cannot be nested."
		),
		"markdown_inline": .unavailable(
			"Markdown has no line comment — only <!-- … -->, which cannot be nested."
		),
		// A `.svelte` file is markup at the top level, and the `//` somebody
		// wants is the one inside its `<script>`. Answering `//` for the whole
		// file would put it in the middle of the markup; answering per region
		// needs a range-to-language map this editor does not have yet, and that
		// is the injected-language boundary rather than a decision about Svelte.
		"svelte": .unavailable(
			"A Svelte file is markup outside its <script> and <style>, and Abydos "
				+ "cannot yet tell which of the three a line is in."
		),
	]
}
