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
