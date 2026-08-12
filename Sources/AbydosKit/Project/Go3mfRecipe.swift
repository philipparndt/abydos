import Foundation

/// A go3mf recipe: YAML naming the parts of an assembly and the file they are
/// built into.
///
/// GoSTL builds and shows one already — `go3mf build <yaml> -o <temp>.3mf`, with
/// the recipe's own directory as the working directory, and the result loaded like
/// any other 3MF. What is here is only the question Abydos has to answer before it
/// offers that: *is this `.yaml` a recipe at all?*
///
/// **A name cannot answer it.** Every other preview in this app routes on the
/// extension, and that works because a `.puml` is a diagram and a `.stl` is a mesh.
/// A repository's YAML is workflows, compose files, Helm charts, lock files and
/// four kinds of configuration, and a *Preview in GoSTL* on all of them would be
/// wrong far more often than right — the same argument `DiagramExport.holdsADiagram`
/// makes about an `Export ▸` over every Markdown file, and it is answered the same
/// way: the name says whether it is worth looking, and a look inside decides.
///
/// The look is **bounded and cheap on purpose**: `inspectedBytes` from the head of
/// the file, once, for the one file somebody has clicked or opened. Nothing that
/// walks a tree asks this — `FilePreview.kind(for:)` and
/// `ModelPreview.previewableExtensions` still answer from the name alone, which is
/// what keeps a right-click in a directory of two thousand files from reading two
/// thousand of them.
public enum Go3mfRecipe {
	/// Extensions worth looking inside. Never an answer on its own.
	public static let extensions: Set<String> = ["yaml", "yml"]

	/// How much of a file is read to decide, in bytes.
	///
	/// The head, because a recipe's `output:` and `objects:` are top-level keys and
	/// a YAML document puts its top level first. 8 KB is a comfortable multiple of
	/// what that takes — the recipe this item came from is 1,091 bytes whole — and
	/// small enough that being wrong about it costs one page of one file.
	public static let inspectedBytes = 8 * 1024

	/// Whether this name is worth looking inside. Costs nothing.
	public static func hasRecipeExtension(_ url: URL) -> Bool {
		extensions.contains(url.pathExtension.lowercased())
	}

	/// Whether this file is a go3mf recipe.
	///
	/// **Reads the file** — `inspectedBytes` of it — when the name is a `.yaml` or a
	/// `.yml`, and nothing at all otherwise. Ask it about one file, on a gesture
	/// somebody made; do not ask it about a directory.
	public static func looksLikeRecipe(_ url: URL) -> Bool {
		guard hasRecipeExtension(url), let head = head(of: url) else { return false }
		return looksLikeRecipe(yaml: head)
	}

	/// The rule, on text, so it can be tested and so an editor holding the file
	/// already need not read it again.
	///
	/// **Top-level `output:` and top-level `objects:`, both.** That is a recipe's
	/// shape — what to build and what to build it from — and it is what `go3mf`'s own
	/// documented example leads with. Either one alone is not a signature: `output:`
	/// on its own is in every second build pipeline, and a lone `objects:` is a
	/// schema, a fixture list or an inventory as often as it is an assembly.
	///
	/// Two things are deliberately *not* part of the test:
	///
	///  * **The `https://github.com/philipparndt/go3mf` line in the comment.** It is
	///    the strongest hint in the file this item came from and it is still wrong to
	///    use, because a recipe somebody wrote from scratch, or copied without the
	///    header, is every bit as much a recipe. A test that reads a comment tests
	///    whose template the file came from.
	///  * **Whether the parts exist, or whether `go3mf` is installed.** Those are
	///    reasons a build fails, and GoSTL says so in its own overlay. This answers
	///    whether the file is the kind of thing to offer the viewer for.
	public static func looksLikeRecipe(yaml: String) -> Bool {
		var hasOutput = false
		var hasObjects = false
		// `isNewline` rather than splitting on "\n". A CRLF is *one* Swift
		// Character, so a file written on Windows does not split on "\n" at all —
		// the whole document comes back as a single line and no key is ever seen.
		for line in yaml.split(whereSeparator: \.isNewline) {
			// Top level only. An `output:` nested three levels down a build
			// pipeline's YAML is a step's output, not a 3MF to write.
			guard let first = line.first, first != " ", first != "\t", first != "#" else { continue }
			let key = line.prefix { $0 != ":" }
			// No colon at all: a document marker, a stray word, the `---` between
			// two documents. Not a key.
			guard key.count < line.count else { continue }
			switch key {
			case "output": hasOutput = true
			case "objects": hasObjects = true
			default: break
			}
			if hasOutput, hasObjects { return true }
		}
		return false
	}

	/// The head of a file, as text.
	///
	/// Lossy on purpose. A prefix of a UTF-8 file can cut a character in half, and a
	/// recipe whose last inspected byte lands mid-character should still be
	/// recognised by the lines above it; anything that is not text at all decodes to
	/// replacement characters and matches nothing, which is the right answer for it.
	private static func head(of url: URL) -> String? {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
		defer { try? handle.close() }
		guard let data = try? handle.read(upToCount: inspectedBytes) else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
}
