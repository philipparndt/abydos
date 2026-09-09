import AppKit
import AbydosKit

/// Bringing a devcontainer up and starting a server inside it — and what to do
/// instead when it will not come up.
extension LanguageService {
	func bringUpDevContainer(_ project: URL, choice: DevContainerFile.Choice?) {
		let path = project.standardizedFileURL.path
		// The container the project's own file describes, and the lifecycle
		// commands it carries. Gated here as well as where the question is
		// asked, for the reason `start` gives: one check on one of several
		// routes is a check the other routes walk past.
		guard ProjectTrust.shared.isTrusted(project) else {
			devcontainerStarting.remove(path)
			return
		}
		guard let choice else {
			// The file went away between the answer and the start, which is not a
			// failure and must not be reported as one.
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "it has no devcontainer.json")
			return
		}
		guard let runtime = ContainerRuntime.discover(
			preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
				?? .automatic
		) else {
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "nothing here can run a container")
			return
		}
		log("\(project.lastPathComponent) is worked on in \(choice.name); "
			+ "its language servers go inside it")

		// **Somewhere to watch it happen**, which is 0444's part 4. The first
		// start is an image pulled or a Dockerfile built and then three lifecycle
		// commands — minutes, during which the only thing that used to reach the
		// screen was a passing toast per step, with the `docker build` output
		// going nowhere a person could read it.
		//
		// `PreparingTerminal` already is the view being asked for and its own note
		// describes it: the tab opens at once, the work is written into it, and the
		// same pane becomes the shell. It was only ever reached from somebody
		// opening a terminal in the container. Now the language-server path opens
		// one too — never taking the keyboard, since the whole point is that they
		// were doing something else when the file they opened started this.
		//
		// Nil when no window is showing this project, which happens: `warmUp` runs
		// while a project is still loading. Then it is toasts, exactly as before.
		let watching = MainWindowController.watchDevContainerStarting(
			project: project, choice: choice
		)
		let progress = watching?.progress ?? DevContainers.Progress(step: { message in
			// A pull and a postCreateCommand are both minutes, and a minute with
			// nothing on screen is a feature that looks broken. The steps and not
			// the output: there is no pane to put ten minutes of `npm ci` in, and
			// it goes to devcontainer.log either way.
			Task { @MainActor in Toast.post(message, kind: .information) }
		})

		Task { @MainActor in
			let outcome = await DevContainers.shared.session(
				for: choice.file, in: project, using: runtime, progress: progress
			)
			devcontainerStarting.remove(path)
			switch outcome {
			case let .running(session):
				devcontainerFailures.remove(path)
				// A language server is something attaching to the container, and
				// `postAttachCommand` is the moment that names.
				await DevContainers.shared.attach(to: session)
				// One question for every server there is, rather than one failed
				// handshake per language — and asked *before* the session is
				// recorded, so that the pair goes in together. Anything that finds
				// a session finds what it carries beside it or finds neither.
				let provides = await DevContainers.shared.provides(
					LanguageServers.known.map(\.command), in: session
				)
				devcontainers.attach(session, providing: provides, to: project)
				log("\(session.name) is up; it has "
					+ "\(provides.isEmpty ? "no" : provides.sorted().joined(separator: ", "))"
					+ " language server(s)")
				// The pane that watched it come up becomes a shell inside it, which
				// is what `PreparingTerminal` is for and is the one thing 0433's
				// report went looking for and could not find: a way to be *in* the
				// container. Without the keyboard — see `becomeShell`.
				watching?.becomeShell(running: DevContainers.terminalCommand(session))
				startWhatWasWaiting(for: project)
			case let .refused(reason):
				// Said yes, and it did not come up. The answer stays on file, so
				// this is the only thing that stops the titlebar saying a container
				// is starting for the rest of the session.
				devcontainerFailures.insert(path)
				// **The pane is the error and the toast points at it.** A failed
				// build is a hundred lines of `docker build` ending in one that
				// matters, and a toast cannot hold either — 0444's part 4. Where
				// there is a pane, the reason goes in it under everything the build
				// said, and what is posted is short and says where to look.
				if let watching, watching.isOpen {
					watching.refuse(reason)
					Toast.post(
						"\(project.lastPathComponent)'s devcontainer was not started",
						detail: "Its language servers run on this machine instead. What the build "
							+ "said is in the \(choice.name) tab in the terminal panel.",
						kind: .error
					)
				} else {
					Toast.post(
						"\(project.lastPathComponent)'s devcontainer was not started",
						detail: "\(reason)\nIts language servers run on this machine instead.",
						kind: .error
					)
				}
				runOnThisMachineInstead(project, because: reason)
			}
		}
	}

	/// The project's servers run here after all, and the reason is said once.
	func runOnThisMachineInstead(_ project: URL, because reason: String) {
		let path = project.standardizedFileURL.path
		devcontainerProjects[path] = false
		log("\(project.lastPathComponent)'s devcontainer is not available (\(reason)); "
			+ "its language servers run on this machine")
		startWhatWasWaiting(for: project)
	}

	/// Starts the servers asked for while the container was coming up, and
	/// hands each the files opened meanwhile.
	private func startWhatWasWaiting(for project: URL) {
		// Gone while the container was on its way — the project was closed — so
		// there is nobody to start a server for.
		for languageId in devcontainers.takeWaiting(for: project).sorted() {
			let key = key(project: project, languageId: languageId)
			guard fetching.remove(key) != nil else { continue }
			guard let server = server(for: languageId, project: project) else { continue }
			replayDeferredOpens(to: server, key: key)
		}
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	/// Starts a server whose image, if it has one, is already here.
	///
	/// **The gate is here as well as at `opened`**, and this is the one that
	/// matters: a server is started from several places — a file opening, a
	/// container arriving, a scope changing under an open file — and a check at
	/// one of them is a check three others walk past. It was: an untrusted
	/// project was photographed with its devcontainer starting gopls.
	func start(
		_ resolved: LanguageServers.Resolution,
		languageId: String,
		project: URL,
		key: String
	) -> Server? {
		guard ProjectTrust.shared.isTrusted(project) else { return nil }
		let client = LSPClient()
		// Before anything is sent, including the handshake: from here on every
		// path going out is the container's and every one coming back is ours.
		client.containerPaths = resolved.launch.paths
		// And what the container it runs in is called, so that stopping this
		// server stops the container too rather than only the process in front
		// of it.
		client.containerLaunch = resolved.launch.container
		client.onDiagnostics = { [weak self] uri, diagnostics in
			guard let self else { return }
			self.diagnostics[uri] = diagnostics
			NotificationCenter.default.post(
				name: .ideaiDiagnosticsChanged,
				object: URL(string: uri)
			)
		}
		// **A server asking this program to change files.** Set on every client
		// because any server may send it — it is usually the second half of a
		// code action that was a command — and answered by whichever window is
		// in front, since applying an edit means the rope of whatever documents
		// are open. Nothing in front is an honest `false`: a server told that
		// the edit did not happen can say so, where one told nothing waits.
		client.onApplyEdit = { [weak self] edit, label, answer in
			self?.serverEditsForTesting += 1
			guard let handler = self?.applyEditFromServer else {
				answer(false, "This editor has no window to apply the edit in.")
				return
			}
			DispatchQueue.main.async { handler(edit, label, answer) }
		}
		client.onExit = { [weak self, weak client] in
			guard let self else { return }
			// Only if the table still holds this very client, rather than
			// whatever is filed under this key now.
			//
			// A server stopped by hand from the list of what is running is taken
			// out of the table at once, and the next file of that language
			// starts another one for the same key — while the first one's
			// process is still on its way out. Removing by key alone then takes
			// the *new* server out of the table a second later, and the app has
			// a running language server it no longer knows about: measured, and
			// it showed as the list going empty and staying empty after a Stop.
			guard let held = self.servers[key]?.client, held === client else { return }
			self.servers.removeValue(forKey: key)
			// A server that died in the middle of preparing. The chip goes with
			// the entry, but the set is what `footer` reads and a key left in it
			// would say "preparing" from the first frame of whatever starts next.
			self.preparing.remove(key)
			self.runningNames.removeAll { $0 == resolved.definition.command }
			self.log("\(resolved.definition.command) exited")
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		// Everything the server says about itself goes to the log, and the part
		// of it that means "I cannot work" is said out loud once.
		client.onMessage = { [weak self] level, text in
			self?.serverSaid(level: level, text: text, definition: resolved.definition, key: key)
		}
		// Twice per server and no more: once when it starts building what the
		// project depends on, once when it has finished. The chip beside the
		// caret is the only thing that reads it, and `.ideaiLanguageServersChanged`
		// is what pushes it there — the same notification every start, stop and
		// refusal already posts, so nothing new has to be listened for.
		client.onPreparing = { [weak self] isPreparing in
			guard let self else { return }
			// By key rather than by client: a server stopped by hand and started
			// again under the same key is a different client, and the one that
			// is filed now is the one the chip is drawn from.
			if isPreparing { self.preparing.insert(key) } else { self.preparing.remove(key) }
			self.log("\(resolved.definition.command) "
				+ (isPreparing ? "is preparing this project" : "has finished preparing"))
			// The same notification the footer's chip is drawn from, and now also
			// what makes a completion list saying "still preparing" ask again:
			// it is posted the moment preparing stops, so nothing polls and
			// nothing sets a timer.
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		client.onStandardError = { [weak self] text in
			guard let self else { return }
			let line = Self.oneLine(text)
			self.log("\(resolved.definition.command) stderr: \(line)")
			// Kept for the message. A server that dies on the way up says why
			// here and nowhere else: "the language server is not running" is
			// what the client knows, and it is the one thing nobody can act on.
			if !line.isEmpty { self.lastStandardError[key] = line }
		}

		let run = resolved.launch.invocation
		do {
			// Rooted where the manifest is, which is not always the project
			// root: a server pointed at a directory with no manifest in it
			// answers nothing and says nothing about why.
			//
			// And with a PATH that has the toolchain on it. A language server
			// runs the compiler; a GUI app's PATH does not have one.
			//
			// Nothing to prepare for a container: what jdtls would be given a
			// directory for is inside the image, and a directory made out here
			// for it would be litter nothing ever reads.
			if resolved.launch.paths == nil {
				LanguageServers.prepare(resolved.definition, root: resolved.root)
			}
			try client.start(
				executable: run.executable,
				arguments: run.arguments,
				// The runtime's own working directory, in the container's case,
				// which it does not mind: where the server starts is `-w`, and
				// that is in the command line already. The environment is the
				// same story — the runtime needs it to find its socket.
				//
				// Out here it is asked for, because for one server it is not the
				// project: sourcekit-lsp builds the package to index it, and 0518
				// found a build of it writing 1424 files into somebody's checkout,
				// because a relative path is written where the process stands.
				// `LanguageServers.workingDirectory` says why the answer for that
				// one is the index's own directory. Only on this route: the
				// directory a container's runtime is started in is not the
				// directory the server runs in, and a cache path from this machine
				// would say nothing about either.
				workingDirectory: resolved.launch.paths == nil
					? LanguageServers.workingDirectory(
						for: resolved.definition, root: resolved.root)
					: canonical(resolved.root),
				environment: LanguageServers.serverEnvironment
			)
			log("\(resolved.definition.command) started for \(languageId) "
				+ "at \(canonical(resolved.root).path) [\(resolved.launch.description)]")
		} catch {
			unavailable.insert(key)
			log("\(resolved.definition.command) would not start: \(error.localizedDescription)")
			Toast.post(
				"\(resolved.definition.command) would not start",
				detail: "\(error.localizedDescription)\n\(Self.logPath) has the rest.",
				kind: .error
			)
			return nil
		}

		let server = Server(
			client: client,
			definition: resolved.definition,
			project: project,
			insideContainer: resolved.launch.hostContainerName,
			origin: resolved.launch.origin
		)
		servers[key] = server
		// A new process is a new question: whatever the last server under this
		// key said about the project was said by a program that is not running
		// any more, and leaving it here would put a strip over a server that has
		// not been given the chance to say anything.
		health.removeValue(forKey: key)
		// And it has not started preparing yet. A key left in this set from the
		// server before would have the chip saying "preparing" from the first
		// frame of a server that may never say a word about progress.
		preparing.remove(key)

		Task { @MainActor in
			// The handshake has to finish before anything else is sent, but
			// nothing waits on it: notifications queue up on the pipe in order,
			// and the first answers simply arrive a moment later.
			do {
				// A Java server reads the build file before it answers the
				// handshake, and on a multi-module Maven project that is tens of
				// seconds. Ten would report a working server as broken.
				let isJava = resolved.definition.setup == .java
				_ = try await client.initialize(
					rootURL: canonical(resolved.root),
					options: LanguageServers.initializationOptions(
						for: resolved.definition,
						root: canonical(resolved.root),
						inContainer: resolved.launch.paths != nil,
						// And whatever this project says to tell it, which for every
						// server but jdtls is the only thing in there. 0466's case is
						// rust-analyzer's `procMacro.server`, a path into a toolchain
						// this repository cannot know the name of.
						merging: overrides(for: project)
							.initializationOptions(forTool: resolved.definition.name)
					),
					timeout: isJava ? 120 : 10
				)
				log("\(resolved.definition.command) initialized")
				// **Said out loud, because something now depends on the moment
				// it happens.** The handshake finishing used to change nothing
				// anybody could see — the strip and the chip are drawn from
				// `preparing`, and a server that never reports progress goes
				// from spawned to usable without touching it. The titlebar's
				// "your tools are ready" is drawn from `readiness`, which turns
				// on exactly here, so exactly here has to post.
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			} catch {
				log("\(resolved.definition.command) handshake failed: \(error.localizedDescription)")

				// Not tried again for this project. A server that dies on the
				// way up dies the same way every time — a rustup shim with no
				// rust-analyzer behind it exits in a second, for ever — and the
				// restart-on-demand rule that brings a crashed server back was
				// turning that into a toast every few seconds. Opening the
				// project again is what asks for another go, which is also when
				// somebody has had the chance to install the thing.
				unavailable.insert(key)
				servers.removeValue(forKey: key)

				// In the server's own words where it left any: "Unknown binary
				// 'rust-analyzer' in official toolchain" says what to do, and
				// "the language server is not running" does not.
				let said = lastStandardError[key] ?? error.localizedDescription
				// **The reproduction 0461 was written from ends here.** The
				// rust-analyzer image, pointed at a project that pins a
				// toolchain the image has not got, prints one line on standard
				// error and exits before the handshake — so the toast said it
				// once and then nothing on screen said anything at all, because
				// the strip above the file only ever knew about servers that had
				// not been *started*.
				changeHealth(of: key) { $0.stopped(saying: said) }
				Toast.post(
					"\(resolved.definition.command) did not answer",
					detail: "\(said)\n\(Self.logPath) has the rest.",
					kind: .error
				)
			}
			runningNames.append(resolved.definition.command)
			missingHints.removeValue(forKey: key)
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		return server
	}

	/// Which server to start, and whether it comes from an image.
	///
	/// An image is named per project in `.abydos/tools.json` or once in
	/// settings, under the tool's own name rather than its command — `pyright`,
	/// not `pyright-langserver`.
	func resolution(for languageId: String, project: URL) -> LanguageServers.Resolution? {
		let choices = choices(for: project)
		// Two questions and they stay two: which server this project wants, and
		// where that server comes from. The image is looked up under the chosen
		// server's name, so a project that changes its mind about the server gets
		// the image named for the one it now uses rather than the one it dropped.
		let image = LanguageServers.definition(forLanguage: languageId, choosing: choices)
			.flatMap { images(for: project).image(for: $0.name) }

		// Looked for only when one is named: finding a runtime means walking the
		// PATH, and most projects name no image at all.
		var runtime: ContainerRuntime?
		if let image, !image.isEmpty {
			runtime = ContainerRuntime.discover(
				preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
					?? .automatic
			)
			if runtime == nil {
				// Said, because the alternative is a project that pinned a
				// version quietly getting whatever is installed instead.
				log("\(image) is named for \(languageId) but nothing here can run a "
					+ "container; using what is installed instead")
			}
		}
		return LanguageServers.resolve(
			languageId: languageId, project: project, image: image, runtime: runtime,
			choosing: choices,
			// The executable this project or this person named for the server, if
			// either did. Asked of the *chosen* server's name, like the image above
			// and for the same reason.
			command: LanguageServers.definition(forLanguage: languageId, choosing: choices)
				.flatMap { overrides(for: project).command(forTool: $0.name) }
		)
	}

	/// What this project's own toolchain pin means for where this server comes
	/// from, or nil when it pins nothing or pins something the server can have.
	///
	/// **Known before anything is started**, which is the whole of 0462: the pin
	/// is a file in the project and the image's toolchain was decided when the
	/// image was built, so the two can be compared at the moment the image is
	/// chosen rather than at the first request that comes back empty. 0461 is
	/// the same failure noticed afterwards, from what the server says; this one
	/// never needed the server to say anything.
	///
	/// The image is taken as *named* rather than as it will resolve. Working out
	/// that a named image cannot be run here at all means walking the PATH for a
	/// runtime, which is not a thing to do while a strip is being drawn — and it
	/// would change only which of two sentences is said about a project neither
	/// of them can read.
	func toolchainObjection(
		for definition: LanguageServerDefinition, project: URL
	) -> ToolchainPins.Objection? {
		let path = project.standardizedFileURL.path
		let pins = toolchainPins[path] ?? {
			let read = ToolchainPins.inProject(project)
			toolchainPins[path] = read
			return read
		}()
		guard let pin = pins.first(where: { $0.tool == definition.name }) else { return nil }
		let named = images(for: project).image(for: definition.name)
		let resolved = named.flatMap {
			ToolImageRecipes.resolve(image: $0, forTool: definition.name)
		}
		return ToolchainPins.objection(
			to: pin,
			// The word a recipe is asked for by is not an image name, so it is
			// turned into the name of the image that would be built — which is
			// still an image, and still one whose toolchain was fixed when it was
			// built.
			comingFrom: resolved,
			// An executable already named for this server answers the pin, so there
			// is nothing to say. Whether that path is any good is the sentence above
			// this one in `notice`, and it says so on its own.
			command: overrides(for: project).command(forTool: definition.name),
			// And a recipe from this repository chosen instead of the tool's own is
			// this project's own answer to the channel — see `isVariantRecipe`.
			imageKnowsChannel: resolved.map {
				ToolImageRecipes.isVariantRecipe($0, forTool: definition.name)
			} ?? false
		)
	}

	/// The images a project asks for, project first and settings behind it.
	func images(for project: URL) -> ToolImages {
		let path = project.standardizedFileURL.path
		if let known = toolImages[path] { return known }
		let resolved = ToolImages.resolve(
			project: ToolImages.inProject(project),
			settings: ToolImages(images: Settings.shared.toolImages)
		)
		toolImages[path] = resolved
		return resolved
	}

	/// Which server a project wants for each language, project first and
	/// settings behind it.
	///
	/// The same order as the images above, and 0424 is where it was settled:
	/// **the file wins and the setting is the default.** A project's choice of
	/// server is a statement about the project — this is the trade we want here
	/// — and a personal preference quietly overriding it would mean two people
	/// on one repository being answered by two different programs.
	func choices(for project: URL) -> LanguageServerChoices {
		let path = project.standardizedFileURL.path
		if let known = serverChoices[path] { return known }
		let resolved = LanguageServerChoices.resolve(
			project: LanguageServerChoices.inProject(project),
			settings: LanguageServerChoices.settings(Settings.shared.languageServers)
		)
		serverChoices[path] = resolved
		return resolved
	}

	/// What a project says about a server's executable and what to tell it,
	/// project first and settings behind it — the same order as everything else
	/// out of this file.
	func overrides(for project: URL) -> LanguageServerOverrides {
		let path = project.standardizedFileURL.path
		if let known = serverOverrides[path] { return known }
		let resolved = LanguageServerOverrides.resolve(
			project: LanguageServerOverrides.inProject(project),
			settings: LanguageServerOverrides.settings(Settings.shared.serverCommands)
		)
		serverOverrides[path] = resolved
		return resolved
	}

	/// What to say about a server that was chosen, exists, and is not here.
	///
	/// The ordinary install hint, and in front of it the fact that somebody
	/// chose this one — without which the sentence reads as though Abydos picked
	/// the server, and the next thought is that surely the other one is running
	/// instead. It is not, and saying so is the difference between five minutes
	/// and an afternoon.
	func chosenButAbsent(
		_ definition: LanguageServerDefinition, languageId: String, project: URL
	) -> String {
		guard let chosen = choices(for: project).chosen(forLanguage: languageId) else {
			return definition.installHint
		}
		let others = LanguageServers.candidates(forLanguage: languageId)
			.map(\.name)
			.filter { $0 != definition.name }
		let instead = others.isEmpty
			? ""
			: " Nothing has been started in its place — not \(others.joined(separator: " and ")) "
				+ "— because \(definition.name) is what was asked for."
		return "\(chosen.source.origin) chose \(definition.name) for this project, and it is not "
			+ "installed here and no image is named for it.\(instead)\n\n\(definition.installHint)"
	}

	/// Tells a server that has just started about the files opened while its
	/// image was being fetched.
	func replayDeferredOpens(to server: Server, key: String) {
		let waiting = deferredOpens.removeValue(forKey: key) ?? [:]
		guard !waiting.isEmpty else { return }
		for (uri, document) in waiting {
			openDocuments[uri] = 1
			documentServers[uri] = key
			didOpenCount += 1
			server.client.didOpen(
				uri: uri, languageId: document.languageId, version: 1, text: document.text
			)
		}
		log("\(server.definition.command) was told about \(waiting.count) file(s) "
			+ "opened while its image was being fetched")
	}

	/// Something the server said about itself.
	///
	/// Everything is logged; an error is also said out loud, once. A server
	/// that cannot load its workspace repeats itself for every file opened
	/// afterwards, and a toast per file would be worse than the silence it
	/// replaces.
	private func serverSaid(
		level: Int,
		text: String,
		definition: LanguageServerDefinition,
		key: String
	) {
		let line = Self.oneLine(text)
		// Everything down to info, which is where a server says what it made of
		// the project — the view it created, the packages it loaded. Not level
		// 4: that is the server's own debug logging, and some of them are
		// generous with it.
		if level <= 3 { log("\(definition.command) says [\(Self.levelName(level))] \(line)") }

		// 1 is an error in the protocol's numbering. Warnings are ordinary
		// enough that a toast for each would be the thing people turn off — and
		// **measured, the level is a poorer signal than it looks**: the
		// rust-analyzer image this repository builds reports a project it could
		// not load at level 2, and reports `duplicate DidOpenTextDocument`, which
		// costs nothing, at level 1. That is why an error here is a report and
		// not a verdict; `ServerHealth` is where the difference is written down.
		guard level == 1 else { return }

		// **Not while it is preparing**, and this is the second half of 0501
		// rather than a nicety. Watched in the real app on a cold open of a
		// package with eighteen C++ targets: `sourcekit-lsp` reports the
		// subprocesses of its own index build at error level — `Finished with
		// signal 2`, `Finished with exit code 1` — and every one of them landed
		// here, so twenty seconds into a perfectly ordinary first open the strip
		// said the server *cannot read this project* and a red toast said it
		// again. That sentence is 0461's, it is about a server that will never
		// answer, and it was being said about one that answered thirty seconds
		// later.
		//
		// `ServerHealth` already says the level is a poorer signal than it looks
		// and that a message is a report rather than a verdict. This is the same
		// argument with a fact the app now has: the server has said it is not
		// ready, so what it says about failures while it gets ready is about the
		// build. Nothing is lost for good — `said` keeps the *first* diagnosis
		// and the state is still `.working`, so a server that really cannot read
		// the project says so again on the next file and is believed then.
		guard !preparing.contains(key) else { return }
		changeHealth(of: key) { $0.said(line) }

		// Once per server, not once per message. A server that cannot load a
		// workspace says so again for every file opened afterwards, with a
		// slightly different URI in it each time — so keying this on the text
		// put the same failure in the corner twice over.
		guard announced.insert(definition.command).inserted else { return }
		Toast.post(
			"\(definition.command) cannot read this project",
			detail: "\(line)\n\n\(Self.logPath) has the rest.",
			kind: .error
		)
	}

	private static func levelName(_ level: Int) -> String {
		switch level {
		case 1: return "error"
		case 2: return "warning"
		case 3: return "info"
		default: return "log"
		}
	}

	/// A server's message on one line, short enough to be read in a corner.
	private static func oneLine(_ text: String) -> String {
		let collapsed = text
			.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.joined(separator: " ")
		return collapsed.count > 300 ? String(collapsed.prefix(300)) + "…" : collapsed
	}
}
