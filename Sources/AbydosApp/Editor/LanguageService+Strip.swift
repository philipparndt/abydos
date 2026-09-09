import AppKit
import AbydosKit

/// What the strip above the editor says, and what the footer beside the caret
/// says: the two places a server's state is reported to somebody who did not
/// ask about servers at all.
extension LanguageService {
	// MARK: - What the strip above the editor should say

	/// What is worth saying above a file, if anything.
	///
	/// This replaces `LanguageServers.suggestion` at the call site, and the
	/// difference is the whole of 0432's second fault. That asks the file
	/// system a question with two answers — the server is on this machine or it
	/// is not — and a devcontainer has a third: it is coming, and it will be
	/// here in anything from a second to a cold `docker build`. Asked of the
	/// file system, that third state reads as the second for ever, which is a
	/// strip saying "install pyright" over a file the container's pyright is
	/// answering about. Asked here, it is a state that ends.
	struct ServerNotice: Equatable {
		let languageId: String
		let languageName: String
		/// The sentence in the strip.
		let text: String
		/// What "How to install" opens, or nil when there is nothing on this
		/// machine to install — a server on its way, or one that belongs in a
		/// container whose copy here would not be used instead.
		let manual: String?
		/// Whether "Ignore for X" is offered. Never while something is on its
		/// way: the answer to "not yet" is to wait, and a language switched off
		/// for ever because a container was slow is the wrong bargain.
		let isIgnorable: Bool
		/// Whether this is something being reported rather than something being
		/// offered. It decides the glyph, and the glyph is what the strip is
		/// read by from across the room: a lightbulb is an idea somebody could
		/// act on, and "your server is not answering for this project" is not
		/// one of those.
		var problem: Bool = false
		/// What the button in front of `manual` says.
		///
		/// Almost always "How to install", which is what all of these were until
		/// two of them were not about installing anything: a project pinning a
		/// toolchain nothing here can supply has no installation to offer, and a
		/// server that is installed, started and complaining has nothing left to
		/// install either. A button saying there is one is the wrong advice
		/// printed in the place somebody looks for the right one.
		var detailsTitle: String = "How to install"
		/// A button offering the one thing that would change this, if there is
		/// one — see `Offer`. Most notices have none.
		var offer: Offer? = nil

		/// The way out of a state somebody chose, offered where they are looking
		/// at the consequence of having chosen it.
		///
		/// A named case rather than a bare button title, so that what the click
		/// agreed to is a value rather than a string match on the words in a
		/// button. There is one of them today.
		enum Offer: Equatable {
			/// Start this project's devcontainer after all, and keep the answer.
			/// Offered to a project whose servers were declined, in either of the
			/// two ways of declining — otherwise "not now" would be a decision
			/// nothing on screen could reverse until the project was reopened.
			case useDevContainer(container: String)

			/// What the button says.
			var title: String {
				switch self {
				case let .useDevContainer(container):
					return DevContainerConsent.offerTitle(container: container)
				}
			}
		}
	}

	/// What to say about a project whose selected launch wants a Java debugger
	/// that is not here, or nil when there is nothing to say.
	///
	/// **Asked when a launch is chosen rather than when Debug is pressed**, which
	/// is what `JavaDebugHost.refusal` was written for and has always said in its
	/// own documentation: every one of these answers is a `PATH` lookup or a jar
	/// on disk, knowable in milliseconds, and finding out afterwards is the same
	/// information delivered as an insult. Pressing Debug on a project with no
	/// jdtls used to start a JVM, suspend it on a port, and only then admit that
	/// nothing was ever going to attach to it.
	///
	/// `.nothingHostsIt` is deliberately not reported. It means the project shows
	/// none of the server's markers — no pom, no Gradle build — and a strip
	/// saying Java cannot be debugged here belongs to a Java project, not to
	/// every project with a launch configuration in it.
	///
	/// Ignorable, and a problem rather than an idea: it is a statement about what
	/// this project cannot do, and somebody who never debugs Java should be able
	/// to put it away for good.
	func javaDebugNotice(project: URL) -> ServerNotice? {
		guard let refusal = JavaDebugHost.refusal(
			project: project,
			inDevContainer: devContainerNameHoldingServers(for: project)
		) else { return nil }
		guard refusal != .nothingHostsIt else { return nil }

		// No manual, and nothing lost by it: every one of these `Failure` cases
		// already carries its own remedy in its sentence — `.notInstalled` has
		// the server's install hint spliced into it, and java-debug is not a
		// program any package manager carries, so a "How to install" button would
		// promise a page that says less than the strip already does.
		return ServerNotice(
			languageId: "java",
			languageName: LanguageRegistry.shared.displayName(for: "java"),
			text: refusal.errorDescription ?? "Java cannot be debugged in this project.",
			manual: nil,
			isIgnorable: true,
			problem: true
		)
	}

