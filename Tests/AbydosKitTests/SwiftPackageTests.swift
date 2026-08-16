import Foundation
import Testing
@testable import AbydosKit

/// Swift packages, read from their manifests.
///
/// `swift package dump-package` is the correct way to ask what a package holds,
/// and it is also a compile-and-run of somebody's build script that takes the
/// better part of a second, leaves a `.build` directory behind, and answers with
/// whichever `swift` is on the PATH. These read what a person reads: the
/// `name:` beside the declaration.
struct SwiftPackageManifestTests {
	private func parse(_ text: String) -> SwiftPackage {
		SwiftPackage.parse(text, manifest: URL(fileURLWithPath: "/pkg/Package.swift"))
	}

	/// The name in the list has to be the *product's*. SwiftPM answers
	/// `error: no executable product named 'AlphaTarget'` when handed the
	/// target's, which was measured rather than assumed.
	@Test func namesTheProductAndNotTheTargetItWraps() {
		let package = parse("""
		// swift-tools-version: 6.0
		import PackageDescription

		let package = Package(
			name: "twoexec",
			products: [
				.executable(name: "alpha-tool", targets: ["AlphaTarget"]),
			],
			targets: [
				.executableTarget(name: "AlphaTarget"),
			]
		)
		""")

		#expect(package.executables.map(\.name) == ["alpha-tool"])
		#expect(package.executables.first?.line == 7)
	}

	/// An executable target no product claims gets an implicit product of its
	/// own name, so it is runnable — under that name.
	@Test func anUnclaimedExecutableTargetIsRunnableUnderItsOwnName() {
		let package = parse("""
		let package = Package(
			name: "twoexec",
			products: [
				.executable(name: "alpha-tool", targets: ["AlphaTarget"]),
			],
			targets: [
				.executableTarget(name: "AlphaTarget"),
				.executableTarget(name: "beta"),
				.testTarget(name: "twoexecTests"),
			]
		)
		""")

		#expect(package.executables.map(\.name) == ["alpha-tool", "beta"])
		#expect(package.testLine == 9)
	}

	/// A manifest with no products at all: every executable target is one.
	@Test func aPackageThatDeclaresNoProducts() {
		let package = parse("""
		let package = Package(
			name: "spike",
			targets: [
				.executableTarget(
					name: "spike",
					dependencies: ["Cadova"],
					swiftSettings: [.interoperabilityMode(.Cxx)]
				),
			]
		)
		""")

		#expect(package.executables == [SwiftPackage.Executable(name: "spike", line: 4)])
		#expect(package.testLine == nil)
	}

	/// A library package offers nothing, rather than an empty group.
	@Test func aLibraryPackageOffersNothing() {
		let package = parse("""
		let package = Package(
			name: "kit",
			products: [.library(name: "Kit", targets: ["Kit"])],
			targets: [.target(name: "Kit")]
		)
		""")

		#expect(package.executables.isEmpty)
		#expect(package.testLine == nil)
	}

	/// The reason this is a scanner and not a regular expression. A commented
	/// target is a target somebody took out, and putting it in the run list
	/// would be reading the one line of the file that says "not this".
	@Test func aCommentedOutTargetIsNotOffered() {
		let package = parse("""
		let package = Package(
			name: "pkg",
			targets: [
				.executableTarget(name: "real"),
				// .executableTarget(name: "retired"),
				/* .executableTarget(name: "also-retired"), */
			]
		)
		""")

		#expect(package.executables.map(\.name) == ["real"])
	}

	/// The other half of the same reason: every dependency URL contains `//`,
	/// and a scanner that treated it as a comment would lose the rest of the
	/// line — and with it the targets that follow on it.
	@Test func aDependencyURLIsNotACommentAndDoesNotSwallowTheLine() {
		let package = parse("""
		let package = Package(
			name: "pkg",
			dependencies: [.package(url: "https://github.com/tomasf/Cadova.git", from: "0.9.0")],
			targets: [.executableTarget(name: "spike"), .testTarget(name: "spikeTests")]
		)
		""")

		#expect(package.executables.map(\.name) == ["spike"])
		#expect(package.testLine == 4)
	}

	/// A name that is computed is a name this cannot know. Dropping it loses an
	/// entry; guessing at it produces one that does not run.
	@Test func aNameThatIsNotALiteralIsLeftOut() {
		let package = parse("""
		let prefix = "abydos-"
		let package = Package(
			name: "pkg",
			targets: [
				.executableTarget(name: "\\(prefix)hook"),
				.executableTarget(name: "plain"),
			]
		)
		""")

		#expect(package.executables.map(\.name) == ["plain"])
	}

	/// The manifest of the repository this test is in: four executable products
	/// with names that are not their targets', beside two libraries and a pile
	/// of computed grammar targets. A real multi-executable manifest, which is
	/// the case worth having a test for and the joke item 0498 was filed on.
	@Test func readsTheManifestOfTheProjectThisIs() throws {
		let manifest = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // AbydosKitTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // the repository
			.appendingPathComponent("Package.swift")
		let package = try #require(
			SwiftPackage.find(in: manifest.deletingLastPathComponent())
		)

