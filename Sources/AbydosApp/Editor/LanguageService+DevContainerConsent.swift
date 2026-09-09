import AppKit
import AbydosKit

/// Whether a project's servers run in its devcontainer, which is somebody's
/// decision and not this app's.
///
/// Nothing is started in a container without being asked, the answer is
/// remembered per project, and a question that is no longer about anything is
/// withdrawn rather than left on screen.
extension LanguageService {
	// MARK: - Servers inside the project's devcontainer

	/// What the strip says about a project whose devcontainer was declined, or
	/// nil when it was not.
	///
	/// The two declines are shown at different moments, and deliberately so.
	/// **"Not now"** is shown always, because nothing is running anywhere and an
	/// editor that is silent about a file has to say why it is silent.
	/// **"Work on this machine"** is shown only once a server here is actually
	/// answering: before that the ordinary sentence — install `pyright` — is the
	/// useful one, and replacing it with a note about a container somebody has
	/// already turned down would be the app arguing with them.
	func declinedNotice(
		languageId: String, name: String, project: URL, key: String
	) -> ServerNotice? {
		guard let consent = consent(for: project), consent != .container else { return nil }
		guard hasDevContainerFile(project) else { return nil }
		if consent == .thisMachine, servers[key]?.client.isRunning != true { return nil }
		// The one this project would use, not the one that sorts first: with
		// several, "its language server is in X, which has not been started" has
		// to name the container the button beside it would start.
		guard let container = containerChoice(for: project)?.name,
		      let text = DevContainerConsent.notice(
		      	language: name, container: container, consent: consent
		      )
		else { return nil }
		return ServerNotice(
			languageId: languageId,
			languageName: name,
			text: text,
			// Nothing to install: what is missing here is a decision, not a
			// binary, and the button beside it is the decision.
			manual: nil,
			// Never. "Ignore for Python" is about the language everywhere on the
			// machine, and this is about one project's toolchain — switching the
			// language off to be rid of a sentence about a container is a bargain
			// nobody would knowingly make.
			isIgnorable: false,
			offer: .useDevContainer(container: container)
		)
	}

	/// Whether this project has a `devcontainer.json` on disk, read once.
	private func hasDevContainerFile(_ project: URL) -> Bool {
		let path = project.standardizedFileURL.path
		if let known = devcontainerFiles[path] { return known }
		let exists = DevContainerFile.exists(in: project)
		devcontainerFiles[path] = exists
		return exists
	}

	/// What was said about this project, from this session or from the
	/// preferences it was written to, or nil when nobody has been asked.
	///
	/// **A yes that names a container the project no longer offers is not an
	/// answer**, and this is where it stops being one. `devcontainer.json` is
	/// committed, so the set of containers a project offers is somebody else's to
	/// change between one session and the next; a stored "use `.devcontainer/go`"
	/// against a checkout that now has `.devcontainer/tools` is about a container
	/// nobody can start. Degrading it to nil puts the question back rather than
	/// failing, and rather than quietly starting whichever one sorts first —
	/// which would be choosing a toolchain for somebody who had chosen a
	/// different one. 0444.
	private func consent(for project: URL) -> DevContainerConsent? {
		let path = project.standardizedFileURL.path
		if let held = devcontainerConsent[path] { return held }
		guard !staleDevcontainerChoices.contains(path) else { return nil }
		guard let stored = Settings.shared.devContainerConsent(forProject: project) else { return nil }
		if stored == .container,
		   let named = Settings.shared.devContainerChoice(forProject: project),
		   DevContainerFile.choice(identified: named, in: project) == nil {
			staleDevcontainerChoices.insert(path)
			log("\(project.lastPathComponent) was to be worked on in \(named), which it no longer "
				+ "offers; it will be asked again")
			return nil
		}
		devcontainerConsent[path] = stored
		return stored
	}

	/// Keeps an answer, in the two places it belongs: for this session always,
	/// and in the preferences when it is one of the two that are about the
	/// project rather than about this afternoon.
	///
	/// The container is written down beside it when the answer names one. It is
	/// left alone otherwise — see `Settings.setDevContainerChoice` for why a
	/// decline does not forget which container this project's is.
	private func remember(
		_ consent: DevContainerConsent, choice: DevContainerFile.Choice?, for project: URL
	) {
		devcontainerConsent[project.standardizedFileURL.path] = consent
		staleDevcontainerChoices.remove(project.standardizedFileURL.path)
		devcontainerFailures.remove(project.standardizedFileURL.path)
		Settings.shared.setDevContainerConsent(consent, forProject: project)
		if consent == .container, let choice {
			Settings.shared.setDevContainerChoice(
				DevContainerFile.identifier(of: choice.file, in: project), forProject: project
			)
		}
	}

