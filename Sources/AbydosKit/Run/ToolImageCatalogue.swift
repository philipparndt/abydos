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
	]

	public static func tool(forKey key: String) -> Tool? {
		tools.first { $0.key == key }
	}

	/// What the choice control offers for a tool: the installed copy, the known
	/// images, and naming one yourself.
	public static func options(for tool: Tool) -> [(label: String, value: String)] {
		[(label: "Installed on this machine", value: useInstalled)]
			+ tool.choices.map { (label: $0.label, value: $0.image) }
			+ [(label: "Custom image…", value: custom)]
	}

	/// Which option a stored value corresponds to.
	///
	/// Anything that is not a known image is "custom", so a project that pins a
	/// version — `plantuml/plantuml:1.2025.4` — shows as custom with its name
	/// in the field beside it rather than as nothing at all.
	public static func selection(for stored: String, tool: Tool) -> String {
		guard !stored.isEmpty else { return useInstalled }
		return tool.choices.contains { $0.image == stored } ? stored : custom
	}
}
