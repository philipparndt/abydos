import Foundation
import Testing
@testable import IdeaiKit

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
}
