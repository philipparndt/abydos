import Foundation
import Testing
@testable import AbydosKit

/// What a Java project holds, and what the JVMs on this machine are.
struct JavaToolingTests {
	@Test func readsJavasTwoVersionSpellings() {
		#expect(JavaTooling.featureVersion(ofVersionString: "21.0.12") == 21)
		#expect(JavaTooling.featureVersion(ofVersionString: "17") == 17)
		// Everything before 9 numbered itself 1.x, and those JDKs are still in
		// service.
		#expect(JavaTooling.featureVersion(ofVersionString: "1.8.0_402") == 8)
		#expect(JavaTooling.featureVersion(ofVersionString: "nonsense") == nil)
	}

	/// jdtls wants Eclipse's name for an execution environment, and ignores
	/// anything else without saying so.
	@Test func namesExecutionEnvironmentsTheWayEclipseDoes() {
		#expect(JavaTooling.environmentName(forVersion: 21) == "JavaSE-21")
		#expect(JavaTooling.environmentName(forVersion: 8) == "JavaSE-1.8")
	}

	@Test func findsAMainMethodHoweverItIsWritten() {
		#expect(JavaTooling.mainMethodLine(in: """
		package com.example;

		public class Server {
			public static void main(String[] args) {
			}
		}
		""") == 4)

		// The modifiers come in any order the language allows.
		#expect(JavaTooling.mainMethodLine(in: "static public void main(String... args) {") == 1)
		// A varargs spelling is still a main method.
		#expect(JavaTooling.mainMethodLine(in: "public static void main(String[] a) {") == 1)
		// And Kotlin's is a top-level function.
		#expect(JavaTooling.mainMethodLine(in: "fun main() {\n}", isKotlin: true) == 1)
	}

	@Test func isNotFooledByCommentsOrOtherMethods() {
		#expect(JavaTooling.mainMethodLine(in: """
		public class Library {
			// public static void main(String[] args) — removed
			public void run(String[] args) {
			}
			public static void mainly(int x) {
			}
		}
		""") == nil)
	}

	@Test func readsThePackageDeclaration() {
		#expect(JavaTooling.packageName(in: "package com.example.api;\n\nclass X {}") == "com.example.api")
		#expect(JavaTooling.packageName(in: "package com.example.api; // the API") == "com.example.api")
		#expect(JavaTooling.packageName(in: "class X {}") == nil)
	}

	/// Kotlin compiles a file's top-level code into a class named after the
	/// file, which is the name the JVM has to be given.
	@Test func namesKotlinsGeneratedClass() {
		#expect(JavaTooling.typeName(of: URL(fileURLWithPath: "/p/App.kt"), source: "fun main() {}") == "AppKt")
		#expect(JavaTooling.typeName(
			of: URL(fileURLWithPath: "/p/App.kt"),
			source: "@file:JvmName(\"Application\")\nfun main() {}"
		) == "Application")
		#expect(JavaTooling.typeName(of: URL(fileURLWithPath: "/p/App.java"), source: "") == "App")
	}

	@Test func findsMainClassesInAProject() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write("<project/>", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write("""
		package com.example.api;

		public class Server {
			public static void main(String[] args) {
				System.out.println("up");
			}
		}
		""", to: root.appendingPathComponent("src/main/java/com/example/api/Server.java"))
		// A test with a main method in it is not something to offer running.
		try JavaTestDirectory.write("""
		package com.example.api;
		public class ServerTest {
			public static void main(String[] args) {}
		}
		""", to: root.appendingPathComponent("src/test/java/com/example/api/ServerTest.java"))
		// Nor is a class file left in target/.
		try JavaTestDirectory.write("""
		public class Stale { public static void main(String[] args) {} }
		""", to: root.appendingPathComponent("target/generated/Stale.java"))

		let found = JavaTooling.mainClasses(in: root)
		#expect(found.map(\.name) == ["com.example.api.Server"])
		#expect(found.first?.line == 4)
		#expect(found.first?.simpleName == "Server")
		#expect(found.first.map { FilePath.canonical(URL(fileURLWithPath: $0.module)) }
			== FilePath.canonical(root))
	}

	/// A prefilter that rejects a file the real test would have accepted is a
	/// main class that stops being offered, so this is the property that matters
	/// rather than any particular speed.
	@Test func theBytePrefilterAcceptsEverySpellingOfAMainMethod() {
		let java = [
			"public static void main(String[] args) {",
			"static public void main(String... args) {",
			"public static void main(String[] a) {",
			"\tpublic static final void main(String[] args) throws Exception {",
		]
		for line in java {
			// Whatever the prefilter does, it must not disagree with the test it
			// stands in front of.
			#expect(JavaTooling.mainMethodLine(in: line) != nil)
			#expect(JavaTooling.contains("main(", in: Data(line.utf8)))
		}

		// Kotlin, where the declaration may carry a space before the paren.
		for line in ["fun main() {", "fun main (args: Array<String>) {"] {
			#expect(JavaTooling.mainMethodLine(in: line, isKotlin: true) != nil)
			#expect(JavaTooling.contains("fun main", in: Data(line.utf8)))
		}

		// And it does reject: a file with no candidate in it at all is the case
		// worth being fast for, since almost every file is that case.
		#expect(!JavaTooling.contains("main(", in: Data("class Library { void run() {} }".utf8)))
		#expect(!JavaTooling.contains("main(", in: Data()))
	}

	/// The anchor names a module, so any source file in the module will do — and
	/// finding one must not cost a walk of the repository.
	@Test func findsAnAnchorInAModuleWithNoMainClassInIt() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		let module = root.appendingPathComponent("services/api")
		try JavaTestDirectory.write("<project/>", to: module.appendingPathComponent("pom.xml"))
		// No `main` anywhere in it. The old anchor search would have found
		// nothing here and fallen back to whatever else the repository held.
		try JavaTestDirectory.write(
			"package api;\npublic class Service {}\n",
			to: module.appendingPathComponent("src/main/java/api/Service.java")
		)
		// A test source is not an anchor: it is in a different jdtls source root
		// and answers about a different classpath.
		try JavaTestDirectory.write(
			"package api;\npublic class ServiceTest {}\n",
			to: module.appendingPathComponent("src/test/java/api/ServiceTest.java")
		)

		let found = JavaTooling.nearestJavaFile(to: module, under: root)
		#expect(found?.hasSuffix("src/main/java/api/Service.java") == true)
	}

	/// A configuration whose directory is the repository root still gets an
	/// answer, and the module's own source beats a loose one at the top.
	@Test func prefersASourceInsideAModuleToOneLyingAtTheRoot() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write(
			"public class Loose {}\n", to: root.appendingPathComponent("Loose.java")
		)
		try JavaTestDirectory.write(
			"package api;\npublic class Service {}\n",
			to: root.appendingPathComponent("api/src/main/java/api/Service.java")
		)

		let found = JavaTooling.nearestJavaFile(to: root, under: root)
		#expect(found?.hasSuffix("api/src/main/java/api/Service.java") == true)
	}

	/// The budget is the only thing standing between a root-level configuration
	/// and the whole-repository walk this replaced.
	@Test func stopsLookingForAnAnchorOnceItsBudgetIsSpent() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write(
			"public class Deep {}\n",
			to: root.appendingPathComponent("a/b/c/Deep.java")
		)

		// One directory read reaches `a/` and no further.
		#expect(JavaTooling.firstJavaFile(under: root, limit: 1) == nil)
		#expect(JavaTooling.firstJavaFile(under: root, limit: 40) != nil)
	}

	/// Concurrent askers join one scan. Both spellings return the same list, so
	/// the count of scans started is the only thing that can tell them apart.
	@Test func sharesOneScanBetweenCallersInsteadOfRepeatingIt() async throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write(
			"package api;\npublic class Server {\n\tpublic static void main(String[] a) {}\n}\n",
			to: root.appendingPathComponent("src/main/java/api/Server.java")
		)

		let before = await MainClassCache.shared.scansStarted(for: root)
		let results = await withTaskGroup(of: Int.self) { group in
			for _ in 0..<4 {
				group.addTask { await JavaTooling.mainClassesOffMain(in: root).count }
			}
			var counts: [Int] = []
			for await count in group { counts.append(count) }
			return counts
		}
		let after = await MainClassCache.shared.scansStarted(for: root)

		#expect(results == [1, 1, 1, 1])
		#expect(after - before == 1)
	}

	/// A kept answer is only as good as the tree it was read from.
	@Test func forgetsAProjectsScanWhenAskedTo() async throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write(
			"package api;\npublic class One {\n\tpublic static void main(String[] a) {}\n}\n",
			to: root.appendingPathComponent("src/main/java/api/One.java")
		)
		#expect(await JavaTooling.mainClassesOffMain(in: root).count == 1)

		try JavaTestDirectory.write(
			"package api;\npublic class Two {\n\tpublic static void main(String[] a) {}\n}\n",
			to: root.appendingPathComponent("src/main/java/api/Two.java")
		)
		// Still one: the answer is kept, which is the point of keeping it.
		#expect(await JavaTooling.mainClassesOffMain(in: root).count == 1)

		await JavaTooling.forgetMainClasses(in: root)
		#expect(await JavaTooling.mainClassesOffMain(in: root).count == 2)
	}

	/// Two checkouts of the same repository must not share an index, or one
	/// project's answers are served for the other.
	@Test func givesEveryProjectItsOwnServerWorkspace() {
		let one = JavaTooling.serverWorkspace(for: URL(fileURLWithPath: "/work/api"))
		let two = JavaTooling.serverWorkspace(for: URL(fileURLWithPath: "/other/api"))
		#expect(one != two)
		#expect(one.lastPathComponent.hasPrefix("api-"))
		// Stable across calls, or every restart would index from scratch.
		#expect(one == JavaTooling.serverWorkspace(for: URL(fileURLWithPath: "/work/api")))
	}

	@Test func knowsWhatABuildFileIs() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(!JavaTooling.isJavaProject(root))
		try JavaTestDirectory.write("<project/>", to: root.appendingPathComponent("pom.xml"))
		#expect(JavaTooling.isJavaProject(root))
		#expect(JavaTooling.buildFile(in: root)?.lastPathComponent == "pom.xml")
	}

	// MARK: - Which module the classpath is asked about

	/// **The anchor chooses the answer.** jdtls answers
	/// `java.project.getClasspaths` about the module the file belongs to, so
	/// taking the project's first main class made a thousand-module repository
	/// resolve whichever the directory walk reached first.
	///
	/// The case measured: a launch configuration for the Eclipse client, whose
	/// working directory is an assembly module holding one pom and no Java at all,
	/// was handed `cli/com.vector.acli.application`'s classpath.
	@Test func theAnchorIsChosenNearTheLaunchsOwnDirectory() {
		let root = "/repo"
		let client = "\(root)/almplus/client/maven.assembly.com.vector.almplus.client"
		let candidates = [
			"\(root)/cli/com.vector.acli.application/src/main/java/com/vector/acli/CliApplication.java",
			"\(root)/almplus/client/core/com.vector.almplus.client.core.base/src/main/java/com/vector/Base.java",
		]

		// The assembly module has no Java of its own, so nearness has to carry it:
		// two shared components under almplus/client beats none under cli.
		#expect(
			JavaTooling.nearestFile(to: client, among: candidates)?.contains("client.core.base") == true
		)
		// And a launch rooted in the CLI still gets the CLI.
		#expect(
			JavaTooling.nearestFile(
				to: "\(root)/cli/com.vector.acli.application", among: candidates
			)?.contains("CliApplication") == true
		)
	}

	/// A file actually inside the directory wins outright, however deep the
	/// alternatives are.
	@Test func aFileInsideTheDirectoryWins() {
		let inside = "/repo/mod/src/main/java/A.java"
		let elsewhere = "/repo/other/src/main/java/B.java"
		#expect(JavaTooling.nearestFile(to: "/repo/mod", among: [elsewhere, inside]) == inside)
	}

	/// Equally near, the shallower one — the more likely module root.
	@Test func tiesGoToTheShallowerPath() {
		let shallow = "/repo/a/A.java"
		let deep = "/repo/a/b/c/d/B.java"
		#expect(JavaTooling.nearestFile(to: "/repo/x", among: [deep, shallow]) == shallow)
	}

	@Test func nothingToChooseFromIsNil() {
		#expect(JavaTooling.nearestFile(to: "/repo/mod", among: []) == nil)
	}
}
