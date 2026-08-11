import Foundation

/// A toolchain a project pins for itself, and what it means for where a tool
/// can come from.
///
/// The two halves of this never meet on their own. **An image fixes its
/// toolchain when the image is built** — `FROM rust:1.97-bookworm`, and that is
/// the only compiler that image will ever have. **A project pins its toolchain
/// when the project is opened** — `rust-toolchain.toml`, read by whatever runs
/// inside it. Nothing reconciles the two, so a project pinning a channel the
/// image has not got starts its server, answers the handshake, and then refuses
/// every question about every file. 0461 is that same failure seen from the
/// other end, once it has happened; this is it seen beforehand.
///
/// Beforehand is possible because the pin is a *file in the project*. It can be
/// read without starting anything, so the disagreement is knowable at the
/// moment the image is chosen rather than at the first request that comes back
/// empty.
///
/// ## Rust only today, and that is a finding rather than an omission
///
/// The same shape exists in the other languages here and none of them fails:
///
/// - **Go.** `go.mod`'s `toolchain` directive names a *release*, and the `go`
///   command in the image downloads it itself unless `GOTOOLCHAIN` forbids it.
///   The image is short of nothing it cannot go and fetch.
/// - **Java.** `.java-version` and `.sdkmanrc` name a JDK, and jdtls resolves a
///   classpath by running Maven, which fetches what it lacks — 0450 measured
///   that from the other side, timing the fetch. Java hides this problem at run
///   time rather than not having it, and the day an image is offered without a
///   network that changes.
/// - **C and C++.** A `compile_commands.json` naming a compiler the image has
///   not got is the same disagreement again, but the file names a *path* rather
///   than a channel, and 0401 already worked around it by driving clangd's
///   fallback instead.
///
/// A reader for any of those would produce sentences about a failure nobody has
/// seen, which is exactly what `ToolImageCatalogue`'s rule about known-good
/// images exists to prevent. So the shape here is per tool: the day one of them
/// does fail, its reader goes beside Rust's rather than replacing it.
public struct ToolchainPin: Equatable, Sendable {
	/// The tool whose environment this pin decides, by the key
	/// `.abydos/tools.json` and the settings page both use.
	public let tool: String
	/// The file that says it, named as this machine names it.
	public let file: URL
	/// What it asks for, verbatim: `esp`, `1.90.0`, `nightly-2025-01-01`.
	public let channel: String
	public let kind: Kind

	/// Whether the channel is something a distributor publishes or something
	/// somebody installed here under a name of their own.
	///
	/// The distinction is the whole of the judgement below it: a release is a
	/// name that means the same thing on every machine on earth and that rustup
	/// can go and fetch, and a custom channel means *whatever was installed
	/// under that name here* and means nothing at all anywhere else. An image is
	/// somewhere else.
	public enum Kind: Equatable, Sendable {
		case release
		case custom
	}

	public init(tool: String, file: URL, channel: String, kind: Kind) {
		self.tool = tool
		self.file = file
		self.channel = channel
		self.kind = kind
	}
}

public enum ToolchainPins {
	// MARK: - Reading a project

	/// The files a pin can be written in, and the tool each one decides.
	///
	/// Both of Rust's, because the bare one is still what a good many
	/// repositories have: `rust-toolchain` predates the TOML file and rustup
	/// still reads it, one line holding the channel and nothing else.
	private static let sources: [(name: String, tool: String)] = [
		("rust-toolchain.toml", "rust-analyzer"),
		("rust-toolchain", "rust-analyzer"),
	]

	/// Every pin this project makes, from its root and the levels below it.
	///
	/// Down, and not only at the root, because a repository commonly keeps the
	/// pinned project a level below the checkout — the case this came from is
	/// `esp32/rust-toolchain.toml` in a repository whose root holds no Rust at
	/// all. The same reason `LanguageServers.markerDirectory` walks, the same
	/// depth, and the same directories skipped, so that the two agree about
	/// which subdirectory is a project.
	///
	/// Breadth first, so a pin one level down wins over one three levels down
	/// inside an example.
	public static func inProject(_ root: URL, maxDepth: Int = 2) -> [ToolchainPin] {
		var found: [ToolchainPin] = []
		var frontier = [root]
		var depth = 0
		while !frontier.isEmpty {
			var next: [URL] = []
			for directory in frontier {
				for source in sources where found.allSatisfy({ $0.tool != source.tool }) {
					let file = directory.appendingPathComponent(source.name)
					guard let channel = channel(in: file, named: source.name) else { continue }
					found.append(ToolchainPin(
						tool: source.tool, file: file, channel: channel, kind: kind(of: channel)
					))
				}
				if depth < maxDepth { next.append(contentsOf: subdirectories(of: directory)) }
			}
			// One pin per tool is all anything downstream can say a sentence
			// about, so a repository with a pin in every one of six crates stops
			// the walk at the first rather than reporting six.
			if found.count == Set(sources.map(\.tool)).count { break }
			frontier = next
			depth += 1
		}
		return found
	}

