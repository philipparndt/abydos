import AppKit
import AbydosKit

/// Starting and stopping servers, and what happens to one when the preference
/// it was started under changes underneath it.
extension LanguageService {
	// MARK: - Servers

	@discardableResult
	func server(for languageId: String, project: URL) -> Server? {
		let key = key(project: project, languageId: languageId)
		if let existing = servers[key] {
			// A server that died — crashed, or killed by somebody's `pkill` —
			// is started again rather than silently doing nothing for ever.
			if existing.client.isRunning { return existing }
			servers.removeValue(forKey: key)
		}
		guard !unavailable.contains(key) else { return nil }
		// One already on its way. Not missing, not started: it arrives when the
		// image does, and asking again would start a second fetch.
		guard !fetching.contains(key) else { return nil }

		// A server this project named and this app has not got. **It stops
		// here** — and stopping here is the whole of it. Falling through to the
		// server that was not chosen would give somebody who asked for the fast
		// one a JVM and 1.9 GB, with nothing anywhere saying why.
		if case let .noSuchServer(name, source) = selection(for: languageId, project: project) {
			unavailable.insert(key)
			let said = LanguageServers.refusal(named: name, forLanguage: languageId, source: source)
			missingHints[key] = said
			log(said)
			// Said out loud, which the ordinary missing server deliberately is
			// not: that one is a language somebody never asked about, and this
			// one is a sentence they wrote themselves and can fix. Once per
			// server per project, because a project full of Java files would
			// otherwise say it on every open.
			if refused.insert(key).inserted {
				Toast.post(
					"No language server called \(name)",
					detail: said,
					kind: .error
				)
			}
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return nil
		}

		// A project that says what it is worked on in has its servers in there.
		if usesDevContainer(project) {
			return serverInDevContainer(for: languageId, project: project, key: key)
		}

		guard let resolved = resolution(for: languageId, project: project) else {
			unavailable.insert(key)
			if let definition = LanguageServers.definition(
				forLanguage: languageId, choosing: choices(for: project)
			), LanguageServers.suits(definition, root: project) {
				missingHints[key] = chosenButAbsent(definition, languageId: languageId, project: project)
				// Logged, not said out loud. Half the projects on a machine
				// touch a language whose server nobody installed, and a toast
				// on every open for something that was never going to work is
				// the notification people turn off. Where it matters — asking
				// for symbols and getting none — the empty state says it.
				log("\(definition.command) is not installed — \(languageId) in "
					+ "\(project.lastPathComponent) has no server. \(definition.installHint)")
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			} else {
				log("nothing to start for \(languageId) in \(project.path)")
			}
			return nil
		}

		guard let image = resolved.launch.image else {
			return start(resolved, languageId: languageId, project: project, key: key)
		}

		// An image that is not on the machine is fetched first, and the first
		// time that is minutes rather than seconds. Nothing waits on it: the
		// fetch runs on its own and the server starts when the image lands,
		// which is the same shape a slow handshake already has. What was opened
		// meanwhile is kept and sent then.
		fetching.insert(key)
		if ToolImageRecipes.isBuiltHere(image.name) {
			buildingHere.insert(key)
		} else {
			buildingHere.remove(key)
		}
		log("\(resolved.definition.command) comes from \(image.name); making sure it is here")
		// **Somewhere to watch it happen**, which is 0459. The sentence below used
		// to be the whole of what reached the screen, and it was written for a
		// pull: `ensure` also *builds*, from a Dockerfile this app ships, and a
		// cold `rust-analyzer` is 164 seconds of a compiler saying nothing anybody
		// could see. `ImageArrival` opens the same pane the devcontainer path
		// opens, on the same terms, and passes the second sink `ensure` has always
		// taken and this call site never gave it.
		let built = ToolImageRecipes.isBuiltHere(image.name)
		// The **name** and not the command, which is the difference between a tab
		// called "Building pyright" and one called "Building pyright-langserver".
		// `LanguageServers.Definition` keeps the two apart for exactly this: the
		// name is what somebody calls the tool and what they typed to ask for it,
		// and the command is the binary inside the image.
		let named = resolved.definition.name
		let arrival = ImageArrival(image: image.name, tool: named, project: project)
		Task { @MainActor in
			let outcome = await ContainerImageStore.shared.ensure(
				image.name,
				using: image.runtime,
				progress: arrival.watch.step,
				output: arrival.watch.output
			)
			// The pane is ended before anything else, and whatever the project did
			// meanwhile: a tab left saying a build is happening after it has
			// stopped is worse than no tab.
			var tab: String?
			if case let .failed(reason) = outcome {
				tab = arrival.failed(reason)
			} else {
				arrival.arrived()
			}
			// Gone while the image was on its way: the project was closed, and a
			// server started for it now would be a process nobody is waiting for.
			guard fetching.remove(key) != nil else { return }
			if case let .failed(reason) = outcome {
				// Not tried again for this project: a name that is wrong is
				// wrong every time, and a registry that wants a sign-in wants
				// one until somebody gives it. Reopening the project asks again.
				unavailable.insert(key)
				// Not running and never will be, under the conditions in force:
				// the strip says so rather than leaving the file looking like
				// one whose language nobody has a server for.
				changeHealth(of: key) { $0.stopped(saying: reason) }
				log("\(resolved.definition.command): \(reason)")
				Toast.post(
					// "could not be fetched" was said of a build too, which is the
					// same conflation 0434 wrote a separate sentence to avoid:
					// nothing in `abydos-built/` is ever fetched from anywhere.
					// The name here too, so the corner and the tab it points at are
					// about the same thing.
					"\(named) could not be \(built ? "built" : "fetched")",
					// The reason *and* where the log is, which is where this parts
					// company with 0444 on purpose — see `ImageArrival.failed`. The
					// sentence is a diagnosis rather than a summary, so it is worth
					// having in the corner; the tab is for the one failure that is a
					// line somewhere in a hundred.
					detail: tab.map {
						"\(reason)\nWhat the \(built ? "build" : "fetch") printed is in the "
							+ "\($0) tab in the terminal panel."
					} ?? reason,
					kind: .error
				)
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
				return
			}
			guard let server = start(resolved, languageId: languageId, project: project, key: key) else { return }
			replayDeferredOpens(to: server, key: key)
		}
		return nil
	}