	/// What is in force for a project, for the titlebar's pill and its menu.
	func devContainerConsent(for project: URL) -> DevContainerConsent? { consent(for: project) }

	/// Whether the last attempt to bring this project's devcontainer up failed,
	/// so that nothing goes on saying it is starting.
	func devContainerFailedToStart(for project: URL) -> Bool {
		devcontainerFailures.contains(project.standardizedFileURL.path)
	}

	/// **Which** of a project's devcontainers its language servers belong in.
	///
	/// The one written down when it is still one of the project's, and the
	/// preferred one otherwise — which covers both a project with a single
	/// container, where there is nothing to choose, and every answer given before
	/// there was anything to choose *with*. Nil only when the project offers none
	/// at all.
	///
	/// This is the single place that turns "yes" into "that one", so the
	/// question, the pill, the menu and the container that actually comes up
	/// cannot come to disagree about which one was meant.
	func containerChoice(for project: URL) -> DevContainerFile.Choice? {
		let choices = DevContainerFile.choices(in: project)
		guard let named = Settings.shared.devContainerChoice(forProject: project) else {
			return choices.first
		}
		return choices.first { DevContainerFile.identifier(of: $0.file, in: project) == named }
			?? choices.first
	}

	/// Work this project inside its devcontainer after all — from the strip
	/// above a file, or from the pill in the titlebar.
	func useDevContainer(for project: URL) {
		move(to: .container, choice: containerChoice(for: project), for: project)
	}

	/// Work this project inside **that** one of its devcontainers — from the
	/// pill's menu, which is the one place with room to list them.
	///
	/// The same call whether the project is already in another container, in none,
	/// or being worked on this machine: `move` is what knows which of those it is,
	/// and all three end with the servers in the container that was clicked.
	func useDevContainer(_ choice: DevContainerFile.Choice, for project: URL) {
		move(to: .container, choice: choice, for: project)
	}

	/// Work this project with the servers on this machine, knowing they are not
	/// the toolchain it names.
	func workOnThisMachine(for project: URL) {
		move(to: .thisMachine, choice: nil, for: project)
	}

	/// Changes which machine — or which container — a project's language servers
	/// run on, after they have already started somewhere.
	///
	/// Everything for the project is ended first, because the two sets answer
	/// differently about the same file and a server left holding a document goes
	/// on publishing diagnostics for it — the fault `opened` guards against one
	/// floor down. The container itself is left up whichever way this goes: it
	/// may hold somebody's terminal, and 0424 is explicit that coming back has to
	/// be instant.
	///
	/// **Moving between two containers is the same move**, which is 0444's part 2
	/// and the reason this takes a choice rather than only a consent. It costs one
	/// thing more than the others: the attachment naming the container the servers
	/// were in has to go, or `warmUp` finds it, decides the project already has a
	/// container, and starts the servers back up in the one somebody has just
	/// asked to leave. A switch that leaves the old container's servers running is
	/// exactly 0427's fault with a gesture behind it.
	private func move(
		to consent: DevContainerConsent, choice: DevContainerFile.Choice?, for project: URL
	) {
		guard hasDevContainerFile(project) else { return }
		let path = project.standardizedFileURL.path
		// Which container this project's servers are in, or would be put in. The
		// one that is actually up when there is one, because that is the fact; the
		// resolved answer otherwise.
		let current = devcontainers[project]?.session.configuration.file
			?? containerChoice(for: project)?.file
		// Nothing to do only when both halves of the answer are already in force.
		// "Use the one we are already using" is a no-op; "use the other one" is
		// not, and the two read identically from the menu.
		let staying = self.consent(for: project) == consent
			&& (consent != .container
				|| choice.map { FilePath.canonical($0.file) } == current.map(FilePath.canonical))
		guard !staying else { return }
		let where_: String
		switch consent {
		case .container: where_ = choice.map { "its devcontainer \($0.name)" } ?? "its devcontainer"
		case .thisMachine, .notNow: where_ = "this machine"
		}
		log("\(project.lastPathComponent)'s language servers move to \(where_)")
		// **The question may still be in the corner, and it holds the guard.**
		// `devcontainerStarting` is what makes ten files opened at once one
		// question rather than ten, and it is held across the *asking* as well as
		// the starting — so a project with a question outstanding cannot start
		// anything, including this. Answering from the pill is answering; the
		// guard is given back here rather than by the withdrawal, so that
		// `questionWithdrawn` finds nothing to hand back and does not log this as
		// an answer nobody gave.
		//
		// **Found by driving it**, and it is the one gesture 0444 makes easy that
		// was hard before: the menu lists every container, so somebody with the
		// question on screen picks from it rather than from the toast — and until
		// this, nothing at all happened, with the pill left saying the container
		// they chose was starting.
		if devcontainerStarting.remove(path) != nil {
			log("\(project.lastPathComponent): the devcontainer question was answered "
				+ "from the titlebar instead")
		}
		withdrawDevContainerQuestion(for: project)
		shutdown(project: project)
		// After the shutdown, which stops them, and before the warm-up, which
		// would otherwise start them straight back up in the container they are
		// leaving. **Only when it is a different container.** Moving onto this
		// machine keeps the attachment, and 0438 proved why: coming back then
		// reuses the very same one, with no second round of asking the image what
		// it carries and no second `is up; it has` in the log.
		if consent == .container, let choice, let current,
		   FilePath.canonical(choice.file) != FilePath.canonical(current) {
			devcontainers.detach(project)
		}
		remember(consent, choice: choice, for: project)
		devcontainerProjects[path] = (consent == .container)
		warmUp(project: project)
		// The files already open belong to the other side's servers now, and
		// nothing here can reach them: the editor groups are what hold the text.
		NotificationCenter.default.post(name: .ideaiLanguageServersMoved, object: project)
	}

