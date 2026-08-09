import Foundation
import WebKit

/// One web view kept warm with Mermaid loaded into it, drawing every diagram in
/// the app.
///
/// The same shape as `PlantUMLServers` and for the same reason: what is
/// expensive is starting the thing, not drawing with it. Loading the 3.6 MB
/// bundle costs 0.16–0.28 s and the first render 0.111 s; every render after
/// that is **0.006–0.019 s**, which is faster than the warm PlantUML container
/// and fast enough to redraw as somebody types.
///
/// Where it differs from the PlantUML server, and each difference is why this
/// was chosen over a container at all (0425):
///
///  * **Nothing has to be installed and nothing is fetched.** No runtime, no
///    daemon, no image, no network. A `.mmd` file draws on a machine with
///    nothing on it.
///  * **There is nothing to leave behind.** A container that outlives the app
///    is 0406's whole problem; a web view dies with the process that made it.
///  * **It is on the main actor**, because `WKWebView` is. Every wait here is
///    an `await` on WebKit rather than on a pipe, so the main thread is not
///    held while a diagram is drawn.
///
/// It still goes away when nobody is drawing, for the same reason the PlantUML
/// server does: a WebContent process resident for the rest of the day, in every
/// project somebody opens, is not free.
@MainActor
public final class MermaidRenderer {
	public static let shared = MermaidRenderer()

	/// How long the web view may sit unused before it is torn down.
	///
	/// The same five minutes as the PlantUML server, and the cost of being
	/// wrong is smaller: reloading is a quarter of a second rather than a
	/// container and a JVM.
	public static let idleTimeout: TimeInterval = 300

	/// How long the bundle gets to load, and a diagram to draw.
	///
	/// Generous, and neither is expected to be approached — 0.3 s and 0.02 s
	/// were measured. It is here because a WebContent process that has been
	/// killed under memory pressure answers nothing at all, and a preview that
	/// spins for ever says nothing about why.
	public static let deadline: TimeInterval = 30

	/// What an exported PNG is rasterised at.
	///
	/// Twice the drawing's own size. A Mermaid diagram is laid out in CSS
	/// pixels, so a 1× PNG of one is a picture that is soft the moment it is put
	/// on any screen made in the last decade — and unlike the preview, which is
	/// a drawing and has no resolution to be wrong about, a PNG has to choose
	/// once and for ever.
	public static let rasterScale: Double = 2

	/// Why a diagram was not drawn: the diagram itself, or everything else.
	///
	/// The same split `DiagramExport` already makes for PlantUML, because the
	/// export makes the same decision on it — a fault names a line and is the
	/// author's to fix, and trouble is this app's.
	public enum Failure: Error, Sendable {
		case fault(DiagramFault)
		case trouble(String)
	}

	private var web: WKWebView?
	/// The load already under way, so two panes opening together wait on one
	/// web view rather than building two.
	private var loading: Task<WKWebView?, Never>?
	private var lastUsed = Date()
	private var reaper: Task<Void, Never>?
	private var loader: Loader?

	public init() {}

	// MARK: - Drawing

