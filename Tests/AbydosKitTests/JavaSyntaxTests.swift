import Foundation
import Testing
@testable import AbydosKit

/// Java, Kotlin and Groovy as the editor sees them: which grammar a file gets,
/// what the highlighter colours, and where it folds.
///
/// Headless on purpose. Whether a file is *coloured* is a fact about the
/// grammar and its queries, and asking the engine is both faster and more
/// specific than looking at a picture of it.
struct JavaSyntaxTests {
	@Test func picksAGrammarForEveryFileAJavaProjectHolds() {
		let registry = LanguageRegistry.shared
		func language(_ name: String) -> String? {
			registry.languageId(for: URL(fileURLWithPath: "/p/\(name)"))
		}

		#expect(language("Server.java") == "java")
		#expect(language("App.kt") == "kotlin")
		#expect(language("build.gradle.kts") == "kotlin")
		#expect(language("build.gradle") == "groovy")
		#expect(language("settings.gradle") == "groovy")
		#expect(language("Jenkinsfile") == "groovy")
		// A POM is XML, and XML reads well enough through HTML's grammar.
		#expect(language("pom.xml") == "html")
		#expect(language("gradlew") == "bash")
	}

	@Test func loadsTheThreeNewGrammars() {
		for id in ["java", "kotlin", "groovy"] {
			#expect(LanguageRegistry.shared.configuration(for: id) != nil, "no grammar for \(id)")
		}
		#expect(LanguageRegistry.shared.displayName(for: "kotlin") == "Kotlin")
		#expect(LanguageRegistry.shared.displayName(for: "groovy") == "Groovy")
	}

	/// The point of a grammar is colour. A file that parses and highlights
	/// nothing is the failure this catches — it is what a missing query bundle
	/// looks like, and it is invisible from the outside.
	@Test func highlightsJava() {
		let source = """
		package com.example.api;

		public class Server {
			public static void main(String[] args) {
				System.out.println("up");
			}
		}
		"""
		let kinds = highlightKinds(of: source, languageId: "java")
		#expect(!kinds.isEmpty)
		#expect(kinds.contains(.keyword))
		#expect(kinds.contains(.string))
		#expect(kinds.contains(.type))
	}

	@Test func highlightsKotlin() {
		let source = """
		package com.example

		fun main(args: Array<String>) {
			val greeting = "hello"
			println(greeting)
		}
		"""
		let kinds = highlightKinds(of: source, languageId: "kotlin")
		#expect(kinds.contains(.keyword))
		#expect(kinds.contains(.string))
	}

	@Test func highlightsAGradleBuildFile() {
		let source = """
		plugins {
			id 'application'
		}

		application {
			mainClassName = 'com.example.Server'
		}
		"""
		let kinds = highlightKinds(of: source, languageId: "groovy")
		#expect(kinds.contains(.string))
	}

	/// tree-sitter-java ships no `folds.scm`, so this is the one that proves
	/// the query written here is found and compiles against the grammar.
	@Test func foldsJavaByItsBodies() {
		#expect(LanguageRegistry.shared.foldQuery(for: "java") != nil)

		let source = """
		public class Server {
			public static void main(String[] args) {
				if (args.length > 0) {
					System.out.println(args[0]);
				}
			}
		}
		"""
		let folds = foldRanges(of: source, languageId: "java")
		// The class body, the method body and the `if` body, each starting on
		// its own line.
		#expect(folds.count == 3)
		#expect(folds.map(\.startLine) == [0, 1, 2])
		#expect(folds.first?.endLine == 6)
	}

	@Test func foldsKotlinByItsBodies() {
		#expect(LanguageRegistry.shared.foldQuery(for: "kotlin") != nil)

		let source = """
		class Server {
			fun start() {
				println("up")
			}
		}
		"""
		let folds = foldRanges(of: source, languageId: "kotlin")
		#expect(folds.count >= 2)
		#expect(folds.first?.startLine == 0)
	}

	// MARK: - Helpers

	private func highlightKinds(of source: String, languageId: String) -> Set<HighlightKind> {
		guard let engine = SyntaxEngine(languageId: languageId) else { return [] }
		let rope = Rope(source)
		engine.parse(rope: rope)
		return Set(engine.highlights(rope: rope, byteRange: 0..<source.utf8.count).map(\.kind))
	}

	private func foldRanges(of source: String, languageId: String) -> [FoldRange] {
		guard let engine = SyntaxEngine(languageId: languageId) else { return [] }
		let rope = Rope(source)
		engine.parse(rope: rope)
		return engine.foldRanges(rope: rope)
	}
}
