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

	private struct Warm: Sendable {
		let name: String
		let port: Int
		let runtime: ContainerRuntime
		var lastUsed: Date
	}

	/// One per image, since two projects naming different versions of PlantUML
	/// must not be drawn by the same one.
	private var warm: [String: Warm] = [:]
	/// The start already under way for an image, so that two renders asking at
	/// once wait on one container rather than starting two.
	private var beingStarted: [String: Task<Warm?, Never>] = [:]
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

	public init() {}

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
	public static func startCommand(
		image: String, name: String, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		(runtime.path, [
			"run", "-d", "--rm", "--name", name,
			"-p", "127.0.0.1::\(containerPort)",
			image, "--http-server:\(containerPort)",
		])
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
		format: PlantUML.Format = .png
	) async -> Data? {
		guard let drawing = await draw(source, image: image, using: runtime, format: format) else {
			return nil
		}
		// A picture of an error is a picture, and the preview shows it — but it
		// is drawn the old way, as it always has been, rather than being a new
		// thing this route started returning. `draw` is where the complaint is
		// wanted.
		return drawing.fault == nil ? drawing.data : nil
	}

	/// The picture and the complaint, from a server kept warm — or nil, meaning
	/// draw it the old way.
	public func draw(
		_ source: String,
		image: String,
		using runtime: ContainerRuntime,
		format: PlantUML.Format = .png
	) async -> Drawing? {
		guard Self.canKeepWarm(runtime), !image.isEmpty else { return nil }
		guard Self.path(for: source, format: format) != nil else { return nil }

		if let existing = warm[image] {
			if let drawn = await fetch(source, format: format, from: existing, starting: false) {
				touch(image)
				return drawn
			}
			// It was there and it is not answering: killed behind our back, or
			// wedged. Forget it, remove whatever is left of it, and try once with
			// a new one — a preview that goes slow for ever because a container
			// was removed once would be its own bug.
			forget(image)
		}

		guard let started = await starting(image: image, using: runtime) else { return nil }
		// It may have become the kept one while this was waiting — two panes
		// opening together ask at the same moment — in which case that one is
		// asked and this one is not started twice.
		guard let drawn = await fetch(source, format: format, from: started, starting: true) else {
			// It started and would not draw. Nothing is kept, so the next render
			// tries again from nothing rather than asking a broken server twice.
			if warm[image]?.name != started.name {
				ToolContainers.shared.releaseInBackground(started.name)
			}
			return nil
		}
		warm[image] = started
		touch(image)
		startReaping()
		return drawn
	}

	/// Removes every server this has kept, now.
	///
	/// For a test, and for anybody who wants the JVM gone without waiting out
	/// the idle timeout. The app going does not need it — every container is
	/// registered with `ToolContainers`, which the app's exit already empties.
	public func stopAll() {
		for (image, _) in warm { forget(image) }
		reaper?.cancel()
		reaper = nil
	}

	/// Which images have a server up, for a test.
	public var images: [String] { warm.keys.sorted() }

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
	private func starting(image: String, using runtime: ContainerRuntime) async -> Warm? {
		if let already = beingStarted[image] { return await already.value }
		let task = Task { await start(image: image, using: runtime) }
		beingStarted[image] = task
		let started = await task.value
		beingStarted[image] = nil
		return started
	}

	/// Starts one, off the actor.
	///
	/// Everything here waits on a subprocess, and a thread from the cooperative
	/// pool is not the thread to wait on one with: a few seconds of `docker run`
	/// held there is a few seconds every other task in the app spends behind it.
	private func start(image: String, using runtime: ContainerRuntime) async -> Warm? {
		let name = ToolContainers.mint("plantuml-server")
		let startCommand = Self.startCommand(image: image, name: name, using: runtime)
		let portCommand = Self.portCommand(name: name, using: runtime)

		return await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				// Claimed rather than merely registered: this is the one container
				// of ours meant to outlive the render that asked for it, so it is
				// also the one whose name is worth being certain is free.
				ToolContainers.shared.claim(name, runtime: runtime)

				let started = RuntimeCommand.run(startCommand, deadline: Self.startDeadline)
				guard started.succeeded else {
					// A port already taken, a daemon not running, an image that is
					// not there: all of them end here, and all of them mean the
					// same thing to the caller. Whatever was made of it is removed.
					ToolContainers.shared.releaseInBackground(name)
					continuation.resume(returning: nil)
					return
				}

				let published = RuntimeCommand.run(portCommand, deadline: 20)
				guard published.succeeded, let port = Self.port(from: published.output) else {
					ToolContainers.shared.releaseInBackground(name)
					continuation.resume(returning: nil)
					return
				}
				continuation.resume(
					returning: Warm(name: name, port: port, runtime: runtime, lastUsed: Date())
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
	) async -> Drawing? {
		guard let url = Self.url(port: server.port, source: source, format: format) else {
			return nil
		}
		let deadline = Date().addingTimeInterval(Self.startDeadline)
		while true {
			do {
				let (data, response) = try await session.data(from: url)
				guard let http = response as? HTTPURLResponse, !data.isEmpty else { return nil }
				if http.statusCode == 200 { return Drawing(data: data, fault: nil) }
				// A diagram it could not parse: 400, a picture of the complaint,
				// and the complaint itself in headers. Anything else with a 400 —
				// a request this does not know how to make — is not a drawing at
				// all, and the caller falls back rather than being told a wrong
				// thing about the diagram.
				guard let fault = DiagramFault(
					errorHeader: http.value(forHTTPHeaderField: Self.errorHeader),
					lineHeader: http.value(forHTTPHeaderField: Self.errorLineHeader)
				) else { return nil }
				return Drawing(data: data, fault: fault)
			} catch {
				let code = (error as NSError).code
				guard starting, Self.stillStarting.contains(code), Date() < deadline else {
					return nil
				}
				try? await Task.sleep(nanoseconds: 200_000_000)
			}
		}
	}

	private func touch(_ image: String) {
		warm[image]?.lastUsed = Date()
	}

	private func forget(_ image: String) {
		guard let server = warm.removeValue(forKey: image) else { return }
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
		for (image, server) in warm where server.lastUsed < cutoff {
			forget(image)
		}
		return !warm.isEmpty
	}

	private func stoppedReaping() {
		reaper = nil
	}
}
