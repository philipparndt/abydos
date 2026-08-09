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
/// Skipped unless docker is here with the image already on it, the way the
/// other live tests are skipped without their server. To run it:
///
///     docker pull alpine:3
///
/// Docker only, per 0406 and 0422: a container kept for a whole editing session
/// is the one that most needs removing again, and that is the verb which could
/// not be proven against Apple's runtime.
struct DevContainerLiveTests {
	/// Small, present on most machines that have docker at all, and pinned to a
	/// major so this does not silently start testing a different distribution.
	static let image = "alpine:3"

	/// Docker, if it is here and already holds the image.
	private var available: ContainerRuntime? {
		guard let runtime = ContainerRuntime.discover(preference: .docker),
		      holdsImage(runtime)
		else { return nil }
		return runtime
	}

	private func holdsImage(_ runtime: ContainerRuntime) -> Bool {
		RuntimeCommand.run(
			ContainerImages.inspect(Self.image, using: runtime), deadline: 10
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

	@Test func opensAProjectInItsDevcontainerAndGivesSomebodyAShellInIt() async throws {
		guard let runtime = available else { return }
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
		#expect(running.output.contains("true"))

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
		// typed at it means anything.
		terminal.write("printf 'IN:%s:%s\\n' \"$(pwd)\" \"$(cat marker.txt)\"\n")
		let deadline = Date().addingTimeInterval(30)
		while Date() < deadline, !seen.text.contains("IN:") {
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
		let deadline = Date().addingTimeInterval(20)
		let listing = (runtime.path, ["ps", "-a", "--format", "{{.Names}}", "--filter", "name=\(name)"])
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
