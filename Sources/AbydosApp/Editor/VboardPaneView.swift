import AbydosKit
import AppKit
import AuthenticationServices
import WebKit

/// A `.vboard` file open as a board, in vboard's own page, on the server named
/// in the settings.
///
/// The file is put on a private temporary board with a key made for this tab,
/// the page is shown, and whatever happens on the board — from this tab or
/// from colleagues given its link — is this tab's unsaved change until ⌘S
/// writes the board back into the file. Closing ends the session.
///
/// Nothing of vboard is in this app. The page comes from the server, the calls
/// are its documented `/api/v1`, and with no server named the tab says so and
/// offers the file as text, which is how a `.vboard` opened before.
///
/// The pieces it is made of, and where each decision is written down:
///
///  * `VboardDocument` — which board, its key, dirty as a count, the save
///    through a temporary, and putting a changed file back.
///  * `VboardClient` — the calls, with the key in a header and the web view's
///    session as cookies.
///  * `VboardPage` — the script that watches the page's own socket, so the tab
///    knows about changes and people without being a participant itself.
@MainActor
final class VboardPaneView: NSView {
	/// The tab's edited dot has something to say.
	var onDirtyChanged: (() -> Void)?
	/// *Open as Text*: the tab is to be replaced by the file opened the
	/// ordinary way.
	var onOpenAsText: (() -> Void)?
	/// What the status bar says for this tab has changed.
	var onStatusChanged: (() -> Void)?
	/// Where the board is, what that means and who else is on it, for the
	/// status bar in place of a line and column. Nil while there is no board.
	private(set) var statusText: String?

	let fileURL: URL
	private(set) var document: VboardDocument?
	var isDirty: Bool { document?.isDirty ?? false }

	private enum State: Equatable {
		/// A provisional or restored tab: nothing sent until somebody asks.
		case waiting
		case notice
		case connecting
		case signingIn
		case uploading
		case onBoard
		/// The board is gone from the server; the tab stays to say so.
		case ended
	}

	private var state: State = .notice
	private var server: URL?
	private var isPlainOverNetwork = false
	private var people = 0
	private var heardDeleted = false
	/// The session ended on purpose: by closing, or by leaving it running for
	/// colleagues. Either way the tab's teardown must not delete it again.
	private var settled = false
	/// The file changed on disk while the board had unsaved changes. Said once
	/// in the status bar and left there, as a text tab leaves such a file alone.
	private var noticedChangeOnDisk = false
	private var said = ""

	private var web: WKWebView?
	private var relay: Relay?
	private var proxy: VboardProxy?
	private var signIn: ASWebAuthenticationSession?
	/// `ABYDOS_VBOARD_TRACE=1`: when each step of opening a board happened, and
	/// every request the proxy forwards, on standard error. For "this page takes
	/// long" (2026-10-23), which a guess could not answer.
	private static let tracing = ProcessInfo.processInfo.environment["ABYDOS_VBOARD_TRACE"] == "1"
	private var traceStart = Date()
	private func trace(_ step: String) {
		guard Self.tracing else { return }
		FileHandle.standardError.write(Data(String(format: "BOARD %7.3f s  %@\n", Date().timeIntervalSince(traceStart), step).utf8))
	}
	private var watchingSettings: NSObjectProtocol?
	/// Renews the board's lease while the tab is open: a session board whose
	/// lease runs out is deleted two hours after the last person leaves.
	private var leaseTimer: Timer?
	private let credentials = KeychainVboardCredentials.shared

	private let noticeTitle = NSTextField(labelWithString: "")
	private let noticeDetail = NSTextField(wrappingLabelWithString: "")
	private let noticeButtons = NSStackView()
	private let notice = NSStackView()