	// MARK: - When a preference changes underneath a server

	/// Settings were written. Which setting is not said — there is one
	/// notification for all of them — so the answer is to look.
	///
	/// **Not at once.** Two reasons, and the second is the one that matters.
	/// Every write posts this, so a slider on the appearance page would otherwise
	/// walk every open project to discover it has nothing to do. And a text field
	/// for an image name is a value on its way to being a value: the field this
	/// app has sends its action when the editing ends rather than per character,
	/// so today's controls settle by themselves — but a preference change costs a
	/// server being stopped and started, and that is not a bill to leave resting
	/// on a control's configuration. Coalescing takes the last of a run of writes
	/// and acts on that one.
	func settingsChanged() {
		reconsidering?.cancel()
		reconsidering = Task { @MainActor in
			try? await Task.sleep(nanoseconds: 400_000_000)
			guard !Task.isCancelled else { return }
			self.reconsider()
		}
	}

	/// Goes back over what is remembered about servers not working, because a
	/// preference that decided it has changed.
	///
	/// The whole of 0460 is here. A server that failed is not tried again for the
	/// project — deliberately, since a name that is wrong is wrong every time —
	/// and until now the only thing that undid it was `shutdown(server:)`, which
	/// is Stop in the list of running servers. So somebody who chose an image for
	/// a server that had already failed got nothing at all: no container, no
	/// build, no message, and nothing on screen disagreeing with what they asked
	/// for.
	///
	/// **It starts what it clears, rather than only unclearing it.** Clearing the
	/// memory alone would make the *next* file of that language ask again, and
	/// the person who has just chosen an image is looking at the editor now.
	/// "It works when you go back to the file" is the same fault with a longer
	/// fuse — they would have gone and looked for the fault somewhere else long
	/// before opening that file again. So an affected project is warmed up as
	/// though it had just been opened, and the files already on screen are
	/// announced again through `.ideaiLanguageServersMoved`, which is the path a
	/// project moving in or out of its devcontainer already takes.
	///
	/// The cost of that is bounded by `ServerReconsideration` deciding what is
	/// affected: a project with nothing to do is not walked at all.
	private func reconsider() {
		let now = ToolPreferences(Settings.shared)
		let change = now.changes(since: preferences)
		guard !change.isEmpty else { return }
		preferences = now

		// Every project this session has asked anything about, which is what the
		// choices cache holds. A project switched away from is included, and that
		// is 0427's promise rather than an oversight: its servers are deliberately
		// still running, so they are servers this can be wrong about.
		for path in serverChoices.keys.sorted() {
			reconsider(URL(fileURLWithPath: path, isDirectory: true), after: change)
		}
	}

