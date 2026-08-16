import Foundation
import Testing
@testable import AbydosKit

/// Which `.swift` files are 3D models, and what a run of one said.
///
/// The first half is the decision 0499 turns on: a `.swift` file is not a model
/// because of anything in it, but because the manifest above it says its target
/// depends on Cadova. The second half is read off real output from the spike —
/// the exact line Cadova prints, and the shape of a build that failed.
struct CadovaModelTests {
	/// A package on disk, so the target-to-directory question has something to
	/// answer against. It is a filesystem question and cannot be faked.
	private func makePackage(
		manifest: String, files: [String], in directory: URL
	) throws -> SwiftPackage {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let path = directory.appendingPathComponent("Package.swift")
		try manifest.write(to: path, atomically: true, encoding: .utf8)
		for file in files {
			let url = directory.appendingPathComponent(file)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "import Cadova\n".write(to: url, atomically: true, encoding: .utf8)
		}
		return SwiftPackage.find(in: directory)!
	}

	private func scratch() -> URL {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("cadova-\(UUID().uuidString)")
	}

	// MARK: - Reading the manifest

	/// The spike's own manifest, unchanged: one executable target, no products,
	/// and `dependencies: ["Cadova"]` written the short way.
	@Test func readsTheTargetsDependenciesAndItsPath() {
		let package = SwiftPackage.parse("""
		// swift-tools-version: 6.3
		let package = Package(
			name: "spike",
			dependencies: [
				.package(url: "https://github.com/tomasf/Cadova.git", .upToNextMinor(from: "0.9.0")),
			],
			targets: [
				.executableTarget(
					name: "spike",
					dependencies: ["Cadova"],
					swiftSettings: [.interoperabilityMode(.Cxx)]
				),
			]
		)
		""", manifest: URL(fileURLWithPath: "/pkg/Package.swift"))

		#expect(package.targets.count == 1)
		let target = package.targets[0]
		#expect(target.name == "spike")
		#expect(target.isExecutable)
		#expect(target.dependencies == ["Cadova"])
		#expect(target.path == nil)
		#expect(package.runnableName(for: target) == "spike")
	}

	/// `.product(name: "Cadova", package: "Cadova")` is the other way to write the
	/// same dependency, and it has to come out the same. Every literal in the
	/// argument is collected, which is what makes both spellings work from one
	/// rule — and is why the package name landing in the list is harmless.
	@Test func aProductDependencyIsTheSameDependency() {
		let package = SwiftPackage.parse("""
		let package = Package(
			name: "parts",
			targets: [
				.executableTarget(
					name: "Bracket",
					dependencies: [.product(name: "Cadova", package: "Cadova")]
				),
			]
		)
		""", manifest: URL(fileURLWithPath: "/pkg/Package.swift"))

		#expect(package.targets[0].dependencies.contains(CadovaModel.dependency))
	}

	/// A library target is read as well as an executable one — it has to be, or a
	/// file in it falls through to whichever executable target was declared next.
	/// It is still not runnable.
	@Test func aLibraryTargetIsReadAndIsNotRunnable() {
		let package = SwiftPackage.parse("""
		let package = Package(
			name: "parts",
			targets: [
				.target(name: "Shapes", dependencies: ["Cadova"]),
				.executableTarget(name: "parts", dependencies: ["Shapes", "Cadova"]),
			]
		)
		""", manifest: URL(fileURLWithPath: "/pkg/Package.swift"))

		#expect(package.targets.map(\.name) == ["Shapes", "parts"])
		#expect(package.runnableName(for: package.targets[0]) == nil)
		#expect(package.runnableName(for: package.targets[1]) == "parts")
		// And the library is not offered in the run list, which is what it was
		// before `.target` was read at all.
		#expect(package.executables.map(\.name) == ["parts"])
	}

	/// A `.target(name:)` *inside* another target's dependencies is a reference,
	/// not a declaration, and reading it as one would put a phantom in the list.
	@Test func aTargetDependencyIsNotADeclaration() {
		let package = SwiftPackage.parse("""
		let package = Package(
			name: "parts",
			targets: [
				.executableTarget(name: "parts", dependencies: [.target(name: "Shapes")]),
				.target(name: "Shapes"),
			]
		)
		""", manifest: URL(fileURLWithPath: "/pkg/Package.swift"))

		#expect(package.targets.map(\.name) == ["parts", "Shapes"])
	}

	/// The name `swift run` takes is the product's when a product claims the
	/// target — the finding 0498 measured rather than assumed.
	@Test func theProductClaimingATargetNamesTheRun() {
		let package = SwiftPackage.parse("""
		let package = Package(
			name: "holder",
			products: [
				.executable(name: "hex-holder", targets: ["Holder"]),
			],
			targets: [
				.executableTarget(name: "Holder", dependencies: ["Cadova"]),
			]
		)
		""", manifest: URL(fileURLWithPath: "/pkg/Package.swift"))

		#expect(package.runnableName(for: package.targets[0]) == "hex-holder")
	}