	/// What to say about a language in a project, or nil for nothing.
	///
	/// Nil is the common answer and the important one: a server that is
	/// answering has nothing to say about itself, and that is what withdraws
	/// the strip when a container's server lands two minutes after the file was
	/// opened.
	func notice(
		forLanguage languageId: String,
		project: URL,
		ignoring: Set<String> = []
	) -> ServerNotice? {
		guard !ignoring.contains(languageId) else { return nil }
		let key = key(project: project, languageId: languageId)

		let definition: LanguageServerDefinition
		switch selection(for: languageId, project: project) {
		case let .server(chosen, _):
			definition = chosen
		case let .noSuchServer(name, source):
			// **The whole point of the item this came from.** Somebody asked for
			// one server and would otherwise be looking at a file with no
			// diagnostics, with nothing on screen saying that what they asked for
			// is not here. Not ignorable: "ignore Java for this session" would
			// bury a sentence about a file they wrote and can fix, and the strip
			// goes as soon as they fix it.
			//
			// No marker check in front of it either. The markers belong to a
			// definition and there is no definition — and a person looking at a
			// Java file is looking at the language they named, whatever the
			// project's build files happen to be.
			return ServerNotice(
				languageId: languageId,
				languageName: LanguageRegistry.shared.displayName(for: languageId),
				text: "\(name) was asked for and is not here, so this file has no language server.",
				manual: LanguageServers.refusal(named: name, forLanguage: languageId, source: source),
				isIgnorable: false
			)
		case .nothing:
			return nil
		}

		// Not a project this server understands — a stray `.py` in a Go
		// repository — so neither the offer nor the wait is about anything.
		//
		// Asked before the running-server return below rather than after it,
		// which is where it used to be: the devcontainer sentence underneath is
		// the one case where a *running* server has something to say about
		// itself, and a return in front of it would hide that. The two orders
		// agree everywhere else, because a server that is running is one that
		// suited the project when it was started.
		guard LanguageServers.suits(definition, root: project) else { return nil }

		let name = LanguageRegistry.shared.displayName(for: languageId)

		// A project that has a devcontainer and is deliberately not being worked
		// on inside it. **The one sentence a running server has to say about
		// itself**, and 0433 is why: a Python file with no squiggles at all and
		// one being checked by a server that is not the project's are the same
		// picture, and telling them apart is the whole of what "no" had to leave
		// behind. It says which of the two declines is in force and offers the
		// way back, since neither is written anywhere else on screen — the pill
		// says *running*, and there is no container running to put one beside.
		if let declined = declinedNotice(languageId: languageId, name: name, project: project, key: key) {
			return declined
		}

		// **An executable somebody named, with nothing at that path.** Ahead of
		// the pin below it, which is the only thing ahead of everything else, and
		// the order is the argument: a pin is a fact about the project that several
		// routes might yet answer, and this is a line in a file that is wrong.
		// Whoever wrote the path is the person looking at the strip and can fix it
		// in one edit, so it is the first thing said.
		//
		// Said rather than falling through to the install hint at the bottom of
		// this function, which would be false twice: something *was* named, and
		// "rustup component add rust-analyzer" is the advice that produces the proxy
		// a named path exists to get away from. 0466.
		if let named = overrides(for: project).override(forTool: definition.name),
		   let command = named.command,
		   LanguageServers.executable(for: definition.running(command)) == nil,
		   // Not in a container. The path is the container's there, and this side
		   // has no way to look at it — a path that is absent here is the ordinary
		   // case rather than the fault, and the server failing to start says so
		   // through `ServerHealth` instead.
		   images(for: project).image(for: definition.name) == nil,
		   !usesDevContainer(project) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: "\(definition.name) was pointed at \(command), and there is nothing to "
					+ "run there, so this file has no language server.",
				manual: LanguageServerOverrides.refusal(
					command: command, forTool: definition.name, source: named.source
				),
				// Nothing to ignore: it is one line in a file, and the strip goes the
				// moment the line is right.
				isIgnorable: false,
				problem: true,
				detailsTitle: "What was named"
			)
		}

		// **A toolchain this project pins that the server cannot have.** Said
		// ahead of every state below it, including the running one, because it is
		// the one thing here that is true whatever the server is doing: it starts,
		// it answers the handshake, and it then refuses every question about every
		// file. Sentences about fetching an image or installing a copy are all
		// beside a project that none of them would read, so this goes first and
		// they are named inside its own details instead.
		if let objection = toolchainObjection(for: definition, project: project) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: objection.sentence,
				manual: objection.detail,
				// Nothing to ignore. "Ignore Rust for ever" would bury a sentence
				// about a file in this project that says exactly what is wrong with
				// it, and the strip goes by itself the moment the pin or the choice
				// of where the server comes from changes.
				isIgnorable: false,
				// Not "How to install": the answer here is not an installation and
				// offering one would be the wrong advice printed on the button.
				detailsTitle: "What can read it"
			)
		}

		// **The third state, and the whole of 0461.** A server that started and
		// then could not make sense of the project is in none of the states
		// below: it is not missing, it is not on its way, and the line under
		// this one used to return nil for it because a client that is running
		// looked like a client that is answering. What the server said about
		// itself is the evidence, and `ServerHealth` is the rule for reading it.
		//
		// In front of the running-server return rather than behind it, for the
		// same reason the devcontainer sentence above is: these are the sentences
		// a *running* server has to say about itself, and a return before them
		// hides exactly the case they exist for.
		//
		// *Behind* the pinned toolchain, though, and the two came from the same
		// project: 0462 knows the cause and can say what would read it, while
		// this only knows the server complained and can quote it. Where both
		// would fire, the one that names the reason is the better sentence.
		if let health = health[key], let text = health.sentence(for: definition.command) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: text,
				// Its own words, which are nearly always better than anything
				// this app could write: "custom toolchain 'esp' specified in
				// override file '/workspace/esp32/rust-toolchain.toml' is not
				// installed" names the toolchain, the file and the fault.
				manual: health.said.map { "\($0)\n\n\(Self.logPath) has the rest." },
				// Never. "Ignore Rust" is about the language on this machine and
				// this is about one project's toolchain; and the strip goes by
				// itself when the server starts answering.
				isIgnorable: false,
				problem: true,
				// Not "How to install": there is nothing missing to install, and
				// what somebody wants here is the sentence the server wrote.
				detailsTitle: "What it said"
			)
		}

		// Answering, or at least running and about to. Nothing to say.
		if let server = servers[key], server.client.isRunning { return nil }

		// On its way. Either the project's devcontainer is coming up with the
		// server inside it, or an image named for the server is being fetched;
		// both are minutes the first time and instant afterwards.
		//
		// **What it says and does not say.** One sentence, no progress, no
		// percentage — the steps are already on screen as toasts from
		// `DevContainers.Progress`, and a terminal opened in the same container
		// joins this very start and shows the whole of it (`PreparingTerminal`).
		// A second progress report would be two things counting the same pull.
		// The strip's job here is only to say why nothing is answering yet, and
		// then to stop saying it.
		if let arriving = arriving(key: key, project: project) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				// Three sentences and not two. "Being fetched" was said of a build
				// as well, and somebody told their server is being downloaded while
				// a compiler runs for three minutes concludes their network is
				// broken — the same conflation `ToolImageRecipes.progressMessage`
				// has its own sentence to avoid. 0459.
				//
				// Written once, in `LanguageServerFooter`, because the chip beside
				// the caret says the same three things in its tool tip and 0463
				// asked that the two agree rather than each invent a vocabulary.
				text: LanguageServerFooter.arrivalSentence(languageName: name, state: arriving),
				manual: nil,
				isIgnorable: false
			)
		}

		// A project worked on in a container whose container does not carry the
		// server. Installing it here would change nothing — the copy on this
		// machine is deliberately not used — so the sentence is the one about
		// the file that would have to carry it.
		if usesDevContainer(project), let hint = missingHints[key] {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: "\(name) has no language server in this project's devcontainer.",
				manual: hint,
				isIgnorable: true
			)
		}

		// `suited:`, because the guard near the top of this function already
		// asked whether the project suits this server and the answer cannot have
		// changed since. The version that takes a root asked again, which was a
		// second depth-2 walk of the project for one file being opened.
		guard let suggestion = LanguageServers.suggestion(
			suited: definition, forLanguage: languageId, ignoring: ignoring
		) else { return nil }
		return ServerNotice(
			languageId: suggestion.languageId,
			languageName: suggestion.languageName,
			text: "\(suggestion.languageName) has no language server. Install \(suggestion.command) "
				+ "for completion, problems and go-to-declaration.",
			manual: suggestion.manual,
			isIgnorable: true
		)
	}

	/// Which of the three waits a server is in, or nil when it is not waiting.
	///
	/// One table lookup and two set lookups; nothing here touches the disk.
	/// `fetching` is the whole of "on its way" and the other two only say which
	/// kind of way it is, which is why they are read inside it — `buildingHere`
	/// is only meaningful while `fetching` holds the same key, and says nothing
	/// to anybody otherwise.
	private func arriving(key: String, project: URL) -> LanguageServerFooter.State? {
		guard fetching.contains(key) else { return nil }
		if devcontainerProjects[project.standardizedFileURL.path] == true { return .starting }
		return buildingHere.contains(key) ? .building : .fetching
	}

	// MARK: - What the footer beside the caret should say

	/// The server answering for a file, for the chip beside the caret's
	/// position, or nil for nothing.
	///
	/// **Nothing here asks the file system anything, and that is the constraint
	/// rather than a nicety.** The answer is pushed into a view that redraws on
	/// every caret move, so this must stay a handful of lookups: the project's
	/// choices, which are cached; the table of running servers; the two sets that
	/// say what is on its way. In particular there is no `LanguageServers.suits`,
	/// which walks the project two levels deep, and no `executable`, which walks
	/// the `PATH` — both of which `notice` above can afford because the strip is
	/// refreshed when a file is opened and this is read beside every keystroke.
	///
	/// **Nil is the common answer and the deliberate one.** A file whose language
	/// has no server running and none coming says nothing at all: most files in
	/// most projects are in that state, and a footer that nags about every one of
	/// them is a footer people stop reading. What there is to say about a missing
	/// server is the strip above the file, which has room for the sentence, the
	/// install hint and a way to switch it off for good.
	///
	/// **Which server, when a file's language has several.** The question does
	/// not arise, and `LanguageServers.serverKey` is why: a running server is
	/// filed under the *server's* name rather than the language's, so a `.c` and
	/// a `.cpp` in one project both find the one `clangd` entry and the chip says
	/// `clangd` under either. The footer follows the file, the file names its
	/// language, and the key turns that into the one server that answers for it.
	func footer(forLanguage languageId: String, project: URL) -> LanguageServerFooter? {
		let key = key(project: project, languageId: languageId)
		let languageName = LanguageRegistry.shared.displayName(for: languageId)

		if let server = servers[key], server.client.isRunning {
			return LanguageServerFooter(
				command: server.definition.command,
				languageName: languageName,
				origin: server.origin,
				// Running is not the same as ready, which is what this used to
				// say. A Swift package whose dependencies are not built answers
				// `No such module` for the minute it spends building them, and
				// the chip said `sourcekit-lsp` throughout — the same word it
				// says when every answer is right. 0501.
				state: preparing.contains(key) ? .preparing : .answering
			)
		}

		guard let arriving = arriving(key: key, project: project),
		      let definition = LanguageServers.definition(
		      	forLanguage: languageId, choosing: choices(for: project)
		      )
		else { return nil }
		// Where it will come from, said now rather than when it lands: a server
		// being fetched has no launch yet, and the two states the wait can be in
		// are exactly the two the name of the image tells apart.
		let origin: LanguageServerFooter.Origin = arriving == .starting
			? .devcontainer(name: nil)
			: .image(images(for: project).image(for: definition.name) ?? "")
		return LanguageServerFooter(
			command: definition.command,
			languageName: languageName,
			origin: origin,
			state: arriving
		)
	}

	/// How a file is named when talking to a language server.
	///
	/// The real path, always: a server resolves a module or a package by
	/// realpath, and a workspace given as `/tmp/x` then does not contain the
	/// module it just found at `/private/tmp/x` — gopls says as much and
	/// answers nothing about any symbol in it.
	func canonical(_ url: URL) -> URL {
		URL(fileURLWithPath: FilePath.canonical(url), isDirectory: true)
	}

	func uri(for url: URL) -> String {
		URL(fileURLWithPath: FilePath.canonical(url)).absoluteString
	}
}
