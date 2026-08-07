import Foundation

/// Writing to a pipe nobody is reading is an error, not a death.
///
/// By default a process that writes to a pipe whose read end has closed is
/// killed outright with SIGPIPE. There is no crash report for it, nothing on
/// standard error, and no chance to handle anything: the process is simply not
/// there any more, with exit status 141. An afternoon went into "Abydos exited
/// again and there is no crash report" before the exit status said what it was.
///
/// It is not a rare corner either. This app writes to a pty every time somebody
/// types, and to a pipe for every `git`, language server, debug adapter and
/// tmux command it runs. Any of those going away between the check and the
/// write — a shell that just exited, a tmux server that stopped — is an
/// ordinary event, and every one of them was fatal.
///
/// Ignoring the signal turns each into `EPIPE` from `write`, which the callers
/// already handle: `PseudoTerminal.drainOnce` has read `errno` and dropped what
/// it could not send since it was written. That code had simply never run.
public enum BrokenPipes {
	/// Sets the disposition, once, however many times this is called.
	///
	/// Every executable in this package should call it before doing anything —
	/// it is process-wide state, and setting it after the first write is a race
	/// with the very thing it prevents.
	public static func ignore() {
		once.pointee = true
	}

	private static let once: UnsafeMutablePointer<Bool> = {
		signal(SIGPIPE, SIG_IGN)
		let flag = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
		flag.initialize(to: true)
		return flag
	}()

	/// Whether the signal is being ignored, for a test to assert on.
	public static var isIgnored: Bool {
		var current = sigaction()
		guard sigaction(SIGPIPE, nil, &current) == 0 else { return false }
		// Compared as addresses: a C function pointer is not Equatable, and
		// SIG_IGN is a sentinel address rather than a function anybody calls.
		let handler = unsafeBitCast(
			current.__sigaction_u.__sa_handler, to: UnsafeRawPointer?.self
		)
		let ignored = unsafeBitCast(SIG_IGN, to: UnsafeRawPointer?.self)
		return handler == ignored
	}
}
