import AbydosKit
import AppKit
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
	/// in the footer and left there, as a text tab leaves such a file alone.
	private var noticedChangeOnDisk = false
	private var said = ""

	private var web: WKWebView?
	private var store: WKWebsiteDataStore?
	private var relay: Relay?

	private let noticeTitle = NSTextField(labelWithString: "")
	private let noticeDetail = NSTextField(wrappingLabelWithString: "")
	private let noticeButtons = NSStackView()
	private let notice = NSStackView()
	private let footer = NSStackView()
	private let footerText = NSTextField(labelWithString: "")
	private let peopleText = NSTextField(labelWithString: "")
	private let copyLink = NoticeButton(title: "Copy Link", symbol: "link")

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
		state = .connecting
		show("Connecting to \(server.host ?? "the server")…", detail: "", text: false, keepState: true)
		let store = WKWebsiteDataStore(forIdentifier: VboardPage.dataStoreID(for: server))
		self.store = store
		let client = VboardClient(server: server, cookies: { [weak store] in
			await store?.httpCookieStore.allCookies() ?? []
		})
		let document = VboardDocument(url: fileURL, client: client)
		document.onDirtyChanged = { [weak self] in self?.onDirtyChanged?() }
		self.document = document
		makeWebView(store: store)
		// The server's web app starts loading now, out of sight, while the file
		// goes up: the page is the slow half of opening a board, and its scripts
		// are then in the cache when the board is ready. Reported on
		// 2026-10-23 as "a bit slow to open the document".
		web?.load(URLRequest(url: server))
		Task { await self.putOnBoard() }
	}

	/// Asks whether somebody needs to sign in, and if not, puts the file on a
	/// board and shows it. Asked first because an import made while signed out
	/// sends the whole file only to be told 401 at the end.
	private func putOnBoard() async {
		guard let document, let server else { return }
		switch await document.client.signedIn() {
		case .done:
			break
		case .signedOut:
			signIn()
			return
		case .unreachable(let why):
			show(
				"\(server.host ?? "The server") cannot be reached",
				detail: why,
				buttons: [("Try Again", "arrow.clockwise", { [weak self] in self?.retry() })],
				text: true
			)
			return
		case let outcome:
			show("\(server.host ?? "The server") would not take the board", detail: describe(outcome), text: true)
			return
		}
		state = .uploading
		show("Uploading \(fileURL.lastPathComponent)…", detail: sizeLine(), text: false, keepState: true)
		let opened = await document.open { [weak self] fraction in
			Task { @MainActor in self?.uploadProgressed(fraction) }
		}
		switch opened {
		case .onBoard:
			showBoard()
		case .failed(.signedOut):
			signIn()
		case .failed(let outcome):
			show("\(server.host ?? "The server") would not take the board", detail: describe(outcome), text: true)
		case .refusedFile:
			// Decided before connecting; a file that changed kind in between is
			// decided again.
			decide(start: false)
		}
	}

	private func retry() {
		show("Connecting…", detail: "", text: false, keepState: true)
		state = .connecting
		Task { await putOnBoard() }
	}

	/// The server's own login, in the tab. Every page that finishes loading on
	/// the server afterwards asks again whether somebody has signed in.
	private func signIn() {
		guard let web, let server else { return }
		state = .signingIn
		hideNotice()
		web.isHidden = false
		web.load(URLRequest(url: server))
		say("Sign in to \(server.host ?? "the server") to open the board")
	}

	private func showBoard() {
		guard let web, let document else { return }
		state = .onBoard
		hideNotice()
		web.isHidden = false
		web.load(URLRequest(url: document.link))
		say("")
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

	private func makeWebView(store: WKWebsiteDataStore) {
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = store
		let controller = WKUserContentController()
		controller.addUserScript(WKUserScript(
			source: VboardPage.socketWatcher, injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		controller.addUserScript(WKUserScript(
			source: VboardPage.slotRefusal, injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		let relay = Relay(self)
		controller.add(relay, name: VboardPage.handlerName)
		self.relay = relay
		configuration.userContentController = controller
		let web = WKWebView(frame: .zero, configuration: configuration)
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
			web.bottomAnchor.constraint(equalTo: footer.topAnchor),
		])
		self.web = web
	}

	fileprivate func received(_ body: Any) {
		guard let document, let message = VboardPage.Message(body, board: document.boardID) else { return }
		switch message {
		case .snapshot(let count), .presence(let count):
			people = count
			refreshFooter()
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
				web?.load(URLRequest(url: document.link))
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
	/// the tab may go.
	///
	/// Synchronous, though a save and a delete are round trips to a server:
	/// closing every tab and swapping projects loop until the tabs are gone, and
	/// a close that returned and finished later would have them spin. So the
	/// main run loop is turned by hand until the answer comes, with a deadline —
	/// the HTML and draw.io panes wait for `takeSnapshot` the same way.
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
		_ = Self.waitTurningRunLoop(seconds: 15, { await self.endSession() })
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
		web?.stopLoading()
		web?.configuration.userContentController.removeScriptMessageHandler(forName: VboardPage.handlerName)
		web?.navigationDelegate = nil
		web?.uiDelegate = nil
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

		footerText.font = .systemFont(ofSize: 11)
		footerText.textColor = Theme.current.gitIgnored
		footerText.lineBreakMode = .byTruncatingTail
		footerText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		peopleText.font = .systemFont(ofSize: 11)
		peopleText.textColor = Theme.current.sidebarText
		copyLink.onClick = { [weak self] in self?.copyBoardLink() }
		footer.setViews([footerText, peopleText, copyLink], in: .leading)
		footer.orientation = .horizontal
		footer.spacing = 12
		footer.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
		footer.translatesAutoresizingMaskIntoConstraints = false
		footer.isHidden = true
		addSubview(footer)

		NSLayoutConstraint.activate([
			notice.centerXAnchor.constraint(equalTo: centerXAnchor),
			notice.centerYAnchor.constraint(equalTo: centerYAnchor),
			notice.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
			noticeDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
			footer.leadingAnchor.constraint(equalTo: leadingAnchor),
			footer.trailingAnchor.constraint(equalTo: trailingAnchor),
			footer.bottomAnchor.constraint(equalTo: bottomAnchor),
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
		refreshFooter()
	}

	private func hideNotice() {
		notice.isHidden = true
		refreshFooter()
	}

	/// The footer's own words, when it has something to add for a moment.
	private func say(_ words: String) {
		transient = words
		refreshFooter()
	}

	private var transient = ""

	/// Where the file is, what that means, and who else is there.
	///
	/// "Encrypted" alone would be read as end-to-end, which vboard's private
	/// boards are not: the server holds the board's content key while anybody
	/// has it open. So it says both, all the time.
	private func refreshFooter() {
		let live = state == .onBoard || state == .signingIn
		footer.isHidden = !live
		guard live, let server else { return }
		var parts = ["On \(server.host ?? server.absoluteString)", "encrypted there, readable by the server while open"]
		if isPlainOverNetwork { parts.append("plain http: the board's key crosses the network unencrypted") }
		if !transient.isEmpty { parts = [transient] + parts }
		footerText.stringValue = parts.joined(separator: "  ·  ")
		let others = max(0, people - 1)
		peopleText.stringValue = state != .onBoard ? "" : others == 0 ? "Only you" : others == 1 ? "1 other here" : "\(others) others here"
		copyLink.isHidden = state != .onBoard
	}

	private func copyBoardLink() {
		guard let document else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(document.link.absoluteString, forType: .string)
		say("Link copied. Whoever opens it can work on the board.")
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
	private func isServer(_ url: URL?) -> Bool {
		guard let url, let server else { return false }
		return url.scheme == server.scheme && url.host?.lowercased() == server.host?.lowercased() && url.port == server.port
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
		// While signing in the login may go to an identity provider and back;
		// that stays in the tab. Once on the board, a link elsewhere is opened
		// where links open, and the tab stays on the board.
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
		// Every page the login lands on asks again. Once the server says
		// somebody is signed in, the file goes up and the board is shown.
		guard state == .signingIn, isServer(webView.url) else { return }
		Task {
			guard let document, await document.client.signedIn() == .done, state == .signingIn else { return }
			await putOnBoard()
		}
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		guard state == .onBoard, let document else { return }
		webView.load(URLRequest(url: document.link))
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
