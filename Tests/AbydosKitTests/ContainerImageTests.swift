import Foundation
import Testing
@testable import AbydosKit

/// Fetching an image before something is asked to run from it.
struct ContainerImageTests {
	private let apple = ContainerRuntime.apple("/usr/local/bin/container")
	private let docker = ContainerRuntime.docker("/usr/bin/docker")

	/// The two runtimes spell the same thing differently — and this said they
	/// were "tried against the real commands rather than guessed from the docs"
	/// while sending Apple's a plural subcommand it does not have. The noun is
	/// singular in both. `ContainerImageLiveTests` is what "tried" means now.
	@Test func eachRuntimeIsAskedInItsOwnWords() {
		let appleInspect = ContainerImages.inspect("plantuml/plantuml", using: apple)
		#expect(appleInspect.executable == "/usr/local/bin/container")
		#expect(appleInspect.arguments == ["image", "inspect", "plantuml/plantuml"])

		let dockerInspect = ContainerImages.inspect("plantuml/plantuml", using: docker)
		#expect(dockerInspect.arguments == ["image", "inspect", "plantuml/plantuml"])

		// Pull is where they do differ: docker's is a verb of its own, Apple's
		// lives under `image` with the rest of them.
		#expect(ContainerImages.pull("x:1", using: apple).arguments == ["image", "pull", "x:1"])
		#expect(ContainerImages.pull("x:1", using: docker).arguments == ["pull", "x:1"])
	}

	/// A runtime complaining about itself is not an image that does not exist.
	///
	/// This is the predicate that turned `Plugin 'container-images' not found`
	/// into "There is no image called plantuml/plantuml:1.2026.6. Check the name
	/// and the tag" — a confident falsehood about a name that was correct, said
	/// to somebody who then went and checked it.
	@Test func aRuntimeComplainingAboutItselfIsNotAMissingImage() {
		// The one that caused it, and its family.
		#expect(!ContainerImages.isUnknownImage("Error: Plugin 'container-images' not found."))
		#expect(!ContainerImages.isUnknownImage("container: command not found"))
		#expect(!ContainerImages.isUnknownImage(
			"docker: executable file not found in $PATH"
		))

		// And the ones that really are a missing image, in both runtimes' words.
		#expect(ContainerImages.isUnknownImage("Error: image not found: nope/nope:1"))
		#expect(ContainerImages.isUnknownImage(
			"Error response from daemon: manifest for nope/nope:1 not found"
		))
		#expect(ContainerImages.isUnknownImage(
			"Error: HTTP request to https://registry-1.docker.io/v2/library/alpine/manifests/"
				+ "99.99 failed with response: 404 Not Found."
		))
		#expect(ContainerImages.isUnknownImage("Error: No such image: a/b:1"))

		// A wrong-verb failure therefore reaches the honest branch instead, which
		// quotes what the runtime actually said.
		let plugin = ContainerImages.explain(
			"Error: Plugin 'container-images' not found.", image: "plantuml/plantuml:1.2026.6"
		)
		#expect(plugin.contains("Plugin 'container-images' not found"))
		#expect(!plugin.contains("Check the name"))
	}

	/// Four things go wrong and each has a different answer: fix the name, sign
	/// in, get a network, start the runtime. Saying which is the whole value —
	/// the runtimes' own words are long and mostly about themselves.
	@Test func aFailureSaysWhichOfTheFourItWas() {
		let name = ContainerImages.explain(
			"Error response from daemon: manifest for plantuml/nope:1 not found", image: "plantuml/nope:1"
		)
		#expect(name.contains("no image called plantuml/nope:1"))

		let auth = ContainerImages.explain(
			"Error response from daemon: pull access denied, repository does not exist "
				+ "or may require 'docker login'", image: "private/thing"
		)
		#expect(auth.contains("sign-in") || auth.contains("private"))

		let network = ContainerImages.explain(
			"Get https://registry-1.docker.io/v2/: dial tcp: lookup registry-1.docker.io: no such host",
			image: "a/b"
		)
		#expect(network.contains("Could not reach the registry"))

		let daemon = ContainerImages.explain(
			"Cannot connect to the Docker daemon at unix:///var/run/docker.sock.", image: "a/b"
		)
		#expect(daemon.contains("not running"))
	}

	/// Anything else keeps the runtime's first line rather than inventing a
	/// reason, and an empty answer says that it said nothing.
	@Test func anythingElseIsPassedOnHonestly() {
		let odd = ContainerImages.explain("something nobody has seen\nand a second line", image: "a/b")
		#expect(odd.contains("something nobody has seen"))
		#expect(!odd.contains("second line"))

		#expect(ContainerImages.explain("", image: "a/b").contains("said nothing"))
		#expect(ContainerImages.explain("   \n  ", image: "a/b").contains("said nothing"))
	}

	/// The two runtimes keep separate stores, so "which one was asked" is part
	/// of the answer rather than a detail.
	@Test func anImageInTheOtherRuntimeIsSaidToBeThere() {
		let said = ContainerImages.visibleElsewhere(
			"abydos/gopls:dev",
			missingFrom: .apple("/usr/local/bin/container"),
			presentIn: .docker("/usr/bin/docker")
		)
		#expect(said.contains("container has no image called abydos/gopls:dev"))
		#expect(said.contains("docker does"))
		// The point of the sentence: it is not the name that is wrong.
		#expect(!said.contains("Check the name"))
	}

	/// Looking for the other family, not the other command: nerdctl and podman
	/// are docker's for this purpose, and asking Apple's about a docker image
	/// is the case worth catching.
	@Test func theAlternativeIsTheOtherFamily() {
		let both: (String) -> String? = { "/usr/bin/\($0)" }
		#expect(ContainerImages.alternative(to: .apple("/x"), locate: both)
			== .docker("/usr/bin/docker"))
		#expect(ContainerImages.alternative(to: .docker("/x"), locate: both)
			== .apple("/usr/bin/container"))
		// Nothing else installed is nothing to suggest.
		#expect(ContainerImages.alternative(to: .apple("/x"), locate: { _ in nil }) == nil)
	}

	@Test func itSaysWhichImageItIsFetching() {
		#expect(ContainerImages.progressMessage(for: "plantuml/plantuml")
			== "Fetching plantuml/plantuml…")
	}
}

