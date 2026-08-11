import Foundation

/// The preferences that decide which server answers for a language and where a
/// tool comes from, held together so that a change to one of them can be told
/// apart from a change to anything else in the settings.
///
/// Settings post one notification for every write and say nothing on it about
/// what was written, so anything wanting to react to *these three* has to keep
/// what they were and compare. That is the whole of this type, and 0460 is why
/// it exists: an image was chosen for a server that had already failed, the
/// preference was written correctly, and nothing happened at all — because what
/// was remembered about the failure was remembered under conditions that had
/// just changed, and nothing went back to look.
///
/// Three settings rather than the one that was reported, because all three are
/// remembered the same way. **Where a tool comes from** is the case somebody
/// hit. **Which server a language uses** is the same question one step along: a
/// project moving from jdtls to kmp-lsp after jdtls has failed is stuck
/// identically. And **the container runtime** sits behind both, since "nothing
/// here can run a container" is remembered as a failure too, and choosing a
/// runtime that *is* installed should undo it.
public struct ToolPreferences: Equatable, Sendable {
	/// Tool name to image, as `Settings.toolImages` holds it.
	public let images: [String: String]
	/// Language id to the name of the server chosen for it, as
	/// `Settings.languageServers` holds it.
	public let servers: [String: String]
	/// Which runtime an image is run by, as `ContainerRuntime.Preference` spells
	/// it.
	public let runtime: String

	/// - Note: an empty value is the same as no value in both tables, and this
	///   is where the settings page's half-finished states stop.
	///
	///   Choosing "Custom image" in the popup writes an empty string for the
	///   tool before anybody has typed the name — it means "the one I am about
	///   to give you", not a change to where anything comes from — and a reader
	///   that told the two apart would stop a running server on the way to a
	///   value that does not exist yet. Everything downstream already treats an
	///   empty image as no image, so this is agreement rather than a new rule.
	public init(images: [String: String], servers: [String: String], runtime: String) {
		self.images = Self.meaningful(images)
		self.servers = Self.meaningful(servers)
		self.runtime = runtime
	}

	public init(_ settings: Settings) {
		self.init(
			images: settings.toolImages,
			servers: settings.languageServers,
			runtime: settings.containerRuntime
		)
	}

	private static func meaningful(_ table: [String: String]) -> [String: String] {
		table.compactMapValues {
			let trimmed = $0.trimmingCharacters(in: .whitespaces)
			return trimmed.isEmpty ? nil : trimmed
		}
	}

	/// What is different between this and what was in force before.
	///
	/// By tool and by language rather than as one flag, because the answer
	/// decides what gets stopped and started: "something changed" would restart
	/// every server in every open project the first time somebody moved a
	/// slider on another page.
	public struct Change: Equatable, Sendable {
		/// Tools whose image is a different answer than it was.
		public let tools: Set<String>
		/// Languages pointed at a different server.
		public let languages: Set<String>
		/// Whether the runtime changed, which is a change to where *every* tool
		/// that comes from an image comes from.
		public let runtime: Bool

		public init(tools: Set<String>, languages: Set<String>, runtime: Bool) {
			self.tools = tools
			self.languages = languages
			self.runtime = runtime
		}

		public var isEmpty: Bool { tools.isEmpty && languages.isEmpty && !runtime }
	}

	public func changes(since previous: ToolPreferences) -> Change {
		Change(
			tools: Self.keysThatDiffer(previous.images, images),
			languages: Self.keysThatDiffer(previous.servers, servers),
			runtime: runtime != previous.runtime
		)
	}

	/// Every key either side has an answer for, where the two answers are not
	/// the same — which includes one side having no answer at all.
	private static func keysThatDiffer(
		_ before: [String: String], _ after: [String: String]
	) -> Set<String> {
		Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
	}
}

