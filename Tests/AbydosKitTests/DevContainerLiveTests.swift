import Foundation
import Testing
@testable import AbydosKit

/// Against a real container, brought up from a real `devcontainer.json`.
///
/// This is the test the whole thing exists for, and the one thing it proves
/// that no amount of comparing command lines can: that a project with a
/// devcontainer file opens into a container which is running, has the checkout
/// where the file said it would, gives somebody a shell inside it, and is gone
/// again afterwards.
///
/// **Run for both runtimes**, which is what lifted 0406's docker-only decision
/// here: everything a devcontainer is made of — the bind mount, `-d` with the
/// keep-alive, `--entrypoint`, `-u`, `-e`, `-w`, `exec -it` onto a pty, and the
/// removal at the end — was exercised on Apple's runtime by running this against
/// it. The one thing that does not work there is a forwarded port, and that is
/// refused by name rather than tested here.
///
/// Skipped, per runtime, unless that runtime has the image already. To run all
/// of it:
///
///     docker pull alpine:3
///     container image pull alpine:3
@Suite(.serialized) struct DevContainerLiveTests {
	/// Small, present on most machines that have docker at all, and pinned to a
	/// major so this does not silently start testing a different distribution.
	static let image = "alpine:3"

	/// That runtime, if it is here and already holds the image.
	private func available(_ preference: ContainerRuntime.Preference) -> ContainerRuntime? {
		guard let runtime = ContainerRuntime.discover(preference: preference),
		      holdsImage(runtime)
		else { return nil }
		return runtime
	}

	private func holdsImage(_ runtime: ContainerRuntime) -> Bool {
		RuntimeCommand.run(
			ContainerImages.inspect(Self.image, using: runtime), deadline: 20
		).succeeded
	}

