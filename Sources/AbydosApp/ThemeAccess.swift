import Foundation

/// Watches which thread the palette is touched from.
///
/// **Why a watcher and not a lock.** 0400 is an abort inside CoreText with a nil
/// font, twice, from the installed build, and the surviving candidate was a torn
/// read of `Theme.current` — a struct of thirty-five colours assigned in one
/// statement and therefore in many stores. The audit found no reader off the
/// main thread, so there is nothing to fix; what there is to do is keep that
/// finding true, because it is a claim about 1580 reads in 99 files and the next
/// person to write one will not have read the audit.
///
/// **It records rather than traps.** An `assert` would turn a rare, real
/// condition into a debug-build crash at the moment it is least convenient to
/// investigate, and this is a bug that has appeared twice in a year. A line in
/// the log names the thread and is written once; the day it appears, the
/// hypothesis is alive again and the item has its evidence.
///
/// **What it costs.** Debug only — in release both calls compile away to
/// nothing, so the read path is exactly what it was. In a debug build it is one
/// `pthread_main_np` per read of the palette, which is a handful of nanoseconds
/// against reads that are already doing colour lookups and font resolution; the
/// suite and a driven session both run at their usual speed with it in.
enum ThemeAccess {
	#if DEBUG
	/// Said once, not once per read: a palette read on the wrong thread would
	/// otherwise be a thousand identical lines a second, which is a way of
	/// hiding it.
	private nonisolated(unsafe) static var said = false
	private nonisolated(unsafe) static var offMainReads = 0
	private nonisolated(unsafe) static var offMainWrites = 0
	private static let lock = NSLock()
	#endif

	@inline(__always)
	static func noteRead() {
		#if DEBUG
		guard !Thread.isMainThread else { return }
		note("read")
		#endif
	}

	@inline(__always)
	static func noteWrite() {
		#if DEBUG
		guard !Thread.isMainThread else { return }
		note("written")
		#endif
	}

	#if DEBUG
	private static func note(_ what: String) {
		lock.lock()
		if what == "read" { offMainReads += 1 } else { offMainWrites += 1 }
		let first = !said
		said = true
		lock.unlock()
		guard first else { return }

		let thread = Thread.current.description
		let where_ = Thread.callStackSymbols.dropFirst(2).prefix(8).joined(separator: "\n    ")
		FileHandle.standardError.write(Data("""
		THEME: the palette was \(what) off the main thread — 0400's surviving candidate is alive.
		    thread: \(thread)
		    \(where_)

		""".utf8))
	}

	/// What the run saw, for a driver to print. Nothing is the answer that keeps
	/// the audit true.
	static var reportForTesting: String {
		lock.lock()
		defer { lock.unlock() }
		guard offMainReads > 0 || offMainWrites > 0 else {
			return "palette touched on the main thread only"
		}
		return "palette touched off the main thread: \(offMainReads) read(s), \(offMainWrites) write(s)"
	}
	#else
	static var reportForTesting: String { "not checked in a release build" }
	#endif
}