	/// - Parameter start: whether to go to the server straight away. Not for a
	///   provisional tab, which is what arrowing through a folder makes, and
	///   not for a tab coming back with a session: either would upload files
	///   nobody asked to open.
	init(url: URL, start: Bool) {
		fileURL = url
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		decide(start: start)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: Deciding where the file goes

	private func decide(start: Bool) {
		if DrivenRun.isActive {
			// A capture that depended on a server would differ by machine, and a
			// scratch file sent to the team's real server is the kind of mistake
			// the house rules exist for.
			show(
				"A driven run does not reach a vboard server",
				detail: "A .vboard opens as a board on the server named in Settings ▸ Tools ▸ vboard, "
					+ "and never on a driven run.",
				text: true
			)
			return
		}
		switch VboardServerAddress(Settings.shared.vboardServer) {
		case .none:
			show(
				"Opening this as a board needs a vboard server",
				detail: "Name one in Settings ▸ Tools ▸ vboard. A file opened there is uploaded as a "
					+ "private temporary board that colleagues you give the link to can work on with you.",
				text: true
			)
		case .unusable(let why):
			show("The vboard server in the settings cannot be used", detail: why, text: true)
		case .server(let url, let plain):
			server = url
			isPlainOverNetwork = plain
			let host = url.host ?? url.absoluteString
			switch VboardFile.inspect(fileURL) {
			case .encrypted:
				show(
					"An encrypted board file cannot be opened as a board",
					detail: "It was exported with “keep encrypted”, and only the key of the board it came "
						+ "from opens it. Nothing was sent to \(host).",
					text: true
				)
			case .notABoard:
				show("This is not a vboard board file", detail: "Nothing was sent to \(host).", text: true)
			case .tooLarge(let bytes):
				show(
					"This file is larger than a vboard server takes",
					detail: "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), and "
						+ "vboard imports up to 700 MB. Nothing was sent to \(host).",
					text: false
				)
			case .board, .empty:
				if start {
					connect()
				} else {
					state = .waiting
					show(
						"Open \(fileURL.lastPathComponent) as a board on \(host)?",
						detail: "Opening uploads it there as a private temporary board, encrypted with a key "
							+ "made for this tab. Closing the tab removes it again.",
						buttons: [("Open on \(host)", "rectangle.on.rectangle", { [weak self] in self?.connect() })],
						text: true,
						keepState: true
					)
				}
			}
		}
	}

	/// Starts a tab that was waiting, because somebody committed to it.
	func startIfWaiting() {
		if state == .waiting { connect() }
	}

	// MARK: Getting onto a board

	private func connect() {
		guard let server else { return }
		traceStart = Date()
		if Self.tracing, VboardProxy.trace == nil {
			VboardProxy.trace = { line in FileHandle.standardError.write(Data("PROXY \(line)\n".utf8)) }
		}
		trace("connecting")
		state = .connecting
		show("Connecting to \(server.host ?? "the server")…", detail: "", text: false, keepState: true)
		if web == nil { makeWebView() }
		Task { await choosePath() }
	}

	/// Direct when the server needs nobody signed in; otherwise through the
	/// proxy, with the token kept from the last sign-in or a new one from the
	/// system's sheet.
	///
	/// Asked before anything is uploaded, because an import made while signed
	/// out sends the whole file only to be told 401 at the end.
	private func choosePath() async {
		guard let server else { return }
		let open = VboardClient(server: server)
		let answer = await open.signedIn()
		trace("asked whether signed in: \(answer)")
		switch answer {
		case .done:
			await begin(with: open)
		case .signedOut:
			if let kept = credentials.credential(for: server) {
				let signed = VboardClient(server: server, token: kept.token)
				switch await signed.signedIn() {
				case .done:
					await beginThroughProxy(with: signed)
					return
				case .signedOut:
					// Expired or revoked: asked for again, never retried.
					credentials.forget(for: server)
				case let outcome:
					fail(outcome)
					return
				}
			}
			askToSignIn()
		case let outcome:
			fail(outcome)
		}
	}

	private func fail(_ outcome: VboardClient.Outcome) {
		let host = server?.host ?? "The server"
		if case .unreachable(let why) = outcome {
			show(
				"\(host) cannot be reached",
				detail: why,
				buttons: [("Try Again", "arrow.clockwise", { [weak self] in self?.connect() })],
				text: true
			)
		} else {
			show("\(host) would not take the board", detail: describe(outcome), text: true)
		}
	}

	/// The page is shown through a proxy on this Mac that signs every request
	/// with the token. The tab's web view cannot sign the page's own requests,
	/// and cannot pass a login that wants a compliant device.
	private func beginThroughProxy(with client: VboardClient) async {
		guard let server, let web else { return }
		if let proxy { VboardProxies.shared.release(proxy) }
		proxy = nil
		let proxy: VboardProxy
		do {
			proxy = try await VboardProxies.shared.acquire(server: server, token: client.token)
		} catch {
			show("The board could not be shown", detail: error.localizedDescription, text: true)
			return
		}
		if let cookie = proxy.cookie() {
			await web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
		}
		if let base = proxy.base {
			let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
			installScripts(extra: [
				VboardPage.appBridge(server: server, version: version),
				VboardPage.linkRewrite(proxy: base, server: server),
			])
		}
		self.proxy = proxy
		trace("proxy at \(proxy.base?.absoluteString ?? "?")")
		await begin(with: client)
	}

	/// Puts the file on a board and shows it.
	private func begin(with client: VboardClient) async {
		guard let server, let web else { return }
		// The page starts loading now, out of sight, while the file goes up:
		// it is the slow half of opening a board, and its scripts are then in
		// the cache when the board is ready. Reported on 2026-10-23 as "a bit
		// slow to open the document".
		web.load(URLRequest(url: page(server)))
		let document = VboardDocument(url: fileURL, client: client)
		document.onDirtyChanged = { [weak self] in self?.onDirtyChanged?() }
		self.document = document
		state = .uploading
		show("Uploading \(fileURL.lastPathComponent)…", detail: sizeLine(), text: false, keepState: true)
		let opened = await document.open { [weak self] fraction in
			Task { @MainActor in self?.uploadProgressed(fraction) }
		}
		trace("file on the board: \(opened)")
		switch opened {
		case .onBoard:
			showBoard()
		case .failed(.signedOut):
			credentials.forget(for: server)
			askToSignIn()
		case .failed(let outcome):
			fail(outcome)
		case .refusedFile:
			// Decided before connecting; a file that changed kind in between is
			// decided again.
			decide(start: false)
		}
	}

	/// Where the web view finds an address of the server: through the proxy
	/// when there is one.
	private func page(_ url: URL) -> URL { proxy?.local(url) ?? url }

	// MARK: Signing in

	/// The server's login, in the system's sign-in sheet rather than the tab.
	///
	/// Entra ID with Conditional Access wants a compliant device, and the proof
	/// of one comes from Apple's Enterprise SSO extension, which answers for the
	/// system's sheet and not for a web view inside an app. Seen on 2026-10-23
	/// as "Set up your device to get access" in place of the board.
	private func askToSignIn() {
		guard let server else { return }
		state = .signingIn
		show(
			"Sign in to \(server.host ?? "the server")",
			detail: "The server's own login opens in the system's sign-in window, where this Mac can prove "
				+ "it is allowed in. You stay signed in for the next board.",
			buttons: [("Sign In", "person.badge.key", { [weak self] in self?.presentSignIn() })],
			text: true,
			keepState: true
		)
		presentSignIn()
	}

	private func presentSignIn() {
		guard let server, signIn == nil else { return }
		let device = "Abydos on \(Host.current().localizedName ?? "this Mac")"
		let session = ASWebAuthenticationSession(
			url: VboardSignIn.url(server: server, device: device),
			callbackURLScheme: VboardSignIn.callbackScheme
		) { [weak self] callback, error in
			DispatchQueue.main.async { self?.signInEnded(callback: callback, error: error) }
		}
		session.presentationContextProvider = self
		// Not ephemeral: the sheet shares Safari's sign-in, so somebody already
		// signed in there is not asked again.
		session.prefersEphemeralWebBrowserSession = false
		signIn = session
		if !session.start() {
			signIn = nil
			show("The sign-in window would not open", detail: "", text: true)
		}
	}

	private func signInEnded(callback: URL?, error: Error?) {
		signIn = nil
		guard let server, state == .signingIn else { return }
		if let callback, let credential = VboardSignIn.credential(from: callback) {
			credentials.keep(credential, for: server)
			state = .connecting
			show("Signed in. Connecting…", detail: "", text: false, keepState: true)
			Task { await beginThroughProxy(with: VboardClient(server: server, token: credential.token)) }
			return
		}
		if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
			show(
				"Sign-in was cancelled",
				detail: "The board opens once you have signed in to \(server.host ?? "the server").",
				buttons: [("Sign In", "person.badge.key", { [weak self] in self?.askToSignIn() })],
				text: true,
				keepState: true
			)
			return
		}
		show("Signing in did not work", detail: error?.localizedDescription ?? "No token came back.", text: true)
	}

