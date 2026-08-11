import Foundation
import Testing
@testable import AbydosKit

/// Against a real language server running from a container image.
///
/// This is the test the whole container path exists for, and the one thing it
/// proves that nothing else can: that a server which has never seen this
/// machine's filesystem answers about files on it. Every URI going out is
/// rewritten to the mount and every one coming back is rewritten home, so a
/// mapping that is subtly wrong shows up here as a diagnostic against a path
/// that does not exist — which is exactly how it would show up in the editor,
/// except that here it fails a test instead of looking like an unreliable
/// server.
///
/// One case per server rather than one test per server, because what is being
/// checked is the same sentence six times over and the differences are a
/// project and a position in it. What is *not* shared is the evidence: an image
/// that has not been driven here has not been driven, and `ToolContainerTests`
/// holds the catalogue to that.
///
/// Skipped, per case, unless one of that server's images is already on this
/// machine — the way the other live tests are skipped without their server. Get
/// one with:
///
///     docker pull pharndt/abydos-gopls:dev      # what the catalogue lists
///     make tool-image TOOL=gopls                # a build of ToolImages/gopls
///
/// Serialized, because each case starts a container with a toolchain in it and
/// six of those at once is a machine doing nothing else.
@Suite(.serialized) struct ContainerLSPLiveTests {
	/// One server, one project, and the one answer that could only come from
	/// the server having read that project.
	struct Probe: Sendable, CustomTestStringConvertible {
		/// The key an image is chosen under, in settings and in
		/// `.abydos/tools.json`. Not always the command: Python's is `pyright`.
		let tool: String
		let languageId: String
		/// The images to try, best first — see `images(for:)`.
		let images: [String]
		/// The project, as paths relative to its root. One of them has to be a
		/// root marker for this server or nothing resolves at all.
		let files: [String: String]
		/// The file that is opened, relative to the root.
		let opened: String
		/// Names `textDocument/documentSymbol` has to come back with. Matched by
		/// prefix: jdtls names a method `greeting()` and gopls names it
		/// `greeting`, and which of those is right is not what this is about.
		let declares: [String]
		/// Where the first of those is *used*, and the line its declaration is
		/// on. Lines and characters are 0-based, as they are on the wire.
		let use: LSPPosition
		let declaredOnLine: Int
		/// How long the handshake is given. Seconds rather than milliseconds for
		/// all of them — a container starts, and then the server reads a project
		/// — and jdtls is in a class of its own: it imports the project into an
		/// Eclipse workspace before it will answer anything.
		let patience: TimeInterval

		var testDescription: String { tool }
	}

	/// Two images per server, and the published one first, because the two
	/// answer different questions and only one of them is the question the
	/// catalogue asks. `abydos/<tool>:dev` is whatever this machine last built,
	/// so a pass against it says the Dockerfile in this repository works — worth
	/// having while somebody is changing it, and no evidence at all about what a
	/// stranger pulls. `pharndt/abydos-<tool>:dev` is the artefact in the
	/// registry, the one `ToolImageCatalogue` may name, and the only one whose
	/// passing means an entry in that list is true. So it is tried first: on a
	/// machine that has both, the published image is the one that gets driven.
	static func images(for tool: String) -> [String] {
		["pharndt/abydos-\(tool):dev", "abydos/\(tool):dev"]
	}

