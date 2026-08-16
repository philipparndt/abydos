import Foundation

/// A Swift file that is a 3D model: one of the sources of an executable target
/// that depends on [Cadova](https://github.com/tomasf/Cadova).
///
/// **The question this answers is not "what is in this file".** Every other
/// preview in the app routes on a name — a `.puml` is a diagram, a `.scad` is a
/// shape — and a `.swift` says nothing at all, because nearly every `.swift`
/// ever written is not a model. A go3mf recipe had the same problem and
/// `Go3mfRecipe` solves it by reading the head of the file; that answer does not
/// work here, because a Cadova model is not a file, it is a *program*: the
/// target's other sources are as much a part of the shape as the one with
/// `Model("hexholder")` in it, and running the target is what makes geometry.
///
/// So the signal is the manifest, which is the only place that says Cadova out
/// loud, and the unit is the target, which is what gets built and run. See 0499
/// for the three answers this represents and why the alternatives lost.
///
/// **What it costs to ask.** A walk up from the file to `Package.swift`, and one
/// read and scan of that manifest — no subprocess, and nothing at all once the
/// walk fails, which it does immediately for a file that is not in a package.
/// Ask it about a file being opened, like `Go3mfRecipe.looksLikeRecipe`; do not
/// ask it about a directory.
public struct CadovaModel: Equatable, Sendable {
	/// The dependency that makes a target a model.
	///
	/// Cadova's product is spelled exactly this, and matching it against every
	/// string literal in the target's `dependencies:` catches both the bare
	/// `"Cadova"` and `.product(name: "Cadova", package: "Cadova")`.
	public static let dependency = "Cadova"

	/// Where `swift run` is invoked, which — since 0498 said so out loud and put
	/// a test behind it — is also where the `.3mf` lands.
	public let packageDirectory: URL
	/// What `swift run` is given: the product's name, not the target's.
	public let product: String
	/// The target's sources. What is watched, because editing any of them
	/// changes the shape, and the file in front is only one of them.
	public let sources: [URL]

	public init(packageDirectory: URL, product: String, sources: [URL]) {
		self.packageDirectory = packageDirectory
		self.product = product
		self.sources = sources
	}

	/// The command line, as somebody would type it in the package root.
	public var command: String { "swift run \(product)" }

	/// The model this file is part of, or nil.
	///
	/// - Parameter stoppingAt: the project root, so the walk up does not climb
	///   out of what is open and find a manifest in somebody's home directory.
	///   Nil walks to the top of the volume, which is what a file opened from
	///   outside a project gets.
	public static func find(for fileURL: URL, stoppingAt root: URL? = nil) -> CadovaModel? {
		// `Package.swift` is a manifest rather than a model, and it is a `.swift`
		// file inside the package it describes — so without this it would be
		// offered a viewer by whichever target's directory it happened to fall in
		// (none, in the standard layout, but a `path: "."` target claims it).
		guard fileURL.pathExtension.lowercased() == "swift",
		      fileURL.lastPathComponent != "Package.swift"
		else { return nil }

		let file = fileURL.standardizedFileURL
		let limit = root?.standardizedFileURL.resolvingSymlinksInPath().path
		var directory = file.deletingLastPathComponent()

		while true {
			if let package = SwiftPackage.find(in: directory),
			   let model = model(in: package, for: file) {
				return model
			}
			// The walk stops at the project root *after* looking at it, so a file
			// in the project's own package is found.
			if let limit, directory.resolvingSymlinksInPath().path == limit { return nil }
			let parent = directory.deletingLastPathComponent().standardizedFileURL
			guard parent.path != directory.path, parent.path != "/" else { return nil }
			directory = parent
		}
	}

	/// The same question against a manifest already read.
	static func model(in package: SwiftPackage, for fileURL: URL) -> CadovaModel? {
		guard let target = package.target(containing: fileURL),
		      target.dependencies.contains(dependency),
		      let product = package.runnableName(for: target)
		else { return nil }
		return CadovaModel(
			packageDirectory: package.directory.standardizedFileURL,
			product: product,
			sources: package.sourceDirectories(of: target)
		)
	}
}

