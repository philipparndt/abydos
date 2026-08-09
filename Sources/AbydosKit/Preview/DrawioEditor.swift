import Foundation
import WebKit

/// draw.io's own editor, in a web view, editing a file this app still owns.
///
/// This is level 2 of 0426 and the part that could go wrong quietly. The
/// question the entry poses is "what happens when the app stops owning the
/// document" — and the answer arrived at here is that **it does not have to**.
///
/// `TextDocument` already is the right model for a `.drawio`: the file is UTF-8
/// XML, it tracks dirty state, it saves atomically and it records what it wrote
/// so the watcher does not mistake the app's own write for somebody else's.
/// What changes is only that the *view* editing it is draw.io rather than a
/// `CodeView`. So this class keeps the document in step with the editor on
/// every change, and everything the app already does — the tab's edited dot,
/// ⌘S, the close-without-saving prompt, auto-save, the file watcher — goes on
/// working with nothing added to it.
///
/// Three things that makes true, and each was a named risk in 0426:
///
///  * **Dirty state is immediate, not every 1.5 seconds.** draw.io's own
///    `autosave` event is on a timer; this listens to the graph model's own
///    change event instead and sends the file XML straight away, so the dot
///    appears when the shape is dropped and ⌘S a moment later writes what is on
///    screen rather than what was on screen a second ago.
///  * **Undo stays draw.io's.** ⌘Z reaches the web view, mxGraph's undo
///    manager handles it, the model changes, and the change comes back here as
///    a new document state. The app's own undo stack is never told about the
///    edits, because a `.drawio` tab has no `CodeView` for it to act on — and
///    that is why a `.drawio` opens in `.preview` with no source half at all.
///  * **The file is written back the way it came.** A compressed document stays
///    compressed and a plain one stays plain, because `Editor.defaultCompressed`
///    is set from what was read. A diff full of noise is how people stop
///    trusting an editor.
///
/// What is *not* claimed: this is not a second document model, there is no
/// merge, and an external change while somebody is drawing reloads the editor
/// and loses draw.io's undo stack — the same trade the text editor makes.
@MainActor
public final class DrawioEditor: NSObject {
	/// The scheme the editor's own files are served under.
	///
	/// A scheme handler rather than a `file:` URL, and rather than the inlined
	/// single document `DrawioRenderer` uses. draw.io's editor is not one file:
	/// it fetches its string bundle, its stylesheet and its icons by relative
	/// path, and a `loadHTMLString` page has no origin to resolve them against.
	/// A scheme of this app's own gives the page a real origin whose every
	/// request is answered from the application bundle and from nowhere else —
	/// which keeps "nothing is fetched" true in the sense that matters: nothing
	/// leaves this machine.
	public static let scheme = "abydos-drawio"
	static let host = "editor"

	/// What the editor asked for and this build does not carry.
	///
	/// `img/lib/` is the one thing deliberately left out — 5.9 MB of clipart —
	/// and the whole point of noticing is that a missing picture is otherwise
	/// silent. See `Drawio.clipartNotice`.
	public var missingAssets: Set<String> { assets.missing }

	/// Called once the editor has said `init`, which is when it will accept a
	/// document.
	public var onReady: (() -> Void)?
	/// The document, as it is now, after any change at all.
	public var onChanged: ((String) -> Void)?
	/// The Save button in draw.io's own toolbar was pressed.
	public var onSaveRequested: ((String) -> Void)?
	/// Something went wrong that somebody should be told about.
	public var onTrouble: ((String) -> Void)?

	public let webView: WKWebView
	private let assets: DrawioAssetScheme
	private var isReady = false
	/// Sent to the editor as soon as it says `init`, when a document arrived
	/// before it was ready — which is the normal order, since the page takes
	/// about a second to load and the file is in hand immediately.
	private var pending: (xml: String, compressed: Bool)?
	/// The same for the theme, which the pane knows before the editor exists.
	private var pendingDark: (chrome: Bool, colours: Bool)?

	/// One editor, or nil when the vendored files are not in this build.
	///
	/// A factory rather than a failable `init()`, which cannot exist on an
	/// `NSObject` subclass: `init()` is already there and is not failable.
	public static func make() -> DrawioEditor? {
		guard let root = DrawioRenderer.assetsRoot else { return nil }
		return DrawioEditor(root: root)
	}

	private init(root: URL) {
		assets = DrawioAssetScheme(root: root)

		let configuration = WKWebViewConfiguration()
		configuration.setURLSchemeHandler(assets, forURLScheme: Self.scheme)
		let controller = WKUserContentController()
		configuration.userContentController = controller
		webView = WKWebView(frame: .zero, configuration: configuration)
		webView.allowsBackForwardNavigationGestures = false
		super.init()
		controller.add(Bridge(self), name: "abydos")
		webView.navigationDelegate = self
	}