	// MARK: - From a file to its target

	@Test func findsTheTargetAFileBelongsTo() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		let package = try makePackage(
			manifest: """
			let package = Package(
				name: "parts",
				targets: [
					.executableTarget(name: "parts", dependencies: ["Cadova"]),
					.target(name: "Shapes"),
				]
			)
			""",
			files: ["Sources/parts/main.swift", "Sources/parts/holder.swift", "Sources/Shapes/hex.swift"],
			in: root
		)

		let inTarget = root.appendingPathComponent("Sources/parts/holder.swift")
		#expect(package.target(containing: inTarget)?.name == "parts")
		let inLibrary = root.appendingPathComponent("Sources/Shapes/hex.swift")
		#expect(package.target(containing: inLibrary)?.name == "Shapes")
	}

	/// A `path:` argument wins over the layout, and the deepest directory wins
	/// over the one above it.
	@Test func anExplicitPathWinsAndTheDeepestOneWins() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		let package = try makePackage(
			manifest: """
			let package = Package(
				name: "parts",
				targets: [
					.target(name: "Outer", path: "code"),
					.executableTarget(name: "Inner", path: "code/inner", dependencies: ["Cadova"]),
				]
			)
			""",
			files: ["code/shared.swift", "code/inner/main.swift"],
			in: root
		)

		#expect(package.target(containing: root.appendingPathComponent("code/shared.swift"))?.name == "Outer")
		#expect(package.target(containing: root.appendingPathComponent("code/inner/main.swift"))?.name == "Inner")
	}

	// MARK: - Which tabs get a model beside them

	/// **The decision.** A `.swift` in an executable target that depends on Cadova
	/// is a model; the same file in a library target beside it is not, and neither
	/// is the manifest.
	@Test func onlyTheSourcesOfACadovaExecutableTargetAreModels() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		_ = try makePackage(
			manifest: """
			let package = Package(
				name: "parts",
				targets: [
					.executableTarget(name: "parts", dependencies: ["Cadova"]),
					.target(name: "Shapes", dependencies: ["Cadova"]),
					.executableTarget(name: "tool"),
				]
			)
			""",
			files: [
				"Sources/parts/main.swift",
				"Sources/parts/holder.swift",
				"Sources/Shapes/hex.swift",
				"Sources/tool/main.swift",
			],
			in: root
		)

		// Every source of the Cadova executable target, not only the one with
		// `Model(…)` in it: running the target is what makes the shape, and a
		// helper file changes it exactly as much as the entry point does.
		for name in ["main.swift", "holder.swift"] {
			let model = CadovaModel.find(for: root.appendingPathComponent("Sources/parts/\(name)"))
			#expect(model?.product == "parts")
			#expect(model?.packageDirectory.path == root.resolvingSymlinksInPath().path
				|| model?.packageDirectory.path == root.path)
			#expect(model?.command == "swift run parts")
		}

		// A library that uses Cadova is not run, so it has no model to show.
		#expect(CadovaModel.find(for: root.appendingPathComponent("Sources/Shapes/hex.swift")) == nil)
		// An executable that does not use Cadova is a program, not a shape.
		#expect(CadovaModel.find(for: root.appendingPathComponent("Sources/tool/main.swift")) == nil)
		// And the manifest is not one of its own package's models.
		#expect(CadovaModel.find(for: root.appendingPathComponent("Package.swift")) == nil)
	}

	/// A `.swift` outside any package costs one failed walk and answers no.
	@Test func aSwiftFileInNoPackageIsNotAModel() {
		let root = scratch()
		#expect(CadovaModel.find(for: root.appendingPathComponent("stray.swift")) == nil)
	}

	/// The walk up stops where the project does, so a file open from outside a
	/// project cannot be claimed by a manifest further up somebody's home
	/// directory.
	@Test func theWalkUpStopsAtTheProjectRoot() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		_ = try makePackage(
			manifest: """
			let package = Package(
				name: "parts",
				targets: [.executableTarget(name: "parts", dependencies: ["Cadova"])]
			)
			""",
			files: ["Sources/parts/main.swift"],
			in: root
		)
		let file = root.appendingPathComponent("Sources/parts/main.swift")

		#expect(CadovaModel.find(for: file, stoppingAt: root) != nil)
		// Told the project is the target's own directory, the walk never reaches
		// the manifest.
		#expect(CadovaModel.find(
			for: file, stoppingAt: root.appendingPathComponent("Sources/parts")
		) == nil)
	}

	/// What the tab hands `FilePreview`, and what `FilePreview` does with it.
	@Test func aCadovaModelOpensWithTheModelBesideIt() {
		let file = URL(fileURLWithPath: "/pkg/Sources/spike/main.swift")
		#expect(FilePreview.kind(for: file) == nil)
		#expect(FilePreview.availableModes(for: file).isEmpty)

		let known = PreviewFacts(isCadovaModel: true)
		#expect(FilePreview.kind(for: file, facts: known) == .model)
		#expect(FilePreview.defaultMode(for: file, facts: known) == .splitRight)
		// Source somebody types, so every mode is on offer — unlike a mesh.
		#expect(FilePreview.availableModes(for: file, facts: known) == PreviewMode.allCases)
		#expect(FilePreview.restoredMode(.source, for: file, facts: known) == .source)
	}

	/// The fact is about a `.swift` and nothing else. Told yes about a `.md`, the
	/// answer is still markdown's.
	@Test func theFactDoesNotChangeWhatOtherFilesDo() {
		let notes = URL(fileURLWithPath: "/pkg/README.md")
		#expect(FilePreview.kind(for: notes, facts: PreviewFacts(isCadovaModel: true)) == .markdown)
	}

	// MARK: - Reading what a run said

	/// The line Cadova prints, exactly as the spike printed it.
	@Test func readsThePathOutOfWhatTheRunSaid() {
		let said = """
		Building for debugging...
		Build complete! (1.23 sec)
		2026-08-16T11:47:03.368 [INFO] Generating "hexholder"...
		2026-08-16T11:47:03.401 [INFO] Wrote model to /tmp/cadova-spike/hexholder.3mf
		"""
		#expect(CadovaRun.wroteModel(in: said)?.path == "/tmp/cadova-spike/hexholder.3mf")
	}

	/// Two models from one target: the last is the one it finished with.
	@Test func theLastModelWrittenIsTheOneShown() {
		let said = """
		[INFO] Wrote model to /tmp/pkg/base.3mf
		[INFO] Wrote model to /tmp/pkg/lid.3mf
		"""
		#expect(CadovaRun.wroteModel(in: said)?.lastPathComponent == "lid.3mf")
	}

	/// A build that failed says nothing about a model, and must not be read as
	/// having written one somewhere relative.
	@Test func aRunThatWroteNothingHasNoPath() {
		#expect(CadovaRun.wroteModel(in: "error: Build failed\n") == nil)
		#expect(CadovaRun.wroteModel(in: "Wrote model to hexholder.3mf") == nil)
	}

	/// SwiftPM colours its diagnostics down a pipe, measured on this machine, so
	/// the escape codes have to come out before anything is matched or shown.
	@Test func stripsTheColoursSwiftPMWritesToAPipe() {
		let coloured = "\u{1B}[0;36m 5 |\u{1B}[0;0m     let spacing = 8.0 +"
		#expect(CadovaRun.stripped(coloured) == " 5 |     let spacing = 8.0 +")
	}

	/// The complaint is the diagnostics, and the box-drawn source lines under
	/// each one are left out — they are indented, and a narrow pane cannot lay
	/// them out.
	@Test func theComplaintIsTheDiagnosticsAndNotTheWholeBuild() {
		let said = """
		Building for debugging...
		/tmp/spike/Sources/spike/main.swift:5:23: \u{1B}[0;31merror: \u{1B}[0;0mbinary operator '+' cannot be applied
		 \u{1B}[0;36m5 |\u{1B}[0;0m     let spacing = 8.0 +
		   \u{1B}[0;36m|\u{1B}[0;0m                       `- error: binary operator '+' cannot be applied
		Failed frontend command:
		/Applications/Xcode.app/…/swift-frontend -frontend -emit-module …
		error: Build failed
		"""
		let complaint = CadovaRun.complaint(in: said)
		#expect(complaint.contains("main.swift:5:23"))
		#expect(complaint.contains("error: Build failed"))
		#expect(!complaint.contains("swift-frontend"))
		#expect(!complaint.contains("`-"))
	}

	/// Nothing that looks like a diagnostic — a shell that could not find
	/// `swift`, a toolchain that refused the manifest — still has to say
	/// something, because 0498's warning is that "no model appeared" must never
	/// be reported as anything but "read what it said".
	@Test func aSilentFailureShowsWhatWasSaidAnyway() {
		let said = "zsh: command not found: swift"
		#expect(CadovaRun.complaint(in: said) == said)
		#expect(!CadovaRun.complaint(in: "   \n \n").isEmpty)
	}

	/// The fallback for a Cadova that words its line differently: the newest
	/// `.3mf` beside the package, written since the run began.
	@Test func fallsBackToTheNewestModelBesideThePackage() throws {
		let root = scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		let old = root.appendingPathComponent("old.3mf")
		try Data().write(to: old)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: old.path
		)

		let started = Date()
		#expect(CadovaRun.newestModel(in: root, since: started) == nil)

		let fresh = root.appendingPathComponent("fresh.3mf")
		try Data().write(to: fresh)
		#expect(CadovaRun.newestModel(in: root, since: started)?.lastPathComponent == "fresh.3mf")
	}
}