	/// The smallest project each server can say something interesting about: one
	/// function calling another, and whatever file makes that a project the
	/// server will open at all.
	static let probes: [Probe] = [
		Probe(
			tool: "gopls",
			languageId: "go",
			images: images(for: "gopls"),
			files: [
				"go.mod": "module example.com/probe\n\ngo 1.24\n",
				"main.go": """
				package main

				import "fmt"

				func greeting() string {
					return "hello"
				}

				func main() {
					fmt.Println(greeting())
				}
				""",
			],
			opened: "main.go",
			declares: ["greeting", "main"],
			use: LSPPosition(line: 9, character: 14),
			declaredOnLine: 4,
			patience: 60
		),
		Probe(
			tool: "rust-analyzer",
			languageId: "rust",
			images: images(for: "rust-analyzer"),
			// No dependencies, and that is deliberate: rust-analyzer runs
			// `cargo metadata`, and a manifest naming a crate would make this
			// test need the network from inside a container as well as an image.
			files: [
				"Cargo.toml": """
				[package]
				name = "probe"
				version = "0.1.0"
				edition = "2021"
				""",
				"src/main.rs": """
				fn greeting() -> &'static str {
					"hello"
				}

				fn main() {
					let message = greeting();
					println!("{}", message);
				}
				""",
			],
			opened: "src/main.rs",
			declares: ["greeting", "main"],
			use: LSPPosition(line: 5, character: 18),
			declaredOnLine: 0,
			patience: 90
		),
		Probe(
			tool: "pyright",
			languageId: "python",
			images: images(for: "pyright"),
			files: [
				"pyproject.toml": """
				[project]
				name = "probe"
				version = "0.1.0"
				""",
				"main.py": """
				def greeting() -> str:
					return "hello"


				def main() -> None:
					message = greeting()
					print(message)
				""",
			],
			opened: "main.py",
			declares: ["greeting", "main"],
			use: LSPPosition(line: 5, character: 14),
			declaredOnLine: 0,
			patience: 60
		),
		Probe(
			tool: "typescript-language-server",
			languageId: "typescript",
			images: images(for: "typescript-language-server"),
			files: [
				"package.json": #"{"name": "probe", "version": "1.0.0", "private": true}"#,
				"tsconfig.json": #"{"compilerOptions": {"target": "ES2020", "strict": true}}"#,
				"src/main.ts": """
				function greeting(): string {
					return "hello";
				}

				function main(): void {
					const message = greeting();
					console.log(message);
				}

				main();
				""",
			],
			opened: "src/main.ts",
			declares: ["greeting", "main"],
			use: LSPPosition(line: 5, character: 20),
			declaredOnLine: 0,
			patience: 60
		),
		Probe(
			tool: "clangd",
			languageId: "c",
			// A `CMakeLists.txt` for the root marker and no compile database,
			// which is the honest fixture rather than the flattering one: a
			// `compile_commands.json` on this machine names paths on this
			// machine, and inside the container none of them exist — so clangd
			// would fall back to its guessed command line anyway. It is that
			// fallback being driven here, and it is what a project without a
			// generated database gets in the editor too.
			images: images(for: "clangd"),
			files: [
				"CMakeLists.txt": """
				cmake_minimum_required(VERSION 3.20)
				project(probe C)
				add_executable(probe main.c)
				""",
				"main.c": """
				#include <stdio.h>

				static const char *greeting(void) {
					return "hello";
				}

				int main(void) {
					printf("%s\\n", greeting());
					return 0;
				}
				""",
			],
			opened: "main.c",
			declares: ["greeting", "main"],
			use: LSPPosition(line: 7, character: 19),
			declaredOnLine: 2,
			patience: 60
		),
		Probe(
			tool: "jdtls",
			languageId: "java",
			images: images(for: "jdtls"),
			// An Eclipse project rather than a Maven one, and that is the whole
			// difference between a test that runs and a test that downloads.
			// `.classpath` is one of the root markers this server looks for, and
			// a project that has one needs no build tool to import: a `pom.xml`
			// would send jdtls to Maven Central from inside the container for
			// every plugin in the default lifecycle.
			files: [
				".project": """
				<?xml version="1.0" encoding="UTF-8"?>
				<projectDescription>
					<name>probe</name>
					<buildSpec>
						<buildCommand>
							<name>org.eclipse.jdt.core.javabuilder</name>
						</buildCommand>
					</buildSpec>
					<natures>
						<nature>org.eclipse.jdt.core.javanature</nature>
					</natures>
				</projectDescription>
				""",
				".classpath": """
				<?xml version="1.0" encoding="UTF-8"?>
				<classpath>
					<classpathentry kind="src" path="src"/>
					<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
					<classpathentry kind="output" path="bin"/>
				</classpath>
				""",
				"src/Probe.java": """
				public class Probe {
					static String greeting() {
						return "hello";
					}

					public static void main(String[] args) {
						String message = greeting();
						System.out.println(message);
					}
				}
				""",
			],
			opened: "src/Probe.java",
			declares: ["greeting", "main"],
			use: LSPPosition(line: 6, character: 22),
			declaredOnLine: 1,
			patience: 180
		),
	]