	/// Whether this project's language servers belong in a container.
	///
	/// **A project with a devcontainer this app can honour gets its servers
	/// inside it, and the container is started for them.** That is a decision
	/// and it could be reversed, so here is the reasoning. A devcontainer.json
	/// is a project saying which toolchain it is worked on with; running the
	/// editor's servers against a different one is how the errors on screen stop
	/// being the errors from the build, which is 0427's fault one floor up and
	/// worse than a slow machine because a red squiggle is believed. The
	/// alternative — servers on this machine beside a container that is up — is
	/// exactly that state. Projects without a devcontainer.json, which is nearly
	/// all of them, are untouched.
	func usesDevContainer(_ project: URL) -> Bool {
		let path = project.standardizedFileURL.path
		if let known = devcontainerProjects[path] { return known }
		let uses = DevContainerFile.exists(in: project)
		devcontainerProjects[path] = uses
		return uses
	}

	/// The server for a language, inside the project's own container.
	func serverInDevContainer(
		for languageId: String, project: URL, key: String
	) -> Server? {
		guard let attachment = devcontainers[project] else {
			// Declined for now. Nothing is started in the container and nothing
			// takes its place here, because "not now" is not "use this machine's"
			// and the difference is the whole reason there are two ways to say no.
			// The strip says so, and offers the container.
			guard consent(for: project) != .notNow else { return nil }
			// Not up yet, and bringing one up is a pull the first time. Held the
			// way a fetched image already is: nothing waits, what is opened
			// meanwhile is kept, and the server starts when the container lands.
			fetching.insert(key)
			devcontainers.wait(for: languageId, in: project)
			startDevContainer(project)
			// So the strip above the file says the server is on its way rather
			// than nothing at all — and, when it lands, stops saying it. The
			// same notification carries both halves.
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return nil
		}
		let session = attachment.session
		guard let resolved = LanguageServers.resolve(
			languageId: languageId, project: project, inDevContainer: session,
			choosing: choices(for: project),
			// Named for the container's own PATH, and honoured here for the same
			// reason as everywhere else: a devcontainer built on a toolchain manager
			// has that manager's proxy on its PATH too.
			command: LanguageServers.definition(
				forLanguage: languageId, choosing: choices(for: project)
			).flatMap { overrides(for: project).command(forTool: $0.name) }
		) else {
			unavailable.insert(key)
			log("nothing to start for \(languageId) in \(project.path)")
			return nil
		}

		// The container has it or it does not, and the file is what decides.
		// Falling back to a copy on this machine would be the thing this whole
		// path exists to avoid: the same code getting different answers
		// depending on whose laptop it is on.
		guard attachment.carries(resolved.definition.command) else {
			unavailable.insert(key)
			let hint = "\(resolved.definition.command) is not in this project's devcontainer. "
				+ "Add it to the image or the Dockerfile that "
				+ "\(session.configuration.file.lastPathComponent) names, or run its "
				+ "postCreateCommand — the copy on this machine is not used for a project that "
				+ "says which toolchain it is worked on with."
			missingHints[key] = hint
			log("\(resolved.definition.command) is not in \(session.name) — \(languageId) in "
				+ "\(project.lastPathComponent) has no server")
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return nil
		}
		return start(resolved, languageId: languageId, project: project, key: key)
	}

