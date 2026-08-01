import Foundation

/// A Go program's `net/http/pprof` endpoint.
///
/// Everything the profiler needs comes from one HTTP server the program is
/// already running: what profiles it offers, and the profiles themselves. No
/// agent, no build flag, nothing to install into the program under study —
/// which is the whole reason this approach is worth having.
public struct PprofEndpoint: Equatable, Sendable {
	/// Where the pprof handlers are mounted, usually `/debug/pprof`.
	public let base: URL

	public init(base: URL) {
		self.base = base
	}

	/// Accepts what somebody would type: a port, a host and port, or a URL.
	///
	/// `6060` and `localhost:6060` and `http://localhost:6060/debug/pprof` all
	/// mean the same thing, and asking for the third when the first is what
	/// you know is a small daily tax.
	public init?(text: String) {
		var trimmed = text.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return nil }

		if let port = Int(trimmed), (1...65535).contains(port) {
			trimmed = "http://localhost:\(port)"
		} else if !trimmed.contains("://") {
			trimmed = "http://" + trimmed
		}

		guard var components = URLComponents(string: trimmed), components.host != nil else {
			return nil
		}
		// A path that already names the handlers is kept; anything else gets
		// the standard mount point.
		let path = components.path
		if !path.contains("/debug/pprof") {
			components.path = (path.hasSuffix("/") ? String(path.dropLast()) : path) + "/debug/pprof"
		}
		while components.path.hasSuffix("/") { components.path.removeLast() }
		guard let url = components.url else { return nil }
		base = url
	}

	public var displayName: String {
		let host = base.host ?? "unknown"
		guard let port = base.port else { return host }
		return "\(host):\(port)"
	}

	/// A profile this endpoint can produce.
	public struct Kind: Equatable, Sendable, Identifiable {
		public let name: String
		/// What it is for, in a sentence.
		public let summary: String
		/// Whether it is collected over time rather than snapshotted.
		public let isTimed: Bool

		public var id: String { name }

		public init(name: String, summary: String, isTimed: Bool = false) {
			self.name = name
			self.summary = summary
			self.isTimed = isTimed
		}
	}

	/// What `net/http/pprof` registers by default.
	///
	/// Listed rather than discovered so the picker has something to show
	/// before anything has been fetched; the index page is read on connecting
	/// and adds whatever else the program registered.
	public static let standardKinds: [Kind] = [
		Kind(name: "profile", summary: "Where the CPU time goes", isTimed: true),
		Kind(name: "heap", summary: "What is holding memory now"),
		Kind(name: "allocs", summary: "Everything allocated since the start"),
		Kind(name: "goroutine", summary: "Every goroutine and where it is"),
		Kind(name: "block", summary: "Waiting on channels and locks"),
		Kind(name: "mutex", summary: "Contended locks"),
		Kind(name: "threadcreate", summary: "Where OS threads come from"),
	]

    /// The URL for one profile.
	public func url(for kind: String, seconds: Int? = nil) -> URL {
		var components = URLComponents(
			url: base.appendingPathComponent(kind), resolvingAgainstBaseURL: false
		)
		// Protobuf rather than the text form: `debug=0` is the default for
		// most, but `goroutine` hands back a text dump unless it is asked.
		var query = [URLQueryItem(name: "debug", value: "0")]
		if let seconds { query.append(URLQueryItem(name: "seconds", value: "\(seconds)")) }
		components?.queryItems = query
		return components?.url ?? base.appendingPathComponent(kind)
	}

	/// The profiles this endpoint actually offers.
	///
	/// The index page lists them, including any a program registered itself.
	/// Parsed from the HTML rather than guessed, because a program that only
	/// mounted some of the handlers should not be offered the rest.
	public static func kinds(inIndexPage html: String) -> [Kind] {
		var found: [String] = []
		var seen: Set<String> = []

		// Links look like `<a href='allocs?debug=1'>`; the name is what comes
		// before the query. Both quote characters, because Go writes the table
		// with single quotes and the links below it with double ones.
		var remainder = Substring(html)
		while let start = remainder.range(of: "href=") {
			remainder = remainder[start.upperBound...]
			guard let quote = remainder.first, quote == "\"" || quote == "'" else { continue }
			remainder = remainder.dropFirst()
			guard let end = remainder.firstIndex(of: quote) else { break }
			let target = String(remainder[..<end])
			remainder = remainder[end...]

			let name = target
				.split(separator: "?").first
				.map(String.init)?
				.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
			// The index links to itself and to the text-only handlers, which
			// are not profiles.
			let notProfiles: Set<String> = ["", "cmdline", "trace", "symbol", "debug/pprof"]
			guard !notProfiles.contains(name), !name.contains("/"), seen.insert(name).inserted
			else { continue }
			found.append(name)
		}

		let known = Dictionary(uniqueKeysWithValues: standardKinds.map { ($0.name, $0) })
		return found.map { name in
			known[name] ?? Kind(name: name, summary: "Registered by the program")
		}
	}
}

/// Fetching profiles over HTTP.
public actor PprofClient {
	public enum Failure: Error, Equatable {
		case unreachable(String)
		case badStatus(Int)
		case notAProfile
	}

	private let session: URLSession

	public init(timeout: TimeInterval = 30) {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = timeout
		// A CPU profile takes as long as it was asked to take, so the resource
		// timeout has to be generous where the request timeout is not.
		configuration.timeoutIntervalForResource = max(timeout, 300)
		session = URLSession(configuration: configuration)
	}

	/// Reads the index page and returns what the program offers.
	public func kinds(at endpoint: PprofEndpoint) async throws -> [PprofEndpoint.Kind] {
		let (data, response) = try await get(endpoint.base)
		guard (200..<300).contains(response.statusCode) else {
			throw Failure.badStatus(response.statusCode)
		}
		let kinds = PprofEndpoint.kinds(inIndexPage: String(decoding: data, as: UTF8.self))
		return kinds.isEmpty ? PprofEndpoint.standardKinds : kinds
	}

	/// Fetches and decodes one profile.
	///
	/// `seconds` applies to the timed ones: a CPU profile is collected over a
	/// window, and the request does not return until it is over.
	public func profile(
		_ kind: String,
		from endpoint: PprofEndpoint,
		seconds: Int? = nil
	) async throws -> PprofProfile {
		let (data, response) = try await get(endpoint.url(for: kind, seconds: seconds))
		guard (200..<300).contains(response.statusCode) else {
			throw Failure.badStatus(response.statusCode)
		}
		do {
			return try PprofDecoder.decode(data)
		} catch {
			// A pprof handler answers an error in plain text with a 200, which
			// would otherwise surface as "corrupt".
			throw Failure.notAProfile
		}
	}

	private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
		do {
			let (data, response) = try await session.data(from: url)
			guard let http = response as? HTTPURLResponse else { throw Failure.notAProfile }
			return (data, http)
		} catch let failure as Failure {
			throw failure
		} catch {
			throw Failure.unreachable(error.localizedDescription)
		}
	}
}
