import Foundation

/// What is known about a language server *after* it has been started.
///
/// Everything else in this program that knows anything about a server's health
/// knows it about starting one: it is installed or it is not, the image is here
/// or it is being fetched, the handshake was answered or it was not. A server
/// that starts, answers the handshake, and then cannot make sense of what it was
/// pointed at is in none of those states, and until 0461 the app had no word for
/// it — `notice(forLanguage:project:)` returned nil the moment the client was
/// running, so the strip went away and nothing on screen disagreed. The first
/// anybody heard was an outline that came back empty.
///
/// It is not one server's problem. jdtls with a classpath it could not resolve,
/// gopls outside a module, clangd with no `compile_commands.json` and
/// rust-analyzer against a toolchain that is not installed all start, all answer
/// the handshake, and all then know nothing. So this is about the state rather
/// than about any of them: what the server said, and whether it has since failed
/// to answer.
///
/// **Why there are two states between working and gone.** The question the item
/// leaves open is whether a message is enough to call a server broken, given
/// that servers log errors which are not fatal. Measured on this machine, with
/// the `rust-analyzer` image this repository builds: against a project whose
/// `Cargo.toml` names a crate that does not exist, the server says "Failed to
/// read Cargo metadata" and "cargo check failed to start" — and then answers
/// `textDocument/documentSymbol` and `workspace/symbol` exactly as it does for a
/// project that loads, because it indexes the crate from source and only the
/// dependencies are missing. A rule that asked a question and read an empty
/// answer as proof would have called that server broken; a rule that trusted the
/// message alone would have called it broken too, and both would have been
/// saying more than anybody knows.
///
/// So the two are kept apart. **Said so** is the server's own words, shown as a
/// report — it is running, it complained, here is what it complained about — and
/// it is withdrawn the moment the server answers anything with content in it,
/// which is what a busy server that logged something non-fatal does within
/// seconds. **Proved it** is that report plus a question it could not answer,
/// and only then does the app say the server cannot read the project.
public struct ServerHealth: Equatable, Sendable {
	public enum State: Equatable, Sendable {
		/// Nothing has been said and nothing has failed. The common answer.
		case working
		/// Running, and it has said at error level that something is wrong. A
		/// report rather than a verdict: the message may yet turn out to have
		/// been survivable, and this state goes when it does.
		case reported(said: String)
		/// It said so, and then a question came back empty or failed. The
		/// server is running and is not going to answer anything useful about
		/// this project.
		case cannotRead(said: String)
		/// Not running: it exited on the way up, or the image it comes from
		/// never arrived. It said why, and that is the whole of the evidence
		/// there is to have — nothing further can be asked of it.
		case notAnswering(said: String)
	}

	public private(set) var state: State = .working

	public init(state: State = .working) { self.state = state }

	/// What the server said, whichever way it is not working.
	public var said: String? {
		switch state {
		case .working: return nil
		case let .reported(said), let .cannotRead(said), let .notAnswering(said): return said
		}
	}

	public var isWorking: Bool { state == .working }

	/// The server said something at error level while running.
	///
	/// **The first diagnosis is kept, not the latest.** A server that cannot
	/// read a project says so once in a sentence worth reading and then says the
	/// consequences of it for ever: the log on this machine has rust-analyzer
	/// following "custom toolchain 'esp' … is not installed" with `ERROR
	/// duplicate DidOpenTextDocument: /workspace/src/main.rs`, which is true,
	/// useless, and would have replaced the one sentence somebody could act on.
	public mutating func said(_ line: String) {
		let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !line.isEmpty else { return }
		switch state {
		case .working: state = .reported(said: line)
		case .reported, .cannotRead, .notAnswering: break
		}
	}

	/// The server is not running, and this is what it left behind.
	///
	/// Overwrites whatever was known: a server that has stopped has settled the
	/// question, and the words it went out with are the ones that say why.
	public mutating func stopped(saying line: String) {
		let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
		state = .notAnswering(said: line.isEmpty ? "It stopped without saying why." : line)
	}

	/// A question was put to the server and this is how it went.
	///
	/// - Parameter withContent: whether the answer had anything in it. False is
	///   an answer that failed or came back empty, and it is only evidence at
	///   all where the server has already said something is wrong — an empty
	///   answer on its own is what a file with nothing declared in it looks
	///   like, every time.
	public mutating func answered(withContent: Bool) {
		switch state {
		case .working:
			break
		case let .reported(said):
			// Working after all, whatever it said. This is the whole of what
			// keeps a server that logs a survivable error out of the strip.
			state = withContent ? .working : .cannotRead(said: said)
		case let .cannotRead(said):
			// It can be wrong, and it stops being wrong by itself: the sentence
			// goes as soon as the server answers something. Kept because the
			// alternative is a strip that stays up over a server which started
			// working while somebody was reading it — see 0460, which is the
			// same fault about a preference nobody went back to look at.
			if withContent { state = .working } else { state = .cannotRead(said: said) }
		case .notAnswering:
			// Nothing to reconsider: the process is gone. A running server under
			// the same key is a new server and a new `ServerHealth`.
			break
		}
	}

	/// The sentence for the strip above the file, or nil when there is nothing
	/// to say.
	///
	/// - Parameter command: the server as somebody would say it — `rust-analyzer`,
	///   `jdtls`. The name is the searchable part and the part they recognise.
	///
	/// **None of the three reads as a crash**, deliberately. The server is a
	/// program that started; two of these say it is still running; and the next
	/// project it is asked about may be perfectly readable. What is wrong is the
	/// pairing of this server with this project, and the sentences say that and
	/// no more.
	public func sentence(for command: String) -> String? {
		switch state {
		case .working:
			return nil
		case .reported:
			return "\(command) is running and says something is wrong with this project."
		case .cannotRead:
			return "\(command) is running and cannot read this project, so nothing here "
				+ "will be answered."
		case .notAnswering:
			// Not "started and stopped", though that is the commonest way in:
			// an image that could not be built or fetched lands here too, and
			// that server never started at all. What both have in common is the
			// only thing worth saying — nothing is running for this project, and
			// here is what was said about it.
			return "\(command) is not running for this project."
		}
	}
}