	/// Asks whether this project's devcontainer should come up, once, however
	/// many languages ask, and then does what the answer says.
	///
	/// **The question is here because this is the choke point.** Every route in —
	/// any language, any number of files opened at once — is funnelled through
	/// this function and guarded by `devcontainerStarting`, so the question has
	/// one place to live and cannot be asked twice for one container. The guard
	/// is held across the asking as well as across the starting, which is what
	/// makes ten files opened at once one question rather than ten.
	///
	/// **And it is here rather than when the project is opened.** Most sessions
	/// in a project never open a file the servers care about, and a dialog in
	/// front of a project that is only being read is the kind of prompt people
	/// learn to dismiss without reading. The moment something needs the container
	/// is the moment the question means anything.
	private func startDevContainer(_ project: URL) {
		// A devcontainer is a container the project's own file describes — an
		// image it names, a `postCreateCommand` it carries — so an untrusted
		// project does not get one, and is not asked about one either: the
		// question would be about running its code.
		guard ProjectTrust.shared.isTrusted(project) else { return }
		let path = project.standardizedFileURL.path
		guard devcontainerStarting.insert(path).inserted else { return }
		guard let consent = consent(for: project) else {
			// Still holding `devcontainerStarting`: the answer resolves it, and
			// until then this project has one question outstanding and no more.
			ask(about: project)
			return
		}
		apply(consent, to: project)
	}

	/// What each of the three answers does. The path is in `devcontainerStarting`
	/// when this is called, and every branch either keeps it there because a
	/// container really is coming up or gives it back.
	private func apply(_ consent: DevContainerConsent, to project: URL) {
		let path = project.standardizedFileURL.path
		switch consent {
		case .container:
			bringUpDevContainer(project, choice: containerChoice(for: project))
		case .thisMachine:
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(
				project, because: "its language servers were asked to run on this machine"
			)
		case .notNow:
			devcontainerStarting.remove(path)
			holdWhatWasWaiting(for: project)
		}
	}

	/// Asks, and applies the answer.
	///
	/// **A toast, and one that stays.** 0433 reached for `NSAlert` — a sheet when
	/// there was a window and `runModal` when there was not — and `Toast.swift`
	/// opens with the rule that should have caught it: nothing interrupts unless
	/// the user asked a question, and a confirmation is modal only when it is the
	/// answer to something somebody just did. Opening a `.py` file is neither. So
	/// the question goes to the corner and stays there until it is answered,
	/// which is what `Toast.Lifetime.untilAnswered` was added for.
	///
	/// **And it needs no window to wait for**, which is the other half of what
	/// the modal cost. `warmUp` runs while a project is still loading, with no
	/// key window and nothing on screen to hang a sheet on, so the old path had
	/// to wait a quarter of a second at a time for one to appear and fall back to
	/// an app-modal dialog in front of nothing. A toast is posted; whichever
	/// window is speaking for the app shows it whenever that turns out to be.
	///
	/// What was opened meanwhile is already being held by `serverInDevContainer`,
	/// so an answer given a minute later still hands the server the file somebody
	/// is looking at.
	/// **The question stays three answers however many containers there are**,
	/// which is 0444's part 1 and the shape that entry proposes. Answers stack
	/// rather than sit in a row — a devcontainer's `name` is a whole sentence, so
	/// three side by side would be three truncations — and a fourth and fifth
	/// stacked under them would be a wall in the corner of the screen for a
	/// decision most projects do not have to make. So the question names the one
	/// it would use, and *which* is asked where there is room: the pill's menu
	/// lists them and can change it afterwards, without reopening the project.
	private func ask(about project: URL) {
		let path = project.standardizedFileURL.path
		guard let choice = containerChoice(for: project) else {
			// The file went away between the check and the question, which is not
			// a failure and must not be reported as one.
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "it has no devcontainer.json")
			return
		}
		let firstStart = DevContainerFile.read(choice.file, project: project)
			.configuration.map(DevContainerConsent.FirstStart.of)

