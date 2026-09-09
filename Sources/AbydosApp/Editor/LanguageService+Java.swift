import AppKit
import AbydosKit

/// Java, which is its own file because jdtls is unlike every other server
/// here: it has to be told where to keep an index, it reports its progress in a
/// notification of its own, and it can take minutes before it will answer.
extension LanguageService {
	// MARK: - Java

	/// What went wrong on the way to a Java debug session.
	///
	/// Each case is a different thing to do about it, which is why they are
	/// separate: install a server, wait for it, or install the bundle it loads
	/// the debugger from.
	enum JavaDebugFailure: LocalizedError {
		case noServer(hint: String)
		case noBundle
		case refused(String)

		var errorDescription: String? {
			switch self {
			case let .noServer(hint):
				return "The Java language server is not running for this project, "
					+ "and it is what hosts the debugger. \(hint)"
			case .noBundle:
				return "The Java language server is running but has no debugger in it: "
					+ "the java-debug bundle was not found when it started."
			case let .refused(reason):
				return reason
			}
		}
	}

	/// Everything a Java launch needs, and it all has to come from one server.
	///
	/// The port and the classpath are two answers from the same jdtls: a port from
	/// one process and a classpath from another would start a JVM with somebody
	/// else's idea of where the classes are.
	struct JavaLaunchTarget {
		let port: Int
		let projectName: String?
		let classPaths: [String]
		/// Whether this came from a jdtls started for the debugger alone, which is
		/// what the log and the status line say — the person who chose the fast
		/// server for editing is paying for a JVM they did not ask to see, and the
		/// least that owes them is a sentence.
		let fromDebugHost: Bool
	}

	/// The port and the classpath a Java launch needs, from whichever jdtls can
	/// give them.
	///
	/// **Two ways in, and which one it is depends on what the project chose for
	/// editing.**
	///
	/// - The chosen server hosts the adapter — jdtls, the default. It is already
	///   running and has already imported the project, so this is the fast path
	///   and the one that existed before 0452.
	/// - The chosen server does not — kmp-lsp. Then jdtls is started *here*, for
	///   the debugger and nothing else, and the wait for its import is what
	///   pressing Debug costs. Which is a wait to explain rather than hide: the
	///   only alternatives were paying it at every project open for the sessions
	///   that never debug, and having no debugger at all.
	///
	/// - Parameter saying: what the wait is waiting for, every time it changes.
	func javaLaunchTarget(
		project: URL,
		anchor: URL?,
		deadline: TimeInterval = 600,
		saying: @escaping (String) -> Void = { _ in }
	) async throws -> JavaLaunchTarget {
		// Off the main actor: this type is @MainActor, and the scan reads every
		// source file in the project. Spelled out rather than through `??`,
		// whose autoclosure cannot carry an await.
		var chosen = anchor
		if chosen == nil {
			chosen = await JavaTooling.mainClassesOffMain(in: project).first
				.map { URL(fileURLWithPath: $0.file) }
		}
		let anchor = chosen

		// The chosen server, when it is one that hosts an adapter. Nothing starts
		// a second jdtls beside a jdtls: the one that is running has the import
		// this needs, and a second would spend the minutes again for the same
		// answer and hold a second copy of it.
		if let server = server(for: "java", project: project), server.client.isRunning,
		   server.definition.hostsDebugAdapter {
			guard JavaTooling.debugPlugin() != nil else { throw JavaDebugFailure.noBundle }
			saying("Asking \(server.definition.name) for a debug port")
			let port = try await portFromEditingServer(server)
			guard let anchor, let resolved = await classpathWaiting(
				for: anchor, project: project, deadline: deadline, saying: saying
			) else {
				throw JavaDebugFailure.refused(
					"\(server.definition.name) is running but has no classpath for this project "
						+ "yet, so there is nothing to start a JVM with. A project it is still "
						+ "importing cannot be debugged until it has finished."
				)
			}
			// An answer with nothing in it, which is a different thing from no
			// answer and was the older code's silent failure: it sent the launch
			// anyway and the JVM died with `ClassNotFoundException` on the class
			// somebody had asked for. Measured on a Tycho bundle, where this is what
			// jdtls says and goes on saying.
			guard !resolved.classPaths.isEmpty else {
				throw JavaDebugHost.Failure.noClasspath(
					project: resolved.projectName ?? project.lastPathComponent
				)
			}
			// Compiled first, for the reason `JavaDebug.buildCommand` records: a
			// classpath is a set of directories and jdtls fills them after the
			// import, so the first launch of a session can be handed a right
			// classpath with nothing in it. A no-op when nothing has changed, which
			// is the ordinary case here — this path is a project somebody has been
			// editing.
			saying("Compiling the project, so there is something on the classpath to run")
			_ = try? await server.client.executeCommand(
				JavaDebug.buildCommand, arguments: [JavaDebug.buildOptions()], timeout: 300
			)
			// **And hot code replace on, before the session exists to want it.**
			// In `AUTO` the provider inside the bundle redefines whatever this
			// server recompiles, so the swap follows the compile finishing rather
			// than this app guessing when it has. Best-effort: a server that will
			// not take the setting costs a session its swaps, where refusing to
			// start over it would cost the debugging too.
			// Logged, because a setting that silently did not take is exactly how
			// this went wrong twice already — first as a dictionary the server
			// refused, then as a JSON string with no `logLevel` in it. Whether
			// the swap is even switched on is not a thing to guess at from the
			// outside.
			let accepted = (try? await server.client.executeCommand(
				JavaDebug.settingsCommand,
				arguments: [JavaDebug.HotSwap.settings(mode: .auto)],
				timeout: 15
			)) != nil
			log("java hot code replace: asked \(server.definition.name) for AUTO — "
				+ (accepted ? "accepted" : "refused or timed out"))
			return JavaLaunchTarget(
				port: port, projectName: resolved.projectName,
				classPaths: resolved.classPaths, fromDebugHost: false
			)
		}

		// Nothing that hosts an adapter is answering about files here, so one is
		// started for the debugger alone.
		guard let anchor else {
			throw JavaDebugFailure.refused(
				"No Java source in this project names a class with a `main` method, so there is "
					+ "nothing for a classpath to be worked out about."
			)
		}
		let host = try debugHost(for: project)
		let ready = try await host.waitUntilLaunchable(
			anchor: anchor, deadline: deadline, saying: saying
		)
		// What a JVM is about to be started with, in the log. A launch that fails
		// says `ClassNotFoundException` on the class somebody asked for, which
		// names the symptom and not one thing about the cause; this is the line
		// that does. Once per session, not per keystroke.
		await host.setHotCodeReplace(.auto)
		log("java launch in \(project.lastPathComponent) from the debugger's own jdtls: "
			+ "project \(ready.projectName ?? "unnamed"), \(ready.classPaths.count) classpath "
			+ "entries, first \(ready.classPaths.first ?? "none")")
		return JavaLaunchTarget(
			port: ready.port, projectName: ready.projectName,
			classPaths: ready.classPaths, fromDebugHost: true
		)
	}

