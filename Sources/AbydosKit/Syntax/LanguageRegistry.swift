import Foundation
import SwiftTreeSitter

import TreeSitterSwift
import TreeSitterRust
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterGo
import TreeSitterJSON
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterJava
import TreeSitterHTML
import TreeSitterTOML
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterSvelte
import TreeSitterOpenscad
import TreeSitterOdin
import TreeSitterZig
import TreeSitterKotlin
import TreeSitterGroovy

// Vendored because their upstream manifests drop the external scanner; see
// Package.swift and Scripts/vendor-grammars.sh.
import TreeSitterCSSVendored
import TreeSitterJavaScriptVendored
import TreeSitterPythonVendored
import TreeSitterMakeVendored
import TreeSitterYAMLVendored

/// A language ideai can parse, plus the queries used to highlight and fold it.
public struct LanguageDefinition {
	public let id: String
	public let displayName: String
	let parser: () -> OpaquePointer
	/// SPM names a resource bundle `<package>_<target>`; several packages ship
	/// more than one grammar, so the bundle name cannot be derived from the id.
	let bundleName: String

	public private(set) var configuration: LanguageConfiguration?
	/// Loaded separately: `Query.queries(for:in:)` only knows about highlights,
	/// injections and locals, and folding needs `folds.scm`.
	public private(set) var foldQuery: Query?
}

/// Resolves a file to a grammar and caches the loaded queries.
///
/// Query compilation is the expensive part (tens of milliseconds for a big
/// grammar), so it happens once per language on first use and is shared by every
/// open document afterwards.
public final class LanguageRegistry {
	public static let shared = LanguageRegistry()

	private var definitions: [String: LanguageDefinition] = [:]
	private var loaded: [String: LanguageConfiguration] = [:]
	private var foldQueries: [String: Query?] = [:]
	private var tagsQueries: [String: Query?] = [:]
	private let lock = NSLock()

	private init() {
		register(id: "swift", name: "Swift", bundle: "TreeSitterSwift_TreeSitterSwift") { tree_sitter_swift() }
		register(id: "rust", name: "Rust", bundle: "TreeSitterRust_TreeSitterRust") { tree_sitter_rust() }
		register(id: "typescript", name: "TypeScript", bundle: "TreeSitterTypeScript_TreeSitterTypeScript") { tree_sitter_typescript() }
		register(id: "tsx", name: "TSX", bundle: "TreeSitterTypeScript_TreeSitterTSX") { tree_sitter_tsx() }
		// Vendored targets live in this package, so their resource bundles are
		// named `<package>_<target>`, and the package is this app.
		register(id: "javascript", name: "JavaScript", bundle: "Abydos_TreeSitterJavaScriptVendored") { tree_sitter_javascript() }
		register(id: "python", name: "Python", bundle: "Abydos_TreeSitterPythonVendored") { tree_sitter_python() }
		register(id: "go", name: "Go", bundle: "TreeSitterGo_TreeSitterGo") { tree_sitter_go() }
		register(id: "json", name: "JSON", bundle: "TreeSitterJSON_TreeSitterJSON") { tree_sitter_json() }
		register(id: "bash", name: "Shell", bundle: "TreeSitterBash_TreeSitterBash") { tree_sitter_bash() }
		register(id: "c", name: "C", bundle: "TreeSitterC_TreeSitterC") { tree_sitter_c() }
		register(id: "cpp", name: "C++", bundle: "TreeSitterCPP_TreeSitterCPP") { tree_sitter_cpp() }
		register(id: "java", name: "Java", bundle: "TreeSitterJava_TreeSitterJava") { tree_sitter_java() }
		register(id: "kotlin", name: "Kotlin", bundle: "TreeSitterKotlin_TreeSitterKotlin") { tree_sitter_kotlin() }
		// Groovy is here for `build.gradle` more than for Groovy itself, which is
		// where nearly every Java project still keeps its build.
		register(id: "groovy", name: "Groovy", bundle: "TreeSitterGroovy_TreeSitterGroovy") { tree_sitter_groovy() }
		register(id: "html", name: "HTML", bundle: "TreeSitterHTML_TreeSitterHTML") { tree_sitter_html() }
		register(id: "css", name: "CSS", bundle: "Abydos_TreeSitterCSSVendored") { tree_sitter_css() }
		register(id: "yaml", name: "YAML", bundle: "Abydos_TreeSitterYAMLVendored") { tree_sitter_yaml() }
		register(id: "make", name: "Makefile", bundle: "Abydos_TreeSitterMakeVendored") { tree_sitter_make() }
		register(id: "toml", name: "TOML", bundle: "TreeSitterTOML_TreeSitterTOML") { tree_sitter_toml() }
		register(id: "markdown", name: "Markdown", bundle: "TreeSitterMarkdown_TreeSitterMarkdown") { tree_sitter_markdown() }
		register(id: "markdown_inline", name: "Markdown (inline)", bundle: "TreeSitterMarkdown_TreeSitterMarkdownInline") { tree_sitter_markdown_inline() }
		register(id: "svelte", name: "Svelte", bundle: "TreeSitterSvelte_TreeSitterSvelte") { tree_sitter_svelte() }
		register(id: "openscad", name: "OpenSCAD", bundle: "TreeSitterOpenscad_TreeSitterOpenscad") { tree_sitter_openscad() }
		register(id: "odin", name: "Odin", bundle: "TreeSitterOdin_TreeSitterOdin") { tree_sitter_odin() }
		register(id: "zig", name: "Zig", bundle: "TreeSitterZig_TreeSitterZig") { tree_sitter_zig() }
	}

