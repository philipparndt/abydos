import Foundation

/// What a project or a person says about a language server beyond *which* one it
/// is and *where it comes from*: the executable to run, and what to tell it in
/// the initialize request.
///
/// The third question `.abydos/tools.json` answers, and it exists because the
/// first two cannot answer it. `LanguageServerChoices` picks a server by name;
/// `ToolImages` says where it comes from. Both name a *tool*, and every route
/// from a tool's name to a process on this machine goes through a `PATH` search
/// — which is exactly the step that fails when a toolchain manager owns the name.
///
/// ## Why a command has to be nameable, and not only for Rust
///
/// `~/.cargo/bin/rust-analyzer` is not rust-analyzer. It is a symlink to
/// `rustup`, byte for byte the same file as `~/.cargo/bin/rustc`, and what it
/// does when run is read the project's `rust-toolchain.toml` and hand the request
/// to the toolchain named there. In a project pinning `channel = "esp"` that is
/// Espressif's fork, which ships no rust-analyzer, and the proxy says so and
/// stops:
///
///     error: 'rust-analyzer' is not installed for the custom toolchain 'esp'.
///
/// There *is* a rust-analyzer that reads that project perfectly — any recent one
/// — because the server is an ordinary executable that shells out to whatever
/// `cargo` the pin resolves to. Reaching it needs one thing the app could not
/// express: an absolute path instead of a name. Measured in 0466, with a stable
/// 1.95 rust-analyzer against a project pinned to the fork: `Vec` resolved into
/// `~/.rustup/toolchains/esp/lib/rustlib/src`, and `#[derive(Serialize)]`
/// expanded out of a dylib the fork's own `rustc` had compiled.
///
/// Every toolchain manager that puts a proxy on the `PATH` has this shape —
/// `pyenv`'s shims, `rbenv`'s, `asdf`'s, `mise`'s — so this is not a Rust escape
/// hatch. It is the one thing missing from "where does the tool come from".
///
/// ## And what to tell it
///
/// `initializationOptions` is the other half, and it was compiled in: jdtls's
/// JDKs and debug bundle, and nothing for anybody else. A setting a *project*
/// needs cannot be a table in this repository — rust-analyzer's
/// `procMacro.server` is a path into a toolchain only that machine has, and the
/// day the fork's proc-macro ABI drifts from the analyzer's it is what makes
/// macro expansion work at all. So it is here, beside the command, in the file
/// that already knows about this project.
///
/// ## The shape
///
///     {
///       "rust-analyzer": {
///         "command": "~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/rust-analyzer",
///         "initializationOptions": {
///           "procMacro": { "server": "~/.rustup/toolchains/esp/libexec/rust-analyzer-proc-macro-srv" }
///         }
///       }
///     }
///
/// Only the table form. A bare string beside a tool's name already means its
/// image, and has since `ToolImages`, so the string cannot be made to mean a
/// second thing — which is what the table was added for.
public struct LanguageServerOverrides: Equatable, Sendable {
	/// What was said about one server.
	public struct Override: Equatable, Sendable {
		/// The executable to run instead of looking the command up on the `PATH`.
		///
		/// A path, and `LanguageServers.executable(for:)` already treats a command
		/// containing `/` as one — so this needs no new rule, only somewhere for a
		/// person to write it. `~` is expanded, because the whole point of writing
		/// it down is that it can be written down: a checked-in file naming
		/// `/Users/somebody/.rustup/…` is one machine's, and `~/.rustup/…` is
		/// everybody's who installed the same way.
		///
		/// Where the server comes from an image this is the command *inside* it,
		/// and the same absolute path is the answer there for the same reason. See
		/// `LanguageServers.resolve`.
		public let command: String?
		/// Merged over whatever the app would have sent, this side winning.
		///
		/// Deep, key by key, so a project adding `procMacro.server` to jdtls-style
		/// options does not silently drop the runtimes underneath it.
		///
		/// **Passed through exactly as written, `~` and all.** Unlike `command`
		/// above, nothing in here is known to be a path — these are one server's
		/// settings, and this app does not have a schema for any of them. Guessing
		/// that a string starting with `~` is a home-relative path would be right
		/// for `procMacro.server` and wrong for the first setting whose value
		/// legitimately begins with one. So a server that wants an absolute path has
		/// to be given one, and the recipe beside this writes them out in full for
		/// the same reason.
		public let initializationOptions: [String: JSONValue]
		/// Which of the two files said it, for the sentence somebody reads when it
		/// turns out to be wrong.
		public let source: LanguageServerChoices.Source

		public init(
			command: String? = nil,
			initializationOptions: [String: JSONValue] = [:],
			source: LanguageServerChoices.Source
		) {
			self.command = command
			self.initializationOptions = initializationOptions
			self.source = source
		}

		public var isEmpty: Bool { command == nil && initializationOptions.isEmpty }
	}