	/// Loads the editor. The document follows once it says `init`.
	public func start() {
		guard let url = URL(string: "\(Self.scheme)://\(Self.host)/host.html")
		else { return }
		webView.load(URLRequest(url: url))
	}

	/// draw.io's own URL parameters, which are its whole configuration surface.
	///
	/// `embed=1&proto=json` is the integration protocol — read out of
	/// `app.min.js` rather than from a blog post, since the file is vendored
	/// here: the editor posts `init`, then `save`, `autosave`, `export` and
	/// `exit`, and accepts `load`, `merge`, `configure`, `dialog`, `spinner`,
	/// `status`, `template`, `layout`, `prompt`, `export` and `exit`.
	///
	/// The rest are decisions:
	///
	///  * `pages=1` — the page tabs along the bottom, which is draw.io's own
	///    answer to the page question and the reason this app does not need a
	///    page control of its own.
	///  * `noExitBtn=1` — there is nothing to exit to. The tab is the window.
	///  * `saveAndExit=0` — likewise.
	///  * `noSaveBtn=0` — the Save button stays, because somebody who has used
	///    draw.io looks for it. It does exactly what ⌘S does.
	///  * `libraries=1` — the shape sidebar, which is most of why anybody wants
	///    the editor rather than the viewer.
	///  * `modified=unsavedChanges` — the editor says so in its own status line
	///    as well as the tab saying so in its dot.
	static let parameters = [
		"embed=1", "proto=json", "pages=1", "libraries=1", "noExitBtn=1",
		"saveAndExit=0", "noSaveBtn=0", "modified=unsavedChanges", "spin=1",
		"browser=0", "gapi=0", "od=0", "gh=0", "gl=0", "tr=0", "db=0", "drive=0",
		"analytics=0", "picker=0",
	].joined(separator: "&")

	// MARK: - Talking to it

	/// Puts a document in the editor, or holds it until the editor is ready.
	public func load(_ mxfile: String, compressed: Bool) {
		guard isReady else {
			pending = (mxfile, compressed)
			return
		}
		send(["action": "load", "xml": mxfile, "autosave": 0])
		// After the load, because `load` resets the editor's own state.
		run("abydosAfterLoad(\(compressed ? "true" : "false"))")
	}

	/// Which way round the editor draws.
	///
	/// Two separate answers, and the split is the point — see `abydosSetDark`.
	/// The chrome follows the app whatever the file says; the shape colours
	/// follow it only when the document has stated no background of its own.
	///
	/// Applied by script rather than by reloading the page with `dark=1` in the
	/// URL, because a reload takes draw.io's undo stack and anything unsaved with
	/// it — and the theme can change with a diagram half drawn.
	public func setDark(chrome: Bool, colours: Bool) {
		guard isReady else {
			pendingDark = (chrome, colours)
			return
		}
		run("abydosSetDark(\(chrome), \(colours))")
	}

	/// Asks the editor for the document as it stands, right now.
	///
	/// Used by ⌘S. The change listener means the app's copy is already current
	/// in every case seen so far, but a save that reads the editor rather than
	/// trusting a cache is the one place worth being certain.
	public func currentDocument() async -> String? {
		try? await webView.callAsyncJavaScript(
			"return abydosFileData()", arguments: [:], in: nil, contentWorld: .page
		) as? String
	}

	/// Draws what is on screen, in the format asked for, through draw.io's own
	/// export rather than through the off-screen renderer.
	public func export(_ format: DiagramFormat) async -> Data? {
		let answer = try? await webView.callAsyncJavaScript(
			"return await abydosExport(format)", arguments: ["format": format.rawValue],
			in: nil, contentWorld: .page
		)
		guard let text = answer as? String else { return nil }
		return format == .png ? Data(base64Encoded: text) : Data(text.utf8)
	}

	private func send(_ message: [String: Any]) {
		guard let data = try? JSONSerialization.data(withJSONObject: message),
		      let json = String(data: data, encoding: .utf8)
		else { return }
		run("abydosSend(\(quoted(json)))")
	}

	private func run(_ script: String) {
		webView.evaluateJavaScript(script) { [weak self] _, error in
			guard let error else { return }
			MainActor.assumeIsolated { self?.onTrouble?(error.localizedDescription) }
		}
	}

	/// A JavaScript string literal, made by the one encoder that cannot be
	/// wrong about a document full of quotation marks.
	private func quoted(_ text: String) -> String {
		let data = try? JSONSerialization.data(withJSONObject: [text])
		let wrapped = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
		return String(wrapped.dropFirst().dropLast())
	}

	// MARK: - What it says back