	/// A project with a devcontainer file and one file to find through the mount.
	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write("""
		{
			// The plainest thing that works: one image and nothing else.
			"name": "Live",
			"image": "\(Self.image)",
			"containerEnv": { "ABYDOS_LIVE": "yes" },
			"remoteEnv": { "ABYDOS_REMOTE": "also" },
		}
		""", to: root.appendingPathComponent(".devcontainer/devcontainer.json"))
		try JavaTestDirectory.write(
			"the checkout is here\n", to: root.appendingPathComponent("marker.txt")
		)
		// Canonical, because that is what the mount will use: a temporary
		// directory on macOS is under `/var`, which is a symlink.
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func opensAProjectInItsDevcontainerAndGivesSomebodyAShellInIt(
		_ preference: ContainerRuntime.Preference
	) async throws {
		guard let runtime = available(preference) else { return }
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let outcome = await DevContainers.shared.session(for: root, using: runtime)
		guard case let .running(session)? = outcome else {
			Issue.record("the devcontainer did not start: \(String(describing: outcome))")
			return
		}
		// From here on nothing throws, so the container is removed at the end
		// however the assertions go.
		#expect(session.name.hasPrefix("abydos-devcontainer-"))
		#expect(ToolContainers.shared.names.contains(session.name))
		#expect(session.configuration.paths.container == "/workspaces/\(root.lastPathComponent)")

		// It is up, and it is the project that is mounted in it.
		let running = RuntimeCommand.run(
			DevContainers.stateCommand(name: session.name, using: runtime), deadline: 20
		)
		#expect(DevContainers.isRunning(running.output, using: runtime))

		let contents = RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: ["cat", "marker.txt"]), deadline: 30
		)
		#expect(contents.output.contains("the checkout is here"))

		// Written on this side, seen on that one, without restarting anything —
		// which is the whole point of the files staying on the host.
		try? Data("later\n".utf8).write(to: root.appendingPathComponent("added.txt"))
		let added = RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: ["cat", "added.txt"]), deadline: 30
		)
		#expect(added.output.contains("later"))

		// The environment the file asked for, on each of the two sides it can be
		// asked for on.
		let environment = RuntimeCommand.run(
			DevContainers.execCommand(
				session, arguments: ["/bin/sh", "-c", "echo $ABYDOS_LIVE-$ABYDOS_REMOTE"]
			), deadline: 30
		)
		#expect(environment.output.contains("yes-also"))

		// Asking again gets the same container rather than a second one, which
		// is what makes switching projects instant.
		let again = await DevContainers.shared.session(for: root, using: runtime)
		if case let .running(second)? = again {
			#expect(second.name == session.name)
		} else {
			Issue.record("the second ask did not find the container it started")
		}

		await aTerminalInIt(session)

		await DevContainers.shared.stop(project: root)
		#expect(isGone(session.name, using: runtime), "the container was not removed")
	}

	/// A project reached through a symlink, built from the Dockerfile its own
	/// devcontainer.json names.
	///
	/// 0430, end to end, and the reason it is a live test rather than only a
	/// parse one: what went wrong was not visible in the configuration unless
	/// you knew what to look at — it was visible as a runtime refusing to build,
	/// saying a Dockerfile that is plainly on disk does not exist. `relative()`
	/// canonicalised the project root and not the file, so under `/tmp` or
	/// `/var` — both symlinks on macOS, and so the shape of every scratch
	/// project this harness makes — the file's folder fell off `shown` and the
	/// Dockerfile resolved to `<project>/Dockerfile`.
	///
	/// The project is opened *by the link*, which is the whole point.
	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func buildsTheDockerfileOfAProjectReachedThroughASymlink(
		_ preference: ContainerRuntime.Preference
	) async throws {
		guard let runtime = available(preference) else { return }
		let base = URL(
			fileURLWithPath: FilePath.canonical(try JavaTestDirectory.make()), isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: base) }
		let real = base.appendingPathComponent("checkout")
		try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
		let root = base.appendingPathComponent("opened-through-here")
		try FileManager.default.createSymbolicLink(at: root, withDestinationURL: real)

		try JavaTestDirectory.write("""
		{
			"name": "Linked",
			// Relative to this file, not to the project — which is what the
			// subtraction that went wrong was for.
			"build": { "dockerfile": "Dockerfile", "context": ".." }
		}
		""", to: root.appendingPathComponent(".devcontainer/devcontainer.json"))
		try JavaTestDirectory.write("""
		FROM \(Self.image)
		RUN echo built-from-the-dockerfile > /built.txt
		""", to: root.appendingPathComponent(".devcontainer/Dockerfile"))
		try JavaTestDirectory.write(
			"the checkout is here\n", to: root.appendingPathComponent("marker.txt")
		)

		let outcome = await DevContainers.shared.session(for: root, using: runtime)
		guard case let .running(session)? = outcome else {
			Issue.record("the devcontainer did not start: \(String(describing: outcome))")
			return
		}

		// The image is the one the Dockerfile built, not the base it came from.
		let built = RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: ["cat", "/built.txt"]), deadline: 30
		)
		#expect(built.output.contains("built-from-the-dockerfile"))
		// And the checkout is mounted by its real name, which is what the
		// runtime knows the directory as.
		let contents = RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: ["cat", "marker.txt"]), deadline: 30
		)
		#expect(contents.output.contains("the checkout is here"))

		await DevContainers.shared.stop(project: root)
		#expect(isGone(session.name, using: runtime), "the container was not removed")
		// The image was made by this test, so this test takes it away again.
		_ = RuntimeCommand.run(
			(runtime.path, ["rmi", "-f", session.configuration.builtImageName]), deadline: 60
		)
	}

	/// A shell in the container, on a real pty, typed at and read back.
	///
	/// The moment this becomes useful to somebody: not "a command ran inside the
	/// container" but "there is a prompt in there and it answers".
	private func aTerminalInIt(_ session: DevContainers.Session) async {
		let command = DevContainers.terminalCommand(session)
		let terminal = PseudoTerminal()
		let seen = Collected()
		terminal.onOutput = { seen.append($0) }
		guard terminal.start(
			executable: command.executable, arguments: command.arguments, rows: 24, columns: 80
		) else {
			Issue.record("no pty for the terminal in the container")
			return
		}
		defer { terminal.terminate() }

		// A shell has to have got as far as reading its input before anything
		// typed at it means anything — and this used to type once, immediately,
		// and wait. On a machine running the rest of this suite beside it, the
		// exec had not reached a shell yet and the line went nowhere; the test
		// then failed saying the container had no checkout in it, which was never
		// true. So it is typed again every few seconds until the answer comes
		// back, which costs nothing when the first one lands.
		//
		// The answer is looked for as `IN:/`, not as `IN:`, because a pty echoes
		// what was typed: the command itself contains `IN:` and would otherwise
		// satisfy the test with its own input.
		//
		// Two agents fixed this race on the same day, one waiting ninety seconds
		// and retyping every three, the other thirty and twice a second. This is
		// the patient one: under the load that caused the race, half a second
		// between attempts fills the shell's input with commands it has not read
		// yet, and thirty seconds is not long enough to be sure.
		let ask = "printf 'IN:%s:%s\\n' \"$(pwd)\" \"$(cat marker.txt)\"\n"
		let deadline = Date().addingTimeInterval(90)
		var lastAsked = Date.distantPast
		while Date() < deadline, !seen.text.contains("IN:/") {
			if Date().timeIntervalSince(lastAsked) > 3 {
				terminal.write(ask)
				lastAsked = Date()
			}
			try? await Task.sleep(nanoseconds: 200_000_000)
		}
		// The prompt is in the workspace folder, and the checkout is under it.
		#expect(seen.text.contains("IN:\(session.configuration.workspaceFolder):"))
		#expect(seen.text.contains("the checkout is here"))
		terminal.write("exit\n")
	}

	/// Whether the runtime has no container by this name any more.
	///
	/// Polled, because removal is asked for in the background: what is being
	/// checked is that it happens, not that it has happened by the next line.
	private func isGone(_ name: String, using runtime: ContainerRuntime) -> Bool {
		guard let listing = ToolContainers.listing(using: runtime) else { return false }
		let deadline = Date().addingTimeInterval(20)
		while Date() < deadline {
			let listed = RuntimeCommand.run(listing, deadline: 15)
			if listed.succeeded, !listed.output.contains(name) { return true }
			Thread.sleep(forTimeInterval: 0.5)
		}
		return false
	}

	/// The bytes a pty produced, from whichever thread they arrived on.
	private final class Collected: @unchecked Sendable {
		private let lock = NSLock()
		private var data = Data()

		func append(_ bytes: Data) {
			lock.lock()
			data.append(bytes)
			lock.unlock()
		}

		var text: String {
			lock.lock()
			defer { lock.unlock() }
			return String(decoding: data, as: UTF8.self)
		}
	}
}