/// What one project has to forget, and what of it has to be stopped, because a
/// preference that decided those things has changed.
///
/// Worked out here rather than where it is applied, so that the rule can be
/// checked without a window and without a language server. What the answer is
/// *used* for is short — take some keys out of the tables that remember
/// refusals, stop the servers that are no longer the ones being asked for, and
/// start what the project needs again — and getting the set wrong in either
/// direction is the whole risk: too small and the preference goes on changing
/// nothing, too large and changing an image for one tool re-imports a Java
/// project that was working.
public struct ServerReconsideration: Equatable, Sendable {
	/// Keys whose remembered answer — unavailable, the hint above the file, the
	/// refusal already said out loud — was given under conditions that have
	/// changed, and is no longer evidence of anything.
	public let forget: Set<String>
	/// Keys whose *running* server is no longer the one being asked for, either
	/// because another server has been chosen for its language or because it is
	/// no longer meant to be coming from where it came from.
	public let stop: Set<String>
	public var isEmpty: Bool { forget.isEmpty && stop.isEmpty }

	/// - Parameters:
	///   - change: what moved in the settings.
	///   - project: the checkout being reconsidered, which is what the keys are
	///     built from.
	///   - was: the choices and images in force a moment ago, already merged
	///     with the project's own file.
	///   - now: the same two, read again.
	///   - running: the keys of the servers this project has running.
	///   - inDevContainer: whether this project's servers live inside its own
	///     devcontainer, in which case where a tool comes from out here is not a
	///     question it asks.
	public init(
		change: ToolPreferences.Change,
		project: URL,
		was: LanguageServerChoices,
		wasFrom: ToolImages,
		now: LanguageServerChoices,
		nowFrom: ToolImages,
		running: Set<String>,
		inDevContainer: Bool,
		among servers: [LanguageServerDefinition] = LanguageServers.known
	) {
		var forget: Set<String> = []
		var stop: Set<String> = []

		// **Which server answers for a language.** A server is filed under its
		// own name, so choosing another one moves the project to a key of its
		// own — which is what makes the *new* server startable without anything
		// being forgotten at all. What is left over is the old one: it is still
		// running, under a key nothing will ask about again, and it goes on
		// publishing diagnostics over files from a server the project no longer
		// uses. Nothing else in this program would ever stop it.
		for languageId in change.languages {
			let before = LanguageServers.serverKey(
				project: project, languageId: languageId, choosing: was, among: servers
			)
			let after = LanguageServers.serverKey(
				project: project, languageId: languageId, choosing: now, among: servers
			)
			// The project's file wins over the setting, so a setting that changed
			// is not necessarily a project that changed. Checked by comparing the
			// merged answers rather than by asking whether there is a file: a
			// project that names the same server the setting now names has
			// nothing to do either.
			guard before != after else { continue }
			forget.insert(before)
			forget.insert(after)
			if running.contains(before) { stop.insert(before) }
		}

		// **Where a tool comes from.** A project worked on inside its own
		// devcontainer takes its servers from in there and asks neither
		// question, so an image named out here is not a change to anything it
		// does — and stopping its server would cost the container's own start
		// for nothing.
		if !inDevContainer {
			var tools = change.tools.filter { wasFrom.image(for: $0) != nowFrom.image(for: $0) }
			if change.runtime {
				// The runtime is what every image is run by, so changing it
				// changes where every tool that comes from one comes from —
				// including the one that came from nowhere because nothing here
				// could run a container at all, which is the failure this is
				// most worth undoing. Only tools with an image named: a project
				// that names none is not affected by which runtime would have
				// run them.
				tools.formUnion(wasFrom.images.keys)
				tools.formUnion(nowFrom.images.keys)
			}
			for tool in tools {
				let key = LanguageServers.serverKey(project: project, server: tool)
				forget.insert(key)
				// A running server is running from where it was asked to come
				// from a moment ago, which is not where it is asked to come from
				// now. Stopped and started again rather than left alone: leaving
				// it is the second half of the same fault — the preference is
				// stored, the editor is answered by the copy it was meant to
				// replace, and nothing on screen disagrees with what was asked
				// for.
				if running.contains(key) { stop.insert(key) }
			}
		}

		self.forget = forget
		self.stop = stop
	}
}