	private func register(
		id: String,
		name: String,
		bundle: String,
		parser: @escaping () -> OpaquePointer
	) {
		definitions[id] = LanguageDefinition(id: id, displayName: name, parser: parser, bundleName: bundle)
	}

	// MARK: - Detection

	/// Language id for a file, or nil when nothing matches.
	///
	/// Name and extension first, then the contents. Sniffing matters more than
	/// it looks: plenty of files carry an extension that is real but unknown —
	/// `Package.resolved` is JSON, `*.lock` is usually TOML or YAML — and an
	/// unknown extension is not evidence that the file is unstructured.
	public func languageId(for url: URL) -> String? {
		let filename = url.lastPathComponent.lowercased()
		if let byName = Self.filenameMap[filename] { return byName }

		let ext = url.pathExtension.lowercased()
		if !ext.isEmpty, let byExtension = Self.extensionMap[ext] { return byExtension }

		return Self.contentLanguage(at: url)
	}

	/// The language a fenced code block names after its backticks.
	///
	/// The same names people type there — `sh`, `js`, `c++` — rather than the
	/// ids used internally, and nil for a fence with no language or one no
	/// grammar is loaded for, which is left as plain text.
	public func languageId(forFenceInfo info: String) -> String? {
		// "```swift title=x" and "```{.python}" both name a language first.
		let word = info
			.trimmingCharacters(in: .whitespaces)
			.lowercased()
			.split(whereSeparator: { " \t{},".contains($0) })
			.first
			.map(String.init)?
			.trimmingCharacters(in: CharacterSet(charactersIn: ".`"))

		guard let word, !word.isEmpty else { return nil }
		if let byExtension = Self.extensionMap[word] { return byExtension }
		if let byAlias = Self.fenceAliases[word] { return byAlias }
		return definitions[word] != nil ? word : nil
	}

	/// Names that appear after backticks and match no file extension.
	static let fenceAliases: [String: String] = [
		"shell": "bash", "console": "bash", "shell-session": "bash", "terminal": "bash",
		"c++": "cpp", "objective-c": "c", "objc": "c",
		"golang": "go",
		"node": "javascript", "es6": "javascript",
		"yml": "yaml",
		"jsonc": "json", "json5": "json",
		"html5": "html", "xml": "html",
	]