	/// Tool name to what was said about it — the same key space as `ToolImages`,
	/// which is the server's `name` and never a language id.
	public let byTool: [String: Override]

	public init(byTool: [String: Override] = [:]) {
		self.byTool = byTool
	}

	public static let none = LanguageServerOverrides()

	public var isEmpty: Bool { byTool.isEmpty }

	public func override(forTool tool: String) -> Override? { byTool[tool] }

	/// The executable a tool was pointed at, exactly as it was written.
	///
	/// Not expanded here, and that is the one subtlety in the whole type: the same
	/// string is used on two sides. On this machine `~` means this person's home
	/// and `LanguageServers.executable(for:)` expands it; inside a container it
	/// means the *image's* home and expanding it here would send
	/// `/Users/somebody/.rustup/…` into a Linux container, which is a path that
	/// exists nowhere and a server that never starts.
	public func command(forTool tool: String) -> String? {
		guard let named = byTool[tool]?.command, !named.isEmpty else { return nil }
		return named
	}

	/// What to add to the initialize request for a tool.
	public func initializationOptions(forTool tool: String) -> [String: JSONValue] {
		byTool[tool]?.initializationOptions ?? [:]
	}

	/// The key under which the executable is named.
	public static let commandKey = "command"
	/// The key under which the initialize options are named.
	public static let optionsKey = "initializationOptions"

	// MARK: - Reading

	/// What a project asks for, or nothing when it asks for nothing.
	///
	/// A file that cannot be read is the same as no file, as it is for the images
	/// and the choices beside it: a broken one should not stop the project
	/// opening.
	public static func inProject(_ root: URL) -> LanguageServerOverrides {
		guard let data = try? Data(contentsOf: ToolImages.url(in: root)) else {
			return LanguageServerOverrides()
		}
		return parse(data, source: .project)
	}

	public static func parse(_ data: Data, source: LanguageServerChoices.Source) -> LanguageServerOverrides {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return LanguageServerOverrides()
		}

		var found: [String: Override] = [:]
		for (tool, value) in root {
			// The section naming which server a language uses has language ids for
			// keys rather than tool names, and `plantuml` is legitimately both. Told
			// apart by that name rather than by shape, exactly as `ToolImages` does
			// it and for the reason written there.
			guard tool != LanguageServerChoices.section else { continue }
			guard let table = value as? [String: Any] else { continue }
			let command = (table[commandKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
			let options = (table[optionsKey] as? [String: Any])?
				.mapValues(JSONValue.init) ?? [:]
			let override = Override(
				command: command, initializationOptions: options, source: source
			)
			guard !override.isEmpty else { continue }
			found[tool] = override
		}
		return LanguageServerOverrides(byTool: found)
	}

	/// One person's answer, across every project they open.
	///
	/// Commands only. A settings page is a text field per tool, and an object of
	/// initialize options typed into one would be a JSON editor nobody asked for
	/// — the options are a fact about a *project* anyway, which is where the
	/// measured case for them came from.
	public static func settings(_ commands: [String: String]) -> LanguageServerOverrides {
		LanguageServerOverrides(byTool: commands.compactMapValues { command in
			command.isEmpty ? nil : Override(command: command, source: .settings)
		})
	}

	/// The project's answers over the ones set for everything.
	///
	/// The same rule as the images and the choices — **the file wins and the
	/// setting is the default** — but applied key by key rather than to the whole
	/// entry, because these are two independent things said under one name. A
	/// project that names initialize options and no command should keep the
	/// command a person set for every project; replacing the entry wholesale
	/// would take it away, and the symptom would be a server that stops starting
	/// because a line about proc macros was added.
	public static func resolve(
		project: LanguageServerOverrides, settings: LanguageServerOverrides
	) -> LanguageServerOverrides {
		var merged = settings.byTool
		for (tool, fromProject) in project.byTool {
			guard let fromSettings = merged[tool] else {
				merged[tool] = fromProject
				continue
			}
			merged[tool] = Override(
				command: fromProject.command ?? fromSettings.command,
				initializationOptions: fromProject.initializationOptions.isEmpty
					? fromSettings.initializationOptions
					: fromProject.initializationOptions,
				source: fromProject.command != nil ? .project : fromSettings.source
			)
		}
		return LanguageServerOverrides(byTool: merged)
	}

	// MARK: - When it is wrong

	/// What to say when a command was named and there is nothing there to run.
	///
	/// Its own sentence rather than falling through to "rust-analyzer is not
	/// installed", which is what a nil from `executable(for:)` says everywhere
	/// else and which would be false twice over here: something *was* named, and
	/// the install hint underneath it — `rustup component add rust-analyzer` — is
	/// the advice that produced the proxy this was written to get away from.
	public static func refusal(
		command: String, forTool tool: String, source: LanguageServerChoices.Source
	) -> String {
		"\(source.origin) points \(tool) at \(command), and there is no executable "
			+ "file there. Nothing has been started in its place — a server you did not "
			+ "name would answer as though you had named it."
	}
}
