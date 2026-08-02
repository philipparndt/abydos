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
		"markdown", "svelte", "openscad", "odin", "zig",
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
		// Shaped after real Odin: a package clause, an import, a struct, and a
		// procedure with a for-loop in it.
		("odin", """
		package main

		import "core:fmt"

		Reading :: struct {
			sensor:  string,
			celsius: f64,
		}

		main :: proc() {
			readings := []Reading{{"kitchen", 21.5}, {"garage", 9.0}}
			for reading in readings {
				fmt.printfln("%s is at %.1f C", reading.sensor, reading.celsius)
			}
		}
		"""),
		("zig", """
		const std = @import("std");

		fn fib(n: u64) u64 {
			if (n < 2) return n;
			return fib(n - 1) + fib(n - 2);
		}

		pub fn main() void {
			std.debug.print("fib(10) = {d}\\n", .{fib(10)});
		}
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

/// The structure view's data: declarations pulled from the grammar's tags
/// query and nested by containment.
struct SymbolOutlineTests {
	@Test func captureNamesMapToKinds() {
		#expect(SymbolOutline.kind(forCapture: "definition.class") == .type)
		#expect(SymbolOutline.kind(forCapture: "definition.method") == .method)
		#expect(SymbolOutline.kind(forCapture: "definition.interface") == .protocolType)
		#expect(SymbolOutline.kind(forCapture: "definition.enum") == .enumeration)
	}

	/// An unrecognised definition still shows up; a symbol with a dull icon is
	/// more useful than a missing one.
	@Test func unknownDefinitionsFallThroughRatherThanVanish() {
		#expect(SymbolOutline.kind(forCapture: "definition.wibble") == .other)
	}

	@Test func nonDefinitionCapturesAreIgnored() {
		#expect(SymbolOutline.kind(forCapture: "name") == nil)
		#expect(SymbolOutline.kind(forCapture: "reference.call") == nil)
	}

	/// `at` is where the name is; `spanning` is the declaration it belongs to.
	private func symbol(
		_ name: String,
		at nameStart: Int,
		spanning range: Range<Int>,
		_ kind: DocumentSymbol.Kind = .method
	) -> DocumentSymbol {
		DocumentSymbol(
			name: name,
			kind: kind,
			line: 0,
			byteRange: range,
			nameRange: nameStart..<(nameStart + name.utf8.count)
		)
	}

	/// A member's name sits inside its type's declaration, which is the only
	/// relationship the tags queries express.
	@Test func membersBecomeChildrenOfTheirType() {
		let nested = SymbolOutline.nest([
			symbol("method", at: 30, spanning: 0..<100),
			symbol("Type", at: 5, spanning: 0..<100, .type),
		])
		#expect(nested.map(\.name) == ["Type"])
		#expect(nested[0].children.map(\.name) == ["method"])
	}

	@Test func nestingGoesMoreThanOneDeep() {
		let nested = SymbolOutline.nest([
			symbol("Outer", at: 5, spanning: 0..<100, .type),
			symbol("Inner", at: 20, spanning: 15..<80, .type),
			symbol("deep", at: 40, spanning: 15..<80),
		])
		#expect(nested[0].children[0].children.map(\.name) == ["deep"])
	}

	/// The case that produced a chain of one property inside the last: several
	/// grammars hang every member's definition capture on the enclosing type,
	/// so all of them share one range. Only a container may adopt.
	@Test func membersSharingOneRangeStaySiblings() {
		let nested = SymbolOutline.nest([
			symbol("Type", at: 5, spanning: 0..<100, .type),
			symbol("first", at: 20, spanning: 0..<100, .property),
			symbol("second", at: 40, spanning: 0..<100, .property),
			symbol("third", at: 60, spanning: 0..<100, .property),
		])
		#expect(nested.map(\.name) == ["Type"])
		#expect(nested[0].children.map(\.name) == ["first", "second", "third"])
		#expect(nested[0].children.allSatisfy { $0.children.isEmpty })
	}

	@Test func siblingsStayAtTheSameLevel() {
		let nested = SymbolOutline.nest([
			symbol("a", at: 0, spanning: 0..<10),
			symbol("b", at: 20, spanning: 20..<30),
		])
		#expect(nested.map(\.name) == ["a", "b"])
		#expect(nested.allSatisfy { $0.children.isEmpty })
	}

	@Test func resultsAreInSourceOrder() {
		let nested = SymbolOutline.nest([
			symbol("later", at: 50, spanning: 50..<60),
			symbol("earlier", at: 0, spanning: 0..<10),
		])
		#expect(nested.map(\.name) == ["earlier", "later"])
	}

	/// The same declaration can be matched by more than one pattern in a
	/// grammar's tags file.
	@Test func duplicateCapturesAreCollapsed() {
		let nested = SymbolOutline.nest([
			symbol("thing", at: 0, spanning: 0..<10),
			symbol("thing", at: 0, spanning: 0..<10),
		])
		#expect(nested.count == 1)
	}

	@Test func anEmptyOutlineIsEmpty() {
		#expect(SymbolOutline.nest([]).isEmpty)
	}
}

/// Against real grammars, since the capture vocabulary is theirs, not ours.
struct SymbolExtractionTests {
	private func symbols(_ source: String, named name: String) async -> [DocumentSymbol] {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-symbols-\(UUID().uuidString)")
			.appendingPathExtension((name as NSString).pathExtension)
		try? source.write(to: url, atomically: true, encoding: .utf8)
		guard let document = try? TextDocument(url: url) else { return [] }

		// The initial parse is off-thread; the query runs behind it.
		let held = MainQueueBox(document)
		return await withCheckedContinuation { continuation in
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
				held.value.symbols { continuation.resume(returning: $0) }
			}
		}
	}

	@Test func findsGoFunctionsAndTypes() async {
		let found = await symbols("""
		package main

		type Server struct {
			port int
		}

		func (s *Server) Start() error {
			return nil
		}

		func main() {
			_ = Server{}
		}
		""", named: "x.go")

		let names = flatten(found).map(\.name)
		#expect(names.contains("Server"))
		#expect(names.contains("Start"))
		#expect(names.contains("main"))
	}

	@Test func findsSwiftTypesAndNestsTheirMethods() async {
		let found = await symbols("""
		struct Thing {
			func act() {}
		}
		""", named: "x.swift")

		#expect(found.map(\.name) == ["Thing"])
		#expect(found.first?.children.map(\.name) == ["act"])
	}

	/// The shape that came out as a chain: a type with several members, each
	/// captured against the type's own declaration range.
	@Test func swiftMembersAreSiblingsNotAChain() async {
		let found = await symbols("""
		struct Holder {
			func first() {}
			func second() {}
			func third() {}
		}
		""", named: "x.swift")

		#expect(found.map(\.name) == ["Holder"])
		#expect(found.first?.children.map(\.name) == ["first", "second", "third"])
		#expect(found.first?.children.allSatisfy { $0.children.isEmpty } == true)
	}

	/// Every member reported the type's line when the definition capture was
	/// used for position.
	@Test func membersReportTheirOwnLine() async {
		let found = await symbols("""
		struct Holder {
			func first() {}

			func second() {}
		}
		""", named: "x.swift")

		let children = found.first?.children ?? []
		#expect(children.first { $0.name == "first" }?.line == 1)
		#expect(children.first { $0.name == "second" }?.line == 3)
	}

	@Test func reportsTheDeclarationLine() async {
		let found = await symbols("""
		package main

		func target() {}
		""", named: "x.go")
		#expect(flatten(found).first { $0.name == "target" }?.line == 2)
	}

	/// Plain text has no grammar, so there is nothing to outline.
	@Test func aFileWithNoGrammarHasNoSymbols() async {
		#expect(await symbols("just words\n", named: "x.unknownext").isEmpty)
	}

	private func flatten(_ symbols: [DocumentSymbol]) -> [DocumentSymbol] {
		symbols.flatMap { [$0] + flatten($0.children) }
	}
}

/// An outline listing every local variable is one nobody can read.
struct SymbolLocalFilteringTests {
	private func symbols(_ source: String, named name: String) async -> [DocumentSymbol] {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-locals-\(UUID().uuidString)")
			.appendingPathExtension((name as NSString).pathExtension)
		try? source.write(to: url, atomically: true, encoding: .utf8)
		guard let document = try? TextDocument(url: url) else { return [] }
		let held = MainQueueBox(document)
		return await withCheckedContinuation { continuation in
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
				held.value.symbols { continuation.resume(returning: $0) }
			}
		}
	}

	private func flatten(_ symbols: [DocumentSymbol]) -> [DocumentSymbol] {
		symbols.flatMap { [$0] + flatten($0.children) }
	}

	@Test func localsInsideAFunctionAreNotListed() async {
		let found = await symbols("""
		struct Thing {
			let member = 1

			func work() {
				let local = 2
				var another = 3
				_ = local + another
			}
		}
		""", named: "x.swift")

		let names = flatten(found).map(\.name)
		#expect(names.contains("Thing"))
		#expect(names.contains("member"))
		#expect(names.contains("work"))
		#expect(!names.contains("local"))
		#expect(!names.contains("another"))
	}

	/// Go's tags query captures top-level vars, which are members and stay.
	@Test func packageLevelDeclarationsAreKept() async {
		let found = await symbols("""
		package main

		func run() {
			inner := 1
			_ = inner
		}
		""", named: "x.go")

		let names = flatten(found).map(\.name)
		#expect(names.contains("run"))
		#expect(!names.contains("inner"))
	}
}


/// Carries a main-thread-only value across a `@Sendable` boundary.
///
/// `TextDocument` is not Sendable by design — it is owned by the main thread —
/// and these tests only ever touch it there. The box says so explicitly rather
/// than silencing the whole module with `@preconcurrency`.
private final class MainQueueBox<Value>: @unchecked Sendable {
	let value: Value
	init(_ value: Value) { self.value = value }
}
