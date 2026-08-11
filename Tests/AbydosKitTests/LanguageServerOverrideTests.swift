import Foundation
import Testing
@testable import AbydosKit

/// A project, or a person, naming the *executable* for a server rather than
/// letting a name be looked up on the `PATH` — and naming what to tell it.
///
/// Nothing here starts a server. What is being checked is the part that decides
/// what would be started: which of the two files was believed, that a path is
/// taken as a path, that `~` is expanded on the side where it means something and
/// left alone on the side where it does not, and that a command reaches both the
/// installed route and the container route.
///
/// The case it comes from is a Rust project pinning `channel = "esp"`, where
/// `rust-analyzer` on the `PATH` is a symlink to `rustup` and refuses to run
/// rather than running the server installed beside it. But nothing here is about
/// Rust: every toolchain manager that puts a proxy on the `PATH` has this shape.
struct LanguageServerOverrideTests {
	private func toolsFile(_ json: String) -> Data { Data(json.utf8) }

	private func project(_ tools: String?) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("server-override-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		if let tools {
			let file = ToolImages.url(in: root)
			try FileManager.default.createDirectory(
				at: file.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try tools.write(to: file, atomically: true, encoding: .utf8)
		}
		return root
	}

	// MARK: - Reading the file

	@Test func aProjectCanNameTheExecutableForAServer() throws {
		let root = try project("""
		{ "rust-analyzer": { "command": "/opt/rust/bin/rust-analyzer" } }
		""")
		let overrides = LanguageServerOverrides.inProject(root)
		#expect(overrides.command(forTool: "rust-analyzer") == "/opt/rust/bin/rust-analyzer")
		#expect(overrides.override(forTool: "rust-analyzer")?.source == .project)
		#expect(overrides.command(forTool: "gopls") == nil)
	}

