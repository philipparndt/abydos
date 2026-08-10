import Foundation
import Testing
@testable import AbydosKit

/// Finding a tool that is installed, on a machine where a version manager
/// decides where "installed" means.
struct ShellPathTests {
	/// The list is asked of a real shell, so what is in it depends on the
	/// machine. What must hold is its shape.
	@Test func theLoginPathIsAListOfAbsoluteDirectories() {
		for entry in UserShell.loginPath {
			#expect(entry.hasPrefix("/"), "\(entry) is not an absolute path")
		}
	}

	@Test func theLoginPathRepeatsNothing() {
		let entries = UserShell.loginPath
		#expect(Set(entries).count == entries.count)
	}

	/// Asked once and remembered. Running somebody's `.zshrc` for every file
	/// they open would be a stall per file.
	@Test func theLoginPathIsWorkedOutOnce() {
		let first = UserShell.loginPath
		let second = UserShell.loginPath
		#expect(first == second)
	}

	@Test func theSearchPathRepeatsNothing() {
		let paths = Executables.searchPaths
		#expect(Set(paths).count == paths.count)
	}

	/// The well-known directories are the floor, whatever the shell says.
	@Test func theSearchPathKeepsTheKnownDirectories() {
		let paths = Set(Executables.searchPaths)
		for directory in Executables.toolDirectories {
			#expect(paths.contains(directory))
		}
	}

	/// A PATH set deliberately still chooses the toolchain, so what this process
	/// was handed comes before anything worked out for it.
	@Test func whatTheProcessWasGivenComesFirst() throws {
		let given = try #require(ProcessInfo.processInfo.environment["PATH"])
		let first = try #require(given.split(separator: ":").first.map(String.init))
		#expect(Executables.searchPaths.first == first)
	}

	/// One search, and not two. A language server was looked for down the login
	/// shell's `PATH` while every other tool made do with four well-known
	/// directories, and the day those two disagreed the app could not see the
	/// container runtime its own terminal pane could.
	@Test func everyToolIsLookedForInTheSameDirectories() {
		let anything = LanguageServerDefinition(
			languageIds: ["x"], command: "env", installHint: "comes with the system"
		)
		#expect(LanguageServers.executable(for: anything) == Executables.locate("env"))
	}

	/// TypeScript 7 is the native compiler and ships no `tsserver.js`, which is
	/// the one file typescript-language-server drives. Installed without the
	/// version, the pair starts and then refuses the handshake — so the sentence
	/// this app prints has to carry it.
	@Test func theTypeScriptHintPinsAVersionThatWorks() throws {
		let definition = try #require(LanguageServers.definition(forLanguage: "tsx"))
		#expect(definition.installHint.contains("typescript@5"))
	}
}
