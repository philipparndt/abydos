import Foundation

/// Which files hold secrets by shape, and where in a line the secret is —
/// the model behind the editor's redaction covers.
///
/// Name shapes, not content sniffing: entropy heuristics are false positives
/// waiting to interrupt somebody's JSON, and the files that put keys in front
/// of a shared screen announce themselves by name. `.env` and its variants
/// are the dotenv convention; `*.dec` is the file a SOPS-style decrypt leaves
/// beside its encrypted original, which is the most secret-laden file a
/// screen can show.
public enum DotenvSecrets {
	/// Whether a file of this name conceals its values.
	public static func conceals(fileNamed name: String) -> Bool {
		let lowered = name.lowercased()
		if lowered == ".env" || lowered.hasPrefix(".env.") { return true }
		if lowered.hasSuffix(".env") { return true }
		if lowered.hasSuffix(".dec") { return true }
		return false
	}

	/// What each line is, once the lines above have had their say.
	///
	/// Line-by-line classification cannot see a YAML block scalar: `pk: |`
	/// carries its value on the *following* more-indented lines, which a
	/// stateless look called plain — and an RSA private key was drawn in the
	/// clear under a dutifully covered `pk: |`. So the roles are computed
	/// over the file: a line whose value is a block-scalar indicator (`|`,
	/// `>`, with chomping and indent modifiers) opens a block, every following
	/// line indented deeper than the key — blank lines included, as YAML keeps
	/// them — is block content, and the first line back at or above the key's
	/// indent closes it and classifies as itself.
	public enum LineRole: Equatable, Sendable {
		case plain
		case value
		case blockContent
	}

	public static func roles(forLines lines: [String]) -> [LineRole] {
		var roles: [LineRole] = []
		var blockIndent: Int?
		for line in lines {
			let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
			let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
			if let opened = blockIndent {
				if isBlank || indent > opened {
					roles.append(.blockContent)
					continue
				}
				blockIndent = nil
			}
			guard let range = valueRange(inLine: line) else {
				roles.append(.plain)
				continue
			}
			if isBlockScalarIndicator(line[range].trimmingCharacters(in: .whitespaces)) {
				blockIndent = indent
			}
			roles.append(.value)
		}
		return roles
	}

	/// `|`, `>`, and their modifier forms — `|-`, `|+`, `>2` — and nothing
	/// else: a value that merely begins with a pipe is a value.
	static func isBlockScalarIndicator(_ value: String) -> Bool {
		guard let first = value.first, first == "|" || first == ">" else { return false }
		return value.dropFirst().allSatisfy { "+-0123456789".contains($0) }
	}

	/// The range of the value in one line — what a cover hides.
	///
	/// After the first separator: `=` for the dotenv shape, and `:` too for
	/// the YAML shape a `.dec` file usually has. `export ` prefixes do not
	/// hide a key's name, quotes are covered with the value they quote, and a
	/// comment, a blank line or a line with no separator has no value to
	/// cover. The separator itself stays readable — `API_KEY=` is the half
	/// somebody shares a screen to talk about.
	public static func valueRange(inLine line: String) -> Range<String.Index>? {
		let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
		guard let first = trimmed.first, first != "#" else { return nil }

		guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
			return nil
		}
		var start = line.index(after: separator)
		// The space after a YAML `:`, kept readable with the separator.
		while start < line.endIndex, line[start] == " " || line[start] == "\t" {
			start = line.index(after: start)
		}
		guard start < line.endIndex else { return nil }
		return start..<line.endIndex
	}
}