/// Fetching once, however many things ask.
struct ContainerImageStoreTests {
	/// An empty name is a no rather than a process launch with no argument.
	@Test func anEmptyNameIsRefusedWithoutAsking() async {
		let store = ContainerImageStore()
		let outcome = await store.ensure("", using: .docker("/usr/bin/docker"))
		#expect(outcome == .failed("No image was named."))
	}

	/// A runtime that is not there fails with a sentence rather than throwing.
	@Test func aRuntimeThatIsNotThereIsAFailureNotACrash() async {
		let store = ContainerImageStore()
		let outcome = await store.ensure(
			"plantuml/plantuml", using: .docker("/nonexistent/docker")
		)
		guard case let .failed(reason) = outcome else {
			Issue.record("expected a failure, got \(outcome)")
			return
		}
		#expect(!reason.isEmpty)
	}

	/// A runtime that reads standard input still finishes.
	///
	/// The bug this pins cost an afternoon. `standardInput = Pipe()` reads as
	/// "nothing on standard input" and means the opposite: this process holds
	/// the write end, so the child is given an input that never ends. Apple's
	/// `container` waits for that end — `container images inspect` with a pipe
	/// held open never answers — so the first check of whether an image was on
	/// the machine hung for ever, taking the pane, the test, or the language
	/// server that asked with it.
	///
	/// Stood in for by a script that reads to end of file, so the test needs no
	/// container runtime and fails on any machine if this comes back.
	@Test func aRuntimeThatReadsItsInputIsGivenAnEnd() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("runtime-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let script = directory.appendingPathComponent("reads-stdin")
		try Data("#!/bin/sh\ncat > /dev/null\nexit 0\n".utf8).write(to: script)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: script.path
		)

