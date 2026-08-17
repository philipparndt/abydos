import Foundation
import Testing
@testable import AbydosKit

/// Handing a paste to tmux instead of typing it at tmux.
///
/// Runs a real tmux, deliberately: what is being checked is that tmux accepts
/// the text and puts it where the pane can read it, and a fake on this side
/// would only be checking that the arguments spell what I think they spell.
struct TmuxPasteTests {
	private func tmux(_ arguments: [String]) -> String? {
		guard let path = Executables.locate("tmux") else { return nil }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: path)
		process.arguments = arguments
		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		process.standardInput = Pipe()
		guard (try? process.run()) != nil else { return nil }
		return ProcessPipes.drainText(process, out: out, err: err).stdout
	}

	@Test func tmuxTakesThePasteAndThePaneReadsIt() async throws {
		guard Executables.locate("tmux") != nil else { return }

		let session = "abydos-paste-test-\(UUID().uuidString.prefix(8))"
		let sink = FileManager.default.temporaryDirectory
			.appendingPathComponent("paste-\(UUID().uuidString).txt")
		defer {
			_ = tmux(["kill-session", "-t", session])
			try? FileManager.default.removeItem(at: sink)
		}

		// A pane that writes whatever it is given to a file.
		_ = tmux(["new-session", "-d", "-s", session, "-x", "80", "-y", "24",
		          "/bin/cat > \(sink.path)"])
		// Waited for rather than slept through: tmux answers `has-session` the
		// moment the server is up, and 700 ms was a guess at how long that takes
		// on a machine that is not busy.
		await waitUntil("tmux started the session") {
			// `list-sessions` and not `has-session`: this helper hands back
			// stdout without looking at the exit status, so a "no such session"
			// would come back as an empty string rather than as nil and the
			// wait would return before tmux had done anything.
			tmux(["list-sessions", "-F", "#{session_name}"])?.contains(session) == true
		}

		let sent = "hello from the buffer\n"
		let accepted = await TmuxMirror.paste(sent, intoSession: session)
		#expect(accepted, "tmux refused the paste")

		// And the pane writing it to the file is a thing that can be looked for.
		await waitUntil("the pane wrote what it was pasted") {
			((try? String(contentsOf: sink, encoding: .utf8)) ?? "").contains("hello from the buffer")
		}
		let landed = (try? String(contentsOf: sink, encoding: .utf8)) ?? ""
		#expect(landed.contains("hello from the buffer"), "the pane never saw it: \(landed.debugDescription)")
		// The markers are tmux's business, and it did not hand them over as text.
		#expect(!landed.contains("\u{1B}[200~"))
		#expect(!landed.contains("[200~"))
	}

	/// A session that is not there is a no, not a crash or a hang.
	@Test func anAbsentSessionIsRefusedQuickly() async {
		guard Executables.locate("tmux") != nil else { return }
		let accepted = await TmuxMirror.paste("x", intoSession: "abydos-no-such-session-\(UUID())")
		#expect(!accepted)
	}

	@Test func emptyTextIsNotWorthAskingAbout() async {
		#expect(!(await TmuxMirror.paste("", intoSession: "anything")))
	}
}
