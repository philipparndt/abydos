import AppKit
import AbydosKit

/// The half of a diff render that owes nothing to the view.
///
/// In a file of its own because `DiffView.swift` is at the length ceiling
/// and this needs nothing of the view: it reads the patch text and hands back
/// the patch parsed and both sides coloured, and `DiffView.setDiff(_:staged:)`
/// is the rows and the redraw. Anything here that is `private` is private to
/// the preparation, which is why it can be an extension without widening a
/// thing the view keeps to itself.
extension DiffView {
	/// The patch parsed and both sides of it coloured, ready for `setDiff`.
	struct Prepared {
		let patch: GitPatch
		let highlights: [Int: [HighlightToken]]
	}

	/// Parses and colours, on whatever thread it is called from.
	///
	/// Two whole tree-sitter parses behind `highlights`, bounded only at
	/// 5,000 lines: 25 to 80 ms warm for a diff of a hundred lines of Swift,
	/// and half a second the first time a language is used in the process,
	/// which is its grammar and queries being loaded.
	nonisolated static func prepare(_ text: String, url: URL?) -> Prepared {
		let patch = GitPatch.parse(text)
		return Prepared(patch: patch, highlights: highlights(for: patch, url: url))
	}

	/// The same, off the main thread.
	///
	/// **This is what took the commit pane's render off the main queue.** It
	/// used to run inline on every selection change, and the pane waited out
	/// the double-click interval before starting it so that a second click's
	/// stage would not queue behind it — half a second on every click and
	/// every arrow key, to protect a gesture that hardly ever changes the
	/// selection. Nothing here touches the view, and the registry and engine
	/// already serve the editor's background parses, so it runs where the git
	/// call before it already ran.
	static func prepareOffMain(_ text: String, url: URL?) async -> Prepared {
		await Task.detached(priority: .userInitiated) { prepare(text, url: url) }.value
	}

	/// Above this many changed lines the colours are not worth the parse.
	///
	/// A diff that size is a lockfile or a generated file, which nobody reads
	/// line by line — and reconstructing both sides of it costs more than the
	/// whole view is meant to.
	private nonisolated static let highlightLineLimit = 5000

	private nonisolated static func highlights(for patch: GitPatch, url: URL?) -> [Int: [HighlightToken]] {
		guard let url, let languageId = LanguageRegistry.shared.languageId(for: url) else { return [:] }
		let lines = patch.hunks.reduce(0) { $0 + $1.lines.count }
		guard lines <= highlightLineLimit else { return [:] }
		return DiffHighlighter.highlight(patch, languageId: languageId)
	}
}
