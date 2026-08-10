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
		// rust-analyzer, a JDK for jdtls. Only gopls lists an image: the point
		// of that list is that somebody has run the thing, and gopls is the one
		// that has been built, pushed, pulled back and driven. What is written
		// down for the other five instead is exactly what an image has to do,
		// which is the same for all of them and short.
		Tool(
			key: "gopls",
			title: "Go — gopls",
			// Built by `ToolImages/gopls/Dockerfile`, pushed by
			// `make toolimage-publish TOOL=gopls`, and — the part that earns it a
			// line here — pulled back from Docker Hub on this machine and driven
			// end to end by `ContainerLSPLiveTests`: diagnostics, symbols and a
			// go-to-declaration, every one of them naming a file on the host.
			// The requirement below is a description of it rather than a wish:
			// `gopls` is the entry point with no arguments and no wrapper, the
			// project is read at /workspace, and the Go toolchain it shells out
			// to is in the image, which is the whole reason the image exists.
			//
			// The tag is `dev` because that is the only tag in the repository —
			// `VERSION` defaulted, and listing `:0.23.0` because it reads better
			// would be listing something nobody can pull, which is the exact
			// failure this list exists to prevent. That it moves is said in the
			// label rather than here, because the person it matters to is
			// choosing it in a menu and will never read this. When a version tag
			// is pushed, that becomes this entry and `:dev` stops being offered.
			choices: [
				Choice(
					// The image's own name, the way the PlantUML labels are, so what
					// is on screen is what would be pulled — 0401 drafted this as
					// "abydos/gopls", which is neither the repository nor anything
					// somebody could type.
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
			choices: [],
			requirement: languageServerRequirement("rust-analyzer")
		),
		Tool(
			key: "pyright",
			title: "Python — pyright",
			choices: [],
			requirement: languageServerRequirement("pyright-langserver --stdio")
		),
		Tool(
			key: "typescript-language-server",
			title: "TypeScript — typescript-language-server",
			choices: [],
			requirement: languageServerRequirement("typescript-language-server --stdio")
		),
		Tool(
			key: "clangd",
			title: "C and C++ — clangd",
			choices: [],
			requirement: languageServerRequirement("clangd")
		),
		Tool(
			key: "jdtls",
			title: "Java — jdtls",
			choices: [],
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
