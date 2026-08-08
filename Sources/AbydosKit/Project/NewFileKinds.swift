import Foundation

/// A kind of file this project is made of, offered as a shortcut when making
/// another one.
public struct NewFileKind: Equatable, Sendable {
	/// Without the dot, lowercased: `swift`, `ts`.
	public let name: String
    /// How many files of this kind the project has, which is why it is here.
	public let count: Int
	/// What to call it in a menu: `Swift (.swift)`, or `.env` where the editor
	/// knows no language for it.
	public let title: String

	public init(name: String, count: Int, title: String) {
		self.name = name
		self.count = count
		self.title = title
	}

	/// The suffix a name has to end in.
	public var suffix: String { "." + name }
}

/// Which kinds of file a project is made of.
///
/// The point is a shortcut past the extension: in a project where nearly every
/// new file is one of two or three kinds, typing `.swift` again and again is
/// the same few characters every time, and getting them wrong is how a file
/// ends up unhighlighted and unrecognised.
///
/// Counted from the project rather than listed in the source, because a list
/// in the source is a list of what somebody expected. Opening a directory of
/// OpenSCAD models should offer `.scad`, and this project should offer
/// `.swift` — neither of which anybody has to have written down.
public enum NewFileKinds {
	/// How many are offered. Long enough to cover what a project is made of,
	/// short enough to read without looking.
	public static let limit = 5

	/// Files that exist but are never made by hand.
	///
	/// Written down rather than inferred: a lock file is ordinary text the
	/// editor is happy to open, it is often among the largest files in a
	/// project, and offering to create another one is offering to break the
	/// build. The list is short and stays short.
	static let neverByHand: Set<String> = [
		"lock", "sum", "log", "map", "tsbuildinfo", "pyc", "class", "o", "a",
		"resolved", "xcuserstate", "pbxuser", "mode1v3",
	]

	/// Whole names, for the ones whose extension is otherwise fine.
	static let generatedNames: Set<String> = [
		"package-lock.json", "yarn.lock", "pnpm-lock.yaml", "composer.lock",
		"cargo.lock", "gemfile.lock", "podfile.lock", "package.resolved",
		"go.sum", ".ds_store",
	]

	/// The kinds worth offering, most of them first.
	///
	/// - Parameter paths: every file in the project, as paths or names. Passed
	///   in rather than walked here so the rule can be tested without a
	///   directory to walk.
	public static func choose(from paths: [String], limit: Int = limit) -> [NewFileKind] {
		var counts: [String: Int] = [:]
		for path in paths {
			let name = (path as NSString).lastPathComponent.lowercased()
			guard !generatedNames.contains(name) else { continue }
			// A dotfile is a whole name rather than a kind: there is nothing to
			// put in front of `.env`, and `.env.local` is not "a local file".
			guard !name.hasPrefix(".") else { continue }
			// A minified bundle is generated, and its extension is the same one
			// somebody writes by hand.
			guard !name.hasSuffix(".min.js"), !name.hasSuffix(".min.css") else { continue }

			let suffix = (name as NSString).pathExtension
			guard !suffix.isEmpty, !neverByHand.contains(suffix) else { continue }
			// Anything that is not text is not something to create empty: a
			// mesh or a photograph is output or an asset, never a new file
			// somebody is about to write in.
			let url = URL(fileURLWithPath: name)
			guard FilePreview.hasReadableSource(url) else { continue }
			if FilePreview.kind(for: url) == .image, suffix != "svg" { continue }

			counts[suffix, default: 0] += 1
		}

		// Most files first. Ties are settled by whether the editor knows the
		// kind at all, and then alphabetically so the menu is the same twice
		// running — `LanguageRegistry` is a tiebreak and not a filter, because
		// as a filter it would drop `.txt` and `.env`, which are perfectly
		// reasonable things to make.
		return counts
			.map { (name: $0.key, count: $0.value) }
			.sorted {
				if $0.count != $1.count { return $0.count > $1.count }
				let known = (isKnown($0.name), isKnown($1.name))
				if known.0 != known.1 { return known.0 }
				return $0.name < $1.name
			}
			.prefix(limit)
			.map { NewFileKind(name: $0.name, count: $0.count, title: title(for: $0.name)) }
	}

	/// The kinds a project on disk is made of.
	///
	/// Walked with the search's own walker, which already prunes `.git` and
	/// whatever the settings exclude. A second walker would disagree with the
	/// first the day somebody adds `target/` to that list.
	public static func inProject(_ root: URL, limit: Int = limit) -> [NewFileKind] {
		let files = ProjectSearch(root: root).collectFiles()
		return choose(from: files.map(\.path), limit: limit)
	}

	/// What to call one in a menu.
	public static func title(for suffix: String) -> String {
		guard let language = LanguageRegistry.shared.languageId(
			for: URL(fileURLWithPath: "a.\(suffix)")
		) else { return ".\(suffix)" }
		let name = LanguageRegistry.shared.displayName(for: language)
		return name.isEmpty ? ".\(suffix)" : "\(name) (.\(suffix))"
	}

	private static func isKnown(_ suffix: String) -> Bool {
		LanguageRegistry.shared.languageId(for: URL(fileURLWithPath: "a.\(suffix)")) != nil
	}

	/// The name a new file of this kind should have, given what was typed.
	///
	/// The extension is the whole point of the shortcut, so it is added — but
	/// only when it is not already there, since somebody who typed it should
	/// not get `thing.ts.ts`.
	public static func name(_ typed: String, endingIn kind: NewFileKind) -> String {
		let trimmed = typed.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return trimmed }
		return trimmed.lowercased().hasSuffix(kind.suffix.lowercased())
			? trimmed
			: trimmed + kind.suffix
	}
}
