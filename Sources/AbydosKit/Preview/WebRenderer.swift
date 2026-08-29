import Foundation
import WebKit

/// A web view kept warm with a bundled page in it, and a way to ask that page
/// for something.
///
/// This is the drawing surface rather than the drawing: it owns the web view,
/// the one-time load, the deadline on every call, and the tearing down of a
/// process nobody is using. What is *in* the page and what the answers mean
/// belong to whoever supplies the page — today that is `MermaidRenderer` and
/// nothing else.
///
/// It exists as its own type because the next thing that needs a rendering
/// surface is draw.io, which is also a web application and has no other form.
/// **This is a seam, not a plugin system.** There is no registry, no protocol
/// with one conformer and no second implementation, because a second client
/// does not exist yet and building for one would be building for a guess. What
/// draw.io would need beyond this is written down in backlog 0425, and the
/// short of it is that draw.io is an *editor* — it takes events back, owns the
/// document, and is a visible view rather than an off-screen one. That is a
/// much larger thing than rendering a string, and it is not pretended at here.
///
/// Two properties this guarantees, and both are the reason it is off-screen and
/// origin-less:
///
///  * **Nothing is fetched, ever.** The page is one document with its script
///    inlined, loaded with no base URL, and any navigation away from it is
///    refused. A diagram cannot reach the network and the app draws with no
///    network at all.
///  * **Nothing waits for ever.** Every call has a deadline, like every other
///    outward call in this codebase, because a WebContent process that has been
///    killed under memory pressure simply never answers.
@MainActor
public final class WebRenderer {
	/// How long the page gets to load, and a call to come back.
	///
	/// **A hang detector, not a bound**, for the reason above: a WebContent
	/// process killed under memory pressure never answers, and this is what
	/// notices. Thirty seconds against a warm render of about fourteen
	/// milliseconds is three orders of magnitude of headroom, which is the
	/// right shape for a number whose job is to notice "never".
	///
	/// Settable so the test suite can be more generous still. A person waiting
	/// at a screen should not be made to wait a minute to be told something
	/// broke; a suite running beside four builds is not a person at a screen,
	/// and at fifteen runnable threads a core the render really did take longer
	/// than thirty seconds with nothing wrong. Raising it there costs a passing
	/// run nothing — the deadline is only ever reached when something has
	/// genuinely stopped answering.
	/// `nonisolated` because it is a knob, not state: set once before anything
	/// renders and read on the main actor thereafter. Isolating it to the main
	/// actor would mean a test could only raise it from a main-actor context,
	/// and reaching for `assumeIsolated` to get there traps outright in a suite
	/// whose type is not itself `@MainActor` — which is exactly what it did.
	nonisolated(unsafe) public static var deadline: TimeInterval = 30

	/// How long the web view may sit unused before it is torn down.
	///
	/// The same five minutes the PlantUML server gets, and for the same reason:
	/// a WebContent process resident all day in every project somebody opens is
	/// not free. The cost of being wrong is smaller here — reloading is a
	/// quarter of a second rather than a container and a JVM.
	public static let idleTimeout: TimeInterval = 300

	/// What went wrong that was not the document's fault.
	public struct Trouble: Error, Sendable {
		public let message: String
		public init(_ message: String) { self.message = message }
	}

	/// The document to load, asked for once and again after an idle teardown.
	/// Nil means the build is missing whatever it is made of.
	private let page: @MainActor () -> String?

	private var web: WKWebView?
	/// The load already under way, so two callers arriving together wait on one
	/// web view rather than building two.
	private var loading: Task<WKWebView?, Never>?
	private var keeper: Keeper?
	private var lastUsed = Date()
	private var reaper: Task<Void, Never>?

	public init(page: @escaping @MainActor () -> String?) {
		self.page = page
	}

	/// Whether a page is loaded, for a test.
	public var isWarm: Bool { web != nil }