	/// Compiles this project's Java for a swap into a running JVM.
	///
	/// **The same request a launch makes, asked for a different reason.** A
	/// change on disk is not a class file until jdtls has been asked, which is
	/// what `buildCommand` is on the launch path for; a swap needs exactly that
	/// and nothing more, because the adapter is listening to the workspace and
	/// redefines what the compile writes.
	///
	/// Whichever jdtls the debugger is using answers: the editing server when it
	/// hosts the adapter, and otherwise the one started for the debugger alone.
	/// Asking the wrong one would compile into a workspace nothing is watching.
	///
	/// Returns false when there is no such server, which is the ordinary state of
	/// a project nobody is debugging — the caller asks only during a session.
	@discardableResult
	func compileJavaForSwap(project: URL, timeout: TimeInterval = 300) async -> Bool {
		if let server = server(for: "java", project: project), server.client.isRunning,
		   server.definition.hostsDebugAdapter {
			return (try? await server.client.executeCommand(
				JavaDebug.buildCommand, arguments: [JavaDebug.buildOptions()], timeout: timeout
			)) != nil
		}
		guard let host = debugHosts[Self.debugHostKey(project: project)], host.isRunning else {
			return false
		}
		return await host.buildWorkspace(timeout: timeout)
	}

	/// The debug port from a jdtls that is already answering about files.
	///
	/// Retried, because "not yet" and "never" look the same from here: a server
	/// that is still importing refuses, and a few seconds later the same call
	/// succeeds. Pressing Debug the moment a project opens is exactly when that
	/// happens.
	private func portFromEditingServer(_ server: Server) async throws -> Int {
		var lastError: Error?
		for attempt in 0..<5 {
			if attempt > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
			do {
				let result = try await server.client.executeCommand(
					JavaDebug.startCommand, timeout: JavaDebug.queryTimeout
				)
				// The port comes back as a number, and which flavour of number
				// depends on the JSON decoder's mood.
				if let port = result as? Int { return port }
				if let port = result as? NSNumber { return port.intValue }
				lastError = JavaDebugFailure.refused("The language server started no debug session.")
			} catch {
				lastError = error
				log("java debug session refused (attempt \(attempt + 1)): \(error.localizedDescription)")
			}
		}
		throw JavaDebugFailure.refused(
			"The Java language server would not start a debug session: "
				+ "\(lastError?.localizedDescription ?? "no reason given"). A project it is still "
				+ "importing cannot be debugged yet — the status bar says when it has finished."
		)
	}