		let store = ContainerImageStore()
		let outcome = await withTaskGroup(of: ContainerImageStore.Outcome?.self) { group in
			group.addTask { await store.ensure("a/b", using: .docker(script.path)) }
			group.addTask {
				try? await Task.sleep(nanoseconds: 10_000_000_000)
				return nil
			}
			let first = await group.next() ?? nil
			group.cancelAll()
			return first
		}
		// Present, because the stand-in exits 0 as an inspect that found it
		// would — and above all, present rather than still waiting.
		#expect(outcome == .present)
	}

	/// An image built locally with docker, asked for through Apple's runtime.
	///
	/// The whole failure this catches is that both of the old sentences were
	/// true and pointed the wrong way: the name is fine, and the pull it then
	/// tried was for something already on the machine. Stood in for by two
	/// scripts, so no runtime has to be installed.
	@Test func anImageTheOtherRuntimeHasIsNotCalledAWrongName() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("stores-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		func script(_ name: String, _ body: String) throws -> String {
			let url = directory.appendingPathComponent(name)
			try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
			try FileManager.default.setAttributes(
				[.posixPermissions: 0o755], ofItemAtPath: url.path
			)
			return url.path
		}

		// Never heard of it, for both the inspect and the pull.
		let blind = try script("blind", "echo 'Error: no such image' >&2\nexit 1")
		// Has it.
		let holder = try script("holder", "exit 0")

		let store = ContainerImageStore(
			alternative: { _ in .docker(holder) }
		)
		let outcome = await store.ensure("abydos/gopls:dev", using: .apple(blind))
		guard case let .failed(reason) = outcome else {
			Issue.record("expected a failure, got \(outcome)")
			return
		}
		#expect(reason.contains("separate stores"))
		#expect(!reason.contains("Check the name"))

		// With nothing else on the machine it stays the plain answer, rather
		// than a suggestion to switch to a runtime that is not there.
		let alone = ContainerImageStore(alternative: { _ in nil })
		let second = await alone.ensure("abydos/gopls:dev", using: .apple(blind))
		guard case let .failed(plain) = second else {
			Issue.record("expected a failure, got \(second)")
			return
		}
		#expect(plain.contains("Check the name"))
	}

	/// Two askers for the same image wait on one fetch rather than starting two.
	@Test func askersForTheSameImageShareTheAnswer() async {
		let store = ContainerImageStore()
		async let first = store.ensure("a/b", using: .docker("/nonexistent/docker"))
		async let second = store.ensure("a/b", using: .docker("/nonexistent/docker"))
		let outcomes = await [first, second]
        #expect(outcomes[0] == outcomes[1])
	}

	/// A build's own output arrives while it is still building.
	///
	/// The whole of 0459 in one claim. `ensure` has always taken an `output` sink
	/// and the build branch has always passed it on; what nobody had checked is
	/// that it arrives *during* the build rather than with the answer — which is
	/// the only thing that makes a pane worth opening, since 0457 measured a cold
	/// `rust-analyzer` at 164 seconds and output that appears at the end is 164
	/// seconds of silence however it is displayed.
	///
	/// The claim is deliberately relative — the first piece is heard a second and
	/// more before the outcome — because an absolute one measures how busy the
	/// machine running the test is.
	///
	/// Stood in for by a script, so this needs no runtime, builds nothing and
	/// runs in a plain `make test`. It pins the other half of the same branch
	/// while it is there: a name in this app's namespace is built, and is never
	/// sent to a registry.
	@Test func aBuildsOwnOutputArrivesWhileItIsStillBuilding() async throws {
		let recipe = try #require(ToolImageRecipes.recipe(forTool: "openscad-lsp"))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("building-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		// What the stand-in was asked to do, so that "built and not pulled" is
		// read off the runtime's own arguments rather than inferred from the
		// outcome.
		let asked = directory.appendingPathComponent("asked")
		let script = directory.appendingPathComponent("runtime")
		try Data("""
		#!/bin/sh
		echo "$1" >> \(asked.path)
		case "$1" in
		build)
			echo '#1 [internal] load build definition from Dockerfile'
			sleep 2
			echo '#8 writing image sha256:deadbeef'
			exit 0
			;;
		*)
			echo 'Error: no such image' >&2
			exit 1
			;;
		esac

		""".utf8).write(to: script)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: script.path
		)

		let heard = Heard()
		let store = ContainerImageStore()
		let outcome = await store.ensure(
			recipe.image, using: .docker(script.path), output: { heard.add($0) }
		)
		let finished = Date()

		#expect(outcome == .built)
		let first = try #require(heard.firstAt)
		#expect(finished.timeIntervalSince(first) > 1)
		#expect(heard.text.contains("load build definition"))
		#expect(heard.text.contains("writing image"))

		// Nothing in `abydos-built/` is fetched from anywhere, which is the
		// requirement this branch exists to keep.
		let subcommands = try String(contentsOf: asked, encoding: .utf8)
		#expect(subcommands.contains("build"))
		#expect(!subcommands.contains("pull"))
	}

	/// What a command said, and when the first of it was heard.
	///
	/// Written from the two threads reading the pipes and read from the test, so
	/// it locks — the same shape `RuntimeCommand` uses for its one bool.
	private final class Heard: @unchecked Sendable {
		private let lock = NSLock()
		private var pieces = ""
		private var first: Date?

		func add(_ piece: String) {
			lock.lock()
			if first == nil { first = Date() }
			pieces += piece
			lock.unlock()
		}

		var text: String {
			lock.lock()
			defer { lock.unlock() }
			return pieces
		}

		var firstAt: Date? {
			lock.lock()
			defer { lock.unlock() }
			return first
		}
	}
}

