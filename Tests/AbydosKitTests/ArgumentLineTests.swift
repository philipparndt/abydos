import Foundation
import Testing
@testable import AbydosKit

/// Typing a command line, and getting arguments out of it.
struct ArgumentLineTests {
	@Test func splitsOnSpaces() {
		#expect(ArgumentLine.split("--verbose -n 4") == ["--verbose", "-n", "4"])
		#expect(ArgumentLine.split("   spaced   out  ") == ["spaced", "out"])
		#expect(ArgumentLine.split("").isEmpty)
	}

	/// A path with a space in it must not silently become two arguments the
	/// program cannot find.
	@Test func respectsQuotes() {
		#expect(ArgumentLine.split("--config \"my file.yaml\"") == ["--config", "my file.yaml"])
		#expect(ArgumentLine.split("'single quoted'") == ["single quoted"])
		#expect(ArgumentLine.split("--path=\"/a b/c\"") == ["--path=/a b/c"])
	}

	@Test func respectsEscapes() {
		#expect(ArgumentLine.split("a\\ b") == ["a b"])
		#expect(ArgumentLine.split("\"say \\\"hi\\\"\"") == ["say \"hi\""])
	}

	/// An empty argument is still an argument.
	@Test func keepsAnEmptyQuotedArgument() {
		#expect(ArgumentLine.split("a \"\" b") == ["a", "", "b"])
	}

	@Test func writesBackWhatCanBeReadAgain() {
		let arguments = ["--config", "my file.yaml", "", "plain"]
		#expect(ArgumentLine.split(ArgumentLine.join(arguments)) == arguments)
	}

	@Test func quotesOnlyWhatNeedsIt() {
		#expect(ArgumentLine.join(["--verbose", "x"]) == "--verbose x")
		#expect(ArgumentLine.join(["a b"]) == "\"a b\"")
	}
}

/// Environment variables written as lines.
struct EnvironmentLinesTests {
	@Test func readsKeyValueLines() {
		let parsed = EnvironmentLines.parse("LOG=debug\nPORT=8080")
		#expect(parsed == ["LOG": "debug", "PORT": "8080"])
	}

	@Test func ignoresBlankLinesAndComments() {
		let parsed = EnvironmentLines.parse("\n# a note\nLOG=debug\n\n")
		#expect(parsed == ["LOG": "debug"])
	}

	/// A value can contain anything, including more equals signs.
	@Test func keepsEverythingAfterTheFirstEquals() {
		#expect(EnvironmentLines.parse("URL=https://x/?a=1&b=2") == ["URL": "https://x/?a=1&b=2"])
	}

	/// Quotes are how a shell keeps spaces, not part of the value.
	@Test func stripsSurroundingQuotes() {
		#expect(EnvironmentLines.parse("GREETING=\"hello there\"") == ["GREETING": "hello there"])
	}

	@Test func skipsLinesThatAreNotAssignments() {
		#expect(EnvironmentLines.parse("nonsense\n=novalue\nLOG=debug") == ["LOG": "debug"])
	}

	@Test func roundTrips() {
		let environment = ["LOG": "debug", "PATH_EXTRA": "/usr/local/bin"]
		#expect(EnvironmentLines.parse(EnvironmentLines.format(environment)) == environment)
	}
}
