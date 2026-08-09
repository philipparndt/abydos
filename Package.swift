// swift-tools-version: 6.0
import PackageDescription

// Grammars are separate SPM packages. Each ships a pre-generated parser.c and
// copies its `queries/` directory in as a resource bundle, which is where the
// highlight and fold queries come from at runtime.
let grammars: [(pkg: String, url: String, version: Version, products: [String])] = [
	("tree-sitter-swift",      "https://github.com/alex-pinkus/tree-sitter-swift",           "0.7.3-with-generated-files", ["TreeSitterSwift"]),
	("tree-sitter-rust",       "https://github.com/tree-sitter/tree-sitter-rust",            "0.24.2", ["TreeSitterRust"]),
	// One product vends both the TypeScript and TSX modules.
	("tree-sitter-typescript", "https://github.com/tree-sitter/tree-sitter-typescript",      "0.23.2", ["TreeSitterTypeScript"]),
	("tree-sitter-go",         "https://github.com/tree-sitter/tree-sitter-go",              "0.25.0", ["TreeSitterGo"]),
	("tree-sitter-json",       "https://github.com/tree-sitter/tree-sitter-json",            "0.24.8", ["TreeSitterJSON"]),
	("tree-sitter-bash",       "https://github.com/tree-sitter/tree-sitter-bash",            "0.25.1", ["TreeSitterBash"]),
	("tree-sitter-c",          "https://github.com/tree-sitter/tree-sitter-c",               "0.24.2", ["TreeSitterC"]),
	("tree-sitter-cpp",        "https://github.com/tree-sitter/tree-sitter-cpp",             "0.23.4", ["TreeSitterCPP"]),
	("tree-sitter-java",       "https://github.com/tree-sitter/tree-sitter-java",            "0.23.5", ["TreeSitterJava"]),
	("tree-sitter-html",       "https://github.com/tree-sitter/tree-sitter-html",            "0.23.2", ["TreeSitterHTML"]),
	("tree-sitter-toml",       "https://github.com/tree-sitter-grammars/tree-sitter-toml",   "0.7.0",  ["TreeSitterTOML"]),
	// Likewise vends both the block and inline Markdown modules.
	("tree-sitter-markdown",   "https://github.com/tree-sitter-grammars/tree-sitter-markdown", "0.5.3", ["TreeSitterMarkdown"]),
	("tree-sitter-svelte",     "https://github.com/tree-sitter-grammars/tree-sitter-svelte", "1.0.2",  ["TreeSitterSvelte"]),
	// Official OpenSCAD grammar. Its manifest has the same relative-path scanner
	// check as the vendored four, but harmlessly so: this grammar has no external
	// scanner, so there is nothing for the broken check to drop.
	("tree-sitter-openscad",   "https://github.com/openscad/tree-sitter-openscad",          "0.7.1",  ["TreeSitterOpenscad"]),
	("tree-sitter-odin",       "https://github.com/amaanq/tree-sitter-odin",                "1.3.0",  ["TreeSitterOdin"]),
	("tree-sitter-zig",        "https://github.com/tree-sitter-grammars/tree-sitter-zig",   "1.1.2",  ["TreeSitterZig"]),
	// Kotlin, for `.kt` and for the Gradle builds written in it. Twenty
	// megabytes of generated parser, which is why it is a package rather than
	// one more vendored grammar in this repository.
	("tree-sitter-kotlin",     "https://github.com/fwcd/tree-sitter-kotlin",                "0.3.8",  ["TreeSitterKotlin"]),
]

// Groovy, for `build.gradle`. The one grammar anybody uses for it has never cut
// a release, so it is pinned by commit — which is the same promise a tag makes
// and the only one on offer here.
let revisionGrammars: [(pkg: String, url: String, revision: String, products: [String])] = [
	("tree-sitter-groovy", "https://github.com/murtaza64/tree-sitter-groovy",
	 "deb0dcf8c4544f07564060f6e9b9f6e4b0bfc27d", ["TreeSitterGroovy"]),
]

// These four are vendored instead of used as packages. Their manifests gate the
// external scanner behind `FileManager.default.fileExists(atPath: "src/scanner.c")`
// — a relative path that never resolves during manifest evaluation, so the
// scanner is dropped and the grammar fails to link. Vendoring lets the source
// list be stated explicitly. See Scripts/vendor-grammars.sh to update them.
let vendoredGrammars = ["CSS", "JavaScript", "Make", "Python", "YAML"]

// Spelled out rather than concatenated inside the Package literal: the type
// checker gives up on an expression that large and the manifest stops
// compiling.
let grammarPackages: [Package.Dependency] =
	grammars.map { .package(url: $0.url, exact: $0.version) }
	+ revisionGrammars.map { .package(url: $0.url, revision: $0.revision) }

