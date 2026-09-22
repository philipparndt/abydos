import Foundation
import WebKit

/// Serving a previewed document and the files beside it to a web view.
///
/// `DrawioAssetScheme` is the model, and the difference is where the bytes come
/// from. That one serves an application bundle, which nobody edits; this one
/// serves a **buffer** for the document and the disk for its neighbours, so the
/// pane shows unsaved work and a stylesheet saved a second ago at the same
/// time. `HtmlPage` holds the two rules it keeps — what the document's own
/// address is, and what is under its directory — because both are worth testing
/// without a web view, and one of them is what stands between a document
/// somebody has not read and the rest of their disk.
///
/// Every request the page makes arrives here, which is the second reason the
/// scheme exists: a refusal can be counted, and a page that renders unstyled
/// can say why.
public final class HtmlScheme: NSObject, WKURLSchemeHandler {
	/// The file being shown. Its directory is the root, and its name is where
	/// the document is served.
	private let file: URL
	private let root: URL
	/// The document as it stands in the editor, put here before every load.
	///
	/// A property rather than a closure back into the pane: a scheme handler is
	/// called by WebKit at a time nobody chose, and reaching into a view from
	/// there is how a pane that has gone away is asked for its text.
	public var document: String
	/// Paths asked for that are not under the directory, or are not there. Read
	/// back by a test; the sentence somebody sees is counted from the document
	/// itself — see `HtmlPage.remoteReferences(in:)`.
	public private(set) var refused: Set<String> = []

	public init(file: URL, document: String = "") {
		self.file = file
		self.root = file.deletingLastPathComponent()
		self.document = document
	}

	public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
		guard let url = task.request.url else {
			task.didFailWithError(URLError(.badURL))
			return
		}
		if HtmlPage.isDocument(path: url.path, of: file) {
			answer(task, url: url, data: Data(document.utf8), mime: "text/html")
			return
		}
		guard let wanted = HtmlPage.file(at: url.path, under: root),
		      let data = try? Data(contentsOf: wanted)
		else {
			refused.insert(url.path)
			// A 404 rather than an error, for `DrawioAssetScheme`'s reason: a
			// page asks for things it can do without — a favicon, a source map —
			// and a failed request it expects must not look like a broken load.
			answer(task, url: url, data: Data(), mime: "text/plain", status: 404)
			return
		}
		answer(task, url: url, data: data, mime: HtmlPage.mediaType(for: wanted.pathExtension))
	}

	public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

	/// An `HTTPURLResponse`, for the reason written out in `DrawioAssetScheme`:
	/// a custom scheme answered with a bare `URLResponse` gives an
	/// `XMLHttpRequest` a status of 0, and a page that checks its own fetch
	/// against 200–299 then fails for a reason nothing reports.
	private func answer(
		_ task: WKURLSchemeTask, url: URL, data: Data, mime: String, status: Int = 200
	) {
		let response = HTTPURLResponse(
			url: url, statusCode: status, httpVersion: "HTTP/1.1",
			headerFields: [
				"Content-Type": mime,
				"Content-Length": String(data.count),
				// One origin, its own.
				"Access-Control-Allow-Origin": "\(HtmlPage.scheme)://\(HtmlPage.host)",
			]
		)!
		task.didReceive(response)
		task.didReceive(data)
		task.didFinish()
	}
}

/// The rule that keeps "nothing is fetched" true for everything a relative path
/// cannot reach.
///
/// A relative reference resolves to this app's own scheme and arrives at
/// `HtmlScheme`, which serves it or refuses it. An absolute `https://` one does
/// not: WebKit fetches it itself, and a navigation delegate never sees it,
/// because a delegate is asked about *navigations* and a stylesheet is not one.
/// Left to a delegate alone, a preview would refuse a click on a link and
/// quietly load a tracking pixel.
///
/// So the pane's web view carries a compiled content rule list that blocks every
/// load whose URL is not this scheme. Compiled once for the process and kept:
/// compiling is measured in tens of milliseconds and a pane is opened as often
/// as somebody presses a button.
@MainActor
public enum HtmlBlocking {
	/// Deny by default, then let this app's own scheme back through. Order is
	/// the whole of it — `ignore-previous-rules` undoes the block above it, and
	/// the two written the other way round block everything.
	static let rules = """
		[
		  {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
		  {"trigger": {"url-filter": "^\(HtmlPage.scheme)://"},
		   "action": {"type": "ignore-previous-rules"}}
		]
		"""

	private static let identifier = "abydos-html-preview"
	private static var compiled: WKContentRuleList?
	private static var compiling: Task<WKContentRuleList?, Never>?

	/// The list, compiled if this is the first pane to ask.
	///
	/// Nil when compiling failed, which is a build with something wrong in the
	/// JSON above rather than anything a document did. The pane treats that as
	/// what it is — it does not load the page at all, because a preview that
	/// cannot promise the network is shut is not a preview this app offers.
	public static func list() async -> WKContentRuleList? {
		if let compiled { return compiled }
		if let compiling { return await compiling.value }
		let task = Task { () -> WKContentRuleList? in
			try? await WKContentRuleListStore.default()?.compileContentRuleList(
				forIdentifier: identifier, encodedContentRuleList: rules
			)
		}
		compiling = task
		let list = await task.value
		compiling = nil
		compiled = list
		return list
	}
}
