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
	public static func objection(
		to pin: ToolchainPin,
		comingFrom image: String?,
		home: URL = rustupHome()
	) -> Objection? {
		guard pin.kind == .custom else { return nil }
		let installed = toolchain(named: pin.channel, in: home)
		let hasServer = installed.map {
			FileManager.default.isExecutableFile(
				atPath: $0.appendingPathComponent("bin/\(pin.tool)").path
			)
		} ?? false

		if image != nil {
			return Objection(
				sentence: "This project pins the Rust toolchain ‘\(pin.channel)’, which is "
					+ "installed by name on a machine and is in no image, so \(pin.tool) will "
					+ "start and then answer nothing about it.",
				detail: detail(pin: pin, image: image, installed: installed, hasServer: hasServer)
			)
		}

		// The installed copy. It is the one route that *can* answer a custom
		// channel, so the question is only whether this machine actually has it
		// — and the answer for the toolchain this came from is no, in a way
		// nobody would guess: `~/.rustup/toolchains/esp` has cargo, rustc and
		// clippy in it and no rust-analyzer, because Espressif builds their fork
		// with `rust-analyzer-proc-macro-srv` and not the server itself.
		guard !hasServer else { return nil }
		return Objection(
			sentence: installed == nil
				? "This project pins the Rust toolchain ‘\(pin.channel)’, and this machine has "
					+ "no toolchain of that name, so \(pin.tool) will start and then answer "
					+ "nothing about it."
				: "This project pins the Rust toolchain ‘\(pin.channel)’, and the copy of it on "
					+ "this machine has no \(pin.tool) in it, so nothing here can read the project.",
			detail: detail(pin: pin, image: image, installed: installed, hasServer: hasServer)
		)
	}

	/// Every route this pin has, and what each of them does with it.
	///
	/// All three said every time, rather than only the one that is failing,
	/// because the question somebody has when they read the strip is "what do I
	/// do instead" and two of the three answers are usually "not this either".
	/// A page that lists them and rules them out is shorter than finding that
	/// out one setting at a time.
	private static func detail(
		pin: ToolchainPin, image: String?, installed: URL?, hasServer: Bool
	) -> String {
		var lines = [
			"\(pin.file.path) pins the toolchain ‘\(pin.channel)’.",
			"",
			"A custom channel is not a version anybody publishes: it is the name a "
				+ "directory has under ~/.rustup/toolchains, put there by an installer of its "
				+ "own — espup for Espressif's Xtensa fork, or `rustup toolchain link` for one "
				+ "built by hand. rustup resolves it by looking for that directory and by "
				+ "nothing else, so it either is on the machine reading the project or the "
				+ "project cannot be read.",
			"",
			"Where \(pin.tool) can come from, and what each does with this pin:",
			"",
			"• An image, published or named by hand. Its toolchain was fixed when it was "
				+ "built and the pin is read afterwards, so unless the image was made knowing "
				+ "this channel's name it has no such toolchain and never will."
				+ (image == nil ? "" : " This is where it is coming from now: \(image ?? "")."),
			"• An image built here from the recipe Abydos ships. The same thing: "
				+ "ToolImages/\(pin.tool)/Dockerfile installs the toolchain from rustup, which "
				+ "can fetch a release and cannot fetch a name only your machine knows.",
		]
		if installed == nil {
			lines.append(
				"• The copy installed on this machine, which is the only route that could "
					+ "answer a custom channel — and there is no ~/.rustup/toolchains/"
					+ "\(pin.channel) here to answer it with."
			)
		} else if hasServer {
			lines.append(
				"• The copy installed on this machine. ~/.rustup/toolchains/\(pin.channel) has "
					+ "\(pin.tool) in it, so choosing “Installed on this machine” for "
					+ "\(pin.tool) in Settings ▸ Tools reads this project."
			)
		} else {
			lines.append(
				"• The copy installed on this machine, which is the only route that could "
					+ "answer a custom channel. It cannot here: ~/.rustup/toolchains/"
					+ "\(pin.channel) has no \(pin.tool) in it. Espressif's toolchain is built "
					+ "with rust-analyzer-proc-macro-srv and without the server itself, and "
					+ "rustup cannot add a component to a custom toolchain."
			)
		}
		lines.append("")
		lines.append(
			"A project that only one machine's toolchain can read is a project to point at "
				+ "the installed copy, in .abydos/tools.json or in Settings ▸ Tools. Where no "
				+ "copy answers it either, there is nothing this editor can do about it and "
				+ "the honest thing is that it says so here rather than by falling silent."
		)
		return lines.joined(separator: "\n")
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
