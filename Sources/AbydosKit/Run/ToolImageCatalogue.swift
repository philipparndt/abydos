import Foundation

/// The images known to work for a tool, and what any other image has to do.
///
/// Typing an image name into a settings field is a guess: nothing says whether
/// it holds the tool, whether the tool is on its entry point, or whether it
/// reads what the app is going to send it. A short list of images that are
/// known to work turns that into a choice, and where somebody names their own
/// the requirements are written down beside the field rather than discovered
/// through an empty pane.
public enum ToolImageCatalogue {
	/// One image somebody can pick.
	public struct Choice: Equatable, Sendable {
		/// What to call it in a menu.
		public let label: String
		/// The image, as `docker pull` would name it.
		public let image: String
		/// Who publishes it, said plainly: whose word this is that it works.
		public let publisher: String

		public init(label: String, image: String, publisher: String) {
			self.label = label
			self.image = image
			self.publisher = publisher
		}
	}

	/// A tool that can come from an image, and everything a settings page has
	/// to say about it.
	public struct Tool: Equatable, Sendable {
		/// The key it is stored under, in settings and in `.abydos/tools.json`.
		public let key: String
		public let title: String
		/// Images known to work, best first.
		public let choices: [Choice]
		/// What an image has to provide, for somebody naming their own. Written
		/// as the contract it is, since anything else leaves them guessing at
		/// why a pane is empty.
		public let requirement: String

		public init(key: String, title: String, choices: [Choice], requirement: String) {
			self.key = key
			self.title = title
			self.choices = choices
			self.requirement = requirement
		}
	}

	/// The value meaning "no image": use whatever is installed on the machine.
	public static let useInstalled = ""

	/// The value meaning "an image I will name myself".
	public static let custom = "custom"

