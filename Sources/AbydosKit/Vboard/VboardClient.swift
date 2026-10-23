import Foundation

/// The few calls a board tab makes to a vboard server: put a file there as a
/// private temporary board, take it back, put a changed file in its place, and
/// remove it.
///
/// Everything here is vboard's documented `/api/v1`, and nothing else. A
/// server of any version that kept that contract is a server this works with,
/// and nothing about vboard has to be on this machine for the program to build.
///
/// Two things every board request carries:
///
///  * **The board's key, in `X-Board-Key`.** Never in a URL. vboard refuses a
///    key in a query string with 400 before it does anything else, and a key in
///    a request line would be in somebody's access log.
///  * **The session of the tab's web view, as cookies.** On a server with a
///    login, the person signs in inside the tab, through the server's own login
///    page. These calls are made by the app, not the page, so they borrow that
///    session rather than having one of their own. No token is made or kept.
///
/// Bodies are streamed from and to files. A board with a recorded workshop on
/// it is hundreds of megabytes of base64, and holding that as a `Data` or a
/// `String` would be the slowest possible way to move it.
public final class VboardClient {
	/// What came of a call, in the terms the tab acts on rather than as a
	/// status code.
	public enum Outcome: Equatable {
		/// The board exists now. Import and create.
		case created
		/// It worked, and there is nothing more to say: a delete, a health check.
		case done
		/// The board's content was swapped for the file's in place.
		case replaced
		/// vboard said no on purpose: an id that is taken, or a replacement whose
		/// file is not newer than the board. The tab's next step differs.
		case refused
		/// No such board, or not for this key — which vboard deliberately
		/// cannot tell apart.
		case gone
		/// The server wants somebody signed in, and nobody is.
		case signedOut
		/// The server answered nothing. The message is the system's.
		case unreachable(String)
		/// Anything else, with what the server said about it.
		case failed(status: Int, message: String)
	}

	/// What a save brings back besides the file.
	public struct Export {
		/// The file, in the directory asked for, under a name of its own.
		public let file: URL
		/// The board's content marker at the moment of the export, which says
		/// whether a later replace is newer.
		public let contentRev: Int?
	}

	public let server: URL
	private let session: URLSession
	private let cookies: () async -> [HTTPCookie]

	/// - Parameters:
	///   - server: the server's address, as somebody typed it into the setting.
	///   - cookies: the tab's web session, read fresh before every call, since a
	///     sign-in can happen at any moment in the page.
	///   - protocolClasses: for a test, a stub that answers in place of a
	///     network. The app passes nothing.
	public init(
		server: URL,
		cookies: @escaping () async -> [HTTPCookie] = { [] },
		protocolClasses: [AnyClass]? = nil
	) {
		self.server = server
		self.cookies = cookies
		let configuration = URLSessionConfiguration.ephemeral
		configuration.urlCache = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
		// Inactivity, not the whole transfer: a 300 MB upload on hotel Wi-Fi is
		// slow and still working.
		configuration.timeoutIntervalForRequest = 60
		configuration.timeoutIntervalForResource = 60 * 60
		// The session is the web view's; this one keeps none of its own.
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		if let protocolClasses { configuration.protocolClasses = protocolClasses }
		session = URLSession(configuration: configuration)
	}

	deinit { session.invalidateAndCancel() }

	// MARK: The calls

	/// Whether something that is a vboard server answers at that address.
	public func health() async -> Outcome {
		await send(request(path: "healthz", method: "GET"))
	}

	/// Whether a board could be made now: `.done` when nobody needs to sign in
	/// or somebody has, `.signedOut` when the server wants a sign-in first.
	///
	/// Asked before an import, because an import made while signed out sends
	/// the whole file — hundreds of megabytes for some boards — only to be told
	/// 401 at the end. `me/usage` is the cheapest call that needs a person: on a
	/// server without a login it answers for the single local user, with one it
	/// answers 401 to anybody not signed in (`registerUsage` in vboard).
	public func signedIn() async -> Outcome {
		await send(request(path: "api/v1/me/usage", method: "GET"))
	}