/// Reading what a Cadova run said.
///
/// A run is `swift run <product>` in the package root, and two things have to be
/// got out of it: **where the model went**, which Cadova prints and nothing else
/// knows, and **why there is no model**, which is a compiler most of the time.
///
/// Kept apart from the pane that shows it so that the parsing is testable
/// against real output, which is the only way to be sure about the second: a
/// failed build on this machine is 130 lines of stderr, most of it one
/// `swift-frontend` command line, with the four lines somebody needs in the
/// middle of it.
public enum CadovaRun {
	/// The line Cadova prints when it has written a model.
	///
	/// Measured rather than guessed — the spike for 0499 prints, on stdout:
	///
	///     2026-08-16T11:47:03.401 [INFO] Wrote model to /…/cadova-spike/hexholder.3mf
	///
	/// The path is absolute, so nothing has to be resolved against anything.
	static let wroteMarker = "Wrote model to "

	/// The model a run wrote, from what it said.
	///
	/// The last such line, not the first: a target may write more than one model,
	/// and the pane shows one. (Which one is a question nobody has asked yet; the
	/// last is at least the one Cadova finished with.)
	public static func wroteModel(in output: String) -> URL? {
		var found: URL?
		for line in stripped(output).split(whereSeparator: \.isNewline) {
			guard let marker = line.range(of: wroteMarker) else { continue }
			let path = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
			guard path.hasPrefix("/") else { continue }
			found = URL(fileURLWithPath: path)
		}
		return found
	}

	/// The newest `.3mf` written into a directory since a moment.
	///
	/// The fallback for a Cadova that words its line differently, and the reason
	/// there is no directory watcher: this is one listing at the end of a run
	/// that has already finished, rather than a stream of events to filter for
	/// the whole time a pane is open. Not recursive, because the working
	/// directory of the run is the package root and that is where a model lands.
	public static func newestModel(in directory: URL, since start: Date) -> URL? {
		let keys: [URLResourceKey] = [.contentModificationDateKey]
		guard let entries = try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
		) else { return nil }

		var best: (url: URL, when: Date)?
		for entry in entries where entry.pathExtension.lowercased() == "3mf" {
			guard let when = try? entry.resourceValues(forKeys: Set(keys)).contentModificationDate,
			      // A second of slack: the run's start is taken in this process and
			      // the timestamp is the filesystem's, and a model written in the
			      // same second as the run began is this run's.
			      when >= start.addingTimeInterval(-1)
			else { continue }
			if best == nil || when > best!.when { best = (entry, when) }
		}
		return best?.url
	}

	/// What to show when a run produced no model.
	///
	/// The diagnostics, when the compiler gave any: every line with `error:` in
	/// it, and the source line SwiftPM prints under each one is left out because
	/// it arrives wrapped in colour codes and box drawing that a pane this narrow
	/// cannot lay out. When there are none — a run that crashed, a toolchain that
	/// refused the manifest, a shell that could not find `swift` — the tail of
	/// what was said, because that is the only clue there is.
	public static func complaint(in output: String) -> String {
		let text = stripped(output)
		let lines = text.split(whereSeparator: \.isNewline).map(String.init)
		let errors = lines.filter { $0.contains("error:") && !$0.hasPrefix(" ") }
		let chosen = errors.isEmpty ? Array(lines.suffix(tailLines)) : Array(errors.prefix(shownErrors))
		let said = chosen.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
		return said.isEmpty ? "The run said nothing and wrote no model." : said
	}

	/// How many diagnostics are worth showing before somebody should be reading
	/// the compiler's own output instead.
	static let shownErrors = 12
	/// How much of the end of a silent failure to show.
	static let tailLines = 12

	/// The last line of a piece of output that says anything.
	///
	/// What a pane shows while a build runs. Here rather than in the pane because
	/// it is called from the reading thread, where the pane — an `NSView`, and so
	/// on the main actor — is not.
	public static func lastLine(of piece: String) -> String? {
		stripped(piece)
			.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.last { !$0.isEmpty }
	}

	/// The same text without the terminal's colour codes.
	///
	/// SwiftPM colours its diagnostics whether or not it is talking to a
	/// terminal — measured, on a pipe — so a pane showing the text raw shows
	/// `[0;36m` in front of every line of it.
	public static func stripped(_ text: String) -> String {
		var result = ""
		result.reserveCapacity(text.count)
		var inEscape = false
		for character in text {
			if inEscape {
				// A CSI sequence ends at its final byte, which is the first
				// character in this range after the parameters.
				if let scalar = character.unicodeScalars.first,
				   (0x40...0x7E).contains(scalar.value), character != "[" {
					inEscape = false
				}
				continue
			}
			if character == "\u{1B}" { inEscape = true; continue }
			result.append(character)
		}
		return result
	}
}
