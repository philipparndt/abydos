import Testing
import Foundation
import SwiftTreeSitter
@testable import IdeaiKit

/// Grammar loading fails *silently* — a missing query bundle just means
/// everything renders uncoloured — so these tests assert that real tokens come
/// back, not merely that nothing threw.
struct SyntaxTests {
	/// Every language the registry claims to support.
	static let allLanguages = [
		"swift", "rust", "typescript", "tsx", "javascript", "python", "go",
		"json", "bash", "c", "cpp", "java", "html", "css", "yaml", "toml",
		"markdown", "svelte", "openscad",
	]

	@Test(arguments: allLanguages)
	func languageLoadsWithHighlightQuery(languageId: String) {
		let configuration = LanguageRegistry.shared.configuration(for: languageId)
		#expect(configuration != nil, "\(languageId): no configuration")
		// The query bundle resolving is the fragile part — assert it explicitly.
		#expect(
			configuration?.queries[.highlights] != nil,
			"\(languageId): highlights.scm did not load; queries bundle was not found"
		)
	}

	@Test(arguments: allLanguages)
	func engineInitialises(languageId: String) {
		#expect(SyntaxEngine(languageId: languageId) != nil, "\(languageId): engine failed to init")
	}

	// MARK: - Real highlighting

	/// A snippet per language that must produce at least one keyword/comment
	/// token. This is what catches a grammar that links but never colours.
	static let samples: [(language: String, source: String)] = [
		("swift", "func greet(name: String) -> Int {\n    // comment\n    return 42\n}\n"),
		("rust", "fn main() {\n    // comment\n    let x = 42;\n}\n"),
		("python", "def greet(name):\n    # comment\n    return 42\n"),
		("javascript", "function greet(name) {\n  // comment\n  return 42;\n}\n"),
		("typescript", "function greet(name: string): number {\n  // comment\n  return 42;\n}\n"),
		("go", "package main\n\nfunc main() {\n\t// comment\n\tx := 42\n}\n"),
		("c", "int main(void) {\n    /* comment */\n    return 42;\n}\n"),
		("java", "class A {\n    // comment\n    int x = 42;\n}\n"),
		("json", "{\n  \"key\": \"value\",\n  \"n\": 42\n}\n"),
		("yaml", "key: value\nlist:\n  - one\n  - two\n"),
		("css", "body {\n  /* comment */\n  color: red;\n}\n"),
		("html", "<html>\n  <body>text</body>\n</html>\n"),
		("bash", "#!/bin/bash\nif [ -f x ]; then\n  echo hi\nfi\n"),
		("markdown", "# Heading\n\nSome *text* here.\n"),
		("toml", "[section]\nkey = \"value\"\n"),
		// Shaped after real OpenSCAD: `use <...>` includes, module definitions
		// with default arguments, and a for-loop with transforms.
		("openscad", """
		// a comment
		use <module/put.scad>
		c = "#ffd090";
		module woven_basket(radius = 45, height = 90, layers = 5) {
		    for (i = [0 : layers - 1]) {
		        translate([0, 0, i * 2]) cylinder(r = radius, h = height);
		    }
		}
		woven_basket(45, 90);
		"""),
	]

	@Test(arguments: samples)
	func producesHighlightTokens(sample: (language: String, source: String)) throws {
		let engine = try #require(
			SyntaxEngine(languageId: sample.language),
			"\(sample.language): engine unavailable"
		)
		let rope = Rope(sample.source)
		engine.parse(rope: rope)

		#expect(engine.hasTree, "\(sample.language): parse produced no tree")

		let tokens = engine.highlights(rope: rope, byteRange: 0..<rope.byteCount)
		#expect(!tokens.isEmpty, "\(sample.language): highlighting produced no tokens")

		// Spans must be ordered, non-overlapping, and inside the document.
		var previousEnd = -1
		for token in tokens {
			#expect(token.range.lowerBound >= previousEnd, "\(sample.language): overlapping spans")
			#expect(token.range.upperBound <= rope.utf16Count, "\(sample.language): span past end")
			previousEnd = token.range.upperBound
		}
	}

	// MARK: - Viewport scoping

	@Test func viewportQueryReturnsOnlyVisibleTokens() throws {
		// The core performance claim: highlighting a slice does not walk the file.
		let line = "func f\(0)() { let x = 1 } // trailing comment\n"
		let source = (0..<2_000).map { _ in line }.joined()
		let engine = try #require(SyntaxEngine(languageId: "swift"))
		let rope = Rope(source)
		engine.parse(rope: rope)

		let viewportStart = rope.byteOffset(ofLine: 500)
		let viewportEnd = rope.byteOffset(ofLine: 560)
		let tokens = engine.highlights(rope: rope, byteRange: viewportStart..<viewportEnd)

		#expect(!tokens.isEmpty)

		let lowerUTF16 = rope.utf16Offset(fromByte: viewportStart)
		let upperUTF16 = rope.utf16Offset(fromByte: viewportEnd)
		for token in tokens {
			#expect(token.range.lowerBound >= lowerUTF16, "token before viewport")
			#expect(token.range.upperBound <= upperUTF16, "token after viewport")
		}
	}

	// MARK: - Incremental editing

	@Test func incrementalEditKeepsHighlightingCorrect() throws {
		let engine = try #require(SyntaxEngine(languageId: "swift"))
		var rope = Rope("let a = 1\nlet b = 2\n")
		engine.parse(rope: rope)

		// Insert a comment marker and confirm the reparsed tree reflects it.
		let insertAt = rope.byteOffset(ofLine: 1)
		let startPoint = Point(row: 1, column: 0)
		rope.replace(byteRange: insertAt..<insertAt, with: "// ")
		engine.applyEdit(
			InputEdit(
				startByte: insertAt,
				oldEndByte: insertAt,
				newEndByte: insertAt + 3,
				startPoint: startPoint,
				oldEndPoint: startPoint,
				newEndPoint: Point(row: 1, column: 3)
			),
			newRope: rope
		)

		let lineStart = rope.byteOffset(ofLine: 1)
		let lineEnd = rope.byteCount
		let tokens = engine.highlights(rope: rope, byteRange: lineStart..<lineEnd)
		#expect(tokens.contains { $0.kind == .comment }, "edited line did not reparse as a comment")
	}

	// MARK: - Folding

	@Test func findsFoldRangesInNestedCode() throws {
		let source = """
		func outer() {
		    if condition {
		        doSomething()
		        doMore()
		    }
		}
		"""
		let engine = try #require(SyntaxEngine(languageId: "swift"))
		let rope = Rope(source)
		engine.parse(rope: rope)

		let folds = engine.foldRanges(rope: rope)
		#expect(!folds.isEmpty, "no fold ranges found")
		// The outer function spans the whole snippet.
		#expect(folds.contains { $0.startLine == 0 && $0.endLine >= 4 })
		// Every fold must hide at least one line, or it is a useless handle.
		#expect(folds.allSatisfy { $0.endLine > $0.startLine })
		// At most one fold handle per line.
		#expect(Set(folds.map(\.startLine)).count == folds.count)
	}

	// MARK: - Detection

	@Test func detectsLanguagesFromFilenames() {
		let cases: [(String, String?)] = [
			("main.swift", "swift"),
			("lib.rs", "rust"),
			("app.tsx", "tsx"),
			("script.py", "python"),
			("config.yaml", "yaml"),
			("config.yml", "yaml"),
			("Makefile", "bash"),
			("package.json", "json"),
			("README.md", "markdown"),
			("Component.svelte", "svelte"),
			("render_baskets.scad", "openscad"),
			("mystery.unknownext", nil),
		]
		for (filename, expected) in cases {
			let detected = LanguageRegistry.shared.languageId(for: URL(fileURLWithPath: "/tmp/\(filename)"))
			#expect(detected == expected, "\(filename) detected as \(detected ?? "nil")")
		}
	}
}
