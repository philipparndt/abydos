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
		#expect(objection.sentence.contains("no image"))
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
}
