import Foundation
import Testing
@testable import AbydosKit

/// An export drawn by the real PlantUML, written to a real folder, and read
/// back.
///
/// This is the one thing no rule test can say: that what lands on disk is a
/// picture of the diagram. A PNG of nought bytes and an SVG of an error message
/// both look like success from everywhere except here.
///
/// Skipped unless the image is already on this machine, the way the other live
/// tests are skipped without their server. Fetch it with:
///
///     docker pull plantuml/plantuml
struct DiagramExportLiveTests {
	static let image = "plantuml/plantuml"

	/// Docker only: the kept-warm server is docker only, and this is meant to go
	/// through the same route the app takes.
	private var available: ContainerRuntime? {
		guard let runtime = ContainerRuntime.discover(preference: .docker),
		      case .docker = runtime, holdsImage(runtime)
		else { return nil }
		return runtime
	}

	private func holdsImage(_ runtime: ContainerRuntime) -> Bool {
		let process = Process()
		let command = ContainerImages.inspect(Self.image, using: runtime)
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		// Nowhere rather than into pipes: only the exit status is wanted, and a
		// pipe nobody drains is how a subprocess capture hangs.
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice
		guard (try? process.run()) != nil else { return false }
		let deadline = Date().addingTimeInterval(10)
		while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
		guard !process.isRunning else {
			process.terminate()
			return false
		}
		return process.terminationStatus == 0
	}

	/// The exports, and then the server they started, removed however they went.
	///
	/// The kept server outlives the render that started it — that is the whole
	/// point of it — so it is this test's to remove even when an expectation
	/// throws out of the middle. It used to be removed by *role prefix*:
	/// everything registered in this process called `abydos-plantuml-server-…`.
	/// That is not this test's set. `PlantUMLServerLiveTests` runs beside this one
	/// and keeps a server of its own with the same role and the same pid in its
	/// name, so this cleanup took that suite's container away mid-render, and the
	/// render sat for its whole patience asking a port that had gone. Four runs
	/// out of four, on a quiet machine. 0435 is what that cost.
	///
	/// `stopAll` is the set that is actually this test's: the servers the actor
	/// this test drew through is holding, by name. The per-render export
	/// containers need nothing here — they are `docker run --rm` and `DiagramExport`
	/// releases each one as it finishes with it.
	///
	/// Not a `defer`, because the removal has to be awaited and a defer body may
	/// not await. The failure is carried past it rather than thrown through it.
	@Test func aDiagramIsWrittenBesideItselfAndAnErrorIsNot() async throws {
		guard let runtime = available else { return }
		let folder = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: folder) }

		let outcome: Result<Void, any Error>
		do {
			try await exportEverything(in: folder, using: runtime)
			outcome = .success(())
		} catch {
			outcome = .failure(error)
		}
		await PlantUMLServers.shared.stopAll()
		try outcome.get()
	}

	private func exportEverything(in folder: URL, using runtime: ContainerRuntime) async throws {
		let tool = PlantUML.Tool.image(ToolContainer(image: Self.image), runtime)

		// A picture of the diagram, in the format asked for — which is not the
		// one the preview shows.
		let file = folder.appendingPathComponent("diagram.puml")
		try JavaTestDirectory.write("@startuml\nAlice -> Bob: hello\n@enduml\n", to: file)
		let written = try requireSuccess(
			await DiagramExport.export(source: source(of: file), of: file, format: .png, tool: tool)
		)
		#expect(written.map(\.lastPathComponent) == ["diagram.png"])
		let png = try Data(contentsOf: written[0])
		#expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
		#expect(png.count > 500)
		#expect(DiagramExport.isDrawnByPlantUML(png))

		// The same diagram as a drawing, which is a different file rather than
		// the one on screen renamed.
		let svgWritten = try requireSuccess(
			await DiagramExport.export(source: source(of: file), of: file, format: .svg, tool: tool)
		)
		let svg = String(decoding: try Data(contentsOf: svgWritten[0]), as: UTF8.self)
		#expect(svg.hasPrefix("<svg"))
		#expect(svg.contains("Alice"))
		#expect(!svg.lowercased().contains("syntax error"))

		// Exporting again replaces the picture this drew, because that is what
		// exporting twice means.
		#expect(throwsNothing(
			await DiagramExport.export(source: source(of: file), of: file, format: .png, tool: tool)
		))

		// A diagram that does not parse is a picture of the complaint, and no
		// picture of a complaint is written: the export says which line instead.
		let broken = folder.appendingPathComponent("broken.puml")
		try JavaTestDirectory.write("@startuml\nAlice -> Bob\nnonsense (((\n@enduml\n", to: broken)
		let refused = await DiagramExport.export(
			source: source(of: broken), of: broken, format: .png, tool: tool
		)
		switch refused {
		case .success:
			Issue.record("a diagram that does not parse was exported as though it had")
		case let .failure(failure):
			#expect(failure.message.contains("broken.puml line 3"))
			#expect(!FileManager.default.fileExists(
				atPath: folder.appendingPathComponent("broken.png").path
			))
		}

		// Somebody else's file with an unlucky name is not written over.
		let taken = folder.appendingPathComponent("taken.puml")
		try JavaTestDirectory.write("@startuml\nA -> B\n@enduml\n", to: taken)
		let theirs = Data(repeating: 0x42, count: 1024)
		try theirs.write(to: folder.appendingPathComponent("taken.png"))
		let stopped = await DiagramExport.export(
			source: source(of: taken), of: taken, format: .png, tool: tool
		)
		#expect(isFailure(stopped))
		#expect(try Data(contentsOf: folder.appendingPathComponent("taken.png")) == theirs)

		// A file with two diagrams in it becomes two pictures, named the way
		// PlantUML's own file output names them — and each holds its own
		// diagram rather than both of them merged into one.
		let several = folder.appendingPathComponent("several.puml")
		try JavaTestDirectory.write(
			"@startuml\nAlice -> Bob: one\n@enduml\n@startuml\nCarol -> Dave: two\n@enduml\n",
			to: several
		)
		let pictures = try requireSuccess(
			await DiagramExport.export(
				source: source(of: several), of: several, format: .svg, tool: tool
			)
		)
		#expect(pictures.map(\.lastPathComponent) == ["several.svg", "several_001.svg"])
		let first = String(decoding: try Data(contentsOf: pictures[0]), as: UTF8.self)
		let second = String(decoding: try Data(contentsOf: pictures[1]), as: UTF8.self)
		#expect(first.contains("Alice") && !first.contains("Carol"))
		#expect(second.contains("Carol") && !second.contains("Alice"))

		// It really did go through the kept-warm server rather than falling back
		// to a container per render — which is the route the app takes, and the
		// only reason six pictures take seconds rather than a minute.
		#expect(await PlantUMLServers.shared.images == [Self.image])
	}

	private func source(of url: URL) -> String {
		(try? String(contentsOf: url, encoding: .utf8)) ?? ""
	}

	private func requireSuccess(
		_ outcome: Result<[URL], DiagramExport.Failure>
	) throws -> [URL] {
		switch outcome {
		case let .success(written): return written
		case let .failure(failure): throw failure
		}
	}

	private func throwsNothing(_ outcome: Result<[URL], DiagramExport.Failure>) -> Bool {
		if case .success = outcome { return true }
		return false
	}

	private func isFailure(_ outcome: Result<[URL], DiagramExport.Failure>) -> Bool {
		if case .failure = outcome { return true }
		return false
	}
}