/// Against a real runtime: that the commands this sends are ones the runtime
/// has, which is the thing no comparison of strings can tell you.
///
/// It is here because the alternative was believed for a whole feature's
/// lifetime: `container images inspect` is not a subcommand, every image-backed
/// thing failed on Apple's runtime because of it, and the failure arrived as a
/// sentence blaming the image's name. A test that asks the real CLI would have
/// caught it the day it was written.
///
/// Skipped, per runtime, unless that runtime is here.
@Suite(.serialized) struct ContainerImageLiveTests {
	/// Small, and pulled by the other live tests anyway.
	static let image = "alpine:3"

	private func runtime(_ preference: ContainerRuntime.Preference) -> ContainerRuntime? {
		ContainerRuntime.discover(preference: preference)
	}

	/// An image the runtime has, found by the command this app sends it.
	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func theInspectCommandIsOneTheRuntimeHas(
		_ preference: ContainerRuntime.Preference
	) async throws {
		guard let runtime = runtime(preference) else { return }
		let asked = RuntimeCommand.run(
			ContainerImages.inspect(Self.image, using: runtime), deadline: 30
		)
		// Either the image is here and it answered, or it is honestly not here —
		// but never "that subcommand does not exist", which is what this is for
		// and is what a wrong verb looks like on both of them.
		guard asked.succeeded else {
			// Installed but not answering is not this test's subject. The user
			// stops one runtime to work with the other, and a suite that goes
			// red for it reports on the machine rather than on the code.
			guard !ContainerImages.isRuntimeDown(asked.output) else { return }
			#expect(
				ContainerImages.isUnknownImage(asked.output),
				"\(runtime.name) did not understand the command: \(asked.output.prefix(200))"
			)
			return
		}
		// It is here, so the store says so without fetching anything.
		let store = ContainerImageStore()
		#expect(await store.ensure(Self.image, using: runtime) == .present)
	}

	/// And an image no registry has, which must come back as a missing image
	/// rather than as whatever the runtime says about itself.
	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func anImageNobodyHasIsSaidToBeMissingRatherThanBlamedOnTheRuntime(
		_ preference: ContainerRuntime.Preference
	) async throws {
		guard let runtime = runtime(preference) else { return }
		let missing = "abydos-probe/definitely-not-an-image:1"
		let asked = RuntimeCommand.run(
			ContainerImages.inspect(missing, using: runtime), deadline: 30
		)
		#expect(!asked.succeeded)
		// Same reason as above: a stopped runtime says nothing about whether a
		// missing image is reported as missing.
		guard !ContainerImages.isRuntimeDown(asked.output) else { return }
		#expect(ContainerImages.isUnknownImage(asked.output), "\(asked.output.prefix(200))")
	}
}
