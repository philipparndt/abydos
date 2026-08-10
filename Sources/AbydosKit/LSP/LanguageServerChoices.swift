import Foundation

/// Which language server a language uses, where there is more than one to have.
///
/// This is a different question from `ToolImages`, which says where a tool comes
/// from — installed here, a published image, one built here. Both are answered
/// in `.abydos/tools.json` and both let one person's settings stand behind the
/// project's file, but they are kept apart in the file as well as in the code:
///
///     {
///       "languages": { "java": "kmp-lsp" },
///       "kmp-lsp":   "pharndt/abydos-kmp-lsp:dev"
///     }
///
/// The section rather than a bare `"java": "kmp-lsp"` at the top level, for two
/// reasons. The keys of that top level are tool names and the keys in here are
/// language ids, and `plantuml` is already both — a renderer that comes from an
/// image and a language a server answers for — so one flat map would have a key
/// whose meaning depends on which reader got to it first. And the two questions
/// stay two questions on the face of the file: which server, and where it comes
/// from.
public struct LanguageServerChoices: Equatable, Sendable {
	/// Where a choice came from.
	///
	/// Carried rather than worked out again at the point of complaint, because
	/// half of what somebody needs when a choice turns out to be wrong is which
	/// of the two files to go and edit.
	public enum Source: String, Equatable, Sendable {
		/// Nobody chose. This is the server this app has for the language, and
		/// where it has several, the first of them.
		case builtIn
		/// One person's answer, for every project they open.
		case settings
		/// The project's own answer, checked in beside it.
		case project

		/// Where to go and change it, said as somebody would look for it.
		public var origin: String {
			switch self {
			case .builtIn: return "Abydos's own default"
			case .settings: return "Settings ▸ Tools ▸ Language servers"
			case .project: return ".abydos/tools.json"
			}
		}
	}

	/// A server a language was pointed at, and who pointed it.
	public struct Choice: Equatable, Sendable {
		/// The server's name — `jdtls`, not `/opt/homebrew/bin/jdtls`.
		public let name: String
		public let source: Source

		public init(name: String, source: Source) {
			self.name = name
			self.source = source
		}
	}

	/// Language id to the server chosen for it.
	public let byLanguage: [String: Choice]

	public init(byLanguage: [String: Choice] = [:]) {
		self.byLanguage = byLanguage
	}

	/// Nobody has said anything, which is what most projects say.
	public static let none = LanguageServerChoices()

	public func chosen(forLanguage languageId: String) -> Choice? { byLanguage[languageId] }

	public var isEmpty: Bool { byLanguage.isEmpty }

	/// The object in `.abydos/tools.json` this lives under.
	public static let section = "languages"

	/// What a project asks for, or nothing when it asks for nothing.
	///
	/// A file that cannot be read is the same as no file, as it is for images:
	/// a broken one should not stop the project opening.
	public static func inProject(_ root: URL) -> LanguageServerChoices {
		guard let data = try? Data(contentsOf: ToolImages.url(in: root)) else {
			return LanguageServerChoices()
		}
		return parse(data, source: .project)
	}

	/// Reads the `languages` object out of the same file the images come from.
	///
	///     { "languages": { "java": "kmp-lsp", "typescript": "…" } }
	///
	/// Only strings. A table — the shape images grew for when a tool wants more
	/// said about it than one name — would be a second way to say the only
	/// thing there is to say here, and nothing reads it.
	public static func parse(_ data: Data, source: Source) -> LanguageServerChoices {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let languages = root[section] as? [String: Any]
		else { return LanguageServerChoices() }

		var found: [String: Choice] = [:]
		for (languageId, value) in languages {
			guard let name = value as? String, !name.isEmpty else { continue }
			found[languageId] = Choice(name: name, source: source)
		}
		return LanguageServerChoices(byLanguage: found)
	}

	/// Settings say it for one person across every project.
	public static func settings(_ byLanguage: [String: String]) -> LanguageServerChoices {
		LanguageServerChoices(byLanguage: byLanguage.compactMapValues {
			$0.isEmpty ? nil : Choice(name: $0, source: .settings)
		})
	}

	/// The project's answers over the ones set for everything.
	///
	/// The same rule 0424 settled for a diagram's theme and `ToolImages` follows
	/// for images: **the file wins and the setting is the default.** A checked-in
	/// answer is a statement about the project — this code is understood by that
	/// server — and a personal preference that quietly overrode it would mean
	/// two people on one repository being answered by two different programs
	/// without either of them having asked for that.
	public static func resolve(
		project: LanguageServerChoices, settings: LanguageServerChoices
	) -> LanguageServerChoices {
		LanguageServerChoices(
			byLanguage: settings.byLanguage.merging(project.byLanguage) { _, fromProject in
				fromProject
			}
		)
	}
}