let grammarProducts: [Target.Dependency] =
	grammars.flatMap { g in g.products.map { Target.Dependency.product(name: $0, package: g.pkg) } }
	+ revisionGrammars.flatMap { g in g.products.map { Target.Dependency.product(name: $0, package: g.pkg) } }
	+ vendoredGrammars.map { .target(name: "TreeSitter\($0)Vendored") }

let package = Package(
	name: "Abydos",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "Abydos", targets: ["Abydos"]),
		// The window layer, so an Xcode app target can be built from the same
		// sources without a second copy of the dependency graph.
		.library(name: "AbydosApp", targets: ["AbydosApp"]),
		.executable(name: "abydos-hook", targets: ["AbydosHook"]),
		// A terminal stress test, run against the app's own terminal.
		.executable(name: "firebench", targets: ["FireBench"]),
		.library(name: "AbydosKit", targets: ["AbydosKit"]),
	],
	dependencies: [
		.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.25.0"),
		// The 3D viewer, hosted in an editor tab. A path dependency for now:
		// see the note in README about what publishing it would take.
		.package(path: "../3d/gostl/GoSTL-Swift"),
	] + grammarPackages,
	targets: [
		// The DOOM fire terminal stress test, ported so it can run unattended.
		.executableTarget(name: "FireBench", path: "Sources/FireBench"),
		// Editor engine: text storage, syntax, folding, git, project model.
		// Kept free of view code so it can be unit-tested without a window.
		.target(
			name: "AbydosKit",
			dependencies: [
				.product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
				.product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
			] + grammarProducts,
			// Queries a grammar does not ship itself. tree-sitter-java has no
			// `folds.scm`, so without this a Java file cannot be folded at all.
			//
			// And the colour schemes, which are data rather than four places in
			// two Swift files. Copied into the module's bundle, which
			// Scripts/bundle.sh carries into the .app beside the grammars — an
			// app that cannot find them draws in the grey fallback and says so
			// in ~/Library/Logs/Abydos/schemes.log.
			// And mermaid's browser bundle, which is what draws Mermaid: it is
			// JavaScript, every command-line form of it is a headless Chromium,
			// and 3.6 MB in a WKWebView beats 2.16 GB in a container (0425).
			// And draw.io, which unlike Mermaid is not one file: the viewer, the
			// editor, every stencil deflated into one bundle, and the furniture
			// they load. 23 MB, and the reason is that draw.io publishes a
			// webapp and nothing smaller (0426).
			resources: [
				.copy("Queries"), .copy("Settings/Schemes"),
				.copy("Preview/mermaid"), .copy("Preview/drawio"),
			],
			// Language mode 5: AppKit's delegate-and-callback surface predates
			// strict concurrency checking and fights it constantly. Isolation here
			// is enforced by design (UI on the main thread, parsing behind an
			// actor) rather than by the 6.0 checker.
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
		// AppKit shell: window, navigator, toolbar, code view.
		//
		// A library rather than the executable itself, so an Xcode application
		// target can be built from these same sources without declaring the
		// dependency graph a second time — two declarations of the same path
		// package build it twice and the link fails.
		.target(
			name: "AbydosApp",
			dependencies: [
				"AbydosKit",
				.product(name: "GoSTLKit", package: "GoSTL-Swift"),
			],
			path: "Sources/AbydosApp",
			// The development pod's chart travels with the app: installing it
			// should not mean finding a checkout of this repository first.
			resources: [.copy("Resources/devpod-chart")],
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
		// Four lines: make an application, give it the delegate, run it.
		.executableTarget(
			name: "Abydos",
			dependencies: ["AbydosApp"],
			path: "Sources/AbydosMain",
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
		// The Claude Code hook, kept apart from the app on purpose: Claude runs
		// it several times per tool call, and starting a binary that links
		// AppKit and a syntax engine to read one line of JSON would be felt in
		// every session on the machine.
		.executableTarget(
			name: "AbydosHook",
			dependencies: ["AbydosKit"],
			path: "Sources/AbydosHook",
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
		.testTarget(
			name: "AbydosKitTests",
			dependencies: ["AbydosKit"],
			// Real profiles, written by Go: the decoder is only worth anything
			// if it reads what the runtime actually produces.
			resources: [.copy("Fixtures")],
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
	] + vendoredGrammars.map { name in
		.target(
			name: "TreeSitter\(name)Vendored",
			path: "Sources/Grammars/TreeSitter\(name)Vendored",
			// Every .c under src/, so multi-file scanners (YAML ships three
			// schema files) are compiled rather than half-linked.
			sources: ["src"],
			resources: [.copy("queries")],
			publicHeadersPath: "include",
			cSettings: [.headerSearchPath("src")]
		)
	}
)
