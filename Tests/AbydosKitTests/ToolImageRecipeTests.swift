import Foundation
import Testing
@testable import AbydosKit

/// The third answer to where a tool comes from: a Dockerfile this app ships,
/// built on the machine that wants it.
///
/// Nothing here starts a container. What is being checked is the part that
/// decides *what would be built and what it would be called* — which is where
/// the whole scheme lives or dies, because the name is what makes an edited
/// recipe rebuild and an unedited one not.
struct ToolImageRecipeTests {
	@Test func aToolWithADockerfileShippedHereHasARecipe() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		#expect(recipe.tool == "openscad-lsp")
		#expect(FileManager.default.fileExists(
			atPath: recipe.context.appendingPathComponent("Dockerfile").path
		))
	}

	@Test func goplsHasOneToo() throws {
		// The recipe route is not a special case for one tool: gopls has both a
		// published image and a Dockerfile, and this is what says the two
		// coexist rather than one displacing the other.
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "gopls"))
		#expect(recipe.image.hasPrefix("abydos-built/gopls:"))
	}

	@Test func aToolWithNoDockerfileHasNoRecipe() {
		#expect(ToolImageRecipes.recipe(forTool: "jdtls") == nil)
		#expect(ToolImageRecipes.recipe(forTool: "") == nil)
		#expect(ToolImageRecipes.recipe(forTool: "../gopls") == nil)
	}

	@Test func theImageIsNamedInThisAppsOwnNamespaceAndTaggedWithAFingerprint() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		let parts = recipe.image.split(separator: ":")
		#expect(parts.first == "abydos-built/openscad-lsp")
		let tag = try #require(parts.last)
		#expect(tag.count == 12)
		#expect(tag.allSatisfy { $0.isHexDigit && !$0.isUppercase })
	}

	@Test func aNameThisAppMadeSaysWhichRecipeItCameFrom() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		let back = try #require(ToolImageRecipes.recipe(forImage: recipe.image))
		#expect(back == recipe)
	}

	@Test func aNameFromARegistryIsNotOneOfOurs() {
		// The one that matters: everything published goes through the same
		// `ensure`, and a published image mistaken for a recipe would be built
		// from a directory that does not exist instead of pulled.
		#expect(ToolImageRecipes.recipe(forImage: "pharndt/abydos-gopls:dev") == nil)
		#expect(ToolImageRecipes.recipe(forImage: "plantuml/plantuml:1.2025.4") == nil)
		#expect(ToolImageRecipes.recipe(forImage: "abydos/gopls:dev") == nil)
		#expect(ToolImageRecipes.recipe(forImage: "abydos-built/nosuchtool:abc") == nil)
	}

	// MARK: - What the fingerprint answers to

	@Test func aRecipeThatChangesIsANewImageAndOneThatDoesNotIsTheSame() throws {
		let context = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: context) }
		let dockerfile = context.appendingPathComponent("Dockerfile")

		try JavaTestDirectory.write("FROM debian:bookworm-slim\n", to: dockerfile)
		let first = try #require(ToolImageRecipes.fingerprint(of: context))
		#expect(ToolImageRecipes.fingerprint(of: context) == first)

		try JavaTestDirectory.write("FROM debian:trixie-slim\n", to: dockerfile)
		#expect(ToolImageRecipes.fingerprint(of: context) != first)
	}

	@Test func everythingInTheContextCounts() throws {
		// The Dockerfile alone would be enough today, because both recipes are
		// one file — and that is a fact about today. A context that gains an
		// entrypoint script and keeps its tag would run an edited script out of
		// an image that never rebuilt, which reads as a caching bug rather than
		// as a rule nobody wrote down.
		let context = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: context) }
		try JavaTestDirectory.write("FROM scratch\n", to: context.appendingPathComponent("Dockerfile"))
		let alone = try #require(ToolImageRecipes.fingerprint(of: context))

		let script = context.appendingPathComponent("entrypoint.sh")
		try JavaTestDirectory.write("#!/bin/sh\nexec tool\n", to: script)
		let withScript = try #require(ToolImageRecipes.fingerprint(of: context))
		#expect(withScript != alone)

		try JavaTestDirectory.write("#!/bin/sh\nexec tool --stdio\n", to: script)
		#expect(ToolImageRecipes.fingerprint(of: context) != withScript)
	}

	@Test func theSameRecipeInTwoPlacesNamesTheSameImage() throws {
		// The app bundle carries a copy of `ToolImages/` and a checkout has the
		// original. A fingerprint that took absolute paths in would name two
		// different images for one recipe, and somebody who ran the installed
		// app after building it here would pay for the build twice.
		let here = try JavaTestDirectory.make()
		let there = try JavaTestDirectory.make()
		defer {
			try? FileManager.default.removeItem(at: here)
			try? FileManager.default.removeItem(at: there)
		}
		for root in [here, there] {
			try JavaTestDirectory.write("FROM alpine:3\n", to: root.appendingPathComponent("Dockerfile"))
			try JavaTestDirectory.write("x\n", to: root.appendingPathComponent("etc/thing"))
		}
		#expect(ToolImageRecipes.fingerprint(of: here) == ToolImageRecipes.fingerprint(of: there))
	}

	@Test func anEmptyDirectoryIsNotARecipe() throws {
		let context = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: context) }
		#expect(ToolImageRecipes.fingerprint(of: context) == nil)
	}

	// MARK: - What a stored value means

	@Test func theWordBuildBecomesAnImageNameAndAnImageNameIsLeftAlone() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		#expect(ToolImageRecipes.resolve(image: "build", forTool: "openscad-lsp") == recipe.image)
		#expect(
			ToolImageRecipes.resolve(image: "plantuml/plantuml", forTool: "plantuml")
				== "plantuml/plantuml"
		)
		#expect(ToolImageRecipes.resolve(image: "", forTool: "gopls") == nil)
	}

	@Test func askingToBuildAToolThisAppShipsNoRecipeForIsNoImageAtAll() {
		// Nil rather than a name, so the caller falls back to the copy installed
		// on this machine. A name invented here would start a container from an
		// image nobody has and report it as the tool being broken.
		#expect(ToolImageRecipes.resolve(image: "build", forTool: "jdtls") == nil)
	}

	// MARK: - The build

	@Test func theBuildCommandNamesTheImageAndTheContextAndNoPlatform() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		for runtime in [ContainerRuntime.docker("/usr/bin/docker"), .apple("/usr/local/bin/container")] {
			let command = ToolImageRecipes.build(recipe, using: runtime)
			#expect(command.executable == runtime.path)
			#expect(command.arguments == ["build", "-t", recipe.image, recipe.context.path])
			// The saving this whole route is for: one architecture, the
			// machine's own, and nothing said about any other.
			#expect(!command.arguments.contains("--platform"))
		}
	}

	@Test func aFailedBuildSaysWhichOfTheFourThingsHappened() throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		let said = { ToolImageRecipes.explain($0, recipe: recipe) }

		#expect(said("Cannot connect to the Docker daemon at unix:///var/run/docker.sock")
			.contains("runtime is not running"))
		#expect(said("failed to do request: dial tcp: lookup registry-1.docker.io: no such host")
			.contains("network was not there"))
		#expect(said("error: failed to authenticate: unauthorized").contains("refused"))
		#expect(said("write /out: no space left on device").contains("no room"))

		// Anything else is the recipe itself failing, and unlike a published
		// image it is a file somebody can open — so the sentence says where.
		let compiler = said("error: could not compile `openscad-lsp` (lib) due to 3 errors")
		#expect(compiler.contains("could not compile"))
		#expect(compiler.contains("ToolImages/openscad-lsp/Dockerfile"))
	}

	@Test func aBuildIsNotCalledADownload() {
		#expect(ContainerImageStore.Outcome.built.isReady)
		#expect(ContainerImageStore.Outcome.fetched.isReady)
		#expect(ContainerImageStore.Outcome.present.isReady)
		#expect(!ContainerImageStore.Outcome.failed("no").isReady)
		#expect(ContainerImageStore.Outcome.built != .fetched)
	}

	// MARK: - Where somebody chooses it

	@Test func theCatalogueOffersBuildingItHereBesideThePublishedAndCustomOnes() throws {
		let tool = try #require(ToolImageCatalogue.tool(forKey: "openscad-lsp"))
		let values = ToolImageCatalogue.options(for: tool).map(\.value)
		#expect(values.first == ToolImageCatalogue.useInstalled)
		#expect(values.last == ToolImageCatalogue.custom)
		#expect(values.contains(ToolImageRecipes.buildHere))
	}

	@Test func aToolWithNoRecipeIsNotOfferedABuild() throws {
		let tool = try #require(ToolImageCatalogue.tool(forKey: "jdtls"))
		#expect(!ToolImageCatalogue.options(for: tool).map(\.value)
			.contains(ToolImageRecipes.buildHere))
	}

	@Test func aStoredBuildShowsAsBuildRatherThanAsACustomImageCalledBuild() throws {
		let tool = try #require(ToolImageCatalogue.tool(forKey: "openscad-lsp"))
		#expect(ToolImageCatalogue.selection(for: "build", tool: tool) == ToolImageRecipes.buildHere)
		#expect(ToolImageCatalogue.selection(for: "", tool: tool) == ToolImageCatalogue.useInstalled)
		#expect(ToolImageCatalogue.selection(for: "someone/else:1", tool: tool)
			== ToolImageCatalogue.custom)
	}

	// MARK: - And what a project asking for it gets

	@Test func aProjectAskingToBuildTheServerGetsTheBuiltImageAndTheProjectMounted() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write("cube(10);\n", to: root.appendingPathComponent("part.scad"))
		try JavaTestDirectory.write(
			"{\"openscad-lsp\": \"build\"}\n", to: ToolImages.url(in: root)
		)

		let asked = try #require(ToolImages.inProject(root).image(for: "openscad-lsp"))
		#expect(asked == "build")

		let runtime = ContainerRuntime.docker("/usr/bin/docker")
		let resolved = try #require(LanguageServers.resolve(
			languageId: "openscad", project: root, image: asked, runtime: runtime
		))
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))
		let image = try #require(resolved.launch.image)
		#expect(image.name == recipe.image)

		let run = resolved.launch.invocation
		#expect(run.arguments.last == recipe.image)
		// Nothing after the image: `--stdio` is on the entry point, because an
		// argument from this side would arrive after the image's own.
		#expect(!run.arguments.contains("--stdio"))
		let paths = try #require(resolved.launch.paths)
		#expect(paths.container == "/workspace")
	}

	@Test func askingToBuildAServerWithNoRecipeFallsBackToTheCopyInstalledHere() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write("class A {}\n", to: root.appendingPathComponent("A.java"))
		try JavaTestDirectory.write("<project/>\n", to: root.appendingPathComponent("pom.xml"))

		let resolved = LanguageServers.resolve(
			languageId: "java", project: root,
			image: "build", runtime: .docker("/usr/bin/docker")
		)
		// Either nothing — jdtls is not installed on this machine — or the
		// installed copy. What it must never be is a container started from an
		// image whose name this app invented.
		#expect(resolved?.launch.image == nil)
	}
}
