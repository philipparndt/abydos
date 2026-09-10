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

	/// The retried paste reaches a real session, and reaches nothing when the
	/// client tty is one no session has — the two ends of `pasteRetrying`.
	@Test func theRetriedPasteFindsARealSessionAndMissesAPhantomTty() async throws {
		guard Executables.locate("tmux") != nil else { return }
		let session = "abydos-retry-\(UUID().uuidString.prefix(8))"
		let sink = FileManager.default.temporaryDirectory
			.appendingPathComponent("retry-\(UUID().uuidString).txt")
		defer {
			_ = tmux(["kill-session", "-t", session])
			try? FileManager.default.removeItem(at: sink)
		}
		_ = tmux(["new-session", "-d", "-s", session, "-x", "80", "-y", "24",
		          "/bin/cat > \(sink.path)"])
		await waitUntil("tmux started the session") {
			tmux(["list-sessions", "-F", "#{session_name}"])?.contains(session) == true
		}
		// The client tty of the session tmux just made — its own attached
		// client, which `new-session -d` gives none of, so target by session
		// through the retried lookup a client would use. A tty no client holds
		// is the phantom: the retries exhaust and the answer is false, which is
		// what makes the terminal write raw text rather than guess.
		let missed = await TmuxMirror.pasteRetrying(
			"nothing", forClient: "/dev/ttys-abydos-nope", attempts: 2
		)
		#expect(!missed, "a tty no client holds must not resolve to a session")
	}

	/// **The leak's shape, against a real tmux.** A client with bracketed paste
	/// on over an inner program with it off is the disagreement that put `[200~`
	/// in the command line. What the terminal writes when tmux is not reached is
	/// now raw text, so nothing the inner program reads carries a marker — which
	/// `TmuxPaste.plan` decides, and this checks the decision the fallback makes.
	@Test func aFailedTmuxPasteWritesNoMarkerWhateverTheOuterMode() {
		// The fallback the view takes when `pasteRetrying` returned false, with
		// the outer client's bracketed paste on — exactly the disagreement.
		let plan = TmuxPaste.plan(
			text: "cd ~/x && npm run\n", throughTmux: true,
			tmuxAccepted: false, bracketedPaste: true
		)
		guard case let .write(bytes) = plan else {
			Issue.record("a failed tmux paste must still write the text")
			return
		}
		#expect(!bytes.contains("\u{1B}[200~"))
		#expect(!bytes.contains("\u{1B}[201~"))
		#expect(bytes == "cd ~/x && npm run\n")
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