	/// Sniffs the first few hundred bytes for a recognisable shape.
	static func contentLanguage(at url: URL) -> String? {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
		defer { try? handle.close() }
		guard let data = try? handle.read(upToCount: 1024) else { return nil }
		return contentLanguage(ofPrefix: data)
	}

	/// Split out from the file read so it can be exercised directly.
	///
	/// Deliberately conservative: a wrong guess colours the whole file wrongly,
	/// which is worse than no highlighting, so each rule needs a marker that
	/// prose or code in another language would not begin with.
	static func contentLanguage(ofPrefix data: Data) -> String? {
		guard let text = String(data: data, encoding: .utf8) else { return nil }

		if let interpreter = shebangLanguage(inFirstLine: text) { return interpreter }

		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let first = trimmed.first else { return nil }

		switch first {
		case "{":
			// A brace also opens a C block and a shell function body, so what
			// settles it is a quoted key or an immediate close, not the brace.
			let head = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
			return head.hasPrefix("\"") || head.hasPrefix("}") ? "json" : nil
		case "[":
			// A leading bracket is far less ambiguous — it opens a TOML table
			// header, and otherwise a JSON array of any value type.
			let head = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
			guard let next = head.first else { return nil }
			if next == "\"" || next == "]" || next == "{" || next == "[" { return "json" }
			if next.isNumber || next == "-" { return "json" }
			if next == "t" && head.hasPrefix("true") { return "json" }
			if next == "f" && head.hasPrefix("false") { return "json" }
			if next == "n" && head.hasPrefix("null") { return "json" }
			return nil
		case "<":
			let lowered = trimmed.lowercased()
			if lowered.hasPrefix("<?xml") || lowered.hasPrefix("<!doctype html") || lowered.hasPrefix("<html") {
				return "html"
			}
			return nil
		case "-":
			// A YAML document marker. Three dashes on their own line; a Markdown
			// front-matter fence looks the same, but that file has an extension.
			if trimmed.hasPrefix("---\n") || trimmed == "---" { return "yaml" }
			return nil
		default:
			return nil
		}
	}

	static let extensionMap: [String: String] = [
		"swift": "swift",
		"rs": "rust",
		"ts": "typescript", "mts": "typescript", "cts": "typescript",
		"tsx": "tsx", "jsx": "tsx",
		"js": "javascript", "mjs": "javascript", "cjs": "javascript",
		"py": "python", "pyi": "python",
		"go": "go",
		"json": "json", "jsonc": "json",
		"sh": "bash", "bash": "bash", "zsh": "bash", "command": "bash",
		"c": "c", "h": "c",
		"cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "hxx": "cpp",
		"java": "java",
		"kt": "kotlin", "kts": "kotlin",
		// `.gradle` is Groovy; `.gradle.kts` lands on `kts` above.
		"groovy": "groovy", "gradle": "groovy", "gvy": "groovy", "jenkinsfile": "groovy",
		"html": "html", "htm": "html", "xhtml": "html", "vue": "html",
		// XML through the HTML grammar, which reads tags, attributes and text the
		// same way. It is what a Java project's `pom.xml` needs, and the
		// alternative is a Maven build displayed as unstructured text.
		"xml": "html", "xsd": "html", "xsl": "html", "pom": "html",
		"css": "css", "scss": "css", "sass": "css",
		"yaml": "yaml", "yml": "yaml",
		"toml": "toml",
		"md": "markdown", "markdown": "markdown", "mdx": "markdown",
		"svelte": "svelte",
		"scad": "openscad",
		"odin": "odin",
		"zig": "zig", "zon": "zig",
		"mk": "make", "make": "make",
		// PlantUML has no grammar here — the ones that exist are stale and
		// partial — so this is a name for the language server's benefit, and
		// the file is shown uncoloured until a grammar is worth vendoring.
		"puml": "plantuml", "plantuml": "plantuml", "pu": "plantuml",
		"iuml": "plantuml", "wsd": "plantuml",
	]

