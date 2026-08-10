import Foundation

/// One PlantUML kept warm in a container, answering over HTTP, instead of a
/// container and a JVM for every diagram.
///
/// A preview redraws as somebody types, and every redraw was
/// `docker run --rm -i plantuml/plantuml -pipe`: two seconds, of which roughly
/// 0.8 is starting the container and 1.2 is starting the JVM and PlantUML.
/// Neither has anything to do with the diagram. The image already offers
/// `--http-server`, so one container answers every render after the first, and
/// the same diagram comes back in a twentieth of the time — byte for byte the
/// same picture.
///
/// The first request to a freshly started server costs about half a second
/// while the JIT warms, so the win appears on the *second* diagram. That is
/// also why this is worth keeping rather than starting per pane.
///
/// Three things this has to be honest about, and each is a decision:
///
///  * **It goes away when nobody is drawing.** Otherwise every project somebody
///    opens leaves a JVM resident for the rest of the day. `idleTimeout`.
///  * **It is docker only, and the reason has changed.** It used to be that a
///    kept container must be removable and that verb was unproven against
///    Apple's runtime; that is proven now (0406). What keeps this docker-only is
///    that on Apple's runtime there is no address to ask. Its `-p` will not take
///    an empty host port, so there is no letting it choose one; a port it does
///    publish never reaches the host; and its containers' own addresses are
///    refused to this app with `EHOSTUNREACH`. All three are the same cause and
///    it is written out under `canKeepWarm`. On Apple's runtime this refuses,
///    and the old render draws the diagram exactly as it does today.
///  * **Anything unexpected falls back rather than fails.** A server that has
///    died, a port that is taken, a runtime that has stopped answering: the old
///    way works and is only slow, so `render` answers nil and the caller draws
///    the diagram the way it always did.
public actor PlantUMLServers {
	public static let shared = PlantUMLServers()

	/// How long a server may sit unused before it is removed.
	///
	/// Five minutes. The cost of being wrong is one 2-second render — which is
	/// what every render costs today — and the cost of being generous is a JVM
	/// resident in somebody's machine for as long as the editor is open. Five
	/// covers coming back from reading the diagram, or from a meeting's worth of
	/// interruption; a project left open all afternoon does not keep a container.
	public static let idleTimeout: TimeInterval = 300

	/// How long the server gets to answer its first request.
	///
	/// It covers pulling nothing and starting everything: the container, the
	/// JVM, and the JIT's half-second on the first diagram. Generous, because
	/// what happens when it is missed is a fall back to the slow render rather
	/// than a failure.
	///
	/// **This number is not a promise to anybody**, and 0435 turned on noticing
	/// that. Missing it is not a preview that fails: it is a preview drawn the
	/// way this app drew every preview before there was a kept server at all.
	/// Nobody is shown an error, and nothing is lost except the optimisation.
	/// So a machine so busy that `docker run` takes longer than a minute is a
	/// machine whose `-pipe` render is just as slow, and raising this would not
	/// help that person — which is why it is still sixty. What was wrong was a
	/// *test* treating a missed optimisation as a broken feature; see
	/// `patience`.
	public static let startDeadline: TimeInterval = 60

	/// How long a render may take once the server is up.
	///
	/// Warm renders are hundredths of a second. This is for the diagram that is
	/// genuinely enormous, and for the server that has stopped answering without
	/// closing its port.
	public static let requestTimeout: TimeInterval = 20

	/// The largest diagram that goes through the URL.
	///
	/// The `~h` form carries the whole source in the request line, doubled by
	/// the hex. Measured against this image: a 512 KB diagram, in a 1 MB request
	/// line, was answered with a picture — there is no ceiling worth calling
	/// one. This cap is a long way below that and a very long way above any real
	/// diagram (the largest in the examples repository is 1.3 KB), and what
	/// happens above it is the old render, which has no such limit.
	public static let sourceLimit = 256 * 1024

	/// What the image's own flag calls the port it listens on.
	private static let containerPort = 8080

	/// A picture, and what PlantUML thinks of the diagram it drew.
	///
	/// The two are not alternatives: a diagram that does not parse comes back as
	/// a picture of the complaint, with a 400 and headers saying what is wrong.
	/// A preview wants the picture — it names the line — and an export wants the
	/// complaint, so both are carried and the caller decides.
	public struct Drawing: Sendable {
		public let data: Data
		public let fault: DiagramFault?
	}

	/// What the server calls the two things it says about a diagram it could not
	/// parse. Measured against the image, not guessed.
	static let errorHeader = "X-PlantUML-Diagram-Error"
	static let errorLineHeader = "X-PlantUML-Diagram-Error-Line"

	/// Why there is no picture from a kept server.
	///
	/// Every case here still means the same thing to the app — draw the diagram
	/// the old way — so this changes nothing about what happens. What it changes
	/// is what can be *said* afterwards. `draw` used to answer nil and throw the
	/// reason away, and a nil with no reason reads as "the feature is broken"
	/// when it may mean "this machine could not start a JVM in a minute". That
	/// cost five agents a day of proving a red was not theirs (0435), because the
	/// live test required a value out of the nil and had nothing else to report.
	///
	/// Each case carries how long it waited, because that is the number that
	/// separates the two: a deadline missed by a machine under load looks
	/// entirely different from a runtime that refused in a tenth of a second.
	public enum Refusal: Error, Sendable, CustomStringConvertible {
		/// Nothing was started and nothing waited on: not docker, no image, or a
		/// diagram too large for a request line.
		case notOffered(String)
		/// The runtime would not start the container, or would not say which port
		/// it published.
		case runtimeRefused(
			command: String, waited: TimeInterval, deadline: TimeInterval,
			timedOut: Bool, said: String
		)
		/// The container is up and the port is published, and nothing behind it
		/// ever answered — all the way to `startDeadline`.
		case neverAnswered(waited: TimeInterval, deadline: TimeInterval, attempts: Int, last: String)
		/// A request that failed for a reason that is not "still starting" —
		/// including its own 20-second `requestTimeout`, which is what a server
		/// that has accepted the connection and is still thinking looks like.
		case requestFailed(waited: TimeInterval, code: Int, said: String)
		/// It answered, and what came back is not a drawing.
		case notADrawing(status: Int, bytes: Int)

		public var description: String {
			switch self {
			case let .notOffered(why):
				return "no kept server offered: \(why)"
			case let .runtimeRefused(command, waited, deadline, timedOut, said):
				let how = timedOut ? "hit its \(Self.seconds(deadline)) deadline" : "failed"
				return "`\(command)` \(how) after \(Self.seconds(waited)): \(Self.trimmed(said))"
			case let .neverAnswered(waited, deadline, attempts, last):
				return "the server never answered in \(Self.seconds(waited)) "
					+ "of a \(Self.seconds(deadline)) start deadline, over \(attempts) attempts; "
					+ "last: \(Self.trimmed(last))"
			case let .requestFailed(waited, code, said):
				return "the request gave up after \(Self.seconds(waited)) "
					+ "(URL error \(code)): \(Self.trimmed(said))"
			case let .notADrawing(status, bytes):
				return "answered \(status) with \(bytes) bytes, which is not a drawing"
			}
		}

		/// Whether this is a machine that could not keep up rather than anything
		/// wrong with the feature.
		///
		/// Deliberately narrow: only the two cases that are a deadline expiring
		/// with nothing else said. A runtime that answered "no such image" in a
		/// tenth of a second is not busy, and a 400 is not busy either.
		public var isMissedDeadline: Bool {
			switch self {
			case .runtimeRefused(_, _, _, let timedOut, _): return timedOut
			case .neverAnswered: return true
			case .requestFailed(_, let code, _): return code == NSURLErrorTimedOut
			case .notOffered, .notADrawing: return false
			}
		}

		private static func seconds(_ interval: TimeInterval) -> String {
			String(format: "%.1f s", interval)
		}

		/// Enough of what a runtime said to know what happened, on one line.
		private static func trimmed(_ said: String) -> String {
			let one = said.split(whereSeparator: \.isNewline).joined(separator: " ")
				.trimmingCharacters(in: .whitespaces)
			if one.isEmpty { return "(said nothing)" }
			return one.count <= 200 ? one : String(one.prefix(200)) + "…"
		}
	}

	private struct Warm: Sendable {
		let name: String
		let image: String
		let port: Int
		let runtime: ContainerRuntime
		var lastUsed: Date
	}

	/// One per image *and per theme*, since two projects naming different
	/// versions of PlantUML must not be drawn by the same one — and since a
	/// server's theme is fixed when it starts.
	///
	/// That second half is a fact about PlantUML rather than a choice, and it was
	/// measured before this was designed: the render route
	/// `/plantuml/<format>/~h<hex>` carries the source and nothing else, so there
	/// is no asking one server for a dark picture. `--dark-mode` is a flag on the
	/// process, so a dark picture means a process started with it.
	///
	/// The alternative was to inject `!theme <something dark>` into the copy of
	/// the source sent over, which would need no second container — and it was
	/// not taken. It would mean *choosing a palette* for somebody out of the
	/// forty PlantUML ships, which is a much larger thing than "draw this dark",
	/// and it would make the warm route draw a different picture from the `-pipe`
	/// route beside it, which is the fault the shared `previewFormat` exists to
	/// avoid. Nothing of anybody's diagram is rewritten anywhere, and what it
	/// costs is at most one extra JVM for five minutes after somebody has drawn
	/// both ways.
	private var warm: [String: Warm] = [:]
	/// The start already under way for a key, so that two renders asking at once
	/// wait on one container rather than starting two.
	private var beingStarted: [String: Task<Result<Warm, Refusal>, Never>] = [:]
	private var reaper: Task<Void, Never>?

	/// Its own session, so a diagram is never answered out of the shared URL
	/// cache and nothing of this is written to anybody's disk.
	private let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
		configuration.timeoutIntervalForRequest = PlantUMLServers.requestTimeout
		configuration.urlCache = nil
		return URLSession(configuration: configuration)
	}()

	/// How long *this* one waits for a server to start.
	///
	/// The app's is `startDeadline`, and that is the default. It is separable
	/// because a live test and the app want different things from the same
	/// number, which is the judgement 0435 asked for:
	///
	/// The app's sixty seconds is the point at which it stops waiting for an
	/// optimisation and draws the diagram the way it always did. A live test
	/// whose subject is "the second diagram is the same picture" wants the
	/// optimisation to have happened at all, so that it has two pictures to
	/// compare; giving up is not an answer to its question. Inheriting the app's
	/// number meant that on a machine which could not start a container in a
	/// minute, the test reported the feature broken — when what it had actually
	/// measured was the machine.
	///
	/// So the test is allowed to be more patient than the app, and the app is
	/// left exactly as it was. Nothing about the shipped behaviour changes here;
	/// what changes is that the test no longer reports on load.
	public let patience: TimeInterval

	public init(patience: TimeInterval = PlantUMLServers.startDeadline) {
		self.patience = patience
	}

	// MARK: - What the URL and the commands look like

	/// Whether a kept server is offered for this runtime at all.
	///
	/// Docker only, still — but not for the reason it was. 0406's reason was that
	/// keeping a container alive is only defensible where killing it again is
	/// proven, and against Apple's runtime it was not. **That reason is gone:**
	/// `container rm --force` is proven, end to end, and everything else this
	/// would need — `-d`, `--rm`, `--name`, the image's `--http-server` — works
	/// there too. A server was started on Apple's runtime and drew the same 1595
	/// bytes as docker's, so the container is not the problem.
	///
	/// **What is left is that this app cannot reach it.** Three attempts, one
	/// cause:
	///
	///  * `-p 127.0.0.1::8080` is rejected outright — `invalid publish host
	///    port` — so there is no asking the runtime to choose a free one, which
	///    is the only form that is safe against a port taken between choosing and
	///    using.
	///  * A port published at a number chosen here *is* listened on, and every
	///    connection to it is accepted and then reset. The runtime's own log says
	///    why: its forwarder cannot connect to the container, `No route to host`.
	///  * The container's own address — Apple's runtime gives each one an address
	///    on `bridge100` — answers `curl` with a picture and answers this app
	///    with nothing. A plain `connect(2)` from a freshly built binary to that
	///    address returns `EHOSTUNREACH`, the same errno the runtime's forwarder
	///    reports, while `curl` from an approved terminal reaches it in the same
	///    second. That is macOS's local-network privacy, and the runtime's helper
	///    is subject to it as much as this app is.
	///
	/// So the third bullet explains the second, and until something on this
	/// machine may talk to `192.168.64.0/24` there is no address for a kept
	/// server to be at. Nothing here is about PlantUML or about cleanup, and one
	/// permission would lift all of it — which is why the `apple` case stays
	/// exactly where it is.
	public static func canKeepWarm(_ runtime: ContainerRuntime) -> Bool {
		if case .docker = runtime { return true }
		return false
	}

	/// The path that asks for a diagram.
	///
	/// `~h` and the hex of the plain source. PlantUML's own compressed encoding
	/// is not needed for this — the hex form is in the server and was what every
	/// measurement here used — and it is the one that can be read off a log line
	/// and pasted into a browser.
	///
	/// Nil for a diagram too large to put in a request line, which is the
	/// caller's signal to draw it the old way.
	public static func path(for source: String, format: PlantUML.Format) -> String? {
		let bytes = Array(source.utf8)
		guard bytes.count <= sourceLimit else { return nil }
		let hex = bytes.map { String(format: "%02x", $0) }.joined()
		return "/plantuml/\(format.rawValue)/~h\(hex)"
	}

	/// The whole address, for a server on this port.
	public static func url(port: Int, source: String, format: PlantUML.Format) -> URL? {
		guard let path = path(for: source, format: format) else { return nil }
		return URL(string: "http://127.0.0.1:\(port)\(path)")
	}

	/// The command that starts one.
	///
	/// Detached, because there is nothing to talk to on standard input and a
	/// process sitting in front of it would only be another thing to keep alive.
	/// That is also exactly why the name matters: with no process to signal, the
	/// name is the only way back to it.
	///
	/// The port is published on the loopback address and chosen by the runtime —
	/// a port picked here would be a port that could be taken between choosing
	/// it and using it, and the failure that produces is a container that starts
	/// and is unreachable.
	/// - Parameter theme: fixed for the life of the server, because the render
	///   route cannot carry one. See `warm`.
	public static func startCommand(
		image: String, name: String, using runtime: ContainerRuntime,
		theme: DiagramTheme? = nil
	) -> (executable: String, arguments: [String]) {
		(runtime.path, [
			"run", "-d", "--rm", "--name", name,
			"-p", "127.0.0.1::\(containerPort)",
			image, "--http-server:\(containerPort)",
		] + PlantUML.darkFlag(theme))
	}

	/// Which kept server a request belongs to.
	static func key(image: String, theme: DiagramTheme?) -> String {
		theme?.isDark == true ? "\(image)#dark" : image
	}

	/// The command that says which port the runtime chose.
	public static func portCommand(
		name: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		(runtime.path, ["port", name, "\(containerPort)/tcp"])
	}

	/// The port out of that command's answer — `127.0.0.1:32768`, or several
	/// such lines when the runtime has published more than one address.
	public static func port(from output: String) -> Int? {
		for line in output.split(separator: "\n") {
			guard let colon = line.lastIndex(of: ":") else { continue }
			let digits = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			if let port = Int(digits), port > 0 { return port }
		}
		return nil
	}

	// MARK: - Drawing

	/// The picture, from a server kept warm — or nil, meaning draw it the old
	/// way.
	///
	/// Nil is never an error to report. Every reason for it is a reason the
	/// caller can do something about by falling back, and the fallback is what
	/// the app did until now.
	public func render(
		_ source: String,
		image: String,
		using runtime: ContainerRuntime,
		format: PlantUML.Format = .png,
		theme: DiagramTheme? = nil
	) async -> Data? {
		guard case let .success(drawing) = await draw(
			source, image: image, using: runtime, format: format, theme: theme
		) else {
			return nil
		}
		// A picture of an error is a picture, and the preview shows it — but it
		// is drawn the old way, as it always has been, rather than being a new
		// thing this route started returning. `draw` is where the complaint is
		// wanted.
		return drawing.fault == nil ? drawing.data : nil
	}

	/// The picture and the complaint, from a server kept warm — or the reason
	/// there is none, which is always a reason to draw it the old way.
	///
	/// A failure here is never worth putting in front of somebody: the fallback
	/// works and is only slow. It is worth *keeping*, which is why this answers a
	/// `Result` rather than nil. See `Refusal`.
	public func draw(
		_ source: String,
		image: String,
		using runtime: ContainerRuntime,
		format: PlantUML.Format = .png,
		theme: DiagramTheme? = nil
	) async -> Result<Drawing, Refusal> {
		guard Self.canKeepWarm(runtime) else {
			return .failure(.notOffered("\(runtime.name) has no address this app can reach"))
		}
		guard !image.isEmpty else { return .failure(.notOffered("no image named")) }
		guard Self.path(for: source, format: format) != nil else {
			return .failure(.notOffered(
				"\(Array(source.utf8).count) bytes is more than a request line holds"
			))
		}
		let key = Self.key(image: image, theme: theme)

		if let existing = warm[key] {
			if case let .success(drawn) = await fetch(
				source, format: format, from: existing, starting: false
			) {
				touch(key)
				return .success(drawn)
			}
			// It was there and it is not answering: killed behind our back, or
			// wedged. Forget it, remove whatever is left of it, and try once with
			// a new one — a preview that goes slow for ever because a container
			// was removed once would be its own bug. The reason kept is the new
			// one's: this one has already been acted on.
			forget(key)
		}

		let started: Warm
		switch await starting(key: key, image: image, using: runtime, theme: theme) {
		case let .success(server): started = server
		case let .failure(refusal): return .failure(refusal)
		}
		// It may have become the kept one while this was waiting — two panes
		// opening together ask at the same moment — in which case that one is
		// asked and this one is not started twice.
		let drawn = await fetch(source, format: format, from: started, starting: true)
		guard case let .success(drawing) = drawn else {
			// It started and would not draw. Nothing is kept, so the next render
			// tries again from nothing rather than asking a broken server twice.
			if warm[key]?.name != started.name {
				ToolContainers.shared.releaseInBackground(started.name)
			}
			return drawn
		}
		warm[key] = started
		touch(key)
		startReaping()
		return .success(drawing)
	}

	/// Removes every server this has kept, now.
	///
	/// For a test, and for anybody who wants the JVM gone without waiting out
	/// the idle timeout. The app going does not need it — every container is
	/// registered with `ToolContainers`, which the app's exit already empties.
	public func stopAll() {
		for (key, _) in warm { forget(key) }
		reaper?.cancel()
		reaper = nil
	}

	/// Which images have a server up, for a test. One entry per image however
	/// many themes of it are warm — the theme is this type's business.
	public var images: [String] { Array(Set(warm.values.map(\.image))).sorted() }

	/// What those servers' containers are called — for a test that wants to
	/// remove one behind this actor's back, which is the failure the fallback
	/// exists for.
	public var containerNames: [String] { warm.values.map(\.name).sorted() }

	// MARK: - Keeping one

	/// One start at a time per image, however many renders ask for it.
	///
	/// A pane draws its diagram when it opens, and a project with two of them
	/// open asks twice in the same instant. Both then found no server, both
	/// started one, and the second overwrote the first — leaving a JVM nothing
	/// would ever ask anything of again until the app quit. Seen: two servers up
	/// from one launch.
	private func starting(
		key: String, image: String, using runtime: ContainerRuntime, theme: DiagramTheme?
	) async -> Result<Warm, Refusal> {
		if let already = beingStarted[key] { return await already.value }
		let task = Task { await start(image: image, using: runtime, theme: theme) }
		beingStarted[key] = task
		let started = await task.value
		beingStarted[key] = nil
		return started
	}

	/// Starts one, off the actor.
	///
	/// Everything here waits on a subprocess, and a thread from the cooperative
	/// pool is not the thread to wait on one with: a few seconds of `docker run`
	/// held there is a few seconds every other task in the app spends behind it.
	private func start(
		image: String, using runtime: ContainerRuntime, theme: DiagramTheme?
	) async -> Result<Warm, Refusal> {
		let name = ToolContainers.mint("plantuml-server")
		let startCommand = Self.startCommand(
			image: image, name: name, using: runtime, theme: theme
		)
		let portCommand = Self.portCommand(name: name, using: runtime)
		let patience = self.patience

		return await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				// Claimed rather than merely registered: this is the one container
				// of ours meant to outlive the render that asked for it, so it is
				// also the one whose name is worth being certain is free.
				ToolContainers.shared.claim(name, runtime: runtime)

				let began = Date()
				let started = RuntimeCommand.run(startCommand, deadline: patience)
				guard started.succeeded else {
					// A port already taken, a daemon not running, an image that is
					// not there: all of them end here, and all of them mean the
					// same thing to the caller. Whatever was made of it is removed.
					// They do *not* all mean the same thing to somebody reading a
					// failure afterwards, which is why the runtime's own words and
					// whether the deadline is what ended it are carried out.
					ToolContainers.shared.releaseInBackground(name)
					continuation.resume(returning: .failure(.runtimeRefused(
						command: "\(runtime.name) run",
						waited: Date().timeIntervalSince(began),
						deadline: patience,
						timedOut: started.timedOut,
						said: started.output
					)))
					return
				}

				let askedPort = Date()
				let published = RuntimeCommand.run(portCommand, deadline: 20)
				guard published.succeeded, let port = Self.port(from: published.output) else {
					ToolContainers.shared.releaseInBackground(name)
					continuation.resume(returning: .failure(.runtimeRefused(
						command: "\(runtime.name) port",
						waited: Date().timeIntervalSince(askedPort),
						deadline: 20,
						timedOut: published.timedOut,
						said: published.output
					)))
					return
				}
				continuation.resume(
					returning: .success(Warm(
						name: name, image: image, port: port, runtime: runtime, lastUsed: Date()
					))
				)
			}
		}
	}

	/// The two ways a request to a server that is still starting fails.
	///
	/// The runtime publishes the port before there is anything behind it, so the
	/// connection is *accepted* and then dropped — which arrives as "the network
	/// connection was lost" rather than as "cannot connect to host". Both mean
	/// the same thing here and neither is worth reporting: a JVM that has not
	/// finished starting. Measured, not guessed: the first is what this got every
	/// time until it was waited through.
	private static let stillStarting = [
		NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
	]

	/// Asks the server for the picture, waiting for it to come up when it has
	/// only just been started.
	///
	/// The wait is the real request rather than a health check: a JVM that is
	/// running is not yet a PlantUML that will answer, and the first diagram has
	/// to be drawn either way.
	///
	/// A server that has answered before gets exactly one attempt. Its failing is
	/// the case this is built around — somebody removed the container, or the
	/// runtime was restarted — and the answer to that is to start another one,
	/// not to spend a minute asking a port that has gone.
	private func fetch(
		_ source: String, format: PlantUML.Format, from server: Warm, starting: Bool
	) async -> Result<Drawing, Refusal> {
		guard let url = Self.url(port: server.port, source: source, format: format) else {
			return .failure(.notOffered("no address for this diagram"))
		}
		let began = Date()
		let deadline = began.addingTimeInterval(patience)
		var attempts = 0
		while true {
			attempts += 1
			do {
				let (data, response) = try await session.data(from: url)
				guard let http = response as? HTTPURLResponse else {
					return .failure(.notADrawing(status: 0, bytes: data.count))
				}
				guard !data.isEmpty else {
					return .failure(.notADrawing(status: http.statusCode, bytes: 0))
				}
				if http.statusCode == 200 { return .success(Drawing(data: data, fault: nil)) }
				// A diagram it could not parse: 400, a picture of the complaint,
				// and the complaint itself in headers. Anything else with a 400 —
				// a request this does not know how to make — is not a drawing at
				// all, and the caller falls back rather than being told a wrong
				// thing about the diagram.
				guard let fault = DiagramFault(
					errorHeader: http.value(forHTTPHeaderField: Self.errorHeader),
					lineHeader: http.value(forHTTPHeaderField: Self.errorLineHeader)
				) else {
					return .failure(.notADrawing(status: http.statusCode, bytes: data.count))
				}
				return .success(Drawing(data: data, fault: fault))
			} catch {
				let waited = Date().timeIntervalSince(began)
				let failure = error as NSError
				guard starting, Self.stillStarting.contains(failure.code) else {
					return .failure(.requestFailed(
						waited: waited, code: failure.code, said: failure.localizedDescription
					))
				}
				guard Date() < deadline else {
					return .failure(.neverAnswered(
						waited: waited, deadline: patience,
						attempts: attempts, last: failure.localizedDescription
					))
				}
				try? await Task.sleep(nanoseconds: 200_000_000)
			}
		}
	}

	private func touch(_ key: String) {
		warm[key]?.lastUsed = Date()
	}

	private func forget(_ key: String) {
		guard let server = warm.removeValue(forKey: key) else { return }
		ToolContainers.shared.releaseInBackground(server.name)
	}

	/// Removes servers nobody has drawn with for a while.
	///
	/// One task while there is anything to reap and none when there is not, so
	/// an editor with no diagram open in it is running nothing on this account.
	private func startReaping() {
		guard reaper == nil else { return }
		reaper = Task { [weak self] in
			while let self, await self.reapIdle() {
				try? await Task.sleep(nanoseconds: 30_000_000_000)
			}
			await self?.stoppedReaping()
		}
	}

	/// Removes what has gone cold, and says whether anything is left to watch.
	private func reapIdle() -> Bool {
		let cutoff = Date().addingTimeInterval(-Self.idleTimeout)
		for (key, server) in warm where server.lastUsed < cutoff {
			forget(key)
		}
		return !warm.isEmpty
	}

	private func stoppedReaping() {
		reaper = nil
	}
}