	public static let tools: [Tool] = [
		Tool(
			key: "plantuml",
			title: "PlantUML",
			// Only images that meet the contract below. `plantuml/plantuml-server`
			// is the same project's other image and is a web service: it answers
			// HTTP and knows nothing about `-pipe`, so listing it as known-good
			// would be listing something that fails in the way this list exists
			// to prevent.
			choices: [
				Choice(
					label: "plantuml/plantuml (latest)",
					image: "plantuml/plantuml",
					publisher: "the PlantUML project"
				),
				Choice(
					label: "plantuml/plantuml (pinned to 1.2025.4)",
					image: "plantuml/plantuml:1.2025.4",
					publisher: "the PlantUML project"
				),
			],
			// The contract this app actually relies on, and nothing more: the
			// same one `plantuml -pipe` has.
			requirement: """
			The image must run PlantUML as its entry point, so that arguments \
			given to `docker run` reach it: it is passed -pipe -tpng, reads the \
			diagram on standard input and writes a PNG to standard output. \
			Graphviz has to be in the image for any diagram that needs it — \
			class, state and component diagrams do; sequence diagrams do not.
			"""
		),
		// The language servers, which are the tools somebody would otherwise
		// have to install by hand — a Go toolchain to get gopls, a Rust one for
		// rust-analyzer, a JDK for jdtls.
		//
		// Each lists one image, and every one of them went the same way round
		// before it appeared here: built from `ToolImages/<tool>/Dockerfile`,
		// pushed for both architectures by `make toolimage-publish TOOL=<tool>`,
		// fetched back out of Docker Hub by a runtime that had none of it, and
		// driven end to end by `ContainerLSPLiveTests` against a project of its
		// own language — diagnostics, symbols and a go-to-declaration, every one
		// of them naming a file on this machine. An entry here is that claim and
		// nothing weaker, which is why `ToolContainerTests` refuses one for an
		// image that test would not run.
		//
		// The requirement beside each is a description rather than a wish: the
		// server is the entry point with no wrapper to print a banner before the
		// first header, the project is read at /workspace, and whatever the
		// server shells out to is in the image — which is the whole reason these
		// are built on a toolchain rather than being a slim image with a binary
		// copied into it.
		//
		// Every tag is `dev`, because that is the only tag in each repository —
		// `VERSION` defaulted. Listing a version that reads better and cannot be
		// pulled is the exact failure this list exists to prevent. That the tag
		// moves is said in each label rather than here, because the person it
		// matters to is choosing in a menu and will never read this; when a
		// version tag is pushed it becomes the entry and `:dev` stops being
		// offered.
		//
		// The labels carry the image's own name, the way the PlantUML ones do,
		// so what is on screen is what would be pulled — 0401 drafted these as
		// "abydos/<tool>", which is neither the repository nor anything somebody
		// could type — and then the versions inside it, since that is what
		// somebody is choosing between.
		Tool(
			key: "gopls",
			title: "Go — gopls",
			choices: [
				Choice(
					label: "pharndt/abydos-gopls:dev (gopls 0.23.0, Go 1.26 — a tag that moves)",
					image: "pharndt/abydos-gopls:dev",
					publisher: "the Abydos project"
				),
			],
			requirement: languageServerRequirement("gopls")
		),
		Tool(
			key: "rust-analyzer",
			title: "Rust — rust-analyzer",
			choices: [
				Choice(
					// The server's version is the toolchain's, and deliberately: it
					// comes from `rustup component add`, so a project is never read
					// by a rust-analyzer newer than the compiler it is asked about.
					label: "pharndt/abydos-rust-analyzer:dev (rust-analyzer 1.97.1, Rust 1.97 — a tag that moves)",
					image: "pharndt/abydos-rust-analyzer:dev",
					publisher: "the Abydos project"
				),
			],
			requirement: languageServerRequirement("rust-analyzer")
		),
		Tool(
			key: "pyright",
			title: "Python — pyright",
			choices: [
				Choice(
					// The Python in the label is the interpreter pyright asks where
					// site-packages are, not one a project runs on. What a project's
					// own environment holds is visible in there only if it lives
					// inside the project directory.
					label: "pharndt/abydos-pyright:dev (pyright 1.1.411, Python 3.11 — a tag that moves)",
					image: "pharndt/abydos-pyright:dev",
					publisher: "the Abydos project"
				),
			],
			requirement: languageServerRequirement("pyright-langserver --stdio")
		),
		Tool(
			key: "typescript-language-server",
			title: "TypeScript — typescript-language-server",
			choices: [
				Choice(
					// TypeScript 5 and not 7, which is the native compiler and ships
					// no `tsserver.js` for this server to drive at all. A project's
					// own copy still wins over the one in the image.
					label: "pharndt/abydos-typescript-language-server:dev (server 5.3.0, TypeScript 5.9 — a tag that moves)",
					image: "pharndt/abydos-typescript-language-server:dev",
					publisher: "the Abydos project"
				),
			],
			requirement: languageServerRequirement("typescript-language-server --stdio")
		),
		Tool(
			key: "clangd",
			title: "C and C++ — clangd",
			choices: [
				Choice(
					label: "pharndt/abydos-clangd:dev (clangd 19.1.7 — a tag that moves)",
					image: "pharndt/abydos-clangd:dev",
					publisher: "the Abydos project"
				),
			],
			requirement: languageServerRequirement("clangd")
		),
		Tool(
			key: "jdtls",
			title: "Java — jdtls",
			choices: [
				Choice(
					// One JDK in the image, so a project targeting an older release
					// is compiled against this one; and no java-debug bundle, so
					// there is no debugging through it.
					label: "pharndt/abydos-jdtls:dev (jdtls 1.55.0, Java 21 — a tag that moves)",
					image: "pharndt/abydos-jdtls:dev",
					publisher: "the Abydos project"
				),
			],
			requirement: languageServerRequirement("jdtls")
		),
		// No published image, and none is wanted: this is the tool the
		// build-here route was written for. Its install hint is `cargo install
		// openscad-lsp`, which is a Rust toolchain on the machine to get one
		// binary — so almost nobody has it installed, and the option offered
		// beside "Installed on this machine" is `ToolImages/openscad-lsp`,
		// built here the first time a `.scad` is opened in a project that asks
		// for it. `options(for:)` adds that entry itself, for any tool a
		// Dockerfile ships for, so there is nothing to list here.
		// The other tool with no published image, and for a different reason than
		// openscad-lsp: what this repository builds is a *fork*, and publishing an
		// image of somebody else's server with a patch in it under this project's
		// name is a claim nobody asked us to make. The recipe says which commit and
		// why, which is a thing a person can read and check; an image on Docker Hub
		// is not. See `ToolImages/kmp-lsp/Dockerfile`.
		Tool(
			key: "kmp-lsp",
			title: "Java — kmp-lsp",
			choices: [],
			requirement: languageServerRequirement("kmp-lsp") + """
			 \nThis one server is the exception to the sentence above, and it is why \
			it is chosen at all: it has no classpath and runs no build tool, so it \
			finds a library's source by walking the caches the build tools left \
			behind. Abydos mounts three directories into it — ~/.m2/repository and \
			~/.gradle/caches read-only at /root/.m2/repository and \
			/root/.gradle/caches, and ~/.cache/kmp-lsp writable at \
			/root/.cache/kmp-lsp, where it unpacks a source file out of a jar so \
			that this editor can open it. An image that looks anywhere else for \
			them finds no dependencies and says nothing about it. It also needs \
			`kmp-jar-indexer` in the same directory as the server: without it the \
			whole jar pipeline is skipped, sources JARs included.
			"""
		),
		Tool(
			key: "openscad-lsp",
			title: "OpenSCAD — openscad-lsp",
			choices: [],
			requirement: languageServerRequirement("openscad-lsp --stdio")
		),
	]