	/// Loads the board, and shows it once the page says its board has loaded.
	///
	/// Not before: a page that has not drawn yet is a white rectangle, which in
	/// a dark editor stood on screen for most of the thirteen seconds a board
	/// took to open on 2026-10-23. The page's socket says when the board is
	/// there; a page that never says so is shown anyway after a while, so a
	/// socket that cannot connect is a page with its own error on it rather
	/// than a notice that never goes.
	private func showBoard() {
		guard let web, let document else { return }
		state = .onBoard
		show("Opening the board…", detail: "", text: false, keepState: true)
		web.load(URLRequest(url: page(document.link)))
		say("")
		leaseTimer?.invalidate()
		leaseTimer = Timer.scheduledTimer(
			withTimeInterval: TimeInterval(VboardDocument.leaseSeconds) / 3, repeats: true
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let document = self?.document else { return }
				Task { await document.renewLease() }
			}
		}
		let shown = document.boardID
		DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
			guard let self, self.document?.boardID == shown else { return }
			self.reveal()
		}
	}

	private func reveal() {
		guard state == .onBoard, let web, web.isHidden else { return }
		hideNotice()
		web.isHidden = false
	}

	private func uploadProgressed(_ fraction: Double) {
		guard state == .uploading else { return }
		let percent = Int((fraction * 100).rounded())
		noticeDetail.stringValue = "\(sizeLine())  ·  \(percent) %"
	}

	private func sizeLine() -> String {
		let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		return size == 0 ? "A new board" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
	}

	private func describe(_ outcome: VboardClient.Outcome) -> String {
		switch outcome {
		case .failed(let status, let message): return "\(message) (\(status))"
		case .unreachable(let why): return why
		case .gone: return "The server answered that there is no such board."
		case .refused: return "The server refused the board id twice."
		case .signedOut: return "The server wants somebody signed in."
		case .created, .replaced, .done: return ""
		}
	}

	// MARK: The page

	/// The server's own store, shared by its board tabs and kept between them:
	/// a store made new for every board fetched the whole web app each time,
	/// which was part of the thirteen seconds a board took to open. No session
	/// lives in it — the proxy's token, or no login at all, is the session.
	private func makeWebView() {
		guard let server else { return }
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: VboardPage.dataStoreID(for: server))
		let controller = WKUserContentController()
		let relay = Relay(self)
		controller.add(relay, name: VboardPage.handlerName)
		self.relay = relay
		configuration.userContentController = controller
		let web = WKWebView(frame: .zero, configuration: configuration)
		self.web = web
		installScripts(extra: [])
		applyTheme()
		watchingSettings = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.applyTheme() }
		}
		web.navigationDelegate = self
		web.uiDelegate = self
		web.allowsBackForwardNavigationGestures = false
		web.isHidden = true
		web.translatesAutoresizingMaskIntoConstraints = false
		addSubview(web, positioned: .below, relativeTo: notice)
		NSLayoutConstraint.activate([
			web.leadingAnchor.constraint(equalTo: leadingAnchor),
			web.trailingAnchor.constraint(equalTo: trailingAnchor),
			web.topAnchor.constraint(equalTo: topAnchor),
			web.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	/// The page's scripts, put in again whenever the proxy's address is new.
	private func installScripts(extra: [String]) {
		guard let controller = web?.configuration.userContentController else { return }
		extraScripts = extra
		controller.removeAllUserScripts()
		for source in [VboardPage.socketWatcher, VboardPage.noServiceWorker] + extra {
			controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
		}
		if let themeScript { controller.addUserScript(themeScript) }
	}

	private var extraScripts: [String] = []
	private var themeScript: WKUserScript?

	fileprivate func received(_ body: Any) {
		// The page's settings button, through the app bridge.
		if (body as? [String: Any])?["app"] as? String == "openSettings" {
			SettingsWindowController.shared.show()
			return
		}
		guard let document, let message = VboardPage.Message(body, board: document.boardID) else { return }
		switch message {
		case .snapshot(let count):
			trace("the page's board loaded (\(count) on it)")
			people = count
			reveal()
			refreshStatus()
		case .presence(let count):
			people = count
			refreshStatus()
		case .changed:
			document.noteChange()
		case .deleted(let reason):
			heardDeleted = true
			guard !settled else { return }
			ended(
				reason == "expired"
					? "The server removed the board because nobody was on it."
					: "Somebody deleted the board on the server."
			)
		case .replaced:
			// The page reloads by itself; vboard closes its socket to make it.
			break
		case .accessRevoked:
			ended("This account may no longer open the board.")
		}
	}

	/// The board went away underneath the tab. Its unsaved changes are kept as
	/// far as the dot is concerned, but there is nothing left to save them from.
	private func ended(_ why: String) {
		state = .ended
		web?.isHidden = true
		show(
			"The board has ended",
			detail: why + (isDirty ? " Changes made since the last save could not be written to the file." : ""),
			buttons: [("Open Again", "arrow.clockwise", { [weak self] in self?.reopen() })],
			text: true,
			keepState: true
		)
	}

	/// The file put on a new board, after the old one ended.
	private func reopen() {
		document?.forgetChanges()
		heardDeleted = false
		document = nil
		if let proxy { VboardProxies.shared.release(proxy) }
		proxy = nil
		web?.removeFromSuperview()
		web = nil
		connect()
	}

	// MARK: Saving

	/// Writes the board into the file. The server's export, through a temporary
	/// beside the file and a rename, and only what was on the board when the
	/// save began counts as saved.
	@discardableResult
	func save() async -> Bool {
		guard let document, state == .onBoard else { return !isDirty }
		say("Saving…")
		do {
			try await document.save()
			say("")
			return true
		} catch {
			say("")
			let why: String
			switch error as? VboardDocument.SaveFailure {
			case .server(let outcome): why = describe(outcome)
			case .disk(let message): why = message
			case nil: why = error.localizedDescription
			}
			Toast.post("Could not save \(fileURL.lastPathComponent)", detail: why)
			return false
		}
	}

	// MARK: The file changing on disk

	/// Somebody else may have written the file. If they did, the board is put
	/// back in step with it — unless the board has unsaved changes, which are
	/// left alone exactly as a text tab leaves a dirty buffer alone.
	func fileMayHaveChanged() {
		guard state == .onBoard, let document, document.hasChangedOnDisk else { return }
		if document.isDirty {
			guard !noticedChangeOnDisk else { return }
			noticedChangeOnDisk = true
			say("The file changed on disk. The board keeps its unsaved changes, and ⌘S writes them over it.")
			return
		}
		Task {
			switch await document.reload() {
			case .replaced:
				// Same id, same key; the page reloads by itself.
				say("The file changed on disk and the board now shows it.")
			case .reopened:
				heardDeleted = false
				web?.load(URLRequest(url: page(document.link)))
				say("The file changed on disk, so it is on a new board. The old link no longer opens it.")
			case .failed:
				ended("The file changed on disk and could not be put on a board again.")
			}
		}
	}

	// MARK: Closing

	/// Closes the board the way the close button means it, asking what has to
	/// be asked: unsaved changes first, as every tab asks, then — when anybody
	/// else is on the board — whether to end the session for them. True when
	/// the tab may go; the board itself is ended afterwards, in the background.
	///
	/// Synchronous, because closing every tab and swapping projects loop until
	/// the tabs are gone. Only a save somebody chose here is waited for, by
	/// turning the main run loop by hand with a deadline — the HTML and draw.io
	/// panes wait for `takeSnapshot` the same way — since the file has to be
	/// written before the tab goes.
	func close() -> Bool {
		guard let document, state == .onBoard || state == .ended else { return true }
		if document.isDirty, state == .onBoard {
			let alert = NSAlert()
			alert.messageText = "Save changes to \(fileURL.lastPathComponent)?"
			alert.informativeText = "Your changes will be lost if you don't save them."
			alert.addButton(withTitle: "Save")
			alert.addButton(withTitle: "Discard")
			alert.addButton(withTitle: "Cancel")
			switch alert.runModal() {
			case .alertFirstButtonReturn:
				// Ten minutes: a board with a recorded workshop on it is hundreds of
				// megabytes, and a save that gives up early leaves the tab open
				// rather than losing anything.
				guard Self.waitTurningRunLoop(seconds: 600, { await self.save() }) == true else { return false }
			case .alertSecondButtonReturn:
				break
			default:
				return false
			}
		}
		let others = max(0, people - 1)
		if others > 0, state == .onBoard {
			let alert = NSAlert()
			alert.messageText = others == 1 ? "Somebody else is on this board." : "\(others) others are on this board."
			alert.informativeText = "Closing it ends the session for them too. If you leave it running, "
				+ "edits made from now on will not reach \(fileURL.lastPathComponent)."
			alert.addButton(withTitle: "End Session")
			alert.addButton(withTitle: "Leave It Running")
			alert.addButton(withTitle: "Cancel")
			switch alert.runModal() {
			case .alertFirstButtonReturn:
				break
			case .alertSecondButtonReturn:
				settled = true
				return true
			default:
				return false
			}
		}
		// The board is ended after the tab has gone, by `tearDown`, which keeps
		// the page alive off screen until it hears the delete. Waiting for that
		// here froze the window for seconds after every close (2026-10-23): the
		// run loop turned by hand draws, but takes no clicks and no keys.
		return true
	}

	/// Runs `work` on the main actor and turns the run loop until it answers or
	/// the deadline passes. Nil when it did not answer in time.
	private static func waitTurningRunLoop<Result>(
		seconds: TimeInterval, _ work: @escaping @MainActor () async -> Result
	) -> Result? {
		var result: Result?
		var answered = false
		Task { @MainActor in
			result = await work()
			answered = true
		}
		let deadline = Date().addingTimeInterval(seconds)
		while !answered, Date() < deadline {
			RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
		}
		return result
	}

	/// Deletes the board, then waits a moment for the page to hear it.
	///
	/// The order matters. vboard's page keeps a backup of every temporary board
	/// it has open and drops it only when it hears the board was deleted; a
	/// page torn down first would offer that backup the next time anything
	/// opens this server.
	private func endSession() async {
		guard let document else { return }
		settled = true
		heardDeleted = false
		_ = await document.end()
		let deadline = Date().addingTimeInterval(2)
		while !heardDeleted, Date() < deadline {
			try? await Task.sleep(nanoseconds: 50_000_000)
		}
	}

	/// Panes whose tab has gone but whose board is still being ended. Kept
	/// alive here so the page is still there to hear the delete.
	private static var ending: Set<VboardPaneView> = []

	/// The tab is going without having been asked — its window closed, the
	/// provisional slot was reused. A board still running is ended in the
	/// background, with the page kept alive until it hears so; there is nobody
	/// left to tell if it fails, and the server's own cleanup of temporary
	/// boards collects whatever this does not.
	func tearDown() {
		guard !settled, document != nil, state == .onBoard || state == .signingIn || state == .uploading else {
			detachPage()
			return
		}
		Self.ending.insert(self)
		Task {
			await endSession()
			detachPage()
			Self.ending.remove(self)
		}
	}

	private func detachPage() {
		leaseTimer?.invalidate()
		leaseTimer = nil
		signIn?.cancel()
		signIn = nil
		if let proxy { VboardProxies.shared.release(proxy) }
		proxy = nil
		if let watchingSettings { NotificationCenter.default.removeObserver(watchingSettings) }
		watchingSettings = nil
		web?.stopLoading()
		web?.configuration.userContentController.removeScriptMessageHandler(forName: VboardPage.handlerName)
		web?.navigationDelegate = nil
		web?.uiDelegate = nil
	}

	/// The app's zoom and its light or dark look, told to the page as the HTML
	/// preview tells its page. Without them a board was drawn at the page's own
	/// size in an app somebody had scaled up — "the boards are very small" —
	/// and in the system's look rather than the editor's.
	private func applyTheme() {
		let theme = Theme.current
		layer?.backgroundColor = theme.editorBackground.cgColor
		guard let web else { return }
		web.pageZoom = theme.scale
		web.appearance = NSAppearance(named: theme.isLight ? .aqua : .darkAqua)
		// Never a white rectangle in a dark editor, around the page or before it.
		web.underPageBackgroundColor = theme.editorBackground
		let style = VboardPage.themeStyle(VboardTheme.tokens(theme))
		themeScript = WKUserScript(
			source: VboardPage.themeScript(style), injectionTime: .atDocumentEnd, forMainFrameOnly: true
		)
		installScripts(extra: extraScripts)
		web.evaluateJavaScript(VboardPage.themeScript(style))
	}

	// MARK: Layout and words

	private func build() {
		noticeTitle.font = .systemFont(ofSize: 15, weight: .semibold)
		noticeTitle.textColor = Theme.current.sidebarHeaderText
		noticeTitle.alignment = .center
		noticeTitle.lineBreakMode = .byWordWrapping
		noticeTitle.maximumNumberOfLines = 2
		noticeDetail.font = .systemFont(ofSize: 12)
		noticeDetail.textColor = Theme.current.gitIgnored
		noticeDetail.alignment = .center
		noticeDetail.isSelectable = true
		noticeButtons.orientation = .horizontal
		noticeButtons.spacing = 10

		notice.setViews([noticeTitle, noticeDetail, noticeButtons], in: .center)
		notice.orientation = .vertical
		notice.alignment = .centerX
		notice.spacing = 10
		notice.setCustomSpacing(16, after: noticeDetail)
		notice.translatesAutoresizingMaskIntoConstraints = false
		addSubview(notice)

		NSLayoutConstraint.activate([
			notice.centerXAnchor.constraint(equalTo: centerXAnchor),
			notice.centerYAnchor.constraint(equalTo: centerYAnchor),
			notice.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
			noticeDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
		])
	}

	private func show(
		_ title: String,
		detail: String,
		buttons: [(String, String, () -> Void)] = [],
		text: Bool,
		keepState: Bool = false
	) {
		if !keepState { state = .notice }
		noticeTitle.stringValue = title
		noticeDetail.stringValue = detail
		noticeDetail.isHidden = detail.isEmpty
		var made: [NSView] = buttons.map { title, symbol, action in
			let button = NoticeButton(title: title, symbol: symbol)
			button.onClick = action
			return button
		}
		// Offered only where the text can be shown: the editor's own limit.
		let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		if text, size <= 64 * 1024 * 1024 {
			let button = NoticeButton(title: "Open as Text", symbol: "doc.plaintext")
			button.onClick = { [weak self] in self?.onOpenAsText?() }
			made.append(button)
		}
		noticeButtons.setViews(made, in: .center)
		noticeButtons.isHidden = made.isEmpty
		notice.isHidden = false
		web?.isHidden = true
		said = title
		refreshStatus()
	}

	private func hideNotice() {
		notice.isHidden = true
		refreshStatus()
	}

	/// The status bar's own words for this tab, when it has something to add for a moment.
	private func say(_ words: String) {
		transient = words
		refreshStatus()
	}

	private var transient = ""

	/// Where the file is, what that means, and who else is there — in the
	/// editor's status bar, where a text tab shows its line and column.
	///
	/// Not a bar of the tab's own: one was tried, and took a row from the board
	/// for a sentence and a button squeezed beside it (2026-10-23). The page's
	/// own share dialog gives the link now that it names the server.
	///
	/// A session board is plain on the server — that is what lets the AI work
	/// on it — so the status bar says where it is and that it is there for the
	/// session, not that it is safe.
	private func refreshStatus() {
		var said: String?
		if state == .onBoard, let server {
			var parts = ["On \(server.host ?? server.absoluteString)", "kept there for this session only"]
			if isPlainOverNetwork { parts.append("plain http: the board crosses the network unencrypted") }
			let others = max(0, people - 1)
			if people > 0 { parts.append(others == 0 ? "only you" : others == 1 ? "1 other here" : "\(others) others here") }
			if !transient.isEmpty { parts = [transient] + parts }
			said = parts.joined(separator: "  ·  ")
		}
		guard said != statusText else { return }
		statusText = said
		onStatusChanged?()
	}

	/// For a driven run: what the tab is showing, in one line.
	var reportForTesting: String {
		"\(fileURL.lastPathComponent) state=\(state) server=\(server?.host ?? "none") "
			+ "people=\(people) dirty=\(isDirty) said=\(said)"
	}

	/// The script message handler, holding the pane weakly: a content
	/// controller keeps its handlers alive, and the pane owns the controller.
	private final class Relay: NSObject, WKScriptMessageHandler {
		weak var pane: VboardPaneView?
		init(_ pane: VboardPaneView) { self.pane = pane }

		func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
			let body = message.body
			MainActor.assumeIsolated { pane?.received(body) }
		}
	}
}