	static let filenameMap: [String: String] = [
		"dockerfile": "bash",
		// A recipe is shell, and everything around it is not: targets,
		// prerequisites and the three kinds of assignment are what a Makefile
		// is mostly made of, and bash's grammar reads none of them.
		"makefile": "make", "gnumakefile": "make", "makefile.am": "make", "makefile.in": "make",
		".bashrc": "bash", ".bash_profile": "bash", ".zshrc": "bash", ".profile": "bash",
		".gitconfig": "toml",
		"cargo.lock": "toml",
		"package.json": "json", "tsconfig.json": "json",
		// A Jenkinsfile is Groovy and carries no extension.
		"jenkinsfile": "groovy",
		// The Gradle wrapper's own files, which are shell and a properties list.
		"gradlew": "bash", "mvnw": "bash",
	]

	private static func shebangLanguage(inFirstLine text: String) -> String? {
		guard let line = text.split(separator: "\n", maxSplits: 1).first,
		      line.hasPrefix("#!")
		else { return nil }

		if line.contains("python") { return "python" }
		if line.contains("bash") || line.contains("/sh") || line.contains("zsh") { return "bash" }
		if line.contains("node") { return "javascript" }
		return nil
	}

	/// Every language that can be chosen by hand, for the status bar's picker.
	public var selectableLanguages: [(id: String, name: String)] {
		Self.knownLanguageIds
			.map { ($0, displayName(for: $0)) }
			.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
	}

	static let knownLanguageIds: [String] = Array(Set(extensionMap.values)).sorted()

	// MARK: - Loading

	public func displayName(for languageId: String) -> String {
		if let known = definitions[languageId]?.displayName { return known }
		return Self.grammarlessNames[languageId] ?? languageId
	}

	/// Languages the editor knows by name but has no grammar for. They open,
	/// they are sent to a language server, and the status bar can still say
	/// what they are rather than showing an internal id.
	static let grammarlessNames = ["plantuml": "PlantUML"]

	/// Loads and caches a language's parser and queries.
	///
	/// A grammar whose query bundle is missing still returns a configuration —
	/// the file parses and folds structurally, it just is not coloured — which
	/// is far better than refusing to open it.
	public func configuration(for languageId: String) -> LanguageConfiguration? {
		lock.lock()
		defer { lock.unlock() }

		if let cached = loaded[languageId] { return cached }
		guard let definition = definitions[languageId] else { return nil }

		let language = Language(definition.parser())
		let configuration: LanguageConfiguration

		// The queries directory is resolved here rather than via
		// LanguageConfiguration's bundleName initialiser, which only looks under
		// `Contents/Resources/`. `swift build` emits flat bundles, so that lookup
		// silently finds nothing and every file renders uncoloured.
		if let queriesURL = Self.queriesDirectory(bundleName: definition.bundleName),
		   let loadedConfiguration = try? LanguageConfiguration(
			   language,
			   name: definition.displayName,
			   queriesURL: queriesURL
		   ) {
			configuration = loadedConfiguration
		} else {
			// Still usable: the file parses and folds structurally, just without
			// colour. Better than refusing to open it.
			configuration = LanguageConfiguration(language, name: definition.displayName, queries: [:])
		}

		loaded[languageId] = configuration
		return configuration
	}

	/// The grammar's `folds.scm`, when it ships one.
	public func foldQuery(for languageId: String) -> Query? {
		lock.lock()
		defer { lock.unlock() }

		if let cached = foldQueries[languageId] { return cached }
		guard let definition = definitions[languageId] else { return nil }

		var result: Query?
		if let url = Self.queryURL(named: "folds.scm", languageId: languageId, definition: definition) {
			let language = Language(definition.parser())
			result = try? Query(language: language, url: url)
		}
		foldQueries[languageId] = result
		return result
	}

