import Foundation

/// A note saying which model the app was about to render, so that a render which
/// kills the process cannot do it twice.
///
/// **The class of fault this exists for.** A 3D viewer is a large amount of
/// somebody else's code reached through SwiftUI, and it can fail in ways nothing
/// here is able to catch: a Swift precondition is not an error, it is the end of
/// the process. That happened — a bundle built without its shader library aborted
/// on `MetalView.swift:80` the moment a viewer was mounted — and the part that
/// made it serious was not the crash. It was that the session faithfully restored
/// the tab that caused it, so the app died a second into every launch and could
/// not be started at all until a file was edited by hand.
///
/// So the note is written *before* the render and cleared a few seconds after,
/// once the app is plainly still alive. Finding one at startup means the last run
/// did not survive that model, and it is not offered again until somebody asks
/// for it.
///
/// Deliberately not a crash reporter. It does not say what went wrong or try to
/// find out; it answers one question — "did this kill us last time?" — which is
/// the only one that has to be answered before deciding whether to try again.
public enum ViewerGuard {
	/// Where the note lives.
	///
	/// Beside the recents rather than in the project: the guard is about this
	/// machine's last run, and a model opened from outside any project has to be
	/// covered by it too.
	public static func noteURL(
		in directory: URL = ViewerGuard.applicationSupport()
	) -> URL {
		directory.appendingPathComponent("mounting-model")
	}

	public static func applicationSupport() -> URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
		return base.appendingPathComponent("Abydos", isDirectory: true)
	}

	/// The model the last run died rendering, if it did.
	public static func blamed(in directory: URL = ViewerGuard.applicationSupport()) -> String? {
		guard let text = try? String(contentsOf: noteURL(in: directory), encoding: .utf8) else {
			return nil
		}
		let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
		return path.isEmpty ? nil : path
	}

	/// Whether this particular model is the one that did it.
	public static func isBlamed(
		_ path: String, in directory: URL = ViewerGuard.applicationSupport()
	) -> Bool {
		guard !path.isEmpty else { return false }
		return blamed(in: directory) == path
	}

	/// Records that a render is about to start.
	///
	/// Written through to the disk before returning, because the whole value of
	/// this is that it outlives a process that is about to stop existing without
	/// warning. A note still sitting in a buffer when the trap fires says nothing.
	public static func begin(
		_ path: String, in directory: URL = ViewerGuard.applicationSupport()
	) {
		guard !path.isEmpty else { return }
		try? FileManager.default.createDirectory(
			at: directory, withIntermediateDirectories: true
		)
		let handle = try? FileHandle(forWritingTo: noteURL(in: directory))
		if let handle {
			try? handle.truncate(atOffset: 0)
			try? handle.write(contentsOf: Data(path.utf8))
			try? handle.synchronize()
			try? handle.close()
		} else {
			try? Data(path.utf8).write(to: noteURL(in: directory), options: .atomic)
		}
	}

	/// Clears the note. Called once the app has plainly survived the render.
	public static func settled(in directory: URL = ViewerGuard.applicationSupport()) {
		try? FileManager.default.removeItem(at: noteURL(in: directory))
	}

	/// How long after a render the app is taken to have survived it.
	///
	/// The failure this guards against arrives during the first layout pass, so
	/// it is a second away rather than a minute. Long enough to cover that and
	/// short enough that quitting straight after opening a model does not leave a
	/// note behind — which would refuse a model that never did anything wrong.
	public static let settleDelay: TimeInterval = 5
}
