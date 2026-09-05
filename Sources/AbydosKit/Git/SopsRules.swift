import Foundation

/// Which paths a project's `.sops.yaml` says should be encrypted.
///
/// **So that the offer to encrypt appears on the handful of files it is meant
/// for.** `sops` decides by matching a file's path against the `path_regex` of
/// each creation rule, and answers only when it is asked to encrypt something
/// — so a chip on every plaintext file, failing on all but a few, is not the
/// question anybody wanted asked. Read the rules instead, and offer where one
/// matches.
///
/// **A line scan, not a YAML parse, and no library for it.** There is no YAML
/// reader in this repository on purpose — the `pnpm-lock.yaml` work wrote down
/// why Yams was not worth its keep for one file — and what is needed here is
/// one field from a flat list. A rule this cannot read yields no match, which
/// is the safe direction: a missing chip costs a menu press, a wrong one costs
/// an unreadable file. `sops` itself enforces the real rules when the press
/// arrives.
public enum SopsRules {
	/// How much of the file is read: a `.sops.yaml` is a page of rules, and one
	/// that is a megabyte long is not a rule set this should be guessing at.
	static let inspectedBytes = 64 * 1024

	/// The `path_regex` values under `creation_rules`, in the order they appear
	/// — which is the order `sops` matches them in, first rule wins.
	public static func pathPatterns(in text: String) -> [String] {
		var patterns: [String] = []
		var insideRules = false
		for line in text.components(separatedBy: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("#") { continue }
			// A key at column zero ends the block: `creation_rules` is
			// top-level, so anything else at that indent is another section.
			if !line.hasPrefix(" "), !line.hasPrefix("\t"), !trimmed.isEmpty {
				insideRules = trimmed.hasPrefix("creation_rules:")
				continue
			}
			guard insideRules else { continue }
			guard let value = value(after: "path_regex:", in: trimmed) else { continue }
			patterns.append(value)
		}
		return patterns
	}

	/// The value of a key on one line, unquoted. A line carrying a comment
	/// after the value is left alone: a `#` inside a regex is a character
	/// class away from being meaningful, and dropping the tail would change
	/// the pattern rather than tidy it.
	private static func value(after key: String, in line: String) -> String? {
		// `- path_regex: …` as well as `path_regex: …`, since the first rule's
		// first key carries the list dash.
		var rest = line
		if rest.hasPrefix("- ") { rest = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
		guard rest.hasPrefix(key) else { return nil }
		var value = String(rest.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
		for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) && value.count > 1 {
			value = String(value.dropFirst().dropLast())
		}
		return value.isEmpty ? nil : value
	}

	/// The rules of the project at `root`, or none where there is no
	/// `.sops.yaml` to read.
	public static func patterns(forProjectAt root: URL) -> [String] {
		let url = root.appendingPathComponent(".sops.yaml")
		guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
		defer { try? handle.close() }
		let data = (try? handle.read(upToCount: inspectedBytes)) ?? Data()
		guard let text = String(data: data, encoding: .utf8) else { return [] }
		return pathPatterns(in: text)
	}

	/// Whether a rule matches this file — asked of the project-relative path,
	/// which is what `sops` matches with `--filename-override`.
	public static func matches(_ file: URL, in root: URL, patterns: [String]) -> Bool {
		let relative = relativePath(of: file, in: root)
		return patterns.contains { pattern in
			guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
			let range = NSRange(relative.startIndex..<relative.endIndex, in: relative)
			return expression.firstMatch(in: relative, range: range) != nil
		}
	}

	public static func matches(_ file: URL, in root: URL) -> Bool {
		matches(file, in: root, patterns: patterns(forProjectAt: root))
	}

	/// The path as the project sees it, standardised at both ends so that a
	/// project under `/tmp` — which is a symlink on this platform — matches its
	/// own files, the way `GitRepository` learnt to.
	static func relativePath(of file: URL, in root: URL) -> String {
		let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
		let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
		guard filePath.hasPrefix(rootPath + "/") else { return file.lastPathComponent }
		return String(filePath.dropFirst(rootPath.count + 1))
	}
}