// MARK: - Navigation, downloads and the page's dialogs

extension VboardPaneView: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
	/// The server's own pages, or the proxy that shows them.
	private func isServer(_ url: URL?) -> Bool {
		guard let url else { return false }
		return [server, proxy?.base].compactMap { $0 }.contains { origin in
			url.scheme == origin.scheme && url.host?.lowercased() == origin.host?.lowercased() && url.port == origin.port
		}
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor action: WKNavigationAction,
		decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
	) {
		if action.shouldPerformDownload {
			decisionHandler(.download)
			return
		}
		// A link elsewhere is opened where links open, and the tab stays on the
		// board. Signing in happens in the system's sheet, never here.
		guard state == .onBoard, action.targetFrame?.isMainFrame != false,
		      let url = action.request.url, !isServer(url), url.scheme != "about", url.scheme != "blob"
		else {
			decisionHandler(.allow)
			return
		}
		decisionHandler(.cancel)
		LinkOpener.open(url)
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor response: WKNavigationResponse,
		decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
	) {
		decisionHandler(response.canShowMIMEType ? .allow : .download)
	}

	func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
		download.delegate = self
	}

	func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
		download.delegate = self
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		trace("page finished loading \(webView.url?.path ?? "")")
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		guard state == .onBoard, let document else { return }
		webView.load(URLRequest(url: page(document.link)))
	}

	/// Downloads the page offers — its own `.vboard` download, an export —
	/// go where a browser puts them, never into the project.
	func download(
		_ download: WKDownload,
		decideDestinationUsing response: URLResponse,
		suggestedFilename: String,
		completionHandler: @escaping @MainActor (URL?) -> Void
	) {
		let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		var candidate = folder.appendingPathComponent(suggestedFilename)
		let stem = candidate.deletingPathExtension().lastPathComponent
		let ext = candidate.pathExtension
		var number = 2
		while FileManager.default.fileExists(atPath: candidate.path) {
			candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
			number += 1
		}
		completionHandler(candidate)
	}

	func downloadDidFinish(_ download: WKDownload) {
		Toast.post("Downloaded from the board", detail: "In your Downloads folder.", kind: .information)
	}

	/// A link that opens a new window: the server's own pages stay in the tab,
	/// anything else goes where links go.
	func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for action: WKNavigationAction,
		windowFeatures: WKWindowFeatures
	) -> WKWebView? {
		if let url = action.request.url {
			if isServer(url) { webView.load(action.request) } else { LinkOpener.open(url) }
		}
		return nil
	}

	func webView(
		_ webView: WKWebView,
		runJavaScriptAlertPanelWithMessage message: String,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor () -> Void
	) {
		let alert = NSAlert()
		alert.messageText = message
		alert.runModal()
		completionHandler()
	}

	func webView(
		_ webView: WKWebView,
		runJavaScriptConfirmPanelWithMessage message: String,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor (Bool) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = message
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		completionHandler(alert.runModal() == .alertFirstButtonReturn)
	}

	func webView(
		_ webView: WKWebView,
		runJavaScriptTextInputPanelWithPrompt prompt: String,
		defaultText: String?,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor (String?) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = prompt
		let field = NSTextField(string: defaultText ?? "")
		field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
		alert.accessoryView = field
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
	}

	/// A picture or a PDF added to the board from disk.
	func webView(
		_ webView: WKWebView,
		runOpenPanelWith parameters: WKOpenPanelParameters,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor ([URL]?) -> Void
	) {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = parameters.allowsMultipleSelection
		panel.canChooseDirectories = parameters.allowsDirectories
		panel.canChooseFiles = true
		completionHandler(panel.runModal() == .OK ? panel.urls : nil)
	}
}

// MARK: - The sign-in sheet

extension VboardPaneView: ASWebAuthenticationPresentationContextProviding {
	func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		window ?? NSApp.keyWindow ?? NSWindow()
	}
}
