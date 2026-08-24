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

	/// Whether something holds a local port right now.
	///
	/// **Asked by trying to take the port, never by connecting to it.** A
	/// connect is not a neutral question to ask of a JDWP port. The JVM's
	/// transport accepts it, waits for the `JDWP-Handshake` bytes, gets a close
	/// instead, and gives up on the session:
	///
	///     Listening for transport dt_socket at address: 51400
	///     Debugger failed to attach: handshake failed - connection prematurally closed
	///
	/// after which the real debugger is refused and a suspended JVM waits for one
	/// that can no longer arrive. The poll below asks five times a second while a
	/// launch is in flight, so the probe was reliably the first thing to reach the
	/// port it was waiting for: it broke every launch it was watching, and the
	/// JVM's complaint named a debugger nobody had started yet.
	///
	/// `bind` asks the kernel who owns the address and touches nothing on the
	/// other side. It answers about ownership rather than about willingness to
	/// talk, which is the better question anyway — a JVM that has printed
	/// `Listening for transport` owns its port well before it will finish a
	/// handshake.
	///
	/// Two things it cannot tell, both harmless here: a port in `TIME_WAIT` reads
	/// as held, and a privileged port under 1024 refuses the bind with `EACCES`
	/// and so reads as free. The ports this waits on are ones `free()` has just
	/// handed out, or Gradle's 5005.
	public static func isOpen(_ port: Int) -> Bool {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { return false }
		defer { close(descriptor) }

		// Deliberately no SO_REUSEADDR: whether the bind is refused *is* the
		// question, and reuse is the one option that stops it being asked.
		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		address.sin_port = in_port_t(UInt16(port).bigEndian)

		let bound = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		if bound == 0 { return false }
		return errno == EADDRINUSE
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