		// Exactly the executable products, in the order the manifest writes
		// them — and none of `AbydosHook`, `AbydosBacklog` or `FireBench`,
		// which are the targets behind three of them and are not what
		// `swift run` takes.
		#expect(package.executables.map(\.name) == ["Abydos", "abydos-hook", "abydos-backlog", "firebench"])
		#expect(package.testLine != nil)

		// Every line points at the declaration it was read from, so the gutter
		// can put a play button beside it.
		let lines = try String(contentsOf: manifest, encoding: .utf8).components(separatedBy: "\n")
		for executable in package.executables {
			#expect(lines[executable.line - 1].contains("\"\(executable.name)\""))
		}
	}
}

/// What a project holding a Swift package offers to run.
struct SwiftPackageRunConfigurationTests {
	/// A package in a subdirectory, which is the shape `searchDirectories`
	/// exists for and the shape a monorepo has.
	private func makeProject(tests: Bool = true) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-swiftpm-\(UUID().uuidString)")
		let package = root.appendingPathComponent("tools")
		try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

		try """
		// swift-tools-version: 6.0
		import PackageDescription

		let package = Package(
			name: "tools",
			products: [
				.executable(name: "alpha-tool", targets: ["AlphaTarget"]),
			],
			targets: [
				.executableTarget(name: "AlphaTarget"),
				.executableTarget(name: "beta"),
		\(tests ? "\t\t.testTarget(name: \"toolsTests\")," : "")
			]
		)
		""".write(to: package.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		return root
	}

	@Test func everyExecutableProductIsSomethingToRun() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .swiftPackage }
		#expect(Set(found.map(\.name)) == [
			"swift run alpha-tool (tools)",
			"swift run beta (tools)",
			"swift test (tools)",
		])
		#expect(found.allSatisfy { $0.executable == "swift" })
		#expect(found.contains { $0.arguments == ["run", "alpha-tool"] })
	}

	/// Where the output of a run lands. Item 0499 depends on this: Cadova
	/// writes its model beside the package, so the package root is the answer
	/// and not the project root above it.
	@Test func itRunsInThePackageRoot() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .swiftPackage }
		#expect(!found.isEmpty)
		#expect(found.allSatisfy {
			$0.workingDirectory == FilePath.canonical(root.appendingPathComponent("tools"))
		})
	}

	/// The play button in the gutter of the manifest, on the line that declares
	/// the thing it starts.
	@Test func eachOneNamesTheLineOfTheManifestThatDeclaresIt() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .swiftPackage }
		#expect(found.allSatisfy { $0.file?.hasSuffix("tools/Package.swift") == true })
		#expect(found.first { $0.name.hasPrefix("swift run alpha-tool") }?.line == 7)
		#expect(found.first { $0.name.hasPrefix("swift run beta") }?.line == 11)
	}

	/// A package with no test target is not offered a `swift test` that would
	/// find nothing to run.
	@Test func aPackageWithoutTestsIsNotOfferedSwiftTest() throws {
		let root = try makeProject(tests: false)
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .swiftPackage }
		#expect(!found.isEmpty)
		#expect(!found.contains { $0.name.hasPrefix("swift test") })
	}

	/// `swift test` is a run and never a saved configuration, which is the rule
	/// this list has always had about tests. It falls out of `isTest` rather
	/// than needing anything said about SwiftPM in particular — which is worth
	/// a test, because it is the whole reason adding the kind was safe.
	@Test func swiftTestIsATestRunAndSwiftRunIsNot() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .swiftPackage }
		let test = try #require(found.first { $0.name.hasPrefix("swift test") })
		let run = try #require(found.first { $0.name.hasPrefix("swift run alpha") })

		#expect(RunConfigurationDiscovery.isTest(test))
		#expect(!RunConfigurationDiscovery.isTest(run))
		// Nothing here can be handed to Delve or to a JVM debugger.
		#expect(!test.isDebuggable)
		#expect(!run.isDebuggable)
	}

	/// A package written after the project was opened has to appear without the
	/// project being reopened — and a save of an ordinary Swift file must not
	/// put the whole search through, which is the fault 0446 measured.
	@Test func aManifestIsWorthRescanningForAndAnOrdinarySourceIsNot() {
		#expect(RunConfigurationDiscovery.couldDefineConfiguration(
			URL(fileURLWithPath: "/repo/tools/Package.swift")))
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			URL(fileURLWithPath: "/repo/Sources/Kit/Thing.swift")))
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			URL(fileURLWithPath: "/repo/Package.resolved")))
	}

	/// A package's own dependencies are checked out under `.build`, each with a
	/// manifest of its own. None of them is this project's to run.
	@Test func theDependenciesUnderDotBuildAreNotOffered() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let checkout = root.appendingPathComponent("tools/.build/checkouts/Cadova")
		try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
		try """
		let package = Package(name: "Cadova", targets: [.executableTarget(name: "cadova-cli")])
		""".write(to: checkout.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .swiftPackage }
		#expect(!found.contains { $0.name.contains("cadova-cli") })
	}
}