	/// What every language server image has to do, which is the same for all of
	/// them: speak the protocol on standard input and output, and see the
	/// project. Written once because repeating it six times would let the six
	/// drift apart.
	private static func languageServerRequirement(_ command: String) -> String {
		"""
		The image must run `\(command)` as its entry point, speaking the \
		language server protocol on standard input and output — not a wrapper \
		that prints a banner first, since the first thing sent is a header. The \
		project is mounted at /workspace and the server is started there, so it \
		has to be able to read it. Anything it needs beyond the project — a \
		toolchain, a module cache, an index — has to be in the image, because \
		nothing else on this machine is visible from inside it.
		"""
	}

	public static func tool(forKey key: String) -> Tool? {
		tools.first { $0.key == key }
	}

	/// What the choice control offers for a tool: the installed copy, the known
	/// images, building the recipe this app ships, and naming one yourself.
	///
	/// The third one is offered only for a tool a Dockerfile exists for, and it
	/// sits between the published images and the custom field on purpose — it
	/// is the same kind of answer as the ones above it, "here is an image that
	/// works", and differs only in where the image comes from. It displaces
	/// neither: a tool whose build is genuinely expensive keeps the published
	/// route, and both entries can be on the list at once.
	public static func options(for tool: Tool) -> [(label: String, value: String)] {
		[(label: "Installed on this machine", value: useInstalled)]
			+ tool.choices.map { (label: $0.label, value: $0.image) }
			+ (ToolImageRecipes.recipe(forTool: tool.key) == nil
				? []
				: [(label: "Built on this machine from the recipe Abydos ships",
				    value: ToolImageRecipes.buildHere)])
			+ [(label: "Custom image…", value: custom)]
	}

	/// Which option a stored value corresponds to.
	///
	/// Anything that is not a known image is "custom", so a project that pins a
	/// version — `plantuml/plantuml:1.2025.4` — shows as custom with its name
	/// in the field beside it rather than as nothing at all.
	public static func selection(for stored: String, tool: Tool) -> String {
		guard !stored.isEmpty else { return useInstalled }
		// Before the list, because it is not an image name and would otherwise
		// fall through to "custom" — which would put the word `build` in the
		// field beside it as though somebody had typed it as an image.
		if stored == ToolImageRecipes.buildHere { return stored }
		return tool.choices.contains { $0.image == stored } ? stored : custom
	}
}
