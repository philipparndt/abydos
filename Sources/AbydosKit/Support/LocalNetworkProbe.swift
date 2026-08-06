import Foundation
import Network

/// Whether this app can reach the local network, asked directly.
///
/// macOS gates local-network traffic per application, and the gate is applied
/// to everything the app launches as well as to the app itself — a debugger, a
/// test run, the program being debugged. What a denied program sees is
/// `EHOSTUNREACH`, reported by Go as "connect: no route to host" and by
/// everything else as something equally unhelpful, which points at the network
/// rather than at a permission.
///
/// Two reasons to be able to ask on purpose. It tells the difference between a
/// broker that is down and a permission that was never granted, which is
/// otherwise guesswork. And asking is what *causes* the system to offer the
/// prompt: the permission belongs to the app, so a program it launches cannot
/// raise it — the app has to touch the network itself, once, for the grant to
/// exist for everything after.
public enum LocalNetworkProbe {
	public enum Result: Equatable, Sendable {
		/// A connection was accepted: the app has the permission it needs.
		case reachable
		/// Refused, which means something answered — the permission is there
		/// and nothing is listening on that port.
		case refused
		/// Nothing answered before the deadline.
		case timedOut
		/// The kernel said the host cannot be reached at all. On a local
		/// address that is what a denied permission looks like.
		case unreachable(String)

		public var summary: String {
			switch self {
			case .reachable:
				return "reachable — this app can use the local network"
			case .refused:
				return "refused — the permission is fine; nothing is listening there"
			case .timedOut:
				return "no answer before the deadline"
			case let .unreachable(detail):
				return """
				unreachable (\(detail))

				On an address in your own network that is what a missing Local Network
				permission looks like: the connection fails immediately rather than
				timing out. macOS grants it per application, and everything this app
				launches inherits the answer.

				System Settings ▸ Privacy & Security ▸ Local Network
				"""
			}
		}
	}

	/// Tries one TCP connection and says what happened.
	///
	/// Network.framework rather than a socket, because this is the path the
	/// system's own gate is expressed in: a denied connection fails here with
	/// the same error a program would get, without waiting for a timeout.
	public static func check(
		host: String,
		port: UInt16,
		timeout: TimeInterval = 5,
		completion: @escaping @Sendable (Result) -> Void
	) {
		let connection = NWConnection(
			host: NWEndpoint.Host(host),
			port: NWEndpoint.Port(integerLiteral: port),
			using: .tcp
		)
		let answered = Answered()

		connection.stateUpdateHandler = { state in
			switch state {
			case .ready:
				guard answered.claim() else { return }
				connection.cancel()
				completion(.reachable)
			case let .failed(error), let .waiting(error):
				guard answered.claim() else { return }
				connection.cancel()
				completion(Self.result(for: error))
			default:
				break
			}
		}
		connection.start(queue: .global())

		DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
			guard answered.claim() else { return }
			connection.cancel()
			completion(.timedOut)
		}
	}

	static func result(for error: NWError) -> Result {
		guard case let .posix(code) = error else { return .unreachable("\(error)") }
		switch code {
		case .ECONNREFUSED: return .refused
		case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN: return .unreachable("\(code)")
		case .ETIMEDOUT: return .timedOut
		default: return .unreachable("\(code)")
		}
	}

	/// The same question asked with a plain socket, for running as a child.
	///
	/// A program the app launches does not use Network.framework and does not
	/// inherit its niceties — it calls `connect` and is told `EHOSTUNREACH`.
	/// This is that, so the answer from a child is comparable with the answer
	/// from the app itself. The difference between the two is the whole
	/// question: the permission belongs to the app, and what is in doubt is
	/// whether what it launches inherits it.
	public static func checkWithSocket(host: String, port: UInt16, timeout: TimeInterval = 5) -> Result {
		var hints = addrinfo(
			ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
			ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
		)
		var list: UnsafeMutablePointer<addrinfo>?
		guard getaddrinfo(host, String(port), &hints, &list) == 0, let first = list else {
			return .unreachable("cannot resolve \(host)")
		}
		defer { freeaddrinfo(list) }

		let descriptor = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
		guard descriptor >= 0 else { return .unreachable("socket: \(errno)") }
		defer { close(descriptor) }

		var deadline = timeval(tv_sec: Int(timeout), tv_usec: 0)
		setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))

		guard connect(descriptor, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0 else {
			switch errno {
			case ECONNREFUSED: return .refused
			case ETIMEDOUT: return .timedOut
			default: return .unreachable("errno \(errno) — \(String(cString: strerror(errno)))")
			}
		}
		return .reachable
	}

	/// `host:port`, as somebody would type it.
	public static func parse(_ target: String) -> (host: String, port: UInt16)? {
		guard let colon = target.lastIndex(of: ":") else { return nil }
		let host = String(target[..<colon])
		guard let port = UInt16(target[target.index(after: colon)...]), !host.isEmpty else { return nil }
		return (host, port)
	}

	/// One answer only, however many ways the connection reports itself.
	private final class Answered: @unchecked Sendable {
		private let lock = NSLock()
		private var taken = false

		func claim() -> Bool {
			lock.lock()
			defer { lock.unlock() }
			if taken { return false }
			taken = true
			return true
		}
	}
}