	/// One message from the page, already decoded.
	fileprivate func received(_ message: [String: Any]) {
		switch message["event"] as? String {
		case "init":
			isReady = true
			onReady?()
			if let pendingDark {
				self.pendingDark = nil
				setDark(chrome: pendingDark.chrome, colours: pendingDark.colours)
			}
			if let pending {
				self.pending = nil
				load(pending.xml, compressed: pending.compressed)
			}
		case "abydosChanged":
			if let xml = message["xml"] as? String { onChanged?(xml) }
		case "save":
			if let xml = message["xml"] as? String { onSaveRequested?(xml) }
		case "abydosTrouble":
			if let said = message["message"] as? String { onTrouble?(said) }
		default:
			break
		}
	}

	/// The message handler, kept apart so the web view's content controller does
	/// not hold this object and stop it ever being freed.
	private final class Bridge: NSObject, WKScriptMessageHandler {
		weak var editor: DrawioEditor?
		init(_ editor: DrawioEditor) { self.editor = editor }

		func userContentController(
			_ controller: WKUserContentController, didReceive message: WKScriptMessage
		) {
			guard let raw = message.body as? String,
			      let data = raw.data(using: .utf8),
			      let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			else { return }
			MainActor.assumeIsolated { editor?.received(decoded) }
		}
	}
}

extension DrawioEditor: WKNavigationDelegate {
	/// The page loads once and goes nowhere.
	///
	/// draw.io is full of links — to its own help, to its templates, to the
	/// shape libraries' documentation — and a click on one inside an editor
	/// pane must not replace the editor with a web page. Anything that is not
	/// this app's own scheme is refused; opening it in a browser is `openLink`'s
	/// job and belongs to whoever wires the pane up.
	public func webView(
		_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		let allowed = action.request.url?.scheme == Self.scheme
		decisionHandler(allowed ? .allow : .cancel)
	}
}

/// Serving draw.io's own files to the editor, out of the application bundle.
///
/// Everything under the vendored directory and nothing else: a request that
/// climbs out of it, or names a file that is not there, is answered 404 and
/// *recorded*. The recording is the point — `img/lib/` is 5.9 MB of clipart
/// this build deliberately does not carry, and without this a diagram using one
/// would draw a gap where a picture goes and say nothing at all.
final class DrawioAssetScheme: NSObject, WKURLSchemeHandler {
	private let root: URL
	/// Paths asked for that are not here, which the editor reads back.
	private(set) var missing: Set<String> = []

	init(root: URL) {
		self.root = root.standardizedFileURL
	}

	func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
		guard let url = task.request.url else {
			task.didFailWithError(URLError(.badURL))
			return
		}
		let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path

		if path.isEmpty || path == "host.html" {
			let page = DrawioEditorPage.host.replacingOccurrences(
				of: "ABYDOS_PARAMETERS", with: DrawioEditor.parameters
			)
			answer(task, url: url, data: Data(page.utf8), mime: "text/html")
			return
		}
		if path == "editor.html" {
			answer(task, url: url, data: Data(DrawioEditorPage.editor.utf8), mime: "text/html")
			return
		}

		let file = root.appendingPathComponent(path).standardizedFileURL
		guard file.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
			missing.insert(path)
			// A 404 rather than an error: draw.io asks for things it can do
			// without, and a failed request it expects must not look like a
			// broken page.
			let response = HTTPURLResponse(
				url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil
			)!
			task.didReceive(response)
			task.didReceive(Data())
			task.didFinish()
			return
		}
		answer(task, url: url, data: data, mime: Self.mime(for: file.pathExtension))
	}

	func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

	/// An `HTTPURLResponse` rather than a plain one, and this is not a detail.
	///
	/// draw.io fetches its string bundle with `XMLHttpRequest` and checks
	/// `status` against 200–299. A custom scheme answered with a bare
	/// `URLResponse` gives that request a status of **0**, so the check fails,
	/// `App.main`'s callback never runs, and the pane says "Opening draw.io…"
	/// for ever with nothing in the console. Seen, for half an hour.
	private func answer(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
		let response = HTTPURLResponse(
			url: url, statusCode: 200, httpVersion: "HTTP/1.1",
			headerFields: [
				"Content-Type": mime,
				"Content-Length": String(data.count),
				// One origin, its own. Nothing here is fetched from anywhere
				// else and nothing here should be reachable from anywhere else.
				"Access-Control-Allow-Origin": "\(DrawioEditor.scheme)://\(DrawioEditor.host)",
			]
		)!
		task.didReceive(response)
		task.didReceive(data)
		task.didFinish()
	}

	static func mime(for extension: String) -> String {
		switch `extension`.lowercased() {
		case "html": return "text/html"
		case "js": return "application/javascript"
		case "css": return "text/css"
		case "xml": return "application/xml"
		case "txt": return "text/plain"
		case "json": return "application/json"
		case "svg": return "image/svg+xml"
		case "png": return "image/png"
		case "gif": return "image/gif"
		case "jpg", "jpeg": return "image/jpeg"
		case "ico": return "image/x-icon"
		default: return "application/octet-stream"
		}
	}
}