	/// The picture, in the format asked for.
	///
	/// The format is asked for rather than taken from whatever is on screen:
	/// the pane draws SVG because a drawing stays sharp at any zoom, and
	/// `Export ▸ PNG` has to mean a PNG. That was the bug in the first version
	/// of the PlantUML export and it is not being reintroduced here.
	public func draw(
		_ source: String, format: DiagramFormat, scale: Double = MermaidRenderer.rasterScale
	) async -> Result<Data, Failure> {
		guard Mermaid.hasDiagram(source) else {
			return .failure(.trouble("There is no diagram here yet."))
		}
		guard let web = await ready() else {
			return .failure(.trouble(Mermaid.missingBundleHint))
		}
		lastUsed = Date()
		startReaping()

		let answer: Any?
		do {
			answer = try await withDeadline(Self.deadline) {
				try await web.callAsyncJavaScript(
					"return await abydosDraw(source)",
					arguments: ["source": source], in: nil, contentWorld: .page
				)
			}
		} catch {
			return .failure(.trouble(said(about: error)))
		}
		guard let raw = answer as? String,
		      let reply = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
		else { return .failure(.trouble("Mermaid answered with nothing this could read.")) }

		if let complaint = reply["error"] as? String {
			return .failure(.fault(Mermaid.fault(message: complaint, line: reply["line"] as? Int)))
		}
		guard let drawn = reply["svg"] as? String else {
			return .failure(.trouble("Mermaid drew nothing."))
		}

		// Sized before anything else looks at it: a drawing with no size of its
		// own rasterises into a 300×150 box, and is written to disk as a file
		// that every viewer guesses the size of differently.
		let svg = DiagramStamp.sign(svg: Mermaid.sized(drawn))
		guard format == .png else { return .success(Data(svg.utf8)) }

		lastUsed = Date()
		let rastered: Any?
		do {
			rastered = try await withDeadline(Self.deadline) {
				try await web.callAsyncJavaScript(
					"return await abydosRaster(svg, scale)",
					arguments: ["svg": svg, "scale": scale], in: nil, contentWorld: .page
				)
			}
		} catch {
			return .failure(.trouble(said(about: error)))
		}
		guard let base64 = rastered as? String, let png = Data(base64Encoded: base64) else {
			return .failure(.trouble("The drawing could not be turned into a picture."))
		}
		return .success(DiagramStamp.sign(png: png))
	}

	/// Tears the web view down now, without waiting out the idle timeout. For a
	/// test, and for anybody who wants the WebContent process gone.
	public func stop() {
		reaper?.cancel()
		reaper = nil
		web?.navigationDelegate = nil
		web = nil
		loader = nil
		loading?.cancel()
		loading = nil
	}

	/// Whether one is loaded, for a test.
	public var isWarm: Bool { web != nil }

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
		guard let url = Mermaid.bundleURL,
		      let bundle = try? String(contentsOf: url, encoding: .utf8)
		else { return nil }

		// A frame with room in it, because Mermaid lays a diagram out by
		// measuring text in the document — a web view of nothing measures
		// nothing. No window is needed and none is made: the rasterising goes
		// through a canvas rather than through a snapshot of the page, which is
		// exactly why an off-screen web view is enough.
		let configuration = WKWebViewConfiguration()
		let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
		                     configuration: configuration)
		let loader = Loader()
		self.loader = loader
		view.navigationDelegate = loader
		view.loadHTMLString(Mermaid.page(bundle: bundle), baseURL: nil)

		let arrived: Bool
		do {
			arrived = try await withDeadline(Self.deadline) { await loader.finished() }
		} catch {
			return nil
		}
		return arrived ? view : nil
	}

	/// Removes the web view when nobody has drawn with it for a while.
	private func startReaping() {
		guard reaper == nil else { return }
		reaper = Task { [weak self] in
			while let self, await self.reapIfIdle() {
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

	private func said(about error: Error) -> String {
		if error is DeadlineExpired {
			return "Mermaid did not answer within \(Int(Self.deadline)) seconds."
		}
		// A `WKError` from `callAsyncJavaScript` carries the JavaScript
		// exception's own message, which is the only useful thing here.
		let said = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
		return said ?? error.localizedDescription
	}

	struct DeadlineExpired: Error {}

	/// Runs something, or gives up on it.
	///
	/// `WKWebView` has no timeout of its own and a WebContent process that has
	/// been killed simply never calls back, so without this a preview waits for
	/// ever and says nothing.
	private func withDeadline<T: Sendable>(
		_ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T
	) async throws -> T {
		try await withThrowingTaskGroup(of: T.self) { group in
			group.addTask { try await work() }
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
				throw DeadlineExpired()
			}
			defer { group.cancelAll() }
			guard let first = try await group.next() else { throw DeadlineExpired() }
			return first
		}
	}
}

/// Waiting for the page to load, once.
///
/// `WKNavigationDelegate` is three callbacks for two outcomes — a load can fail
/// before it is committed or after — and all three end the same wait here.
private final class Loader: NSObject, WKNavigationDelegate {
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
}
