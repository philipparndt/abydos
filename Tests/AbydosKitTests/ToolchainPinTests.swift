import Foundation
import Testing
@testable import AbydosKit

/// A project pinning a toolchain the tool's environment has not got.
///
/// Nothing here starts a server or a container. What is being checked is the
/// part that can be known *before* either — that the pin is a file, that it can
/// be read where it actually lives, and that what is said about it is different
/// for each of the places the tool could be coming from. The whole point of the
/// item is that this is answerable without running anything.
struct ToolchainPinTests {
	private func project(_ files: [String: String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("toolchain-pin-\(UUID().uuidString)")
		for (path, contents) in files {
			let file = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: file.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try contents.write(to: file, atomically: true, encoding: .utf8)
		}
		return root
	}

	// MARK: - Reading the pin

	@Test func aProjectPinningAChannelSaysSoInAFileThatCanBeReadFirst() throws {
		let root = try project(["rust-toolchain.toml": "[toolchain]\nchannel = \"esp\"\n"])
		let pin = try #require(ToolchainPins.pin(forTool: "rust-analyzer", in: root))
		#expect(pin.channel == "esp")
		#expect(pin.kind == .custom)
		#expect(pin.file.lastPathComponent == "rust-toolchain.toml")
	}

	/// The case this came from is not at the root: the checkout is a smart-home
	/// repository and the Rust in it is one directory of firmware. A reader that
	/// only looked at the root would have found nothing and said nothing, which
	/// is the state before this item.
	@Test func aPinOneDirectoryDownIsTheProjectsPinToo() throws {
		let root = try project([
			"README.md": "not Rust",
			"esp32/rust-toolchain.toml": "[toolchain]\nchannel = \"esp\"\n",
		])
		let pin = try #require(ToolchainPins.pin(forTool: "rust-analyzer", in: root))
		#expect(pin.channel == "esp")
		#expect(pin.file.pathComponents.suffix(2).first == "esp32")
	}

	@Test func theLegacyFileWithNothingInItButTheChannelIsReadAsWell() throws {
		let root = try project(["rust-toolchain": "nightly-2025-01-01\n"])
		let pin = try #require(ToolchainPins.pin(forTool: "rust-analyzer", in: root))
		#expect(pin.channel == "nightly-2025-01-01")
		#expect(pin.kind == .release)
	}

	@Test func aProjectThatPinsNothingHasNoPin() throws {
		let root = try project(["Cargo.toml": "[package]\nname = \"x\"\n"])
		#expect(ToolchainPins.pin(forTool: "rust-analyzer", in: root) == nil)
		#expect(ToolchainPins.inProject(root).isEmpty)
	}

	@Test func aToolNothingPinsAToolchainForIsNotAskedAbout() throws {
		let root = try project(["rust-toolchain.toml": "[toolchain]\nchannel = \"esp\"\n"])
		#expect(ToolchainPins.pin(forTool: "gopls", in: root) == nil)
		#expect(ToolchainPins.pin(forTool: "jdtls", in: root) == nil)
	}

	/// The output directories are skipped for the reason the marker walk skips
	/// them: a vendored copy of somebody else's crate carries its own pin, and
	/// answering with it would be a sentence about a project nobody opened.
	@Test func aPinInsideAnOutputDirectoryIsNotTheProjectsPin() throws {
		let root = try project([
			"target/debug/build/x/rust-toolchain.toml": "[toolchain]\nchannel = \"esp\"\n",
			"vendor/x/rust-toolchain.toml": "[toolchain]\nchannel = \"esp\"\n",
		])
		#expect(ToolchainPins.pin(forTool: "rust-analyzer", in: root) == nil)
	}

	// MARK: - Which channels are which

	@Test func aChannelAnybodyCanFetchIsARelease() {
		for channel in [
			"stable", "beta", "nightly", "1.90", "1.90.0",
			"nightly-2025-01-01", "stable-aarch64-apple-darwin", "1.97.0-x86_64-unknown-linux-gnu",
		] {
			#expect(ToolchainPins.kind(of: channel) == .release, "\(channel)")
		}
	}

	@Test func aChannelOnlyOneMachineKnowsIsCustom() {
		for channel in ["esp", "my-fork", "1.x", "dev"] {
			#expect(ToolchainPins.kind(of: channel) == .custom, "\(channel)")
		}
	}

	// MARK: - What is said, and to whom

	/// The judgement worth defending: a pinned *release* is not worth a
	/// sentence. rustup inside the image fetches one it has not got, so the
	/// first request is slower and nothing is broken — and a strip over every
	/// pinned Rust project on the machine is a strip nobody reads by the end of
	/// the week.
	@Test func aPinnedReleaseIsNotWorthSayingAnythingAbout() throws {
		let pin = ToolchainPin(
			tool: "rust-analyzer", file: URL(fileURLWithPath: "/p/rust-toolchain.toml"),
			channel: "1.90.0", kind: .release
		)
		#expect(ToolchainPins.objection(to: pin, comingFrom: "pharndt/abydos-rust-analyzer:dev") == nil)
		#expect(ToolchainPins.objection(to: pin, comingFrom: nil) == nil)
	}

	@Test func aCustomChannelIsInNoImageAndTheSentenceSaysSoBeforeAnythingStarts() throws {
		let pin = ToolchainPin(
			tool: "rust-analyzer", file: URL(fileURLWithPath: "/p/esp32/rust-toolchain.toml"),
			channel: "esp", kind: .custom
		)
		let objection = try #require(
			ToolchainPins.objection(to: pin, comingFrom: "pharndt/abydos-rust-analyzer:dev")
		)
		#expect(objection.sentence.contains("esp"))
		// "no ordinary image" since 0466, which is the correction rather than a
		// softening: `espressif/idf-rust` is an image with the fork in it, and the
		// recipe beside this one builds another. What a custom channel is in no
		// image *reached by an ordinary Rust recipe* is still true and is what this
		// sentence is about.
		#expect(objection.sentence.contains("no ordinary image"))
		// Every route named, including the one that is not being used, because
		// the question somebody has on reading it is what to do instead.
		#expect(objection.detail.contains("Installed on this machine")
			|| objection.detail.contains("installed on this machine"))
		#expect(objection.detail.contains("ToolImages/rust-analyzer/Dockerfile"))
		#expect(objection.detail.contains("/p/esp32/rust-toolchain.toml"))
	}

	/// The installed copy is the one route a custom channel *can* take, so
	/// whether it is worth saying anything depends on this machine rather than
	/// on the pin — and the answer is read off the toolchain directory rather
	/// than assumed either way.
	@Test func anInstalledToolchainCarryingTheServerIsNotComplainedAbout() throws {
		let home = try project([
			"toolchains/esp/bin/rust-analyzer": "#!/bin/sh\n",
			"toolchains/esp/bin/cargo": "#!/bin/sh\n",
		])
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: home.appendingPathComponent("toolchains/esp/bin/rust-analyzer").path
		)
		let pin = ToolchainPin(
			tool: "rust-analyzer", file: URL(fileURLWithPath: "/p/rust-toolchain.toml"),
			channel: "esp", kind: .custom
		)
		#expect(ToolchainPins.objection(to: pin, comingFrom: nil, home: home) == nil)
		// Still worth saying when it is coming from an image, because the copy
		// that has it is not the copy being used.
		#expect(ToolchainPins.objection(to: pin, comingFrom: "some/image", home: home) != nil)
	}

	/// Espressif's toolchain, as it is on the machine this was reported from:
	/// `cargo`, `rustc`, `clippy` — and no `rust-analyzer`, because the fork is
	/// built with `rust-analyzer-proc-macro-srv` and not the server. So "use the
	/// installed copy instead" is not the answer here, and the strip must not
	/// offer it as one.
	@Test func anInstalledToolchainWithoutTheServerIsStillNoAnswer() throws {
		let home = try project([
			"toolchains/esp/bin/cargo": "#!/bin/sh\n",
			"toolchains/esp/libexec/rust-analyzer-proc-macro-srv": "#!/bin/sh\n",
		])
		let pin = ToolchainPin(
			tool: "rust-analyzer", file: URL(fileURLWithPath: "/p/rust-toolchain.toml"),
			channel: "esp", kind: .custom
		)
		let objection = try #require(ToolchainPins.objection(to: pin, comingFrom: nil, home: home))
		#expect(objection.sentence.contains("no rust-analyzer"))
		#expect(objection.detail.contains("rust-analyzer-proc-macro-srv"))
	}

	@Test func aMachineWithoutTheToolchainAtAllSaysThatInsteadOfGuessing() throws {
		let home = try project(["toolchains/stable-aarch64-apple-darwin/bin/cargo": "#!/bin/sh\n"])
		let pin = ToolchainPin(
			tool: "rust-analyzer", file: URL(fileURLWithPath: "/p/rust-toolchain.toml"),
			channel: "esp", kind: .custom
		)
		let objection = try #require(ToolchainPins.objection(to: pin, comingFrom: nil, home: home))
		#expect(objection.sentence.contains("no toolchain of that name"))
	}

	// MARK: - What 0466 corrected

	private func executable(_ home: URL, _ path: String) throws {
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: home.appendingPathComponent(path).path
		)
	}

	private let espPin = ToolchainPin(
		tool: "rust-analyzer", file: URL(fileURLWithPath: "/p/esp32/rust-toolchain.toml"),
		channel: "esp", kind: .custom
	)

	/// **The claim 0462 got wrong.** It looked in the *pinned* toolchain, found no
	/// server and concluded that nothing on this machine could read the project —
	/// a statement about one directory presented as a statement about the machine.
	/// A release toolchain beside it has the server, and the pin does not decide
	/// which server runs, so there is something to offer and it is named.
	@Test func aServerInAnotherToolchainIsOfferedRatherThanTheSubjectBeingClosed() throws {
		let home = try project([
			"toolchains/esp/bin/cargo": "#!/bin/sh\n",
			"toolchains/esp/libexec/rust-analyzer-proc-macro-srv": "#!/bin/sh\n",
			"toolchains/stable-aarch64-apple-darwin/bin/rust-analyzer": "#!/bin/sh\n",
		])
		try executable(home, "toolchains/stable-aarch64-apple-darwin/bin/rust-analyzer")

		let objection = try #require(ToolchainPins.objection(to: espPin, comingFrom: nil, home: home))
		// Still says what is wrong…
		#expect(objection.sentence.contains("no rust-analyzer in it"))
		// …and then what reads it, which is the half that was missing.
		#expect(objection.sentence.contains("stable-aarch64-apple-darwin"))
		#expect(objection.sentence.contains("reads it"))
		#expect(objection.detail.contains("\"command\""))
		#expect(objection.detail.contains("Settings ▸ Tools"))
		// And the sentence this file used to end on is gone.
		#expect(!objection.detail.contains("nothing this editor can do"))
	}

	@Test func theServersOnThisMachineAreFoundWhereverTheyAre() throws {
		let home = try project([
			"toolchains/esp/bin/cargo": "#!/bin/sh\n",
			"toolchains/my-fork/bin/rust-analyzer": "#!/bin/sh\n",
			"toolchains/1.95.0-aarch64-apple-darwin/bin/rust-analyzer": "#!/bin/sh\n",
		])
		try executable(home, "toolchains/my-fork/bin/rust-analyzer")
		try executable(home, "toolchains/1.95.0-aarch64-apple-darwin/bin/rust-analyzer")

		let found = ToolchainPins.servers(named: "rust-analyzer", in: home)
		#expect(found.map(\.toolchain) == ["1.95.0-aarch64-apple-darwin", "my-fork"])
		// A release first, because it is the one most likely to be close in version
		// to a fork — and a proc macro is loaded across that boundary.
		#expect(found.first?.path.hasSuffix("bin/rust-analyzer") == true)
	}

	/// **An executable already named answers the pin, so there is nothing to
	/// object to.** This is the whole of 0466's correction in one assertion: the
	/// pin decides which `cargo` and `rustc` read the project — which is right —
	/// and it does not decide which server binary runs.
	@Test func anExecutableAlreadyNamedForTheServerAnswersThePin() throws {
		let home = try project(["toolchains/esp/bin/cargo": "#!/bin/sh\n"])
		#expect(ToolchainPins.objection(
			to: espPin, comingFrom: nil,
			command: "~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/rust-analyzer",
			home: home
		) == nil)
		// Including where it comes from an image, since the command is the command
		// *inside* it and the image's own proxy is what it is getting away from.
		#expect(ToolchainPins.objection(
			to: espPin, comingFrom: "espressif/idf-rust:esp32_1.95.0.0",
			command: "/home/esp/rust-analyzer", home: home
		) == nil)
		// An empty one is not a command and changes nothing.
		#expect(ToolchainPins.objection(
			to: espPin, comingFrom: nil, command: "", home: home
		) != nil)
	}

	/// A recipe from this repository chosen *instead of* the tool's own is this
	/// project's own answer to the channel, and an app that warned about its own
	/// answer is one nobody believes the second time. Every other image is still
	/// objected to, because what is in a stranger's image cannot be known from its
	/// name.
	@Test func aRecipeChosenForThisChannelIsNotObjectedTo() throws {
		let home = try project(["toolchains/esp/bin/cargo": "#!/bin/sh\n"])
		#expect(ToolchainPins.objection(
			to: espPin, comingFrom: "abydos-built/rust-analyzer-esp:abc123abc123",
			imageKnowsChannel: true, home: home
		) == nil)
		#expect(ToolchainPins.objection(
			to: espPin, comingFrom: "espressif/idf-rust:esp32_1.95.0.0",
			imageKnowsChannel: false, home: home
		) != nil)
	}

	/// The detail names both routes now, and names them as things to do rather
	/// than as things that will not work.
	@Test func theDetailSaysWhatToDoAndNamesTheImageThatHasTheFork() throws {
		let home = try project(["toolchains/esp/bin/cargo": "#!/bin/sh\n"])
		let objection = try #require(ToolchainPins.objection(to: espPin, comingFrom: nil, home: home))
		#expect(objection.detail.contains("What to do:"))
		#expect(objection.detail.contains("rustup component add rust-analyzer --toolchain stable"))
		#expect(objection.detail.contains("espressif/idf-rust"))
		// And the reason the proxy is what fails, quoted as rustup says it.
		#expect(objection.detail.contains("is not installed for the custom toolchain"))
	}
}
