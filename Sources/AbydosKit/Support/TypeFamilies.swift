import Foundation
import UniformTypeIdentifiers

/// Which of a list of content types stand for the others.
///
/// Launch Services resolves a type through its parents when nothing binds it
/// directly, and macOS confirms every `setDefaultApplication` with a dialog
/// of its own. Claiming sixteen kinds was sixteen dialogs — *Do you want all
/// "Source Code" documents to open with Abydos?*, then the same for scripts,
/// for shell scripts, for Markdown, one after another. Claiming the roots
/// first asks the question once for a family.
public enum TypeFamilies {
	/// The types in the list that conform to no other type in it, in the
	/// list's order.
	public static func roots(of types: [UTType]) -> [UTType] {
		types.filter { type in
			!types.contains { other in other != type && type.conforms(to: other) }
		}
	}

	/// Types an editor may be *offered* for but must never take the default
	/// of, because macOS reads that claim as a claim on something else.
	///
	/// **`public.html` is how the default browser is set.** Launch Services
	/// expresses the browser role as a content type — Safari's own claim list
	/// names `com.apple.default-app.web-browser` beside `public.html` — so an
	/// app that becomes the handler for HTML becomes the default browser, and
	/// the `http` and `https` schemes follow it. This app declares no URL
	/// scheme and does nothing with a link, so `open https://…` handed the URL
	/// to an editor that silently dropped it and exited 0. That happened on
	/// somebody's machine and took a while to explain, because nothing in the
	/// bundle mentions `http` anywhere.
	///
	/// The declaration stays: HTML is a file this editor genuinely opens, and
	/// the bundle offers it under *Open With* at `Alternate` rank, which claims
	/// nothing. Only the taking is refused.
	public static let belongToAnotherKindOfApp: Set<String> = ["public.html"]

	/// Of the types declared, the ones it is this app's business to become the
	/// default for.
	public static func claimable(_ types: [UTType]) -> [UTType] {
		types.filter { !belongToAnotherKindOfApp.contains($0.identifier) }
	}
}
