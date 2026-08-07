import Foundation
import Testing
@testable import AbydosKit

/// Bazel workspaces, read from their build files.
///
/// `bazel query` is the correct way to ask what a workspace holds, and it is
/// also a build-graph load that needs Bazel installed and can take a minute on
/// a large repository. These read what a person reads instead: the rule name
/// and the `name = "…"` beside it.
struct BazelBuildTests {
	private let workspace = URL(fileURLWithPath: "/repo")

	private func targets(_ contents: String, at path: String = "/repo/app/BUILD") -> [BazelBuild.Target] {
		BazelBuild.targets(in: URL(fileURLWithPath: path), contents: contents, workspace: workspace)
	}

	@Test func readsABinaryAndATest() {
		let found = targets("""
		load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_test")

		cc_binary(
		    name = "server",
		    srcs = ["server.cc"],
		    deps = [":lib"],
		)

		cc_test(
		    name = "server_test",
		    srcs = ["server_test.cc"],
		)
		""")

		#expect(found.map(\.label) == ["//app:server", "//app:server_test"])
		#expect(found[0].rule == "cc_binary")
		#expect(!found[0].isTest)
		#expect(found[1].isTest)
	}

	/// A library is a thing to build, not a thing to start. Listing every one
	/// would bury the two or three anybody asks for.
	@Test func leavesLibrariesOut() {
		let found = targets("""
		cc_library(
		    name = "lib",
		    srcs = ["lib.cc"],
		)
		filegroup(name = "data")
		""")
		#expect(found.isEmpty)
	}

	/// The label says where the package is, and a build file at the root is
	/// `//:name` rather than `//:` with an empty path.
	@Test func writesLabelsFromWhereTheFileIs() {
		#expect(targets("go_binary(name = \"tool\")", at: "/repo/BUILD").map(\.label) == ["//:tool"])
		#expect(
			targets("go_binary(name = \"tool\")", at: "/repo/cmd/tool/BUILD.bazel").map(\.label)
				== ["//cmd/tool:tool"]
		)
	}

	/// The line, so a marker can go beside the rule that declared it.
	@Test func saysWhichLineDeclaredIt() {
		let found = targets("""
		# a comment

		py_binary(
		    name = "hello",
		)
		""")
		#expect(found.first?.line == 3)
	}

	/// A commented-out rule is not a target, and neither is `name` inside a
	/// list of sources.
	@Test func ignoresCommentsAndOtherPeoplesNames() {
		let found = targets("""
		# cc_binary(
		#     name = "ghost",
		# )

		sh_binary(
		    srcs = [":name"],
		    name = "real",
		)
		""")
		#expect(found.map(\.label) == ["//app:real"])
	}

	/// An indented call is an argument to something else, and `load` names a
	/// file rather than a target.
	@Test func onlyReadsRulesAtTheMargin() {
		let found = targets("""
		load("@rules_go//go:def.bzl", "go_binary")

		go_binary(
		    name = "outer",
		    x = inner_binary(name = "not_a_target"),
		)
		""")
		#expect(found.map(\.label) == ["//app:outer"])
	}

	/// A rule with no name is not offered: there would be nothing to ask for.
	@Test func skipsARuleWithNoName() {
		#expect(targets("cc_binary(\\n    srcs = [\"a.cc\"],\\n)").isEmpty)
	}

	/// `run` for a binary, `test` for a test — Bazel's own verbs.
	@Test func usesBazelsOwnVerbs() {
		let binary = BazelBuild.Target(rule: "go_binary", label: "//app:server", file: workspace, line: 1)
		#expect(BazelBuild.command(for: binary) == ("bazel", ["run", "//app:server"]))

		let test = BazelBuild.Target(rule: "go_test", label: "//app:server_test", file: workspace, line: 1)
		#expect(BazelBuild.command(for: test) == ("bazel", ["test", "//app:server_test"]))
	}

	/// The workspace is the nearest directory above with a marker in it —
	/// bzlmod's or the old one.
	@Test func findsTheWorkspaceAbove() {
		let present: Set<String> = ["/repo/MODULE.bazel"]
		let found = BazelBuild.workspaceRoot(for: URL(fileURLWithPath: "/repo/app/server")) {
			present.contains($0)
		}
		#expect(found?.path == "/repo")
	}

	@Test func findsNoWorkspaceWhereThereIsNone() {
		#expect(BazelBuild.workspaceRoot(for: URL(fileURLWithPath: "/elsewhere/app")) { _ in false } == nil)
	}
}

