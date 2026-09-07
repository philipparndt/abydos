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
}