	/// The jdtls this project debugs through, started if it is not up.
	///
	/// Filed under a key of its own so the list of what is running has a row for
	/// it and Stop reaches it. It is a JVM holding gigabytes that nobody chose,
	/// and a process this app started and cannot be seen is exactly what 0427 was
	/// about.
	private func debugHost(for project: URL) throws -> JavaDebugHost {
		let key = Self.debugHostKey(project: project)
		if let existing = debugHosts[key] {
			if existing.isRunning { return existing }
			debugHosts.removeValue(forKey: key)
		}
		let host = try JavaDebugHost.start(
			project: project,
			// A project worked on inside its devcontainer is refused rather than
			// given a jdtls out here. That was already true before this existed —
			// `initializationOptions` offers no bundle to a containerised server —
			// and it is now a sentence rather than a silence.
			inDevContainer: devContainerNameHoldingServers(for: project)
		)
		debugHosts[key] = host
		log("jdtls started for the debugger alone in \(project.lastPathComponent): "
			+ "the server answering about files does not host an adapter")
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)

		Task { @MainActor in
			do {
				try await host.handshake()
			} catch {
				log("the debugger's jdtls would not shake hands: \(error.localizedDescription)")
			}
		}
		return host
	}

	/// The devcontainer a project's language servers live inside, when they do.
	///
	/// Asked by the debugger, which cannot follow them in there: the java-debug
	/// bundle is a path on this machine and the JVM would be this machine's, so
	/// what got debugged would be a different toolchain from what the project
	/// builds with.
	func devContainerNameHoldingServers(for project: URL) -> String? {
		guard usesDevContainer(project) else { return nil }
		return devcontainers[project]?.session.name ?? "its devcontainer"
	}

	/// The key a debug host is filed under.
	///
	/// The server's name with what it is here for beside it, so a row in the list
	/// of what is running says why there is a second jdtls — and so it can never
	/// collide with the key the *editing* jdtls would hold for the same project.
	static func debugHostKey(project: URL) -> String {
		LanguageServers.serverKey(project: project, server: "jdtls (debugger)")
	}

	/// The runtime classpath of the project a file belongs to.
	///
	/// Java cannot be started without one and nothing but the build knows it,
	/// which is why this asks the server that read the build file rather than
	/// guessing from `target/` and `build/`.
	///
	/// **An answer about another project is not an answer.** Before jdtls has
	/// imported the project it replies about `jdt.ls-java-project`, the fallback
	/// workspace it keeps inside its own `-data` directory — a well-formed
	/// classpath, for the wrong thing. Taking it starts a JVM that fails with
	/// `UnsupportedClassVersionError` or `ClassNotFoundException`, which reads as a
	/// broken project. See `JavaDebugHost.classpath(for:)`, where this was found.
	/// The classpath, waiting while the server is still working it out.
	///
	/// **One ask used to be the whole of it**, and "not yet" — which is what a
	/// large project answers for as long as it is importing — was reported as
	/// "there is nothing to start a JVM with". It recovered if somebody pressed
	/// Debug again a few minutes later, which is the shape of a wait misreported
	/// as a failure, and it left a suspended JVM behind each time.
	///
	/// The other route to a debug session — `JavaDebugHost.waitUntilLaunchable` —
	/// has waited on the same deadline with the same progress from the start. This
	/// is the editing-server route catching up, so which of the two you get no
	/// longer decides whether Debug can work on a big repository.
	///
	/// Says what it is waiting for, every few seconds: an import of a thousand
	/// modules is minutes of nothing on screen otherwise, and "still importing" is
	/// the difference between a wait somebody will sit through and a hang they
	/// will kill.
	private func classpathWaiting(
		for anchor: URL,
		project: URL,
		deadline: TimeInterval,
		saying: @escaping (String) -> Void
	) async -> (projectName: String?, classPaths: [String])? {
		let started = Date()
		while true {
			if let resolved = await javaClasspath(for: anchor, project: project),
			   !resolved.classPaths.isEmpty {
				return resolved
			}
			let waited = Int(Date().timeIntervalSince(started))
			guard Double(waited) < deadline else { return nil }

			// The server's own state rather than a guess: "importing" is a wait
			// with an end, and anything else is a server that answered "no
			// classpath" and will go on answering it.
			let importing = isPreparing(languageId: "java", project: project)
			saying(
				importing
					? "Waiting for the classpath — jdtls is still importing, \(waited) s"
					: "Waiting for the classpath — \(waited) s"
			)
			// In the log as well as on screen, at a coarser interval: the status
			// line is gone the moment the launch ends, and a launch that failed
			// after four minutes of waiting is unanswerable afterwards without
			// this. Twice today it was.
			if waited > 0, waited % 15 < 3 {
				log("java classpath still unresolved after \(waited) s for "
					+ "\(project.lastPathComponent)"
					+ (importing ? " — jdtls is importing" : " — jdtls is not importing"))
			}
			try? await Task.sleep(nanoseconds: 3_000_000_000)
		}
	}

	func javaClasspath(for url: URL, project: URL) async -> (projectName: String?, classPaths: [String])? {
		guard let server = server(for: "java", project: project), server.client.isRunning else { return nil }
		do {
			let result = try await server.client.executeCommand(
				JavaDebug.classpathCommand,
				arguments: [uri(for: url), JavaDebug.classpathOptions()],
				timeout: JavaDebug.queryTimeout
			)
			guard let object = result as? [String: Any] else { return nil }
			guard let answeredFor = object["projectRoot"] as? String,
			      JavaDebugHost.isInside(answeredFor, project)
			else {
				log("java classpath for \(url.lastPathComponent) came back about "
					+ "\((object["projectRoot"] as? String) ?? "no project") rather than about "
					+ "\(project.lastPathComponent) — the import has not finished")
				return nil
			}
			let paths = object["classpaths"] as? [String] ?? []
			let modules = object["modulepaths"] as? [String] ?? []
			return (
				JavaDebugHost.projectName(fromRoot: answeredFor), paths + modules
			)
		} catch {
			log("java classpath unavailable for \(url.lastPathComponent): \(error.localizedDescription)")
			return nil
		}
	}

	/// How far the Java server is from being able to *launch* something, as
	/// against being able to answer about a file.
	///
	/// 0452's central measurement, and a probe of its own rather than
	/// `startJavaDebugAdapter` because that one retries five times over eight
	/// seconds — the right thing when somebody has pressed Debug, and ruinous
	/// when what is being timed is the moment the answer changes.
	///
	/// Two questions, because they become answerable at different moments and
	/// the distance between them is the finding. The port says java-debug is
	/// loaded and listening, which needs the bundle and nothing else. The
	/// classpath says the import has got far enough to say what a launch would
	/// *run*, and a port with an empty classpath is not a debuggable project.
	/// - Returns: the port, and what the classpath command said — `nil` for a
	///   question it did not answer, and a count for one it did. **The difference
	///   matters and cost an hour to find.** On a Tycho bundle jdtls answers
	///   `getClasspaths` promptly and with *nothing in it*, which through a
	///   `?? 0` is indistinguishable from a server that has not finished — and one
	///   of those is a wait and the other is an answer nobody should wait for.
	func javaDebugReadinessForTesting(
		url: URL, project: URL
	) async -> (port: Int?, classPaths: Int?) {
		guard let server = server(for: "java", project: project), server.client.isRunning,
		      server.definition.hostsDebugAdapter
		else { return (nil, nil) }

		var port: Int?
		if let result = try? await server.client.executeCommand(JavaDebug.startCommand) {
			port = (result as? Int) ?? (result as? NSNumber)?.intValue
		}
		return (port, await javaClasspathCount(for: url, project: project))
	}

	/// How many entries the classpath command answered with, or nil when it did
	/// not answer at all.
	private func javaClasspathCount(for url: URL, project: URL) async -> Int? {
		guard let server = server(for: "java", project: project), server.client.isRunning,
		      let result = try? await server.client.executeCommand(
		      	JavaDebug.classpathCommand,
		      	arguments: [uri(for: url), JavaDebug.classpathOptions()]
		      ),
		      let object = result as? [String: Any]
		else { return nil }
		return (object["classpaths"] as? [String] ?? []).count
			+ (object["modulepaths"] as? [String] ?? []).count
	}
}