	private func reconsider(_ project: URL, after change: ToolPreferences.Change) {
		let path = project.standardizedFileURL.path
		let wasChoosing = choices(for: project)
		let wasFrom = images(for: project)
		// Read again, both of them, and from the project's file as well as from
		// settings: what is in force is the two merged, and only one half is known
		// to have moved.
		serverChoices.removeValue(forKey: path)
		toolImages.removeValue(forKey: path)

		let decision = ServerReconsideration(
			change: change,
			project: project,
			was: wasChoosing,
			wasFrom: wasFrom,
			now: choices(for: project),
			nowFrom: images(for: project),
			running: Set(servers.keys),
			inDevContainer: usesDevContainer(project)
		)
		guard !decision.isEmpty else { return }

		// Stopped first, and through the same call the list of running servers
		// uses, so a server that is no longer the one being asked for goes the way
		// a server stopped by hand goes: the protocol's own shutdown, the process,
		// the container if it had one, and the documents it held forgotten.
		//
		// **Stopping it is the disruptive reading and it is the right one.** A
		// project holds one server per language and no more, because two answering
		// over one file is two sets of diagnostics with no rule for which wins; and
		// what the old one goes on publishing is a toolchain the project no longer
		// uses, which is the fault 0432 is about. jdtls's import is minutes and
		// those minutes are the cost of the choice that was just made, paid now,
		// while somebody is looking at the thing they changed — rather than at some
		// later moment they cannot connect to it.
		for key in decision.stop.sorted() {
			shutdown(server: key, because: "because a preference changed")
		}

		// And the debugger's own jdtls, if the project has just asked for a server
		// that hosts the adapter itself. It is then a second JVM importing the same
		// reactor for an answer the editing server is about to have, and the next
		// Debug would go through that one — so what this leaves running is a
		// gigabyte or two of nothing.
		//
		// Only in that direction. A project that has just moved *away* from jdtls
		// keeps its debug host, because it is what debugging goes through now.
		let hostKey = Self.debugHostKey(project: project)
		if debugHosts[hostKey] != nil,
		   LanguageServers.definition(
		   	forLanguage: "java", choosing: choices(for: project)
		   )?.hostsDebugAdapter == true {
			shutdown(
				server: hostKey,
				because: "because the project's own Java server now hosts the debugger"
			)
		}

		for key in decision.forget {
			unavailable.remove(key)
			missingHints.removeValue(forKey: key)
			lastStandardError.removeValue(forKey: key)
			refused.remove(key)
			// **Where 0461 meets 0460.** A server that is running and cannot read
			// the project is exactly the state somebody fixes by choosing another
			// image, another server or a runtime that works — and what it said
			// was said about a toolchain that is no longer the one being asked
			// for. Left behind, the strip would go on reporting a refusal from a
			// server that has since been replaced.
			health.removeValue(forKey: key)
			preparing.remove(key)
			// An image still on its way, for an answer that has been replaced. The
			// fetch itself is left to finish — the image is worth having on the
			// machine either way — but taking the key out is what makes it stop at
			// the guard it already has and not start a server nobody asked for.
			fetching.remove(key)
			deferredOpens.removeValue(forKey: key)
		}
		// Said out loud again if it happens again, which is what `shutdown(project:)`
		// does for the same reason.
		announced.removeAll()

		log("\(project.lastPathComponent): a preference changed — "
			+ "\(decision.forget.count) server(s) reconsidered, "
			+ "\(decision.stop.count) stopped")

		warmUp(project: project)
		// The files already open have to be announced to whatever answers for them
		// now: a server that was stopped forgot them, and one that has just started
		// never knew. Nothing here can reach the text — the editor groups hold it —
		// which is what this notification is for.
		NotificationCenter.default.post(name: .ideaiLanguageServersMoved, object: project)
	}
}