	/// The file as a new private temporary board, under `id`.
	///
	/// Under an id because the import that takes one is the one that keeps the
	/// file's item ids; without it every item came back renamed.
	public func importBoard(
		file: URL,
		id: String,
		key: VboardKey,
		progress: ((Double) -> Void)? = nil
	) async -> Outcome {
		var request = request(
			path: "api/v1/boards/import",
			query: [URLQueryItem(name: "temporary", value: "true"), URLQueryItem(name: "id", value: id)],
			method: "POST",
			key: key
		)
		request.setValue("application/vnd.vboard+json", forHTTPHeaderField: "Content-Type")
		return await upload(request, from: file, progress: progress) { status, json in
			switch status {
			case 201: return .created
			// The same id, a temporary board and a newer file: vboard replaced it.
			case 200 where json?["replaced"] as? Bool == true: return .replaced
			case 409: return .refused
			case 410: return .gone
			default: return nil
			}
		}
	}

	/// Puts a changed file in place of the board's content, same id and key.
	///
	/// vboard does this only when the file's marker is newer than the board's.
	/// A hand-edited file or an older checkout is refused, and the tab opens the
	/// file again as a new board instead.
	public func replace(file: URL, id: String, key: VboardKey) async -> Outcome {
		await importBoard(file: file, id: id, key: key)
	}

	/// A blank private temporary board, for a file that has nothing in it yet.
	///
	/// The key travels in the body here: that is where vboard's create call
	/// takes it. It is still never in a URL.
	public func create(id: String, name: String, key: VboardKey) async -> Outcome {
		var request = request(path: "api/v1/boards", method: "POST")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONSerialization.data(withJSONObject: [
			"id": id, "name": name, "temporary": true, "private": true, "key": key.encoded,
		])
		return await send(request) { status, _ in
			switch status {
			case 201: return .created
			// "Replays": an id that exists and is the caller's comes back as 200
			// unchanged. A board id made from eight random bytes is not one this
			// tab made before, so it is somebody else's and the id is taken.
			case 200, 409: return .refused
			default: return nil
			}
		}
	}

	/// The board as a file, written into `directory` under a name of its own.
	///
	/// Into a directory the caller names — beside the file it will replace — so
	/// the rename that puts it in place never crosses a volume and is atomic.
	public func export(id: String, key: VboardKey, into directory: URL) async -> Result<Export, ExportFailure> {
		let request = await signed(request(path: "api/v1/boards/\(id)/export.vboard", method: "GET", key: key))
		do {
			let (temporary, response) = try await session.download(for: request)
			defer { try? FileManager.default.removeItem(at: temporary) }
			let status = (response as? HTTPURLResponse)?.statusCode ?? 0
			guard status == 200 else {
				let body = try? Data(contentsOf: temporary)
				return .failure(ExportFailure(outcome: Self.outcome(status: status, body: body, response: response)))
			}
			// A login page answered with 200 is not a board, and writing it over
			// somebody's file is the one thing a save must never do.
			guard VboardFile.inspect(temporary) == .board else {
				return .failure(ExportFailure(outcome: .signedOut))
			}
			let destination = directory.appendingPathComponent(".\(id)-\(UUID().uuidString).vboard-part")
			try FileManager.default.moveItem(at: temporary, to: destination)
			let rev = (response as? HTTPURLResponse)?
				.value(forHTTPHeaderField: "X-Vboard-Content-Rev").flatMap { Int($0) }
			return .success(Export(file: destination, contentRev: rev))
		} catch {
			return .failure(ExportFailure(outcome: .unreachable(error.localizedDescription)))
		}
	}

	public struct ExportFailure: Error, Equatable {
		public let outcome: Outcome
	}

	/// Removes the board for everybody on it.
	public func delete(id: String, key: VboardKey) async -> Outcome {
		await send(request(path: "api/v1/boards/\(id)", method: "DELETE", key: key)) { status, _ in
			switch status {
			case 204, 200: return .done
			default: return nil
			}
		}
	}

	// MARK: Plumbing

	func request(path: String, query: [URLQueryItem] = [], method: String, key: VboardKey? = nil) -> URLRequest {
		var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
		let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
		components.path = base + "/" + path
		components.queryItems = query.isEmpty ? nil : query
		components.fragment = nil
		var request = URLRequest(url: components.url!)
		request.httpMethod = method
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if let key { request.setValue(key.encoded, forHTTPHeaderField: "X-Board-Key") }
		return request
	}

