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
	///
	/// The same two formats every diagram in this app is exported to, whichever
	/// tool draws it: the menu says PNG and SVG over a `.puml` and over a `.mmd`
	/// alike, and one type for both is what keeps the two menus from drifting.
	public typealias Format = DiagramFormat

	/// What a preview asks for, whichever way the diagram is drawn.
	///
	/// SVG, for the resolution. PlantUML sizes a PNG in points — a diagram that
	/// comes back 834 pixels wide reports itself as 834 points wide — and a
	/// screen with a backing scale factor of 2 draws those 834 points across
	/// 1668 pixels, so every pixel of the picture is stretched over two of the
	/// screen's. That is the whole of why previews looked soft, and it is the
	/// same fault the terminal fixed by reporting a cell in pixels rather than
	/// in points. A drawing has no resolution to be wrong about: it is
	/// rasterised at whatever the screen can draw, so it is sharp on a Retina
	/// display and stays sharp through the app's own ⌘+ as well, which asking
	/// for twice the pixels would not.
	///
	/// One constant rather than a default at each call, because there are two
	/// ways a diagram is drawn — the kept-warm server and `docker run … -pipe`
	/// behind it — and a picture whose sharpness depended on which of them
	/// happened to answer would read as an intermittent fault.
	public static let previewFormat: Format = .svg

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
	///
	/// - Parameter name: what to call the container, for the image form. A
	///   render that hangs is stopped by removing the container by name, and a
	///   container with no name cannot be found again at all — see 0406.
	/// - Parameter theme: which way round to draw it, or nil to impose nothing —
	///   which is what a file that states its own look gets.
	public static func invocation(
		for tool: Tool,
		format: Format = .png,
		name: String? = nil,
		theme: DiagramTheme? = nil
	) -> (executable: String, arguments: [String]) {
		// `-charset UTF-8` because a diagram with a German label in it is not
		// exotic, and the default depends on the platform's locale.
		let common = ["-pipe", "-t\(format.rawValue)", "-charset", "UTF-8"] + darkFlag(theme)
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
			return container.named(name).invocation(using: runtime, arguments: common)
		}
	}

	// MARK: - Which way round it is drawn

	/// PlantUML's own name for "draw this dark", and it is a command-line flag
	/// rather than anything that can be written in a diagram.
	///
	/// **Measured, on `plantuml/plantuml:1.2026.6`, before any of this was
	/// designed** — because 0429 asked for that and because the answer decided
	/// the shape of the whole change:
	///
	///  * `--dark-mode` exists, and so does `--theme <name>`. Either draws a dark
	///    picture; `--dark-mode` is PlantUML's own idea of dark rather than one of
	///    the forty-odd shipped themes, so it is the one that does not overrule an
	///    author by picking a palette for them.
	///  * `--dark-mode` emits an actual `<rect fill="#1B1B1B">` as the first thing
	///    in the drawing. That matters more than it sounds: the light output
	///    states its background as CSS on the root element, which CoreSVG ignores
	///    — which is exactly why the pane paints paper by hand. The dark output
	///    needs no paper painted for it, and covers whatever is painted anyway.
	///  * **There is no way to say it in a diagram.** There is no `!pragma` for
	///    it (the whole `PragmaKey` list was read out of the jar), no `skinparam`,
	///    and no preprocessor variable — dark mode is global configuration that
	///    the `%is_dark()` builtin can only *read*. So the only source-level dark
	///    is `!theme <one of the dark ones>`, which is picking somebody's palette
	///    for them.
	///  * **The kept-warm HTTP route cannot carry it.** `/plantuml/<format>/~h<hex>`
	///    is the source and nothing else: `?dark=true` on the end is answered 500,
	///    and there is no `/plantuml/dsvg/…`. Measured against a live server.
	///
	/// Those two together are why nothing is injected into anybody's source, not
	/// even into the copy sent to the renderer: the flag goes on the command line
	/// for `-pipe`, and the kept-warm server is started with it and kept per
	/// theme — see `PlantUMLServers`. Both routes then draw the same picture,
	/// which is the property the format already had and would have lost.
	static func darkFlag(_ theme: DiagramTheme?) -> [String] {
		theme?.isDark == true ? ["--dark-mode"] : []
	}

	/// What in a diagram states a look of its own, or nil when it says nothing.
	///
	/// The question is about PlantUML's language, so the answer is here. Three
	/// things count, and the third is the one 0429 named explicitly — a diagram
	/// that sets only a background colour has still chosen:
	///
	///  * `!theme <name>`, which is the whole of choosing a palette.
	///  * `skinparam backgroundColor <colour>`, in either of its two spellings —
	///    on its own line, or inside a `skinparam { … }` block.
	///  * `BackgroundColor` inside a `<style>` block, which is the same decision
	///    in PlantUML's newer style language.
	///
	/// What does *not* count is a `skinparam` that colours one thing —
	/// `sequenceArrowColor red` is somebody colouring an arrow, not somebody
	/// choosing how the diagram is lit, and treating it as a choice would take
	/// the app's theme away from most real diagrams.
	public static func statedLook(in source: String) -> String? {
		var inSkinparamBlock = false
		var inStyleBlock = false
		for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = raw.trimmingCharacters(in: .whitespaces)
			let lower = line.lowercased()
			if lower.hasPrefix("'") { continue }

			if lower.hasPrefix("!theme ") {
				return line.split(separator: " ").prefix(2).joined(separator: " ")
			}
			if lower.hasPrefix("<style") { inStyleBlock = true; continue }
			if lower.hasPrefix("</style") { inStyleBlock = false; continue }
			if lower.hasPrefix("skinparam"), line.hasSuffix("{") {
				inSkinparamBlock = true
				continue
			}
			if inSkinparamBlock, lower.hasPrefix("}") { inSkinparamBlock = false; continue }

			if lower.hasPrefix("skinparam backgroundcolor") { return "skinparam backgroundColor" }
			if inSkinparamBlock, lower.hasPrefix("backgroundcolor") {
				return "skinparam backgroundColor"
			}
			if inStyleBlock, lower.hasPrefix("backgroundcolor") { return "<style> BackgroundColor" }
		}
		return nil
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