	/// An image on this machine and a runtime that has it, or nil when there is
	/// no such pair.
	///
	/// Every runtime installed rather than only the preferred one, and it has to
	/// hold the image rather than merely exist: an image built with docker is
	/// not visible to Apple's `container`, and preferring Apple's — which is
	/// what the app does — would skip this test on a machine that can run it.
	///
	/// Image outermost, runtime innermost: the published image under whichever
	/// runtime has it beats the locally built one under the preferred runtime,
	/// because which image ran is what this test is evidence about.
	private func available(for probe: Probe) -> (runtime: ContainerRuntime, image: String)? {
		for image in probe.images {
			for preference in [ContainerRuntime.Preference.apple, .docker] {
				guard let runtime = ContainerRuntime.discover(preference: preference),
				      holdsImage(image, in: runtime)
				else { continue }
				return (runtime, image)
			}
		}
		return nil
	}

	private func holdsImage(_ image: String, in runtime: ContainerRuntime) -> Bool {
		let process = Process()
		let command = ContainerImages.inspect(image, using: runtime)
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		// Nowhere rather than into pipes. Only the exit status is wanted, and a
		// pipe nobody drains is how a subprocess capture hangs — see
		// `ProcessPipes`, which exists because of exactly that.
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		// Not a `Pipe()`: this process would hold its write end open, and a
		// runtime that reads standard input then waits for an end that never
		// comes. Apple's `container` does exactly that.
		process.standardInput = FileHandle.nullDevice
		guard (try? process.run()) != nil else { return false }

		// With a deadline of its own, because asking a runtime a question is not
		// always answered: Apple's `container` talks to a service that can wedge
		// — every subcommand then waits, `container ls` included — and a test
		// that waits with it is the hang this suite is meant not to have. A
		// runtime that cannot answer whether it has the image is a runtime this
		// test cannot use, which is the same as not having it.
		let deadline = Date().addingTimeInterval(5)
		while process.isRunning, Date() < deadline {
			Thread.sleep(forTimeInterval: 0.05)
		}
		guard !process.isRunning else {
			process.terminate()
			return false
		}
		return process.terminationStatus == 0
	}

	/// The project on disk, with an `.abydos/tools.json` naming the image —
	/// which is how somebody actually asks for one.
	private func makeProject(_ probe: Probe, image: String) throws -> URL {
		let root = try JavaTestDirectory.make()
		for (path, contents) in probe.files {
			try JavaTestDirectory.write(contents, to: root.appendingPathComponent(path))
		}
		// The per-project route rather than the settings one. They meet at
		// `LanguageServers.resolve`, but everything before that differs: a file
		// on disk, parsed, keyed by the tool's name rather than the server's
		// command. A test that handed `resolve` a string would prove the half
		// that was never in doubt.
		try JavaTestDirectory.write(
			"{\"\(probe.tool)\": \"\(image)\"}\n", to: ToolImages.url(in: root)
		)
		// Canonical, because that is what the mount and every URI will use: a
		// temporary directory on macOS is under `/var`, which is a symlink.
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	/// `.serialized` here as well as on the suite: without it the six cases of
	/// one parameterised test run at once, which is six containers with a
	/// toolchain in each starting together.
	@Test(.serialized, arguments: probes)
	func aServerInAContainerAnswersAboutFilesOnThisMachine(_ probe: Probe) async throws {
		guard let (runtime, image) = available(for: probe) else { return }
		// What a run that was killed before it could tidy up left behind, on the
		// way in rather than on the way out: a `defer` and a `deinit` both run only
		// for the exits that were going well anyway, and the exit that leaves a
		// container is `run-tests.sh` killing a run for outliving its deadline.
		// Once per process, and language servers only — see `ContainerLeftovers`.
		_ = ContainerLeftovers.swept
		// Said out loud, because a live test that skips is silent and six silent
		// skips look exactly like six passes — which is the trap `project.md`
		// warns about, multiplied by six. This is the line that separates "the
		// suite is green" from "this server was driven from this image".
		print("  \(probe.tool): driving \(image) with \(runtime.name)")
		let root = try makeProject(probe, image: image)
		defer { try? FileManager.default.removeItem(at: root) }

		// Read back out of the project, the way the editor reads it: the tool's
		// key is the server definition's `name`, and a file that named it
		// anything else would resolve to no image at all.
		let definition = try #require(LanguageServers.definition(forLanguage: probe.languageId, choosing: .none))
		#expect(definition.name == probe.tool)
		let named = try #require(ToolImages.inProject(root).image(for: definition.name))
		#expect(named == image)

		let resolved = try #require(LanguageServers.resolve(
			languageId: probe.languageId, project: root, image: named, runtime: runtime,
			choosing: .none
		))