	/// The image and the command are two answers under one name and both are read,
	/// because they are two different questions: where the tool comes from, and
	/// which program in there is the tool.
	@Test func anImageAndACommandLiveTogetherUnderOneName() throws {
		let root = try project("""
		{
		  "rust-analyzer": {
		    "image": "build:rust-analyzer-esp",
		    "command": "/home/esp/rust-analyzer"
		  }
		}
		""")
		#expect(ToolImages.inProject(root).image(for: "rust-analyzer") == "build:rust-analyzer-esp")
		#expect(LanguageServerOverrides.inProject(root).command(forTool: "rust-analyzer")
			== "/home/esp/rust-analyzer")
	}

	/// The bare string beside a tool's name has meant its image since `ToolImages`,
	/// so it cannot be made to mean a second thing. The table is what a second
	/// thing goes in, which is what the table was added for.
	@Test func aBareStringIsStillAnImageAndNeverACommand() throws {
		let root = try project("""
		{ "plantuml": "plantuml/plantuml:1.2025.4" }
		""")
		#expect(LanguageServerOverrides.inProject(root).isEmpty)
		#expect(ToolImages.inProject(root).image(for: "plantuml") == "plantuml/plantuml:1.2025.4")
	}

	/// The section naming which server a language uses has language ids for keys
	/// rather than tool names, and it must not be read as a tool. Told apart by
	/// that name rather than by shape, for `ToolImages`' reason: `plantuml` is both
	/// a tool that comes from an image and a language a server answers for.
	@Test func theLanguagesSectionIsNotATool() throws {
		let root = try project("""
		{ "languages": { "java": "kmp-lsp" }, "kmp-lsp": { "command": "/opt/kmp-lsp" } }
		""")
		let overrides = LanguageServerOverrides.inProject(root)
		#expect(overrides.byTool.keys.sorted() == ["kmp-lsp"])
	}

	@Test func aFileThatCannotBeReadIsTheSameAsNoFile() throws {
		#expect(LanguageServerOverrides.inProject(try project(nil)).isEmpty)
		#expect(LanguageServerOverrides.inProject(try project("{ not json")).isEmpty)
		#expect(LanguageServerOverrides.inProject(try project("""
		{ "rust-analyzer": { "command": "" } }
		""")).isEmpty)
	}

	@Test func initializationOptionsAreCarriedThroughUnchanged() throws {
		let root = try project("""
		{
		  "rust-analyzer": {
		    "initializationOptions": {
		      "procMacro": { "enable": true, "server": "/toolchains/esp/libexec/srv" },
		      "cargo": { "buildScripts": { "enable": true } }
		    }
		  }
		}
		""")
		let options = LanguageServerOverrides.inProject(root)
			.initializationOptions(forTool: "rust-analyzer")
		#expect(options["procMacro"] == .object([
			"enable": .bool(true), "server": .string("/toolchains/esp/libexec/srv"),
		]))
		#expect(options["cargo"] == .object(["buildScripts": .object(["enable": .bool(true)])]))
	}

	// MARK: - Which of the two files wins

	/// The rule the images and the choices already follow: **the file wins and the
	/// setting is the default.**
	@Test func theProjectsCommandWinsOverThePersons() {
		let resolved = LanguageServerOverrides.resolve(
			project: .parse(toolsFile("""
			{ "rust-analyzer": { "command": "/from/project" } }
			"""), source: .project),
			settings: .settings(["rust-analyzer": "/from/settings"])
		)
		#expect(resolved.command(forTool: "rust-analyzer") == "/from/project")
		#expect(resolved.override(forTool: "rust-analyzer")?.source == .project)
	}

	/// Key by key rather than entry by entry, and this is the case that decides it:
	/// a project adding initialize options and no command must not take away the
	/// command a person set for every project. Replacing the entry wholesale would,
	/// and the symptom would be a server that stops starting because a line about
	/// proc macros was added.
	@Test func aProjectAddingOptionsKeepsThePersonsCommand() {
		let resolved = LanguageServerOverrides.resolve(
			project: .parse(toolsFile("""
			{ "rust-analyzer": { "initializationOptions": { "procMacro": { "enable": true } } } }
			"""), source: .project),
			settings: .settings(["rust-analyzer": "/from/settings"])
		)
		#expect(resolved.command(forTool: "rust-analyzer") == "/from/settings")
		#expect(resolved.initializationOptions(forTool: "rust-analyzer")["procMacro"]
			== .object(["enable": .bool(true)]))
		// And the origin named is the settings, since that is where the command
		// somebody would go and change actually is.
		#expect(resolved.override(forTool: "rust-analyzer")?.source == .settings)
	}

	@Test func aPersonsCommandStandsWhereTheProjectSaysNothing() {
		let resolved = LanguageServerOverrides.resolve(
			project: .none, settings: .settings(["rust-analyzer": "/from/settings", "gopls": ""])
		)
		#expect(resolved.command(forTool: "rust-analyzer") == "/from/settings")
		#expect(resolved.command(forTool: "gopls") == nil)
	}

	// MARK: - What it does to what gets started

	/// The one rule about what a command is, stated once: a `/` in it makes it a
	/// path. `executable(for:)` already had it — 0466 only had to give somebody
	/// somewhere to write one down.
	@Test func aNamedPathIsRunAndNothingIsSearchedFor() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("named-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let binary = directory.appendingPathComponent("rust-analyzer")
		try "#!/bin/sh\n".write(to: binary, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

		let rust = try #require(LanguageServers.server(named: "rust-analyzer"))
		#expect(LanguageServers.executable(for: rust.running(binary.path)) == binary.path)
		// The name is carried over, because everything a server is filed under is
		// its name: the running server, the image chosen for it, the project's own
		// choice of it.
		#expect(rust.running(binary.path).name == "rust-analyzer")
		#expect(rust.running(binary.path).languageIds == rust.languageIds)
	}

	/// Something named and absent is nil rather than a search: a name substituted
	/// for a path would be the proxy this exists to get away from, arriving
	/// silently.
	@Test func somethingNamedAndAbsentIsNotSubstitutedFor() throws {
		let rust = try #require(LanguageServers.server(named: "rust-analyzer"))
		#expect(LanguageServers.executable(for: rust.running("/nowhere/rust-analyzer")) == nil)
	}

	/// `~` on the side where it means something. A checked-in file naming
	/// `/Users/somebody/.rustup/…` is one machine's; `~/.rustup/…` is everybody's
	/// who installed the same way, which is the whole point of writing it down.
	@Test func aTildeIsExpandedForACommandOnThisMachine() throws {
		let rust = try #require(LanguageServers.server(named: "rust-analyzer"))
		// `/bin/sh` under a tilde that cannot exist proves the expansion happened
		// without depending on what this machine has installed.
		let home = NSHomeDirectory()
		#expect(LanguageServers.executable(for: rust.running("~/../..\(home)/../../bin/sh"))
			== "\(home)/../..\(home)/../../bin/sh")
	}

	/// And left alone on the side where it does not: inside a container `~` is the
	/// *image's* home, and expanding it here would send `/Users/somebody/…` into a
	/// Linux container — a path that exists nowhere and a server that never starts.
	@Test func aTildeIsNotExpandedForTheContainersSide() {
		let overrides = LanguageServerOverrides.parse(toolsFile("""
		{ "rust-analyzer": { "command": "~/rust-analyzer" } }
		"""), source: .project)
		#expect(overrides.command(forTool: "rust-analyzer") == "~/rust-analyzer")
	}

	/// A command reaches the container route too, and it has to: the proxy is on
	/// the `PATH` inside an image as readily as out here — `espressif/idf-rust`
	/// puts `/home/esp/.cargo/bin` first and has no rust-analyzer behind it.
	@Test func aCommandIsWhatRunsInsideTheImageAsWell() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("in-image-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		try "[package]\nname = \"x\"\n".write(
			to: root.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8
		)

		let resolution = try #require(LanguageServers.resolve(
			languageId: "rust", project: root,
			image: "espressif/idf-rust:esp32_1.95.0.0",
			runtime: .apple("/usr/local/bin/container"),
			choosing: .none,
			command: "/home/esp/rust-analyzer"
		))
		guard case let .image(container, runtime, _) = resolution.launch else {
			Issue.record("expected an image launch"); return
		}
		#expect(container.command == ["/home/esp/rust-analyzer"])
		// After the image name, which is where a command belongs: it replaces the
		// image's own CMD.
		let line = container.invocation(using: runtime).arguments
		let image = try #require(line.firstIndex(of: "espressif/idf-rust:esp32_1.95.0.0"))
		#expect(line[(image + 1)...] == ["/home/esp/rust-analyzer"])
	}

	@Test func namingNothingLeavesTheEntryPointAlone() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("no-command-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		try "[package]\nname = \"x\"\n".write(
			to: root.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8
		)
		let resolution = try #require(LanguageServers.resolve(
			languageId: "rust", project: root, image: "some/image",
			runtime: .apple("/usr/local/bin/container"), choosing: .none
		))
		guard case let .image(container, _, _) = resolution.launch else {
			Issue.record("expected an image launch"); return
		}
		#expect(container.command.isEmpty)
	}

	// MARK: - What to tell it

	/// The other half, and it was compiled in: jdtls's JDKs and nothing for
	/// anybody else. A server that gets nothing from the table can now be told
	/// something, which is the only way `procMacro.server` — a path into a
	/// toolchain this repository cannot know the name of — could ever be said.
	@Test func aServerThatGetsNoOptionsCanStillBeToldSomething() throws {
		let rust = try #require(LanguageServers.server(named: "rust-analyzer"))
		let root = URL(fileURLWithPath: "/p")
		#expect(LanguageServers.initializationOptions(for: rust, root: root) == nil)

		let options = try #require(LanguageServers.initializationOptions(
			for: rust, root: root,
			merging: ["procMacro": .object(["server": .string("/toolchains/esp/libexec/srv")])]
		))
		let procMacro = try #require(options["procMacro"] as? [String: Any])
		#expect(procMacro["server"] as? String == "/toolchains/esp/libexec/srv")
	}

	/// Deep, and this is the case that decides it: `settings.java.format` added
	/// from a project file must not replace the whole of `settings` and take the
	/// runtimes with it. The symptom would be a Java project compiled against the
	/// wrong JDK because somebody turned formatting on.
	@Test func optionsAreMergedAllTheWayDownAndNotOverTheTop() throws {
		let jdtls = try #require(LanguageServers.server(named: "jdtls"))
		let options = try #require(LanguageServers.initializationOptions(
			for: jdtls, root: URL(fileURLWithPath: "/p"), inContainer: true,
			merging: ["settings": .object(["java": .object([
				"format": .object(["enabled": .bool(true)]),
			])])]
		))
		let java = try #require((options["settings"] as? [String: Any])?["java"] as? [String: Any])
		#expect((java["format"] as? [String: Any])?["enabled"] as? Bool == true)
		// Still there, which is the whole assertion.
		#expect(java["configuration"] != nil)
		#expect(java["import"] != nil)
	}

	// MARK: - When it is wrong

	@Test func aPathWithNothingAtItIsItsOwnSentenceAndNotAnInstallHint() {
		let said = LanguageServerOverrides.refusal(
			command: "/opt/rust/bin/rust-analyzer", forTool: "rust-analyzer", source: .project
		)
		#expect(said.contains(".abydos/tools.json"))
		#expect(said.contains("/opt/rust/bin/rust-analyzer"))
		#expect(said.contains("no executable file"))
		// Never the install hint, which for this tool is the advice that produces
		// the proxy a named path exists to get away from.
		#expect(!said.contains("rustup component add"))
	}

	// MARK: - The second recipe

	/// A recipe nothing can ask for is not a route. `build` means the tool's own
	/// recipe and `build:<recipe>` means another of them, which is how a project
	/// pinning Espressif's fork gets an image built on Espressif's toolchain
	/// without every other Rust project paying a gigabyte for it.
	@Test func aProjectCanAskForARecipeThatIsNotTheToolsOwn() throws {
		let plain = try #require(ToolImageRecipes.resolve(image: "build", forTool: "rust-analyzer"))
		#expect(plain.hasPrefix("abydos-built/rust-analyzer:"))

		let esp = try #require(
			ToolImageRecipes.resolve(image: "build:rust-analyzer-esp", forTool: "rust-analyzer")
		)
		#expect(esp.hasPrefix("abydos-built/rust-analyzer-esp:"))
		// And the name still finds its way back to the recipe, so an edited one
		// rebuilds exactly as the tool's own does.
		#expect(ToolImageRecipes.recipe(forImage: esp)?.tool == "rust-analyzer-esp")
		#expect(ToolImageRecipes.isVariantRecipe(esp, forTool: "rust-analyzer"))
		#expect(!ToolImageRecipes.isVariantRecipe(plain, forTool: "rust-analyzer"))
		#expect(!ToolImageRecipes.isVariantRecipe("espressif/idf-rust:esp32_1.95.0.0",
		                                          forTool: "rust-analyzer"))
	}

	@Test func askingForARecipeNobodyShipsIsNotAnImageName() {
		#expect(ToolImageRecipes.resolve(image: "build:nonesuch", forTool: "rust-analyzer") == nil)
		#expect(ToolImageRecipes.resolve(image: "build:", forTool: "rust-analyzer") == nil)
		// And an ordinary image name is still left exactly as it was.
		#expect(ToolImageRecipes.resolve(image: "some/image:1", forTool: "rust-analyzer")
			== "some/image:1")
	}

	/// The entry point is the one line that makes the esp recipe work and the one
	/// that is easy to get wrong, since `rust-analyzer` is correct in every other
	/// image in this repository and wrong only in this one — there it is rustup's
	/// proxy, asking `esp` for a component it has not got.
	@Test func theEspRecipeStartsAnAbsolutePathAndNotTheProxy() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "rust-analyzer-esp"))
		let text = try String(
			contentsOf: recipe.context.appendingPathComponent("Dockerfile"), encoding: .utf8
		)
		let entryPoint = try #require(
			text.components(separatedBy: .newlines).last { $0.hasPrefix("ENTRYPOINT") }
		)
		#expect(entryPoint.contains("[\"/"))
		#expect(!entryPoint.contains("[\"rust-analyzer\"]"))
		// And the other recipe still starts it by name, which is right everywhere
		// else and is why the two are separate files.
		let plain = try #require(ToolImageRecipes.recipe(forTool: "rust-analyzer"))
		let ordinary = try String(
			contentsOf: plain.context.appendingPathComponent("Dockerfile"), encoding: .utf8
		)
		#expect(ordinary.contains("ENTRYPOINT [\"rust-analyzer\"]"))
	}

	/// The claim 0466 disproved, gone from the file that made it. A comment that
	/// confident and that wrong costs somebody an afternoon.
	@Test func theRustRecipeNoLongerClaimsNothingCouldChangeIt() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "rust-analyzer"))
		let text = try String(
			contentsOf: recipe.context.appendingPathComponent("Dockerfile"), encoding: .utf8
		)
		#expect(!text.contains("nothing to add to this file that would change it"))
		#expect(!text.contains("No image reached by name has it"))
		#expect(text.contains("espressif/idf-rust"))
		// The two things that stay ruled out stay written down.
		#expect(text.contains("aarch64-apple-darwin"))
		#expect(text.contains("custom toolchain"))
	}
}
