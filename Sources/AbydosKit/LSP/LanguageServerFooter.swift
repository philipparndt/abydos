import Foundation

/// What the editor's footer says about the server answering for the file
/// somebody is looking at.
///
/// It exists because of one afternoon. A Rust project was pointed at an image
/// built on this machine; the container started, `rust-analyzer` initialised and
/// answered, and from the outside that was indistinguishable from nothing having
/// happened — *"the rust container is selected, but I have the strong feeling
/// that it is not used at all."* It was being used. `container ls` knew,
/// `lsp.log` knew and Running Servers knew, and every one of those is somewhere
/// somebody has to go. Nothing beside the file said anything at all.
///
/// **A value in the engine rather than strings assembled where the bar is
/// drawn**, for two reasons that pull the same way. The words are the part worth
/// arguing about and the suite cannot reach a view in the app target, so this is
/// the half that can be claimed and checked. And the bar is redrawn on every
/// caret move, so what it says has to be worked out when the *server* changes
/// and then held — which is what `LanguageService.footer(forLanguage:project:)`
/// is for, called from the same places the strip above the file is refreshed
/// from and never from `draw`.
public struct LanguageServerFooter: Equatable, Sendable {
	/// Where the server came from, which is the half that was missing.
	///
	/// Installed is the answer people assume, and that is exactly why the other
	/// two have to be visible: somebody who chose an image and is being answered
	/// by the copy on their machine cannot tell, and somebody who chose an image
	/// and *is* being answered by it could not tell either, which is the
	/// afternoon above.
	public enum Origin: Equatable, Sendable {
		/// The copy on this machine, at the path the search resolved. The path is
		/// 0427's question as well — the servers were running out of swiftly's
		/// toolchain while the build used Xcode's — so it is what the tool tip
		/// says rather than the bare word "installed".
		case installed(executable: String?)
		/// An image started for this server and removed with it.
		case image(String)
		/// The project's own devcontainer, which was up before any of this and
		/// holds somebody's terminal. The name is for the tool tip only; see
		/// `text(containerMark:)` for why the chip does not repeat it.
		case devcontainer(name: String?)
	}

	/// What the server is doing.
	///
	/// Three of the four states 0463 names. The fourth — started, answered the
	/// handshake, and cannot read the project — is 0461's to *detect*, and this
	/// deliberately has no case for it yet: a case here with nothing setting it
	/// would be a design 0461 then has to fight. When it lands it is one more
	/// case and one more sentence, and the push already built for these three
	/// carries it.
	public enum State: Equatable, Sendable {
		case answering
		/// An image on its way down the wire.
		case fetching
		/// An image being built on this machine, which 0459 measured at 164
		/// seconds the first time and nothing at all afterwards.
		case building
		/// The project's devcontainer coming up with the server inside it.
		case starting
	}

	/// The server's own name — `rust-analyzer`, not the path it was found at,
	/// which is the tool tip's business.
	public let command: String
	/// The language of the file the footer is under, for the sentence.
	public let languageName: String
	public let origin: Origin
	public let state: State

	public init(command: String, languageName: String, origin: Origin, state: State) {
		self.command = command
		self.languageName = languageName
		self.origin = origin
		self.state = state
	}

	/// What the chip says, which has to fit in a corner of a bar the file is
	/// using the rest of.
	///
	/// **The name first, always, and everything else after it**, because the
	/// chip is what truncates when the editor is narrow — the answer 0458
	/// reached for a card whose title would not fit. `rust-analyzer` is what
	/// somebody is looking for and the image behind it is what they can afford
	/// to lose to an ellipsis.
	///
	/// **A running server in a devcontainer wears the mark and no name.** The
	/// titlebar's pill already says this window is working inside a container
	/// and names it, and a container is a fact about the *window* rather than
	/// about this file — repeated on every file it would be the same word over
	/// and over, which is how a footer stops being read. An image is the other
	/// way round: it is chosen per tool, it is written nowhere else on screen,
	/// and which image is the whole question somebody has when they wonder
	/// whether their choice took.
	///
	/// - Parameter containerMark: the `⬢` the titlebar pill and the terminal tab
	///   in a container already wear. Passed in rather than written here because
	///   the app is what owns that glyph — `MainWindowController.containerMark`
	///   — and three things wearing the same mark by copying it is the sort of
	///   agreement that stops being true.
	public func text(containerMark: String) -> String {
		switch state {
		case .answering:
			switch origin {
			case .installed: return command
			case let .image(image): return "\(command) \(containerMark) \(image)"
			case .devcontainer: return "\(command) \(containerMark)"
			}
		// One word each, and the same three distinctions the strip draws in a
		// sentence: a fetch is the network, a build is this machine's compiler
		// for a couple of minutes, and a start is the project's container coming
		// up. Somebody told their server is being downloaded while a compiler
		// runs for three minutes concludes their network is broken — 0459.
		case .fetching: return "\(command) — fetching"
		case .building: return "\(command) — building"
		case .starting: return "\(command) — starting"
		}
	}

	/// The whole of it, for the tool tip, in sentences.
	///
	/// The last line says where the click goes, because a chip that is a control
	/// and does not say so is a chip nobody presses.
	public var detail: String {
		switch state {
		case .answering:
			return answering + "\n\nClick for everything this app is running."
		case .fetching, .building, .starting:
			return Self.arrivalSentence(languageName: languageName, state: state)
				+ "\n\nClick for everything this app is running."
		}
	}

	private var answering: String {
		switch origin {
		case let .installed(executable):
			return "\(command) is answering for \(languageName) in this project, from "
				+ (executable ?? "the copy installed on this machine") + "."
		case let .image(image):
			return "\(command) is answering for \(languageName) in this project, "
				+ "from the image \(image)."
		case let .devcontainer(name):
			return "\(command) is answering for \(languageName) in this project, inside "
				+ (name.map { "its devcontainer, \($0)" } ?? "its devcontainer") + "."
		}
	}

	/// What is said while a server is on its way.
	///
	/// **Said in one place and read in two.** The strip above the file says this
	/// and so does the chip's tool tip, and the item that built the chip asked
	/// for exactly that: whatever words the footer chooses should agree with the
	/// strip rather than invent a second vocabulary for the same three waits.
	/// Two copies of a sentence agreeing by eye is how they come to disagree.
	///
	/// `.answering` has nothing to arrive and returns an empty string; callers
	/// that can be handed one — the strip cannot — have their own sentence.
	public static func arrivalSentence(languageName: String, state: State) -> String {
		switch state {
		case .answering: return ""
		case .fetching: return "\(languageName)'s language server is being fetched."
		case .building:
			return "\(languageName)'s language server is being built on this machine. "
				+ "It happens once, and the terminal panel shows it happening."
		case .starting:
			return "\(languageName)'s language server is starting in this project's devcontainer."
		}
	}
}

public extension LanguageServerLaunch {
	/// Where this server came from, said as the footer says it.
	///
	/// Worked out once, when the server starts, and carried on the entry in
	/// `LanguageService` — not asked again when somebody wants to know. The
	/// footer is pushed to a view that redraws on every caret move, and 0443
	/// built a card's struct for the same reason: the state a view draws has to
	/// be a value it already holds.
	var origin: LanguageServerFooter.Origin {
		switch self {
		case let .installed(executable, _): return .installed(executable: executable)
		case let .image(container, _, _): return .image(container.image)
		case let .devcontainer(session, _, _, _): return .devcontainer(name: session.name)
		}
	}
}
