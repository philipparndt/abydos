import Foundation
import Testing
@testable import AbydosKit

/// Which files conceal, and where in a line the secret is.
struct DotenvSecretsTests {
	@Test func theNameShapesConceal() {
		#expect(DotenvSecrets.conceals(fileNamed: ".env"))
		#expect(DotenvSecrets.conceals(fileNamed: ".env.local"))
		#expect(DotenvSecrets.conceals(fileNamed: "production.env"))
		#expect(DotenvSecrets.conceals(fileNamed: "secrets.yaml.dec"))
	}

	@Test func ordinaryNamesDoNot() {
		#expect(!DotenvSecrets.conceals(fileNamed: "environment.swift"))
		#expect(!DotenvSecrets.conceals(fileNamed: "decode.swift"))
		#expect(!DotenvSecrets.conceals(fileNamed: "envelope.md"))
		#expect(!DotenvSecrets.conceals(fileNamed: "README.md"))
	}

	private func value(of line: String) -> String? {
		DotenvSecrets.valueRange(inLine: line).map { String(line[$0]) }
	}

	@Test func aPlainValueIsTheValue() {
		#expect(value(of: "API_KEY=sk-abc123") == "sk-abc123")
	}

	/// The quotes go under the cover with what they quote: a cover that left
	/// them out would say how the value is delimited.
	@Test func aQuotedValueIsCoveredWhole() {
		#expect(value(of: "TOKEN=\"abc def\"") == "\"abc def\"")
	}

	@Test func anExportPrefixDoesNotHideTheKey() {
		#expect(value(of: "export TOKEN=abc") == "abc")
	}

	@Test func aYamlLineCoversAfterTheColon() {
		#expect(value(of: "password: hunter2") == "hunter2")
	}

	@Test func aCommentIsNotASecret() {
		#expect(value(of: "# rotate this monthly") == nil)
		#expect(value(of: "   # indented too") == nil)
	}

	@Test func anEmptyValueHasNothingToCover() {
		#expect(value(of: "EMPTY=") == nil)
		#expect(value(of: "") == nil)
		#expect(value(of: "no separator here") == nil)
	}

	/// Only the first separator splits: everything after it is value,
	/// whatever it contains.
	@Test func aValueContainingASeparatorIsOneValue() {
		#expect(value(of: "URL=https://user:pass@host/a=b") == "https://user:pass@host/a=b")
	}
}

/// Roles over a whole file, because a block scalar's value is not on its own
/// line: an RSA key sat in the clear under a covered `pk: |`.
struct DotenvSecretRolesTests {
	private func roles(_ lines: [String]) -> [DotenvSecrets.LineRole] {
		DotenvSecrets.roles(forLines: lines)
	}

	@Test func aBlockScalarsLinesAreItsValue() {
		let file = [
			"github:",
			"    vehub-deployment-app:",
			"        # rotated 2026-04-09",
			"        pk: |",
			"            -----BEGIN RSA PRIVATE KEY-----",
			"            MIIEowIBAAKCAQEAwQp0Zmqa",
			"",
			"            -----END RSA PRIVATE KEY-----",
			"        next: value",
		]
		#expect(roles(file) == [
			.plain, .plain, .plain, .value,
			.blockContent, .blockContent, .blockContent, .blockContent,
			.value,
		])
	}

	/// A parent key with children is a mapping, not a block: the children are
	/// keys and stay readable.
	@Test func aMappingsChildrenAreNotCovered() {
		#expect(roles(["github:", "    app:", "        pk: x"])
			== [.plain, .plain, .value])
	}

	@Test func theModifierFormsOpenBlocksToo() {
		#expect(roles(["a: |-", "  x", "b: >2", "   y", "c: v"])
			== [.value, .blockContent, .value, .blockContent, .value])
	}

	/// The dedent closes the block, and the closing line is itself again.
	@Test func aDedentEndsTheBlock() {
		#expect(roles(["pk: |", "  secret", "other: v"])
			== [.value, .blockContent, .value])
	}

	@Test func aValueMerelyStartingWithAPipeIsAValue() {
		#expect(roles(["cmd: |grep x", "  indented: v"])
			== [.value, .value])
	}
}