/// Conan packages: a package manager, so commands rather than targets.
struct ConanProjectTests {
	@Test func aRecipeCanDoEverythingAndAListOfRequirementsCannot() {
		let recipe = ConanProject.recipe(URL(fileURLWithPath: "/p/conanfile.py"))
		#expect(recipe.actions == [.install, .build, .create, .test])

		// A conanfile.txt says what to fetch and holds no recipe, so build and
		// create would be offering an error message.
		let requirements = ConanProject.requirements(URL(fileURLWithPath: "/p/conanfile.txt"))
		#expect(requirements.actions == [.install])
	}

	/// The recipe wins where both are present: that is the project, and the
	/// text file beside it is usually for the examples.
	@Test func prefersTheRecipe() {
		let found = ConanProject.find(in: URL(fileURLWithPath: "/p")) { path in
			path.hasSuffix("conanfile.py") || path.hasSuffix("conanfile.txt")
		}
		#expect(found == .recipe(URL(fileURLWithPath: "/p/conanfile.py")))

		let onlyText = ConanProject.find(in: URL(fileURLWithPath: "/p")) {
			$0.hasSuffix("conanfile.txt")
		}
		#expect(onlyText == .requirements(URL(fileURLWithPath: "/p/conanfile.txt")))
		#expect(ConanProject.find(in: URL(fileURLWithPath: "/p")) { _ in false } == nil)
	}

	/// Conan 2's spelling, with `--build=missing` — a dependency with no binary
	/// for this platform is the ordinary case on an ARM Mac, and building it is
	/// what somebody was going to do next anyway.
	@Test func usesConanTwosCommands() {
		let project = ConanProject.recipe(URL(fileURLWithPath: "/p/conanfile.py"))
		#expect(project.command(for: .install) == ("conan", ["install", ".", "--build=missing"]))
		#expect(project.command(for: .build) == ("conan", ["build", "."]))
		#expect(project.command(for: .create) == ("conan", ["create", ".", "--build=missing"]))
		#expect(project.command(for: .test) == ("conan", ["test", "test_package", "."]))
	}

	/// It runs where the file is.
	@Test func runsBesideTheConanfile() {
		#expect(
			ConanProject.recipe(URL(fileURLWithPath: "/p/pkg/conanfile.py")).directory.path == "/p/pkg"
		)
	}

	/// The name is read, not executed: running a recipe to fill in a menu means
	/// running somebody's build script to fill in a menu.
	@Test func readsThePackageNameFromTheRecipe() {
		#expect(ConanProject.packageName(inRecipe: """
		from conan import ConanFile

		class FmtConan(ConanFile):
		    name = "fmt"
		    version = "10.2.1"
		""") == "fmt")

		#expect(ConanProject.packageName(inRecipe: "class X(ConanFile):\\n    pass") == nil)
	}
}

/// The two of them as the app finds them: real files on disk, discovered the
/// way a project being opened discovers everything else.
struct BazelConanDiscoveryTests {
	@Test func findsWhatIsInAWorkspaceOnDisk() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-bazel-\(UUID().uuidString)")
		let package = root.appendingPathComponent("cmd/server")
		try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		try "module(name = \"example\")".write(
			to: root.appendingPathComponent("MODULE.bazel"), atomically: true, encoding: .utf8
		)
		try """
		cc_binary(
		    name = "server",
		    srcs = ["server.cc"],
		)

		cc_test(name = "server_test")

		cc_library(name = "lib")
		""".write(to: package.appendingPathComponent("BUILD.bazel"), atomically: true, encoding: .utf8)

		try """
		from conan import ConanFile

		class ExampleConan(ConanFile):
		    name = "example"
		""".write(to: root.appendingPathComponent("conanfile.py"), atomically: true, encoding: .utf8)

		let found = RunConfigurationDiscovery.discover(in: root)

		let bazel = found.filter { $0.source == .bazel }
		let names: [String] = bazel.map(\.name)
		#expect(names == ["//cmd/server:server", "//cmd/server:server_test"])
		#expect(bazel.first?.executable == "bazel")
		#expect(bazel.first?.arguments == ["run", "//cmd/server:server"])
		// Run from the workspace, which is where labels resolve from.
		#expect(bazel.first?.workingDirectory == FilePath.canonical(root))
		#expect(bazel.last?.arguments.first == "test")

		let conan = found.filter { $0.source == .conan }
		#expect(conan.count == 4)
		// Named after the package, so two in one repository are told apart.
		#expect(conan.allSatisfy { $0.name.contains("(example)") })
		#expect(conan.contains { $0.arguments == ["install", ".", "--build=missing"] })
	}

	/// A directory with neither offers neither, rather than an empty group.
	@Test func findsNothingWhereThereIsNothing() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-empty-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let found = RunConfigurationDiscovery.discover(in: root)
		#expect(!found.contains { $0.source == .bazel || $0.source == .conan })
	}
}