	/// The pin bearing on one tool, or nil when the project makes none.
	public static func pin(forTool tool: String, in root: URL, maxDepth: Int = 2) -> ToolchainPin? {
		guard sources.contains(where: { $0.tool == tool }) else { return nil }
		return inProject(root, maxDepth: maxDepth).first { $0.tool == tool }
	}

	/// The channel a pin file names, or nil when the file is not there or says
	/// nothing.
	///
	/// Hand-read rather than parsed as TOML, and this is the one place that is
	/// worth defending: the file has one table with one key in it in every
	/// project anybody has ever written, a dependency to read it would be a
	/// dependency for four lines, and the failure mode of getting it wrong is a
	/// sentence not being said rather than anything breaking. `channel` is also
	/// the only key here that could ever be answered — `components`, `targets`
	/// and `profile` are things rustup installs *into* a toolchain, and a
	/// toolchain that is not there has nothing to install into.
	static func channel(in file: URL, named name: String) -> String? {
		guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
		guard name.hasSuffix(".toml") else {
			// The legacy file is the channel and nothing else, comments and all
			// stripped by there being nowhere to put one.
			let bare = text.trimmingCharacters(in: .whitespacesAndNewlines)
			return bare.isEmpty ? nil : bare
		}
		for line in text.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("channel") else { continue }
			guard let equals = trimmed.firstIndex(of: "=") else { continue }
			let value = trimmed[trimmed.index(after: equals)...]
				.trimmingCharacters(in: .whitespaces)
				.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
			return value.isEmpty ? nil : value
		}
		return nil
	}

	/// Whether a channel is one rustup can go and fetch or one that means
	/// whatever is installed here under that name.
	///
	/// rustup's own grammar, in the only part of it that matters: a release is
	/// `stable`, `beta`, `nightly` or a version, each optionally carrying a date
	/// and a host triple after a dash. Everything else is a directory in
	/// `~/.rustup/toolchains` that somebody's installer put there, and this is
	/// deliberately the *permissive* direction — a name that looks like a
	/// release is treated as one, so the sentence below is said only where there
	/// is no doubt.
	static func kind(of channel: String) -> ToolchainPin.Kind {
		let head = channel.split(separator: "-", maxSplits: 1).first.map(String.init) ?? channel
		if ["stable", "beta", "nightly"].contains(head) { return .release }
		let parts = head.split(separator: ".", omittingEmptySubsequences: false)
		if (2...3).contains(parts.count), parts.allSatisfy({
			!$0.isEmpty && $0.allSatisfy(\.isNumber)
		}) {
			return .release
		}
		return .custom
	}

	private static let skipped: Set<String> = [
		"node_modules", "vendor", ".build", ".git", "target", "dist",
	]

	private static func subdirectories(of directory: URL) -> [URL] {
		let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
		let entries = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: keys, options: []
		)) ?? []
		return entries.filter { entry in
			let values = try? entry.resourceValues(forKeys: Set(keys))
			return values?.isDirectory == true && values?.isHidden != true
				&& !skipped.contains(entry.lastPathComponent)
		}.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	// MARK: - What it means for where the tool comes from

	/// What is worth saying about a pin, once it is known where the tool would
	/// be coming from.
	public struct Objection: Equatable, Sendable {
		/// One line, for the strip above the file.
		public let sentence: String
		/// The whole of it, for the dialog behind the strip's button: what each
		/// of the three places a tool can come from would do with this pin.
		public let detail: String

		public init(sentence: String, detail: String) {
			self.sentence = sentence
			self.detail = detail
		}
	}

	/// Whether this pin and where the tool comes from disagree, and what to say
	/// about it — nil, which is the ordinary answer, meaning they do not.
	///
	/// - Parameters:
	///   - pin: what the project asks for.
	///   - image: the image the tool would come from, or nil for the copy
	///     installed on this machine.
	///   - home: where rustup keeps its toolchains, for a test that must not
	///     depend on what this machine happens to have installed.
	///
	/// Nil for a release channel whatever it is coming from, and that is the
	/// judgement worth writing down: rustup inside the image fetches a release
	/// it has not got, so a project pinning `1.90.0` against an image built on
	/// 1.97 is slower on its first request and is not broken. Saying something
	/// about it would be a sentence over every pinned Rust project on the
	/// machine, which is how a warning stops being read.
	/// - Parameter command: the executable already named for this tool, in
	///   `.abydos/tools.json` or in Settings ▸ Tools, or nil when none is. **A
	///   named executable answers the pin and there is nothing to object to**, and
	///   that is 0466's correction to this whole file rather than a special case
	///   bolted onto it: the pin decides which `cargo` and `rustc` read the
	///   project, which is right and wanted, and it does not decide which
	///   *language server* runs. The server is an ordinary program that shells out
	///   to the pinned toolchain, so any recent one reads the project as long as it
	///   is reached by a path rather than by a name a rustup proxy would answer.
	///   Measured against the project this came from, with a stable 1.95
	///   rust-analyzer and the `esp` fork: the sysroot resolved into
	///   `~/.rustup/toolchains/esp`, and `#[derive(Serialize)]` expanded out of a
	///   dylib the fork's own compiler had built.
	///
	///   Whether the path is any good is not asked here. Something named and
	///   absent is its own sentence, said by whoever is going to say it — see
	///   `LanguageServerOverrides.refusal` — and it would be a worse one for being
	///   mixed up with a paragraph about toolchains.
	/// - Parameter imageKnowsChannel: whether the image was built from a recipe in
	///   this repository chosen *for* this case rather than the tool's ordinary one
	///   — `ToolImageRecipes.isVariantRecipe`. Then there is nothing to object to:
	///   the recipe is a file here, it says at the top what channel it is for, and
	///   an app warning about its own answer is an app nobody believes the second
	///   time. Every other image is still objected to, because what is inside a
	///   stranger's image cannot be known from its name.
	public static func objection(
		to pin: ToolchainPin,
		comingFrom image: String?,
		command: String? = nil,
		imageKnowsChannel: Bool = false,
		home: URL = rustupHome()
	) -> Objection? {
		guard pin.kind == .custom else { return nil }
		guard command.map(\.isEmpty) ?? true else { return nil }
		guard !imageKnowsChannel else { return nil }

		let installed = toolchain(named: pin.channel, in: home)
		let hasServer = installed.map {
			FileManager.default.isExecutableFile(
				atPath: $0.appendingPathComponent("bin/\(pin.tool)").path
			)
		} ?? false
		// And the servers this machine has *somewhere else*, which is the thing
		// 0462 did not ask and which turns most of this from a refusal into an
		// offer. See `servers(named:in:)`.
		let elsewhere = hasServer ? [] : servers(named: pin.tool, in: home)
			.filter { $0.toolchain != pin.channel }

		if image != nil {
			return Objection(
				sentence: "This project pins the Rust toolchain ‘\(pin.channel)’, which is "
					+ "installed by name on a machine and is in no ordinary image, so \(pin.tool) "
					+ "will start and then answer nothing about it.",
				detail: detail(
					pin: pin, image: image, installed: installed,
					hasServer: hasServer, elsewhere: elsewhere
				)
			)
		}

		// The installed copy. It is the one route that needs nothing else to
		// answer a custom channel, so the question is whether this machine has a
		// server to answer it *with* — and the surprise for the toolchain this came
		// from is that `~/.rustup/toolchains/esp` has cargo, rustc and clippy in it
		// and no rust-analyzer, because Espressif build their fork with
		// `rust-analyzer-proc-macro-srv` and without the server itself.
		guard !hasServer else { return nil }
		let name = elsewhere.first.map { "\(pin.tool) from ‘\($0.toolchain)’" }
		return Objection(
			sentence: {
				let opening = installed == nil
					? "This project pins the Rust toolchain ‘\(pin.channel)’, and this machine has "
						+ "no toolchain of that name"
					: "This project pins the Rust toolchain ‘\(pin.channel)’, and the copy of it on "
						+ "this machine has no \(pin.tool) in it"
				// The second half is the whole difference 0466 makes, and it is a
				// different *kind* of sentence: one says what is wrong, the other says
				// what to do. Where there is a server to point at, saying so is worth
				// more than a longer account of the fault.
				guard installed != nil, let name else {
					return opening + ", so \(pin.tool) will start and then answer nothing about it."
				}
				return opening + " — but \(name) reads it, if you name that path for "
					+ "\(pin.tool) rather than letting rustup pick."
			}(),
			detail: detail(
				pin: pin, image: image, installed: installed,
				hasServer: hasServer, elsewhere: elsewhere
			)
		)
	}

	/// A copy of the server that is on this machine but not in the pinned
	/// toolchain, and which toolchain it belongs to.
	public struct Elsewhere: Equatable, Sendable {
		public let toolchain: String
		public let path: String

		public init(toolchain: String, path: String) {
			self.toolchain = toolchain
			self.path = path
		}
	}

	/// Every toolchain here that has this server in it, newest-looking first.
	///
	/// **The question 0462 did not ask.** It looked in the *pinned* toolchain,
	/// found nothing, and concluded that nothing on this machine could read the
	/// project — which was a claim about one directory presented as a claim about
	/// the machine. `~/.rustup/toolchains` commonly holds several, and rustup will
	/// put rust-analyzer in any of them for the asking; what it will not do is
	/// hand one over through a *proxy* while the project's pin says `esp`, and that
	/// refusal is what looked like an absence.
	///
	/// Sorted so a release channel comes before a custom one and the two are
	/// otherwise alphabetical. It only decides which of several is named in one
	/// sentence, and a release is the safe thing to name: it is the toolchain most
	/// likely to be close in version to the fork, which is what the proc-macro
	/// bridge needs to hold.
	public static func servers(named tool: String, in home: URL = rustupHome()) -> [Elsewhere] {
		let toolchains = home.appendingPathComponent("toolchains")
		let entries = (try? FileManager.default.contentsOfDirectory(
			at: toolchains, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []
		return entries.compactMap { directory -> Elsewhere? in
			let binary = directory.appendingPathComponent("bin/\(tool)")
			guard FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }
			return Elsewhere(toolchain: directory.lastPathComponent, path: binary.path)
		}.sorted { left, right in
			let leftIsRelease = kind(of: left.toolchain) == .release
			let rightIsRelease = kind(of: right.toolchain) == .release
			if leftIsRelease != rightIsRelease { return leftIsRelease }
			return left.toolchain < right.toolchain
		}
	}

	/// Every route this pin has, what each of them does with it, and what to do.
	///
	/// All the routes said every time rather than only the one that is failing,
	/// because the question somebody has when they read the strip is "what do I do
	/// instead". A page that lists them and says which is which is shorter than
	/// finding that out one setting at a time.
	///
	/// **0466 rewrote the end of this, and the reason is worth keeping.** What
	/// 0462 wrote here was true of the routes it looked at and too strong about the
	/// case: it ended by saying that where no toolchain here has the server there
	/// is nothing this editor can do. There is. The pin decides which `cargo` and
	/// `rustc` read the project; it does not decide which *server binary* runs, and
	/// the missing piece was never the toolchain — it was that both routes reached
	/// the server through a rustup proxy that insists on getting it from the pinned
	/// toolchain and refuses. A path instead of a name is the whole of the fix, on
	/// either route, and it is measured rather than reasoned: see 0466.
	private static func detail(
		pin: ToolchainPin, image: String?, installed: URL?, hasServer: Bool,
		elsewhere: [Elsewhere]
	) -> String {
		var lines = [
			"\(pin.file.path) pins the toolchain ‘\(pin.channel)’.",
			"",
			"A custom channel is not a version anybody publishes: it is the name a "
				+ "directory has under ~/.rustup/toolchains, put there by an installer of its "
				+ "own — espup for Espressif's Xtensa fork, or `rustup toolchain link` for one "
				+ "built by hand. rustup resolves it by looking for that directory and by "
				+ "nothing else.",
			"",
			"That decides which cargo and which rustc read this project, which is what the "
				+ "pin is for. It does not decide which \(pin.tool) runs: the server is an "
				+ "ordinary program that shells out to the pinned toolchain, so any recent one "
				+ "reads the project — as long as it is reached by a path. Reached by *name* it "
				+ "is rustup's proxy, and inside this project the proxy resolves to "
				+ "‘\(pin.channel)’ and stops:",
			"",
			"    error: '\(pin.tool)' is not installed for the custom toolchain "
				+ "'\(pin.channel)'.",
			"",
			"Where \(pin.tool) can come from, and what each does with this pin:",
			"",
			"• An image, published or named by hand. Its toolchain was fixed when it was "
				+ "built and the pin is read afterwards, so an ordinary Rust image has no such "
				+ "toolchain and never will."
				+ (image == nil ? "" : " This is where it is coming from now: \(image ?? "")."),
			"• An image built here from the recipe Abydos ships. "
				+ "ToolImages/\(pin.tool)/Dockerfile installs the toolchain from rustup, which "
				+ "fetches a release and cannot fetch a name only your machine knows — so that "
				+ "recipe does not read this project either, and says so at the top of itself.",
		]
		if installed == nil {
			lines.append(
				"• The copy installed on this machine. There is no ~/.rustup/toolchains/"
					+ "\(pin.channel) here, so nothing here reads the project the way it is "
					+ "pinned: the toolchain has to be installed first, by whichever installer "
					+ "owns that name."
			)
		} else if hasServer {
			lines.append(
				"• The copy installed on this machine. ~/.rustup/toolchains/\(pin.channel) has "
					+ "\(pin.tool) in it, so choosing “Installed on this machine” for "
					+ "\(pin.tool) in Settings ▸ Tools reads this project."
			)
		} else {
			lines.append(
				"• The copy installed on this machine. ~/.rustup/toolchains/\(pin.channel) has "
					+ "no \(pin.tool) in it — Espressif's fork is built with "
					+ "rust-analyzer-proc-macro-srv and without the server itself, and rustup "
					+ "will not add a component to a custom toolchain. That is a fact about "
					+ "that one directory rather than about this machine."
			)
		}

		lines.append("")
		if hasServer {
			return lines.joined(separator: "\n")
		}

		lines.append("What to do:")
		lines.append("")
		if let found = elsewhere.first {
			lines.append(
				"• Name the executable. ~/.rustup/toolchains/\(found.toolchain) has \(pin.tool) "
					+ "in it, and pointing at it by path skips the proxy while cargo and rustc "
					+ "still resolve to ‘\(pin.channel)’ through the pin — which is what should "
					+ "happen. In .abydos/tools.json:"
			)
			lines.append("")
			lines.append("    { \"\(pin.tool)\": { \"command\": \"\(shortening(found.path))\" } }")
			lines.append("")
			lines.append(
				"  or in Settings ▸ Tools, as the Executable for \(pin.tool). Verified for "
					+ "Espressif's fork: the sysroot resolves inside ~/.rustup/toolchains/"
					+ "\(pin.channel), and proc macros built by the fork's own compiler expand. "
					+ "The one condition is version: keep the server close to the fork's rustc, "
					+ "since a proc macro is loaded across that boundary."
			)
		} else {
			lines.append(
				"• Put a server on this machine and name it by path. `rustup component add "
					+ "\(pin.tool) --toolchain stable` gives one; naming its path — in "
					+ ".abydos/tools.json as { \"\(pin.tool)\": { \"command\": \"…\" } }, or as "
					+ "the Executable for \(pin.tool) in Settings ▸ Tools — skips the proxy, "
					+ "while cargo and rustc still resolve to ‘\(pin.channel)’ through the pin. "
					+ "Keep it close in version to the pinned toolchain's rustc: a proc macro is "
					+ "loaded across that boundary."
			)
		}
		lines.append(
			"• Or an image that knows about this channel, with the same rule inside it. "
				+ "Espressif publish espressif/idf-rust (linux/arm64 as well as amd64, tagged "
				+ "esp32_<version>), and espup installs the fork inside a container as well as "
				+ "on a machine — what cannot be done is `rustup toolchain install \(pin.channel)`. "
				+ "Such an image still needs \(pin.tool) added from a release toolchain and "
				+ "named by its path, because ~/.cargo/bin/\(pin.tool) in there is the same "
				+ "proxy giving the same error."
		)
		return lines.joined(separator: "\n")
	}

	/// A path under the home directory written the way somebody would type it, so
	/// the line can be copied into a file two people share.
	private static func shortening(_ path: String) -> String {
		let home = NSHomeDirectory()
		guard path.hasPrefix(home + "/") else { return path }
		return "~" + path.dropFirst(home.count)
	}

	/// Where rustup keeps its toolchains.
	public static func rustupHome() -> URL {
		if let named = ProcessInfo.processInfo.environment["RUSTUP_HOME"], !named.isEmpty {
			return URL(fileURLWithPath: named)
		}
		return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".rustup")
	}

	/// The directory a named toolchain lives in, or nil when it is not here.
	static func toolchain(named channel: String, in home: URL) -> URL? {
		let directory = home.appendingPathComponent("toolchains").appendingPathComponent(channel)
		var isDirectory: ObjCBool = false
		let there = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
		return there && isDirectory.boolValue ? directory : nil
	}
}