		// In the order the answers are offered in, the project's own first. There
		// is no Escape to wire "not now" to any more, and it does not need one:
		// the answer that decides nothing is a button like the others, and a
		// question that cannot be dismissed by accident is the point of it.
		let answers = DevContainerConsent.answersInOrder.map { answer in
			Toast.Answer(DevContainerConsent.buttonTitle(answer, container: choice.name)) {
				[weak self] in
				guard let self else { return }
				self.log("\(project.lastPathComponent): \(choice.name) — \(answer.rawValue)")
				// The container the question named, written down with the yes: it
				// is the one thing the answer meant that a bare `container` cannot
				// carry, and a project offering several must not be able to start a
				// different one from the one whose name was on the button.
				self.remember(answer, choice: choice, for: project)
				self.apply(answer, to: project)
			}
		}

		Toast.ask(Toast(
			kind: .information,
			title: DevContainerConsent.questionTitle,
			detail: DevContainerConsent.questionBody(
				project: project.lastPathComponent, container: choice.name, firstStart: firstStart
			),
			answers: answers,
			lifetime: .untilAnswered,
			identifier: Self.questionIdentifier(for: project),
			onWithdrawn: { [weak self] in self?.questionWithdrawn(about: project) }
		))
	}

	/// What a question about this project's devcontainer is filed under, so that
	/// it can be taken back.
	private static func questionIdentifier(for project: URL) -> String {
		"devcontainer-question:" + FilePath.canonical(project)
	}

	/// The window stopped showing this project, so the question about its
	/// devcontainer has nobody left to answer it.
	///
	/// Called by whatever moved — switching project, or moving between the
	/// subprojects of one. **Withdrawing is not answering**: nothing is decided
	/// and nothing is written down, because leaving a question about a project
	/// nobody is looking at one click from being answered is how somebody agrees
	/// to a `docker build` for a checkout they left.
	func withdrawDevContainerQuestion(for project: URL) {
		Toast.withdraw(Self.questionIdentifier(for: project))
	}

	/// The question went off the screen unanswered.
	///
	/// **The guard has to be given back**, and this is the only thing that does
	/// it. `devcontainerStarting` is held across the asking as well as the
	/// starting — which is what makes ten files opened at once one question — so
	/// a question withdrawn without releasing it would leave the project unable
	/// ever to ask again and unable to start anything either: a state nothing on
	/// screen could get somebody out of. What was waiting stops waiting, for the
	/// same reason "not now" makes it stop — the strip must not go on saying a
	/// server is on its way to a container nobody is bringing up.
	private func questionWithdrawn(about project: URL) {
		let path = project.standardizedFileURL.path
		guard devcontainerStarting.remove(path) != nil else { return }
		log("\(project.lastPathComponent): the devcontainer question was withdrawn unanswered")
		holdWhatWasWaiting(for: project)
	}

	/// Nothing is started, here or there, and what was held stops being held.
	///
	/// Without the second half the strip goes on saying a server is on its way to
	/// a container nobody is bringing up. Nothing takes its place: a server on
	/// this machine is the *other* answer, and quietly giving it to somebody who
	/// said "not now" would be the app deciding whose toolchain the code is
	/// checked against — which is what the whole devcontainer path exists to
	/// avoid.
	private func holdWhatWasWaiting(for project: URL) {
		for languageId in devcontainers.takeWaiting(for: project) {
			fetching.remove(key(project: project, languageId: languageId))
		}
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	/// Brings up **that** devcontainer of the project's, the answer having been
	/// yes to it by name.
	///
	/// **The file rather than the project**, which is 0444's part 1 arriving at
	/// the bottom of it. `DevContainers.session(for project:)` starts whichever
	/// container the project prefers and has nowhere to be told otherwise; a
	/// session is remembered against the file, so asking by file is what lets a
	/// project have its servers in the second of two containers, and lets the pill
	/// move them to the other one.
	///
	/// The toast that used to say "this project offers N devcontainers … so the
	/// first is used" is gone with the thing it was apologising for. What replaced
	/// it is not a quieter apology: the question names the container it would use,
	/// the answer is written down as a *which*, and the pill's menu lists all of
	/// them with the one in use marked. A toast repeating that would be news about
	/// a decision somebody made.
}
