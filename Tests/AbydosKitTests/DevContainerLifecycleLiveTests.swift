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
/// **Docker, and not both runtimes**, unlike `DevContainerLiveTests` beside it,
/// and the reason is that there is nothing here for the second one to prove. A
/// lifecycle command is `exec` and `RuntimeCommand`, and both of those are
/// already exercised on Apple's runtime by that test — the mount, `-d`, `-u`,
/// `-e`, `-w` and `exec -it` onto a pty. What running this matrix twice adds is
/// six more container creations and removals on the runtime whose service is
/// this suite's known bottleneck (0406), which buys flakiness rather than
/// coverage.
///
/// Skipped unless docker already has the image:
///
///     docker pull alpine:3
@Suite(.serialized) struct DevContainerLifecycleLiveTests {
	static let image = "alpine:3"

	private var available: ContainerRuntime? {
		guard let runtime = ContainerRuntime.discover(preference: .docker),
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
	@Test func runsEachLifecycleCommandAtItsOwnMomentAndOnlyThen() async throws {
		guard let runtime = available else { return }
		// `initializeCommand` runs out here, in the checkout, and its evidence is
		// a file on this machine rather than in the container.
		//
		// `onCreateCommand` installs something: a program in the container's own
		// PATH that was not in the image, which is what "the container came up
		// with what the file asked for" means when you go and look.
		//
		// The two members of `postCreateCommand` each say they are here and then
		// wait for the other to say it. That is what "in parallel" means, said in
		// a way a clock cannot get wrong: run one after the other, the first can
		// never see the second, however slow or fast the machine is.
		let waitForTheOther = { (mine: String, theirs: String) in
			"touch /tmp/\(mine).here; i=0; while [ $i -lt 60 ]; do "
				+ "if [ -f /tmp/\(theirs).here ]; then touch /tmp/\(mine).saw-\(theirs); break; fi; "
				+ "sleep 0.2; i=$((i+1)); done; echo post-create-\(mine) >> /tmp/created.log"
		}
		let root = try makeProject("""
		{
			"image": "\(Self.image)",
			"initializeCommand": "echo host > initialized.txt",
			"onCreateCommand": "printf '#!/bin/sh\\\\necho probe-tool v1\\\\n' > /usr/local/bin/probe-tool; chmod +x /usr/local/bin/probe-tool; echo on-create >> /tmp/created.log",
			"updateContentCommand": ["/bin/sh", "-c", "echo update-content >> /tmp/created.log"],
			"postCreateCommand": {
				"one": "\(waitForTheOther("one", "two"))",
				"two": "\(waitForTheOther("two", "one"))"
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

		// The three creation commands, in the order the spec puts them in — and
		// the two members of the third in either order, because they overlapped.
		let created = inside(session, "cat /tmp/created.log")
		#expect(created == "on-create\nupdate-content\npost-create-one\npost-create-two"
			|| created == "on-create\nupdate-content\npost-create-two\npost-create-one",
			"the creation commands ran as: \(created)")
		#expect(inside(session, "cat /tmp/started.log") == "started")

		// Parallel: `one` saw `two` running. Run one after the other, the first
		// of them could not have — which is the whole of the assertion, with no
		// clock in it.
		#expect(inside(session, "ls /tmp/one.saw-two /tmp/two.saw-one 2>&1")
			== "/tmp/one.saw-two\n/tmp/two.saw-one",
			"the two postCreateCommand members did not run at the same time")

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
	@Test func aFailedLifecycleCommandNamesItselfAndStopsWhatFollows() async throws {
		guard let runtime = available else { return }
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