	/// The request with the tab's session on it, as a `Cookie` header.
	///
	/// Set by hand rather than left to the session's cookie store: whether a
	/// store's cookies reach a request depends on policies a test's stub never
	/// sees, and a session that silently goes unsent is a save that silently
	/// fails as "signed out". A scratch `HTTPCookieStorage()` was tried for the
	/// matching and kept nothing at all, which is that failure exactly.
	private func signed(_ request: URLRequest) async -> URLRequest {
		var request = request
		request.httpShouldHandleCookies = false
		guard let url = request.url else { return request }
		let header = HTTPCookie.requestHeaderFields(with: Self.cookies(await cookies(), for: url))
		for (field, value) in header { request.setValue(value, forHTTPHeaderField: field) }
		return request
	}

	/// The cookies a browser would send to this address: the domain is the
	/// host or a parent of it, the path is a prefix of the URL's, a `Secure`
	/// cookie goes only over HTTPS, and an expired one not at all.
	static func cookies(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
		guard let host = url.host?.lowercased() else { return [] }
		let path = url.path.isEmpty ? "/" : url.path
		return cookies.filter { cookie in
			let domain = cookie.domain.lowercased()
			let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
			let domainMatches = host == bare || host.hasSuffix("." + bare)
			let pathMatches = path.hasPrefix(cookie.path)
				&& (cookie.path.hasSuffix("/") || path.count == cookie.path.count
					|| path[path.index(path.startIndex, offsetBy: cookie.path.count)] == "/")
			let secureMatches = !cookie.isSecure || url.scheme == "https"
			let fresh = cookie.expiresDate.map { $0 > now } ?? true
			return domainMatches && pathMatches && secureMatches && fresh
		}
	}

	private func send(
		_ request: URLRequest,
		decide: (Int, [String: Any]?) -> Outcome? = { status, _ in (200..<300).contains(status) ? .done : nil }
	) async -> Outcome {
		do {
			let (body, response) = try await session.data(for: await signed(request))
			return Self.outcome(response: response, body: body, decide: decide)
		} catch {
			return .unreachable(error.localizedDescription)
		}
	}

	private func upload(
		_ request: URLRequest,
		from file: URL,
		progress: ((Double) -> Void)?,
		decide: (Int, [String: Any]?) -> Outcome?
	) async -> Outcome {
		do {
			let delegate = progress.map(ProgressRelay.init)
			let (body, response) = try await session.upload(for: await signed(request), fromFile: file, delegate: delegate)
			return Self.outcome(response: response, body: body, decide: decide)
		} catch {
			return .unreachable(error.localizedDescription)
		}
	}

	static func outcome(
		response: URLResponse,
		body: Data,
		decide: (Int, [String: Any]?) -> Outcome?
	) -> Outcome {
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
		// A 2xx that is not JSON is a login page the server redirected to. vboard
		// answers every API call it understands with JSON.
		if (200..<300).contains(status), status != 204, json == nil, !body.isEmpty,
		   !(response.mimeType ?? "").contains("json") {
			return .signedOut
		}
		if let decided = decide(status, json) { return decided }
		return outcome(status: status, body: body, response: response)
	}

	static func outcome(status: Int, body: Data?, response: URLResponse) -> Outcome {
		switch status {
		case 401: return .signedOut
		case 404: return .gone
		default:
			let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
			let message = json?["error"] as? String
				?? HTTPURLResponse.localizedString(forStatusCode: status)
			return .failed(status: status, message: message)
		}
	}
}

/// Hands a transfer's progress to whoever asked, as a fraction.
///
/// Through the task's own `Progress`, picked up when the task is made, because
/// the async upload and download calls have no other place to report it.
private final class ProgressRelay: NSObject, URLSessionTaskDelegate {
	let report: (Double) -> Void
	private var observation: NSKeyValueObservation?

	init(report: @escaping (Double) -> Void) { self.report = report }

	func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
		observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
			report(progress.fractionCompleted)
		}
	}
}
