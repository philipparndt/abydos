import AbydosKit
import Foundation

/// One proxy per server, shared by that server's board tabs.
///
/// One, because a server's tabs share one web data store — that is what keeps
/// the page's cache and service worker from one board to the next — and the
/// proxy's secret is a cookie in that store, scoped to 127.0.0.1 and not to a
/// port. Two proxies for one store would overwrite each other's cookie, and the
/// first would then refuse its own page. On the port each server asks for
/// first, because the port is part of the page's origin.
@MainActor
final class VboardProxies {
	static let shared = VboardProxies()

	private var running: [String: (proxy: VboardProxy, users: Int)] = [:]
	private var starting: [String: Task<VboardProxy, Error>] = [:]

	/// The server's proxy, started if need be, signing with `token` from now on.
	func acquire(server: URL, token: String?) async throws -> VboardProxy {
		let origin = MemoryVboardCredentials.origin(of: server)
		if let entry = running[origin] {
			entry.proxy.token = token
			running[origin] = (entry.proxy, entry.users + 1)
			return entry.proxy
		}
		if let pending = starting[origin] {
			let proxy = try await pending.value
			proxy.token = token
			if let entry = running[origin] { running[origin] = (entry.proxy, entry.users + 1) }
			return proxy
		}
		let task = Task { () throws -> VboardProxy in
			let proxy = VboardProxy(upstream: server, token: token)
			_ = try await proxy.start(preferredPort: VboardPage.preferredPort(for: server))
			return proxy
		}
		starting[origin] = task
		defer { starting[origin] = nil }
		let proxy = try await task.value
		running[origin] = (proxy, (running[origin]?.users ?? 0) + 1)
		return proxy
	}

	/// A tab is done with its server's proxy; the last one stops it.
	func release(_ proxy: VboardProxy) {
		let origin = MemoryVboardCredentials.origin(of: proxy.upstream)
		guard let entry = running[origin], entry.proxy === proxy else { return }
		if entry.users > 1 {
			running[origin] = (proxy, entry.users - 1)
		} else {
			running[origin] = nil
			proxy.stop()
		}
	}
}
