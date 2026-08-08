import Foundation
import Testing
@testable import AbydosKit

/// Fetching an image before something is asked to run from it.
struct ContainerImageTests {
	private let apple = ContainerRuntime.apple("/usr/local/bin/container")
	private let docker = ContainerRuntime.docker("/usr/bin/docker")

	/// The two runtimes spell the same thing differently, and both were tried
	/// against the real commands rather than guessed from the docs.
	@Test func eachRuntimeIsAskedInItsOwnWords() {
		let appleInspect = ContainerImages.inspect("plantuml/plantuml", using: apple)
		#expect(appleInspect.executable == "/usr/local/bin/container")
		#expect(appleInspect.arguments == ["images", "inspect", "plantuml/plantuml"])

		let dockerInspect = ContainerImages.inspect("plantuml/plantuml", using: docker)
		#expect(dockerInspect.arguments == ["image", "inspect", "plantuml/plantuml"])

		#expect(ContainerImages.pull("x:1", using: apple).arguments == ["images", "pull", "x:1"])
		#expect(ContainerImages.pull("x:1", using: docker).arguments == ["pull", "x:1"])
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
}
