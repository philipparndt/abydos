import Foundation

/// What git would ignore under a folder, and by which rule.
///
/// Asked of git rather than matched here: `.gitignore` syntax has a dozen
/// corners — negation, anchoring, `**`, a trailing slash, the chain of files
/// from the root down, the global excludes file — and every one of them is a
/// row that would be greyed on one side of the page and coloured in the
/// navigator beside it. `check-ignore` answers for every path in one process,
/// with `-v` naming the file and line that decided each, which is what the
/// row's tip says.
///
/// A folder outside any repository ignores nothing this way; the built-in
/// list of build-output names is the whole of what applies there, and it is
/// decided at listing time, not here.
enum FolderIgnore {
	/// The paths git ignores, each with the rule that did it, as `<file>:<line>
	/// <pattern>`. Empty when the folder is not in a repository.
	static func ignoredPaths(_ relativePaths: [String], under root: URL) async -> [(String, String)] {
		guard !relativePaths.isEmpty else { return [] }
		// One record per path, NUL-terminated in and out: a file name with a
		// newline in it is rare and a mis-parse on it is a wrong row.
		let input = Data((relativePaths.joined(separator: "\0") + "\0").utf8)
		let result = await GitRepository.run(
			["check-ignore", "-v", "-z", "--stdin", "--non-matching"], in: root, input: input
		)
		// 0: some ignored; 1: none; 128: not a repository, or git is upset.
		guard result.exitCode == 0 else { return [] }
		return parse(result.stdout)
	}

	/// `-v -z --non-matching` writes four fields per path — source, line,
	/// pattern, path — with the first three empty for a path nothing matched.
	static func parse(_ output: String) -> [(String, String)] {
		let fields = output.split(separator: "\0", omittingEmptySubsequences: false)
		var result: [(String, String)] = []
		var index = 0
		while index + 3 < fields.count {
			let source = fields[index], line = fields[index + 1], pattern = fields[index + 2], path = fields[index + 3]
			index += 4
			guard !source.isEmpty else { continue }
			result.append((String(path), "\(source):\(line) \(pattern)"))
		}
		return result
	}
}
