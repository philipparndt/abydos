import Foundation
import Testing
@testable import AbydosKit

/// Getting a tool from an image instead of from the machine.
struct ToolContainerTests {
	/// Apple's first, because it needs no daemon running before it will answer
	/// — the difference between a feature that works and one that says "cannot
	/// connect to the daemon".
	@Test func prefersTheOneThatNeedsNoDaemon() {
		let found = ContainerRuntime.discover(locate: { name in
			["container": "/usr/local/bin/container", "docker": "/usr/bin/docker"][name]
		})
		#expect(found == .apple("/usr/local/bin/container"))
	}

	/// Anything that speaks docker's command line will do, since all of them
	/// take the three flags this needs.
	@Test func fallsBackToWhateverSpeaksDocker() {
		#expect(ContainerRuntime.discover(locate: { $0 == "docker" ? "/usr/bin/docker" : nil })
			== .docker("/usr/bin/docker"))
		#expect(ContainerRuntime.discover(locate: { $0 == "podman" ? "/usr/bin/podman" : nil })
			== .docker("/usr/bin/podman"))
		#expect(ContainerRuntime.discover(locate: { _ in nil }) == nil)
	}

	/// Removed when it stops, and standard input kept open — a renderer reads
	/// its diagram there. No tty: a tty turns output meant for a pipe into
	/// output meant for a terminal.
	@Test func runsOnceAndLeavesNothingBehind() {
		let run = ToolContainer(image: "plantuml/plantuml")
			.invocation(using: .apple("/usr/local/bin/container"), arguments: ["-pipe", "-tpng"])
		#expect(run.executable == "/usr/local/bin/container")
		#expect(run.arguments == ["run", "--rm", "-i", "plantuml/plantuml", "-pipe", "-tpng"])
		#expect(!run.arguments.contains("-t"))
	}

	/// A tool that has to see the project gets it mounted, and read-only where
	/// it has no business writing.
	@Test func showsTheContainerWhatItNeedsToSee() {
		let container = ToolContainer(
			image: "some/language-server",
			command: ["serve"],
			mounts: [ContainerMount(host: "/Users/me/project", container: "/work", isReadOnly: true)],
			workingDirectory: "/work"
		)
		let run = container.invocation(using: .docker("/usr/bin/docker"))
		#expect(run.arguments == [
			"run", "--rm", "-i",
			"-v", "/Users/me/project:/work:ro",
			"-w", "/work",
			"some/language-server", "serve",
		])
	}

	// MARK: - Which image

	@Test func readsEitherShapeOfTheFile() {
		let plain = ToolImages.parse(Data(#"{"plantuml": "plantuml/plantuml:1.2025.4"}"#.utf8))
		#expect(plain.image(for: "plantuml") == "plantuml/plantuml:1.2025.4")

		let table = ToolImages.parse(Data(#"{"plantuml": {"image": "plantuml/plantuml"}}"#.utf8))
		#expect(table.image(for: "plantuml") == "plantuml/plantuml")
	}

	/// A file nobody can read is the same as no file: a broken one must not
	/// stop a project opening.
	@Test func survivesAFileThatMakesNoSense() {
		#expect(ToolImages.parse(Data("not json at all".utf8)).isEmpty)
		#expect(ToolImages.parse(Data("[1, 2, 3]".utf8)).isEmpty)
		#expect(ToolImages.parse(Data(#"{"plantuml": ""}"#.utf8)).isEmpty)
		#expect(ToolImages.parse(Data()).isEmpty)
	}

	/// The project wins: what a checked-in diagram is drawn by is the project's
	/// business, and a personal default must not change how it looks.
	@Test func theProjectOverridesTheSetting() {
		let resolved = ToolImages.resolve(
			project: ToolImages(images: ["plantuml": "plantuml/plantuml:1.2025.4"]),
			settings: ToolImages(images: ["plantuml": "plantuml/plantuml:latest", "gopls": "golang:1.23"])
		)
		#expect(resolved.image(for: "plantuml") == "plantuml/plantuml:1.2025.4")
		// And a setting the project says nothing about still applies.
		#expect(resolved.image(for: "gopls") == "golang:1.23")
	}

	// MARK: - PlantUML through a container

	/// An image that was asked for wins over a local copy: naming one is a
	/// decision about which version draws these diagrams, and a local install
	/// quietly overriding it is how the same file comes to look different on
	/// two machines.
	@Test func aNamedImageBeatsAnInstalledCopy() {
		let tool = PlantUML.discover(
			image: "plantuml/plantuml",
			environment: [:],
			locate: { ["plantuml": "/opt/homebrew/bin/plantuml", "container": "/usr/local/bin/container"][$0] },
			fileExists: { _ in false }
		)
		#expect(tool == .image(ToolContainer(image: "plantuml/plantuml"), .apple("/usr/local/bin/container")))
	}

	/// An image named where nothing can run it is not a PlantUML, and the local
	/// copy is used instead of failing.
	@Test func fallsBackWhenNothingCanRunTheImage() {
		let tool = PlantUML.discover(
			image: "plantuml/plantuml",
			environment: [:],
			locate: { $0 == "plantuml" ? "/opt/homebrew/bin/plantuml" : nil },
			fileExists: { _ in false }
		)
		#expect(tool == .command("/opt/homebrew/bin/plantuml"))
	}

	/// The flags PlantUML needs go to the image, which runs PlantUML as its
	/// entry point. Nothing is mounted: the diagram arrives on standard input.
	@Test func drawsThroughTheImageWithTheSameFlags() {
		let tool = PlantUML.Tool.image(
			ToolContainer(image: "plantuml/plantuml"), .apple("/usr/local/bin/container")
		)
		let run = PlantUML.invocation(for: tool)
		#expect(run.executable == "/usr/local/bin/container")
		#expect(run.arguments == [
			"run", "--rm", "-i", "plantuml/plantuml", "-pipe", "-tpng", "-charset", "UTF-8",
		])
	}
}

/// Which runtime, and which image — both asked rather than guessed.
struct ToolChoiceTests {
	/// Nothing said: Apple's first, since it needs no daemon running before it
	/// will answer.
	@Test func automaticPrefersTheOneWithNoDaemon() {
		let found = ContainerRuntime.discover(preference: .automatic) { name in
			["container": "/usr/local/bin/container", "docker": "/usr/bin/docker"][name]
		}
		#expect(found == .apple("/usr/local/bin/container"))
	}

	/// Somebody who says Docker gets Docker, even where Apple's is installed.
	@Test func aStatedPreferenceIsHonoured() {
		let both: (String) -> String? = { name in
            ["container": "/usr/local/bin/container", "docker": "/usr/bin/docker"][name]
        }
		#expect(ContainerRuntime.discover(preference: .docker, locate: both) == .docker("/usr/bin/docker"))
		#expect(ContainerRuntime.discover(preference: .apple, locate: both) == .apple("/usr/local/bin/container"))
	}

	/// And somebody who says Docker and has none finds none — a problem worth
	/// being told about, not a silent substitution of the other one.
	@Test func aPreferenceIsNotQuietlySubstituted() {
		let onlyApple: (String) -> String? = { $0 == "container" ? "/usr/local/bin/container" : nil }
		#expect(ContainerRuntime.discover(preference: .docker, locate: onlyApple) == nil)

		let onlyDocker: (String) -> String? = { $0 == "docker" ? "/usr/bin/docker" : nil }
		#expect(ContainerRuntime.discover(preference: .apple, locate: onlyDocker) == nil)
	}

	/// The list a settings page offers: the installed copy, the known images,
	/// and naming one yourself.
	@Test func offersTheInstalledCopyTheKnownImagesAndACustomOne() throws {
		let tool = try #require(ToolImageCatalogue.tool(forKey: "plantuml"))
		let options = ToolImageCatalogue.options(for: tool)

		#expect(options.first?.value == ToolImageCatalogue.useInstalled)
		#expect(options.last?.value == ToolImageCatalogue.custom)
		#expect(options.contains { $0.value == "plantuml/plantuml" })
	}

	/// A pinned version is not on the list and is still a real choice: it shows
	/// as custom, with the name in the field beside it, rather than as nothing.
	@Test func anUnknownImageIsCustomRatherThanNothing() throws {
		let tool = try #require(ToolImageCatalogue.tool(forKey: "plantuml"))
		#expect(ToolImageCatalogue.selection(for: "", tool: tool) == ToolImageCatalogue.useInstalled)
		#expect(ToolImageCatalogue.selection(for: "plantuml/plantuml", tool: tool) == "plantuml/plantuml")
		#expect(
			ToolImageCatalogue.selection(for: "ghcr.io/me/plantuml:1.2025.4", tool: tool)
				== ToolImageCatalogue.custom
		)
	}

	/// The language servers are offered, and none of them claims a known-good
	/// image.
	///
	/// The point of that list is that somebody has run the thing. Listing one
	/// nobody has tried would be the failure the list exists to prevent, so
	/// they offer the installed copy and a custom image and nothing else.
	@Test func languageServersAreOfferedWithoutPretendingAboutImages() throws {
		for key in ["gopls", "rust-analyzer", "pyright", "typescript-language-server",
		            "clangd", "jdtls"] {
			let tool = try #require(ToolImageCatalogue.tool(forKey: key), "\(key) is not offered")
			#expect(tool.choices.isEmpty, "\(key) claims an image nobody has run")

			let options = ToolImageCatalogue.options(for: tool)
			#expect(options.first?.value == ToolImageCatalogue.useInstalled)
			#expect(options.last?.value == ToolImageCatalogue.custom)
			#expect(options.count == 2)
		}
	}

	/// And each says the same three things an image has to do, since getting
	/// any of them wrong is a server that starts and never answers.
	@Test func everyLanguageServerSaysWhatItsImageMustDo() throws {
		for key in ["gopls", "rust-analyzer", "clangd"] {
			let tool = try #require(ToolImageCatalogue.tool(forKey: key))
			#expect(tool.requirement.contains("entry point"))
			#expect(tool.requirement.contains("standard input and output"))
			#expect(tool.requirement.contains("/workspace"))
			// The one that is easy to miss: a wrapper printing anything before
			// the protocol starts breaks the first header.
			#expect(tool.requirement.contains("banner"))
		}
	}

	/// What a custom image has to do is written down, not left to be discovered
	/// through an empty pane.
	@Test func saysWhatACustomImageMustProvide() throws {
		let tool = try #require(ToolImageCatalogue.tool(forKey: "plantuml"))
		#expect(tool.requirement.contains("entry point"))
		#expect(tool.requirement.contains("standard input"))
		#expect(tool.requirement.contains("Graphviz"))
	}
}