	/// Runs something in the page and hands back what it returned.
	///
	/// The script is an async function body — `return await …` — and the
	/// arguments are passed as values rather than pasted into the source, so
	/// nothing has to be escaped and a diagram containing a quotation mark is
	/// not a syntax error in somebody else's language.
	public func call(_ script: String, arguments: [String: Any] = [:]) async throws -> Any? {
		guard let web = await ready() else {
			throw Trouble("The page this draws with is missing from this build of Abydos.")
		}
		lastUsed = Date()
		startReaping()
		do {
			return try await withDeadline {
				try await web.callAsyncJavaScript(
					script, arguments: arguments, in: nil, contentWorld: .page
				)
			}
		} catch is DeadlineExpired {
			throw Trouble("The page did not answer within \(Int(Self.deadline)) seconds.")
		} catch {
			// A `WKError` from `callAsyncJavaScript` carries the JavaScript
			// exception's own message, which is the only useful thing in it.
			let said = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
			throw Trouble(said ?? error.localizedDescription)
		}
	}

	/// Tears the web view down now, without waiting out the idle timeout.
	public func stop() {
		reaper?.cancel()
		reaper = nil
		web?.navigationDelegate = nil
		web = nil
		keeper = nil
		loading?.cancel()
		loading = nil
	}

	// MARK: - Keeping one

	private func ready() async -> WKWebView? {
		if let web { return web }
		if let loading { return await loading.value }
		let task = Task { await load() }
		loading = task
		let loaded = await task.value
		loading = nil
		web = loaded
		return loaded
	}

	private func load() async -> WKWebView? {
		guard let document = page() else { return nil }

		let configuration = WKWebViewConfiguration()
		// Nothing in the page is a link and nothing in it should become one.
		configuration.suppressesIncrementalRendering = true
		// A frame with room in it, because a diagram is laid out by measuring
		// text in the document and a web view of nothing measures nothing. No
		// window is made: rasterising goes through a canvas rather than through
		// a snapshot of the page, which is exactly why off-screen is enough.
		let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
		                     configuration: configuration)
		view.allowsBackForwardNavigationGestures = false
		let keeper = Keeper()
		self.keeper = keeper
		view.navigationDelegate = keeper
		view.loadHTMLString(document, baseURL: nil)

		do {
			return try await withDeadline({ await keeper.finished() }) ? view : nil
		} catch {
			return nil
		}
	}

	private func startReaping() {
		guard reaper == nil else { return }
		reaper = Task { [weak self] in
			// No `await` on the call: this renderer is main-actor isolated, so the
			// task it starts is too, and `reapIfIdle` is a plain call from here.
			while let self, self.reapIfIdle() {
				try? await Task.sleep(nanoseconds: 30_000_000_000)
			}
		}
	}

	private func reapIfIdle() -> Bool {
		guard web != nil else { return false }
		guard Date().timeIntervalSince(lastUsed) < Self.idleTimeout else {
			stop()
			return false
		}
		return true
	}

	// MARK: - Waiting

	struct DeadlineExpired: Error {}

	/// Runs something, or gives up on it.
	private func withDeadline<T: Sendable>(
		_ work: @escaping @Sendable () async throws -> T
	) async throws -> T {
		try await withThrowingTaskGroup(of: T.self) { group in
			group.addTask { try await work() }
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(Self.deadline * 1_000_000_000))
				throw DeadlineExpired()
			}
			defer { group.cancelAll() }
			guard let first = try await group.next() else { throw DeadlineExpired() }
			return first
		}
	}
}

/// Waiting for the page to load, once — and refusing to let it go anywhere.
///
/// `WKNavigationDelegate` is three callbacks for two outcomes, since a load can
/// fail before it is committed or after, and all three end the same wait.
///
/// The refusal is the other half of "nothing is fetched". The page is loaded
/// from a string with no base URL, so the only navigation that should ever
/// happen is that one; anything else is a document trying to leave, and it is
/// cancelled rather than followed.
private final class Keeper: NSObject, WKNavigationDelegate {
	private var waiting: CheckedContinuation<Bool, Never>?
	private var settled: Bool?

	func finished() async -> Bool {
		if let settled { return settled }
		return await withCheckedContinuation { continuation in
			if let settled {
				continuation.resume(returning: settled)
			} else {
				waiting = continuation
			}
		}
	}

	private func settle(_ outcome: Bool) {
		guard settled == nil else { return }
		settled = outcome
		waiting?.resume(returning: outcome)
		waiting = nil
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { settle(true) }

	func webView(
		_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
	) { settle(false) }

	func webView(
		_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	) { settle(false) }

	func webView(
		_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		let url = navigationAction.request.url
		let isTheDocumentItself = url == nil || url?.absoluteString == "about:blank"
		decisionHandler(isTheDocumentItself ? .allow : .cancel)
	}
}
