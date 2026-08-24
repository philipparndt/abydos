import Foundation

/// What has been typed in the palette is asking for.
///
/// The prefixes are VS Code's, because this is the field VS Code taught people
/// to open and they arrive already knowing what `>` does.
///
/// **In the kit rather than beside the popover, and for one reason.** Adding
/// files to the palette meant adding a fourth kind of thing to the unprefixed
/// list, and the claim worth holding on to is a negative one: that `>` and `:`
/// still mean exactly what they meant. That claim is about this decision alone —
/// no window, no popover, no project — so it is testable here and was not
/// testable where it was.
public enum PaletteScope: Equatable, Sendable {
	/// Everything at once, ranked: projects, files, branches, then actions.
	case everything(String)
	/// `>` — actions only, which is what a command palette normally is.
	case commands(String)
	/// `:` — a line in the file being edited.
	case line(Int?)

	/// What a line of typing means.
	public static func of(_ text: String) -> PaletteScope {
		let typed = text.trimmingCharacters(in: .whitespaces)
		if typed.hasPrefix(">") {
			return .commands(rest(of: typed, after: ">").lowercased())
		}
		if typed.hasPrefix(":") {
			let digits = rest(of: typed, after: ":")
			return .line(digits.isEmpty ? nil : Int(digits))
		}
		return .everything(typed.lowercased())
	}

	private static func rest(of text: String, after prefix: String) -> String {
		String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
	}

	/// The query, where there is one.
	public var query: String? {
		switch self {
		case let .everything(query), let .commands(query): return query
		case .line: return nil
		}
	}

	/// Whether files belong in this list.
	///
	/// Only the unprefixed scope, and only once there is something to match:
	/// `>` is actions and `:` is a line number, and both were already whole
	/// answers before files existed. Every file in the project under an empty
	/// query is not a list, it is the project.
	public var offersFiles: Bool {
		guard case let .everything(query) = self else { return false }
		return !query.isEmpty
	}
}
