import Foundation
import Testing
@testable import AbydosKit

/// Against `cadova-models` in the examples repository: a real Swift package,
/// with real executables, that really writes a 3MF.
///
/// 0498 settled what a Swift package offers by reading manifests written into
/// the test — which is the right way to settle a parser and cannot say whether
/// the names it produces are the names SwiftPM answers to. This is the other
/// half: one package on disk, built and run, whose two executables are spelled
/// the two ways a package can spell one — `hex-key-holder` is a product whose
/// target is `HexKeyHolder`, and `coaster` is a bare executable target that no
/// product claims.
///
/// Skipped, like everything else that wants the examples, when
/// `../abydos-examples` is not beside this checkout.
///
/// **The building is on the other side of a line, and the line is not the
/// skip.** Reading the manifest costs nothing and runs whenever the fixture is
/// there. A cold build of this package is 65 seconds and seven packages off the
/// network, and a machine with the examples beside it is the ordinary case
/// rather than the exceptional one — so "skips when the repository is absent"
/// would have put a minute of downloads in `make test` for everybody who has
/// one. `runsAndWritesAThreeMF` therefore asks the same question
/// `BuiltToolImageLiveTests` asks about an image it would have to build: it
/// runs when the package is already built, and otherwise only when it is asked
/// for by name.
///
///     ABYDOS_BUILD_EXAMPLES=1 xcrun swift test --filter CadovaExampleLiveTests
///
/// One run of that builds it; every run afterwards takes about three seconds.
@Suite(.serialized) struct CadovaExampleLiveTests {
	/// The package, when the examples repository is beside this checkout.
	private var package: URL? {
		guard let examples = ExampleProjects.root else { return nil }
		let directory = examples.appendingPathComponent("cadova-models")
		guard FileManager.default.fileExists(
			atPath: directory.appendingPathComponent("Package.swift").path
		) else { return nil }
		return directory
	}

	// MARK: - What the manifest says, which costs nothing

	/// The claim the run list depends on, against the manifest as committed.
	///
	/// The two names here are the fixture's whole reason for existing: a run
	/// list that offers `HexKeyHolder` is offering something `swift run`
	/// refuses, and only a real package can catch that.
	@Test func theExampleOffersTwoExecutablesSpelledTwoDifferentWays() throws {
		guard let package else { return }

		let read = try #require(SwiftPackage.find(in: package))
		// **The two spellings are the claim; the list is not.** This asked for
		// the whole list in order, so the examples repository gaining a third
		// model — which is what an examples repository is for — failed a test
		// about how names are spelt. What matters is that both of these are
		// offered, and how.
		#expect(read.executables.map(\.name).contains("hex-key-holder"))
		#expect(read.executables.map(\.name).contains("coaster"))
		// A product's name and a bare target's, and not the target the product
		// wraps — which is the one SwiftPM will not answer to.
		#expect(!read.executables.contains { $0.name == "HexKeyHolder" })
		// No test target in this package, so nothing offers a `swift test` that
		// would find nothing to run.
		#expect(read.testLine == nil)
		// Where a run of either of them starts, and so where the 3MF lands.
		#expect(read.directory.lastPathComponent == "cadova-models")

		// Pinned, and the pins committed. Cadova is below 1.0 and keeps its API
		// only within a minor version, so an unpinned example is an example
		// with a date on it.
		let manifest = try String(contentsOf: read.manifest, encoding: .utf8)
		#expect(manifest.contains(".upToNextMinor(from:"))
		#expect(FileManager.default.fileExists(
			atPath: package.appendingPathComponent("Package.resolved").path
		))
	}

	// MARK: - And what it writes, which costs a build

	/// Both executables, run the way the run list runs them, and the 3MF each
	/// one leaves behind.
	@Test func runsAndWritesAThreeMF() throws {
		guard let package, mayBuild(in: package) else { return }

		let models = package.appendingPathComponent("Models")
		for executable in ["hex-key-holder", "coaster"] {
			let written = models.appendingPathComponent("\(executable).3mf")
			try? FileManager.default.removeItem(at: written)

			let (status, output) = swift(["run", "-j", "4", executable], in: package)
			#expect(status == 0, "swift run \(executable) exited \(status): \(output)")

			// 3MF is a zip with a model part in it, and the four bytes that say
			// so are the cheapest thing that distinguishes a model from an empty
			// file somebody's `open` created.
			let data = try #require(
				try? Data(contentsOf: written),
				"nothing at \(written.path) — \(output)"
			)
			#expect(data.count > 1000)
			#expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04], "not a zip")
		}
	}

	// MARK: - Running swift

	/// Whether this run may build: already built, or asked for by name.
	///
	/// `.build/debug/coaster` rather than `.build` itself, which `swift package
	/// resolve` alone is enough to create.
	private func mayBuild(in package: URL) -> Bool {
		if ProcessInfo.processInfo.environment["ABYDOS_BUILD_EXAMPLES"] != nil { return true }
		return FileManager.default.fileExists(
			atPath: package.appendingPathComponent(".build/debug/coaster").path
		)
	}

	/// `xcrun swift`, and not whichever `swift` is first on the `PATH`.
	///
	/// The same reason the Makefile pins it and `XcodeToolchain` exists: a
	/// version manager's Swift is a release behind, and this manifest is
	/// `swift-tools-version: 6.3`, which one release back cannot read at all.
	private func swift(_ arguments: [String], in directory: URL) -> (Int32, String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["swift"] + arguments
		process.currentDirectoryURL = directory
		// **The same thing the preview pane says to its own runs**, and for the
		// same reason: Cadova reveals what it writes, and a suite that opened a
		// Finder window per model would be a suite nobody runs twice. The
		// examples used to say it from inside the model; upstream reads
		// `CADOVA_REVEAL_FILES` now, so it is said by whoever starts the run —
		// here, that is this.
		process.environment = CadovaModel.runEnvironment()
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		process.standardInput = FileHandle.nullDevice

		guard (try? process.run()) != nil else { return (-1, "xcrun did not start") }
		let data = ProcessPipes.drain(process, out: pipe)
		process.waitUntilExit()
		return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
	}
}
