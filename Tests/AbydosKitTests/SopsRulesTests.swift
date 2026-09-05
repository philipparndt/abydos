import Foundation
import Testing
@testable import AbydosKit

/// Which paths a project's `.sops.yaml` says should be encrypted.
///
/// The shapes are the ones `sops` documents and the ones on this machine: a
/// list of rules, each with a `path_regex` and a key, the first rule's first
/// key carrying the list dash.
struct SopsRulesTests {
	@Test func aRuleSaysWhichPathsItIsFor() {
		let text = """
		creation_rules:
		  - path_regex: ".*.(conf|yaml)"
		    age: age1d36ec3gz0m6djc7vdqq03g3k89wz8el2ndzlnvswlwy0tjcm552s027ws8
		"""
		#expect(SopsRules.pathPatterns(in: text) == [".*.(conf|yaml)"])
	}

	@Test func severalRulesKeepTheirOrder() {
		let text = """
		creation_rules:
		  - path_regex: secrets/prod/.*\\.yaml$
		    age: age1prod
		  - path_regex: 'secrets/dev/.*\\.yaml$'
		    age: age1dev
		"""
		#expect(SopsRules.pathPatterns(in: text)
			== ["secrets/prod/.*\\.yaml$", "secrets/dev/.*\\.yaml$"])
	}

	/// **Only under `creation_rules`.** A `path_regex` under some other
	/// top-level key is not a rule about encrypting anything, and reading it as
	/// one would offer the press on files nobody meant.
	@Test func aPathRegexOutsideTheRulesIsNotARule() {
		let text = """
		stores:
		  yaml:
		    indent: 2
		something_else:
		  - path_regex: .*
		"""
		#expect(SopsRules.pathPatterns(in: text).isEmpty)
	}

	@Test func aCommentIsNotARule() {
		let text = """
		creation_rules:
		  # - path_regex: .*
		  - path_regex: secrets/.*
		    age: age1x
		"""
		#expect(SopsRules.pathPatterns(in: text) == ["secrets/.*"])
	}

	@Test func aMatchingPathIsOfferedAndAnotherIsNot() {
		let root = URL(fileURLWithPath: "/tmp/project")
		let patterns = ["secrets/.*\\.yaml$"]
		#expect(SopsRules.matches(
			root.appendingPathComponent("secrets/dev.yaml"), in: root, patterns: patterns
		))
		#expect(!SopsRules.matches(
			root.appendingPathComponent("README.md"), in: root, patterns: patterns
		))
		#expect(!SopsRules.matches(
			root.appendingPathComponent("secrets/dev.json"), in: root, patterns: patterns
		))
	}

	/// **The path as the project sees it**, because that is what `sops` is
	/// handed with `--filename-override`: a rule naming `secrets/` must not be
	/// matched by an absolute path that happens to have `secrets/` somewhere
	/// above the project.
	@Test func theRuleIsMatchedAgainstTheProjectRelativePath() {
		let root = URL(fileURLWithPath: "/Users/me/secrets/project")
		#expect(!SopsRules.matches(
			root.appendingPathComponent("README.md"), in: root, patterns: ["^secrets/"]
		))
		#expect(SopsRules.matches(
			root.appendingPathComponent("secrets/a.yaml"), in: root, patterns: ["^secrets/"]
		))
	}

	/// A pattern this cannot compile yields no match rather than a wrong one:
	/// a missing chip costs a menu press, a wrong one costs an unreadable file.
	@Test func aPatternThatCannotBeReadOffersNothing() {
		let root = URL(fileURLWithPath: "/tmp/project")
		#expect(!SopsRules.matches(
			root.appendingPathComponent("secrets/dev.yaml"), in: root, patterns: ["secrets/[("]
		))
	}

	@Test func aProjectWithNoRulesFileHasNoRules() {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("no-sops-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(SopsRules.patterns(forProjectAt: root).isEmpty)
		#expect(!SopsRules.matches(root.appendingPathComponent("secrets.yaml"), in: root))
	}

	@Test func theRulesAreReadFromTheProject() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("sops-rules-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		try """
		creation_rules:
		  - path_regex: secrets/.*\\.yaml$
		    age: age1x
		""".write(to: root.appendingPathComponent(".sops.yaml"), atomically: true, encoding: .utf8)

		#expect(SopsRules.matches(root.appendingPathComponent("secrets/dev.yaml"), in: root))
		#expect(!SopsRules.matches(root.appendingPathComponent("notes.md"), in: root))
	}
}
