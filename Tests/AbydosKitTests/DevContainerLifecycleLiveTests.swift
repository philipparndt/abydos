import Foundation
import Testing
@testable import AbydosKit

/// The lifecycle commands, run against a real container.
///
/// The thing this proves that no comparison of command lines can: that a
/// project whose `devcontainer.json` says "install these before I work in you"
/// gets a container with them installed — and that each of the six ran at its
/// own moment and not at anybody else's. Getting that wrong means re-running an
/// installer on every launch, or never running it at all, and both look from
/// outside like a container that came up.
///
/// Skipped, per runtime, unless that runtime already has the image:
///
///     docker pull alpine:3
///     container image pull alpine:3
@Suite(.serialized) struct DevContainerLifecycleLiveTests {
	static let image = "alpine:3"

	private func available(_ preference: ContainerRuntime.Preference) -> ContainerRuntime? {
		guard let runtime = ContainerRuntime.discover(preference: preference),
		      RuntimeCommand.run(
		      	ContainerImages.inspect(Self.image, using: runtime), deadline: 20
		      ).succeeded
		else { return nil }
		return runtime
	}

	private func makeProject(_ file: String) throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write(
			file, to: root.appendingPathComponent(".devcontainer/devcontainer.json")
		)
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	/// What a command inside the container printed.
	private func inside(_ session: DevContainers.Session, _ script: String) -> String {
		RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: ["/bin/sh", "-c", script]), deadline: 60
		).output.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Each at its own moment

	/// All six, and the marker that keeps three of them from running twice.
	///
	/// Nothing here needs the network, deliberately: what is under test is when
	/// each command runs, and a test that also has to reach a package mirror
	/// fails for reasons that have nothing to do with it. The example in the
	/// repository beside this one installs a real package, and the last test in
	/// this file runs that one.
	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func runsEachLifecycleCommandAtItsOwnMomentAndOnlyThen(
		_ preference: ContainerRuntime.Preference
	) async throws {
		guard let runtime = available(preference) else { return }
		// `initializeCommand` runs out here, in the checkout, and its evidence is
		// a file on this machine rather than in the container.
		//
		// `onCreateCommand` installs something: a program in the container's own
		// PATH that was not in the image, which is what "the container came up
		// with what the file asked for" means when you go and look.
		//
		// The two members of `postCreateCommand` each record when they started
		// and when they finished, because "in parallel" is not a thing a count
		// of lines can show — overlapping intervals is.
		let root = try makeProject("""
		{
			"image": "\(Self.image)",
			"initializeCommand": "echo host > initialized.txt",
			"onCreateCommand": "printf '#!/bin/sh\\\\necho probe-tool v1\\\\n' > /usr/local/bin/probe-tool; chmod +x /usr/local/bin/probe-tool; echo on-create >> /tmp/created.log",
			"updateContentCommand": ["/bin/sh", "-c", "echo update-content >> /tmp/created.log"],
			"postCreateCommand": {
				"one": "date +%s > /tmp/one.start; sleep 3; date +%s > /tmp/one.end; echo post-create-one >> /tmp/created.log",
				"two": "date +%s > /tmp/two.start; sleep 3; date +%s > /tmp/two.end; echo post-create-two >> /tmp/created.log"
			},
			"postStartCommand": "echo started >> /tmp/started.log",
			"postAttachCommand": "echo attached >> /tmp/attached.log",
		}
		""")
		defer { try? FileManager.default.removeItem(at: root) }

		let outcome = await DevContainers.shared.session(for: root, using: runtime)
		guard case let .running(session)? = outcome else {
			Issue.record("the devcontainer did not start: \(String(describing: outcome))")
			return
		}
		defer { Task { await DevContainers.shared.stop(project: root) } }

		// On this machine, not in the container: the file it wrote is in the
		// checkout and the container has no such thing on its own side.
		let initialized = root.appendingPathComponent("initialized.txt")
		#expect((try? String(contentsOf: initialized, encoding: .utf8))?.contains("host") == true)

		// What onCreateCommand installed, asked of the container rather than
		// assumed from an exit status.
		#expect(inside(session, "probe-tool").contains("probe-tool v1"))

		// The three creation commands, in the order the spec puts them in.
		#expect(inside(session, "cat /tmp/created.log")
			== "on-create\nupdate-content\npost-create-one\npost-create-two"
			|| inside(session, "cat /tmp/created.log")
				== "on-create\nupdate-content\npost-create-two\npost-create-one")
		#expect(inside(session, "cat /tmp/started.log") == "started")

		// Parallel, shown as overlapping rather than as a stopwatch: each member
		// slept three seconds, so if they ran one after the other neither
		// interval contains a moment of the other.
		let one = (Int(inside(session, "cat /tmp/one.start")) ?? 0,
		           Int(inside(session, "cat /tmp/one.end")) ?? 0)
		let two = (Int(inside(session, "cat /tmp/two.start")) ?? 0,
		           Int(inside(session, "cat /tmp/two.end")) ?? 0)
		#expect(one.0 > 0 && two.0 > 0)
		#expect(one.0 < two.1 && two.0 < one.1, "the two postCreateCommand members did not overlap")

		// The marker, which is how "has this container been created?" is
		// answered — inside the container, so that it dies with it.
		#expect(inside(session, "cat \(DevContainers.creationMarker)").contains("created by Abydos"))

		// And what it buys: the container starting again runs postStartCommand
		// again and does *not* run the three that created it.
		await DevContainers.shared.runLifecycle(session)
		#expect(inside(session, "wc -l < /tmp/created.log").trimmingCharacters(in: .whitespaces) == "4")
		#expect(inside(session, "cat /tmp/started.log") == "started\nstarted")

		// postAttachCommand is per attach, and two terminals are two attaches.
		await DevContainers.shared.attach(to: session)
		await DevContainers.shared.attach(to: session)
		#expect(inside(session, "cat /tmp/attached.log") == "attached\nattached")

		await DevContainers.shared.stop(project: root)
		#expect(isGone(session.name, using: runtime), "the container was not removed")
	}

	// MARK: - When one fails

	/// A command that fails names itself, and nothing after it runs.
	///
	/// The shape of `devcontainers/post-create-fails` in the examples repository:
	/// a `postCreateCommand` that exits 3 some way in, with a `postStartCommand`
	/// after it that must not run — a container that went on to start what it
	/// was told to start after its tools failed to install is the state this
	/// whole thing exists to avoid.
	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func aFailedLifecycleCommandNamesItselfAndStopsWhatFollows(
		_ preference: ContainerRuntime.Preference
	) async throws {
		guard let runtime = available(preference) else { return }
		let root = try makeProject("""
		{
			"image": "\(Self.image)",
			"postCreateCommand": "echo 'step 1 of 3 — this works'; echo 'error: no such package: a-package-that-does-not-exist' >&2; exit 3",
			"postStartCommand": "touch /tmp/must-not-exist",
		}
		""")
		defer { try? FileManager.default.removeItem(at: root) }

		let outcome = await DevContainers.shared.session(for: root, using: runtime)
		guard case let .refused(reason)? = outcome else {
			await DevContainers.shared.stop(project: root)
			Issue.record("a postCreateCommand exiting 3 was not refused: \(String(describing: outcome))")
			return
		}

		// The command, by the name of the field somebody would go and edit; its
		// exit status; and what it said — which is on standard error, beside a
		// standard output whose last line is only how far it got.
		#expect(reason.contains("postCreateCommand"))
		#expect(reason.contains("exited 3"))
		#expect(reason.contains("no such package: a-package-that-does-not-exist"))
		#expect(reason.contains("open the project again"))

		// Nothing is left holding the project's mount, and nothing after the
		// failure ran — the container it would have run in is gone.
		#expect(await DevContainers.shared.existingSession(for: root) == nil)
		#expect(noContainerLeft(using: runtime), "a container was left behind by the failure")
	}

	// MARK: - The example, which installs something real

	/// `devcontainers/post-create` in the examples repository, end to end.
	///
	/// The fixture 0424 asks for: a `postCreateCommand` slow enough to need
	/// saying on screen, which fetches the tools the image deliberately does not
	/// carry. What it proves that the test above cannot is the whole point of
	/// running these at all — `jq` was not in `alpine:3.21` and it is in the
	/// container.
	@Test func theExamplesPostCreateInstallsWhatTheImageDoesNotCarry() async throws {
		guard let examples = ExampleProjects.root else { return }
		let project = examples.appendingPathComponent("devcontainers/post-create")
		guard DevContainerFile.exists(in: project) else { return }
		guard let runtime = ContainerRuntime.discover(preference: .docker),
		      RuntimeCommand.run(
		      	ContainerImages.inspect("alpine:3.21", using: runtime), deadline: 20
		      ).succeeded
		else { return }

		let said = Announced()
		let outcome = await DevContainers.shared.session(
			for: project, using: runtime, progress: { said.record($0) }
		)
		guard case let .running(session)? = outcome else {
			Issue.record("the example did not come up: \(String(describing: outcome))")
			return
		}
		defer { Task { await DevContainers.shared.stop(project: project) } }

		// Said once, with what it is doing — `ContainerImages.progressMessage`'s
		// bargain, which a command that takes fifteen seconds needs more than a
		// pull does.
		#expect(said.all.contains { $0.contains("postCreateCommand") })
		#expect(said.all.contains { $0.contains("post-create.sh") })

		// And the thing itself: a tool the image does not carry, in the
		// container, because the file said to put it there.
		#expect(inside(session, "jq --version").contains("jq-"))

		await DevContainers.shared.stop(project: project)
		#expect(isGone(session.name, using: runtime), "the container was not removed")
	}

	// MARK: - Afterwards

	private func isGone(_ name: String, using runtime: ContainerRuntime) -> Bool {
		guard let listing = ToolContainers.listing(using: runtime) else { return false }
		let deadline = Date().addingTimeInterval(30)
		while Date() < deadline {
			let listed = RuntimeCommand.run(listing, deadline: 15)
			if listed.succeeded, !listed.output.contains(name) { return true }
			Thread.sleep(forTimeInterval: 0.5)
		}
		return false
	}

	/// Whether no devcontainer of ours is on the machine at all.
	private func noContainerLeft(using runtime: ContainerRuntime) -> Bool {
		guard let listing = ToolContainers.listing(using: runtime) else { return false }
		let deadline = Date().addingTimeInterval(30)
		while Date() < deadline {
			let listed = RuntimeCommand.run(listing, deadline: 15)
			if listed.succeeded, !listed.output.contains("abydos-devcontainer-") { return true }
			Thread.sleep(forTimeInterval: 0.5)
		}
		return false
	}

	/// What went to the progress closure, from whichever thread it arrived on.
	private final class Announced: @unchecked Sendable {
		private let lock = NSLock()
		private var lines: [String] = []

		func record(_ line: String) {
			lock.lock()
			lines.append(line)
			lock.unlock()
		}

		var all: [String] {
			lock.lock()
			defer { lock.unlock() }
			return lines
		}
	}
}