	/// The `tags.scm` query, which names a grammar's declarations.
	///
	/// Written for ctags-style indexing rather than for an outline, but it is
	/// the only query most grammars ship that says "this is a definition and
	/// this is its name" — which is exactly what a structure view needs.
	public func tagsQuery(for languageId: String) -> Query? {
		lock.lock()
		defer { lock.unlock() }

		if let cached = tagsQueries[languageId] { return cached }
		guard let definition = definitions[languageId] else { return nil }

		var result: Query?
		if let url = Self.queryURL(named: "tags.scm", languageId: languageId, definition: definition) {
			let language = Language(definition.parser())
			result = try? Query(language: language, url: url)
		}
		tagsQueries[languageId] = result
		return result
	}

	/// Where a named query file is, preferring the grammar's own.
	///
	/// Not every grammar ships every query — tree-sitter-java has no `folds.scm`
	/// and no upstream is going to add one on our schedule — so a query written
	/// here, under `Sources/AbydosKit/Queries/<language>/`, stands in. The
	/// grammar's own always wins, so vendoring a newer version of a grammar
	/// silently takes over from ours rather than being shadowed by it.
	private static func queryURL(
		named name: String,
		languageId: String,
		definition: LanguageDefinition
	) -> URL? {
		if let directory = queriesDirectory(bundleName: definition.bundleName) {
			let url = directory.appendingPathComponent(name)
			if FileManager.default.isReadableFile(atPath: url.path) { return url }
		}
		guard let supplement = supplementDirectory(languageId: languageId) else { return nil }
		let url = supplement.appendingPathComponent(name)
		return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
	}

	/// This module's own queries for a language, when it has any.
	private static func supplementDirectory(languageId: String) -> URL? {
		for base in searchDirectories {
			let bundle = base.appendingPathComponent("Abydos_AbydosKit.bundle", isDirectory: true)
			for layout in ["Contents/Resources/Queries", "Queries"] {
				let directory = bundle
					.appendingPathComponent(layout, isDirectory: true)
					.appendingPathComponent(languageId, isDirectory: true)
				if FileManager.default.fileExists(atPath: directory.path) { return directory }
			}
		}
		return nil
	}

	/// Anchor for locating this module's own bundle, which is what makes
	/// resource lookup work under XCTest as well as in the app.
	private final class BundleAnchor {}

	/// Directories that may contain the grammar resource bundles.
	///
	/// Three contexts have to work and they disagree about where resources sit:
	/// a packaged `.app` (main bundle resources), a bare `swift run` executable
	/// (the directory next to the binary), and an XCTest run (where `Bundle.main`
	/// is the *test runner*, not this code). Rather than branch on which one we
	/// are in, try each candidate and take the first that actually has the file.
	private static let searchDirectories: [URL] = {
		var candidates: [URL] = []
		if let resources = Bundle.main.resourceURL { candidates.append(resources) }
		candidates.append(Bundle.main.bundleURL)

		let own = Bundle(for: BundleAnchor.self)
		if let resources = own.resourceURL { candidates.append(resources) }
		// SPM places dependency bundles beside the test bundle, one level up.
		candidates.append(own.bundleURL.deletingLastPathComponent())

		return candidates
	}()

	/// Locates a grammar's `queries/` directory.
	///
	/// Both bundle layouts must work: `swift build` emits flat bundles
	/// (`X.bundle/queries`), while a packaged `.app` carries the wrapped form
	/// (`X.bundle/Contents/Resources/queries`).
	private static func queriesDirectory(bundleName: String) -> URL? {
		for base in searchDirectories {
			let bundle = base.appendingPathComponent("\(bundleName).bundle", isDirectory: true)
			for layout in ["Contents/Resources/queries", "queries"] {
				let directory = bundle.appendingPathComponent(layout, isDirectory: true)
				if FileManager.default.fileExists(atPath: directory.path) { return directory }
			}
		}
		return nil
	}
}
