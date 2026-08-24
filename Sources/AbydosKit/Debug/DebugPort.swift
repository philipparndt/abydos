import Foundation

/// Local TCP ports, for the two questions a debugger asks about one.
///
/// Both were already here in one form: `PortForward` needed a free port to
/// forward a pod onto, and it found one the way this does. It is here now
/// because a second caller wants it — a JVM started by a wrapper script is
/// waiting on a port on *this* machine, with no pod and no forward involved —
/// and a copy of the socket dance in two files is how the two drift apart.
public enum DebugPort {
	/// A port nobody is using, found by asking the kernel for one and letting it
	/// go again.
	///
	/// There is a gap between letting it go and something else binding it, and
	/// nothing can close that gap: the JVM has to be told a number before it
	/// starts, and it is the JVM that binds. What makes it safe enough is that
	/// the kernel hands out ephemeral ports in a rotation rather than reusing the
	/// last one, so the number is not one anything else is about to be given.
	public static func free() -> Int? {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { return nil }
		defer { close(descriptor) }

		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		address.sin_port = 0

		let bound = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bound == 0 else { return nil }

		var assigned = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		let named = withUnsafeMutablePointer(to: &assigned) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				getsockname(descriptor, $0, &length)
			}
		}
		guard named == 0 else { return nil }
		return Int(UInt16(bigEndian: assigned.sin_port))
	}

	/// How long a single probe may take. Loopback either answers at once or is
	/// not going to.
	private static let probeTimeout: TimeInterval = 0.25

	/// Whether something is listening on a local port right now.
	///
	/// **Non-blocking, and that is not a refinement.** A plain `connect` to a
	/// listening socket whose backlog is full does not fail — it waits, through
	/// SYN retransmissions, for as long as the kernel feels like. A test that
	/// probed such a port took 88 seconds, and this is called from the poll loop
	/// below while a launch is in flight, so a probe that blocks is a launch that
	/// hangs with nothing on screen explaining it.
	public static func isOpen(_ port: Int) -> Bool {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { return false }
		defer { close(descriptor) }

		let flags = fcntl(descriptor, F_GETFL, 0)
		guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }

		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		address.sin_port = in_port_t(UInt16(port).bigEndian)

		let started = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		// Loopback commonly completes inside the call.
		if started == 0 { return true }
		guard errno == EINPROGRESS else { return false }

		var watched = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
		guard poll(&watched, 1, Int32(probeTimeout * 1000)) > 0 else { return false }

		// Writable is not the same as connected: a refused connection becomes
		// writable too, and the error is only readable off the socket itself.
		var failure: Int32 = 0
		var length = socklen_t(MemoryLayout<Int32>.size)
		guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &failure, &length) == 0 else {
			return false
		}
		return failure == 0
	}

	/// Waits until something is listening, or gives up.
	///
	/// **Polled, and the poll is the point.** A JVM under a wrapper script does
	/// not open its port when the script starts: Maven has to resolve plugins,
	/// Gradle has to talk to a daemon and compile, and either can take a minute
	/// on a cold cache. There is nothing to be notified by — the port is opened
	/// by a grandchild process this app never sees — so the only question is how
	/// long to keep asking.
	///
	/// A default of two minutes, because the alternative failure is worse: giving
	/// up on a build that was going to work leaves a JVM suspended at its first
	/// instruction with nothing coming to release it, and the program simply
	/// never runs.
	///
	/// - Returns: true when the port opened, false on timeout or cancellation.
	@discardableResult
	public static func waitUntilOpen(
		_ port: Int,
		timeout: TimeInterval = 120,
		interval: TimeInterval = 0.2,
		isOpen: (Int) -> Bool = DebugPort.isOpen
	) async -> Bool {
		// Counted in attempts rather than against a clock, so a machine that
		// suspends mid-wait does not decide it has timed out on waking.
		let attempts = max(1, Int(timeout / interval))
		for _ in 0..<attempts {
			if Task.isCancelled { return false }
			if isOpen(port) { return true }
			// Sleeping rather than spinning: `connect` to a closed port on
			// loopback returns immediately, so without this the loop is a busy
			// wait on a core for as long as the build takes.
			try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
		}
		return isOpen(port)
	}
}