		// The image was chosen over anything installed, and the project is
		// mounted where the catalogue says it will be.
		let paths = try #require(resolved.launch.paths)
		#expect(paths.host == root.path)
		#expect(paths.container == "/workspace")

		let run = resolved.launch.invocation
		#expect(run.executable == runtime.path)
		#expect(run.arguments.contains("--rm"))
		#expect(run.arguments.contains("\(root.path):/workspace"))
		#expect(run.arguments.contains(image))
		// Nothing after the image: the server is the entry point, and whatever
		// arguments it needs — `--stdio`, and pyright's `pyright-langserver` —
		// are part of that entry point rather than something this side adds.
		#expect(run.arguments.last == image)

		// The name of the container this is about to start, so that this test can
		// end the one thing it began. Every container a test removes is one it
		// noted the name of as it started it — `ContainerCleanupTests` is the rule
		// written down, and 0435 is what the alternatives cost.
		let started = try #require(resolved.launch.container)

		let client = LSPClient()
		client.containerPaths = paths
		client.callbackQueue = .global()
		defer {
			client.stop()
			// And then waited for. `stop` posts the removal to a background queue
			// and deliberately does not wait — closing a project should not pause
			// on a runtime — which is right in the app and not enough here: a test
			// process exits within milliseconds of its last test, before that queue
			// has been reached, and the container goes on running with nobody left
			// who knows its name. That is 0473, and it is why every leak found on
			// this machine was the *last* container a run started: the five before
			// it had a whole test's worth of time to be removed in.
			_ = RuntimeCommand.run(
				ToolContainers.removal(of: [started.name], using: started.runtime),
				deadline: ToolContainers.removalDeadline
			)
		}

		let file = root.appendingPathComponent(probe.opened)
		let fileURI = URL(fileURLWithPath: FilePath.canonical(file)).absoluteString

		let diagnosed = Diagnosed()
		client.onDiagnostics = { uri, _ in diagnosed.record(uri) }

		try client.start(
			executable: run.executable,
			arguments: run.arguments,
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)

