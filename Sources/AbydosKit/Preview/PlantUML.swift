import Foundation

/// Running PlantUML on a diagram, without shipping PlantUML.
///
/// Nothing is bundled and nothing is installed on anybody's behalf: PlantUML is
/// a Java program that draws with Graphviz, and the copy already on the machine
/// is the one whose version the diagrams were written against. What this does
/// is find whichever form of it is here, run it, and — when there is none — say
/// in one sentence what to install rather than leaving an empty pane.
///
/// Three forms, because all three are common:
///
///  * `plantuml` on the PATH, which is what Homebrew and most distributions
///    install, itself usually a shell script around the jar;
///  * a jar named by `PLANTUML_JAR`, which is how people who download the
///    release keep it;
///  * `java -jar` on a jar found where the downloads usually land.
public enum PlantUML {
	/// What the picture comes back as.
	public enum Format: String, Sendable, CaseIterable {
		case png
		case svg

		/// The flag that asks for it.
		var flag: String { "-t\(rawValue)" }
	}

	/// A PlantUML that is actually present.
	public enum Tool: Equatable, Sendable {
		/// The `plantuml` command, at this path.
		case command(String)
		/// A jar, run with the `java` at this path.
		case jar(path: String, java: String)
		/// An image, run by whichever container runtime is here. Nothing has to
		/// be installed for this one — which is the point of it.
		case image(ToolContainer, ContainerRuntime)

		/// What to say it is, for a pane that has to explain itself.
		public var description: String {
			switch self {
			case let .command(path): return path
			case let .jar(path, _):  return "java -jar \(path)"
			case let .image(container, runtime): return "\(runtime.name) run \(container.image)"
			}
		}
	}

	/// How to run it: reading the diagram on standard input and writing the
	/// picture to standard output.
	///
	/// `-pipe` is what makes that possible, and it is the only mode worth using
	/// here: the alternative writes a file beside the source, which means
	/// littering somebody's repository with pictures they did not ask for every
	/// time the preview refreshes.
	public static func invocation(
		for tool: Tool,
		format: Format = .png
	) -> (executable: String, arguments: [String]) {
		// `-charset UTF-8` because a diagram with a German label in it is not
		// exotic, and the default depends on the platform's locale.
		let common = ["-pipe", format.flag, "-charset", "UTF-8"]
		switch tool {
		case let .command(path):
			return (path, common)
		case let .jar(path, java):
			// `-Djava.awt.headless=true` or the JVM bounces the Dock icon and
			// steals focus every time a preview refreshes.
			return (java, ["-Djava.awt.headless=true", "-jar", path] + common)
		case let .image(container, runtime):
			// The image's own entry point is PlantUML, so the same flags go to
			// it. Nothing is mounted: the diagram arrives on standard input and
			// the picture leaves on standard output, so the container never
			// needs to see the project at all.
			return container.invocation(using: runtime, arguments: common)
		}
	}

	/// Where a downloaded jar usually is.
	public static let jarDirectories = [
		"/opt/homebrew/opt/plantuml/libexec",
		"/usr/local/opt/plantuml/libexec",
		"/opt/homebrew/share/plantuml",
		"/usr/local/share/plantuml",
		"/usr/share/plantuml",
	]

	/// The name it is usually saved under.
	public static let jarNames = ["plantuml.jar", "plantuml-mit.jar"]

	/// Finds a PlantUML, or nothing.
	///
	/// - Parameters:
	///   - environment: the process environment, for `PLANTUML_JAR`.
	///   - locate: how to find a command on the PATH.
	///   - fileExists: how to check a jar is there.
	public static func discover(
		image: String? = nil,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		locate: (String) -> String? = { Executables.locate($0) },
		fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
		runtime: ContainerRuntime? = nil,
		runtimePreference: ContainerRuntime.Preference = .automatic
	) -> Tool? {
		// An image that was asked for wins over anything installed. Naming one
		// is a decision — this project's diagrams are drawn by that version —
		// and a local copy quietly overriding it would make the same file look
		// different on two machines, which is what naming it was meant to stop.
		if let image, !image.isEmpty,
		   let runtime = runtime ?? ContainerRuntime.discover(preference: runtimePreference, locate: locate) {
			return .image(ToolContainer(image: image), runtime)
		}

		// The command next: somebody who installed it that way expects that
		// one to run, including whatever options its wrapper script sets.
		if let command = locate("plantuml") { return .command(command) }

		guard let java = locate("java") else { return nil }

		// Named outright: the setting people who download the release use.
		if let named = environment["PLANTUML_JAR"], !named.isEmpty, fileExists(named) {
			return .jar(path: named, java: java)
		}

		for directory in jarDirectories {
			for name in jarNames where fileExists("\(directory)/\(name)") {
				return .jar(path: "\(directory)/\(name)", java: java)
			}
		}
		return nil
	}

	/// The one sentence somebody needs when there is no PlantUML here.
	public static let installHint = """
		PlantUML is not installed. Either `brew install plantuml`, or name an \
		image in .abydos/tools.json — {"plantuml": "plantuml/plantuml"} — and \
		it will be drawn in a container instead.
		"""

	/// Whether a file is a diagram this draws.
	public static func isDiagram(_ url: URL) -> Bool {
		extensions.contains(url.pathExtension.lowercased())
	}

	/// The extensions PlantUML's own tooling recognises.
	public static let extensions = ["puml", "plantuml", "pu", "iuml", "wsd"]

	/// Whether what came back is a picture at all.
	///
	/// PlantUML answers a diagram it cannot parse with a picture of the error
	/// rather than with a failure, which is worth showing — it says which line
	/// is wrong, in the pane where the diagram would be. Empty output is the
	/// case that is not worth showing, and it is what a missing Graphviz looks
	/// like.
	public static func isPicture(_ data: Data) -> Bool { !data.isEmpty }

	/// A diagram that says nothing yet.
	///
	/// PlantUML refuses text with no `@start`, and an empty file or one
	/// somebody has only started typing is the ordinary state of a new
	/// document — not something to draw an error for.
	public static func hasDiagram(_ text: String) -> Bool {
		text.contains("@start")
	}
}