		// Generous: starting a container and reading a project is seconds rather
		// than milliseconds, the machine running this may be doing something
		// else, and jdtls imports a workspace before it says anything.
		let capabilities = try await client.initialize(
			rootURL: root,
			// What the app sends, and for the same reason: jdtls learns from this
			// where the project is, and `inContainer` is what stops it being
			// offered the JDKs and the debug bundle on *this* machine, which are
			// paths that name nothing in there.
			options: LanguageServers.initializationOptions(
				for: definition, root: root, inContainer: true
			),
			timeout: probe.patience
		)
		#expect(capabilities["definitionProvider"] != nil)
		#expect(capabilities["documentSymbolProvider"] != nil)

		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: fileURI, languageId: probe.languageId, version: 1, text: text)

		// Diagnostics are the server's first unprompted word about a file, and
		// the first chance to see a URI it chose rather than one it was given.
		//
		// The file's own, and not merely the first to arrive. This waited for the
		// first diagnostic of any kind and required it to be about the file just
		// opened, which is a race the suite lost about half the time on jdtls: an
		// Eclipse import publishes a diagnostic *against the project directory*
		// before it publishes one against any file in it — `file:///…/probe`, no
		// filename — and which of the two lands first is decided by how busy the
		// machine is. That is the whole of 0473's red suite, and the container an
		// earlier run had left behind was a coincidence: with one deliberately
		// present this passes, and on a machine with none it failed twice.
		let deadline = Date().addingTimeInterval(probe.patience)
		while !diagnosed.saw(fileURI), Date() < deadline {
			try? await Task.sleep(nanoseconds: 250_000_000)
		}
		// Named as this machine names it, not as /workspace/….
		#expect(diagnosed.saw(fileURI), "\(probe.tool) diagnosed \(diagnosed.uris) and not \(fileURI)")
		// And nothing at all came back in the container's names. This is the claim
		// the test is really here for, and it is now made about every URI the
		// server chose rather than about whichever one arrived first: a mapping
		// that missed one would show up as a path under the mount, or as a path in
		// some other project, and either is a file this machine does not have.
		// Without the trailing slash a directory URL carries, so that the project's
		// own URI — which is what jdtls names — compares equal, and so that the
		// prefix below is a whole path component rather than a string match. Two
		// projects called `probe` and `probe-notes` are the mistake that rule is
		// for, and `ContainerPaths.moved` states it on the other side of the wire.
		let inside = {
			let home = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true).absoluteString
			return home.hasSuffix("/") ? String(home.dropLast()) : home
		}()
		let strayed = diagnosed.uris.filter { uri in
			guard uri.hasPrefix("file:") else { return false }
			return uri != inside && !uri.hasPrefix(inside + "/")
		}
		#expect(strayed.isEmpty, "\(probe.tool) named files outside the project: \(strayed)")

		let symbols = try await settled(within: probe.patience) {
			try await client.documentSymbols(uri: fileURI)
		}
		for declared in probe.declares {
			#expect(
				symbols.contains { $0.name.hasPrefix(declared) },
				"\(probe.tool) did not declare \(declared): \(symbols.map(\.name))"
			)
		}

		// And the answer that is a place rather than a name: the declaration of
		// the first of them, from a use of it further down the file.
		let locations = try await settled(within: probe.patience) {
			try await client.definition(uri: fileURI, position: probe.use)
		}
		let declaration = try #require(locations.first, "\(probe.tool) found no declaration")
		#expect(declaration.uri == fileURI)
		#expect(declaration.url?.path == file.path)
		#expect(declaration.range.start.line == probe.declaredOnLine)
	}

	/// Asks again while the server says it is still catching up.
	///
	/// `ContentModified` — `-32801` — is the protocol's way of saying "I have
	/// changed my mind about the project since you asked, ask again"; it is not
	/// a failure and it is not about this request. rust-analyzer answers every
	/// request with it until the crate graph is built, and the first one arrives
	/// well before that: waiting for diagnostics is not enough, because it
	/// publishes those from its own analysis before cargo has been asked
	/// anything.
	///
	/// **This is a gap in the editor and not only in this test.** `LSPClient`
	/// hands the error to the caller, and nothing above it asks again — so a
	/// go-to-declaration in the first seconds of a Rust project fails silently
	/// rather than arriving a moment late. Written down here because that is
	/// where it was found; fixing it belongs to whatever item owns the client.
	private func settled<Value>(
		within patience: TimeInterval,
		_ ask: () async throws -> Value
	) async throws -> Value {
		let deadline = Date().addingTimeInterval(patience)
		while true {
			do {
				return try await ask()
			} catch LSPClient.ClientError.failed(-32801, _) where Date() < deadline {
				try? await Task.sleep(nanoseconds: 500_000_000)
			}
		}
	}

	/// Collects the callbacks from whichever thread they arrive on.
	///
	/// Every URI rather than the latest one, and in the order they came. A server
	/// publishes diagnostics about whatever it likes and in whatever order it
	/// finishes thinking about them — jdtls says something about the project
	/// directory itself before it says anything about a file in it — so "the one
	/// that arrived" is not a question with a stable answer, and a test that asked
	/// it was a coin toss. The whole list is also what makes a failure worth
	/// reading: it says what the server did name, which is the first thing anybody
	/// looking at this wants to know.
	private final class Diagnosed: @unchecked Sendable {
		private let lock = NSLock()
		private var seen: [String] = []

		var uris: [String] { lock.lock(); defer { lock.unlock() }; return seen }

		func saw(_ uri: String) -> Bool { uris.contains(uri) }

		func record(_ uri: String) {
			lock.lock()
			seen.append(uri)
			lock.unlock()
		}
	}
}
