import Foundation

/// A line in `~/Library/Logs/Abydos/<name>.log`.
///
/// For the things that go wrong on somebody else's desk. A language server that
/// will not load a workspace, a `+` that made the wrong kind of tab: both are
/// invisible from here, both are reproducible over there, and the difference
/// between a bug report that can be acted on and one that cannot is whether the
/// person hitting it could see anything at all.
///
/// Written on the event rather than behind a switch, so it is already there the
/// first time somebody looks — a log that has to be turned on is a log that is
/// always off when it is wanted. Nothing writes per keystroke; these are
/// lifetime events, a handful per session.
public enum DiagnosticLog {
	/// Where the logs are, said the way somebody would type it.
	public static func path(_ name: String) -> String {
		"~/Library/Logs/Abydos/\(name).log"
	}

	public static func directory() -> URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Logs/Abydos", isDirectory: true)
	}

	public static func url(_ name: String) -> URL {
		directory().appendingPathComponent("\(name).log")
	}

	/// Past this, the log starts again — the previous one kept beside it as
	/// `<name>.log.1`. A talkative language server can write a megabyte in an
	/// afternoon, and a log nobody can open is a log nobody reads.
	static let sizeLimit = 1_000_000

	/// Appends one line, stamped. Never throws: a log that can break the thing
	/// it is logging is worse than no log.
	public static func write(_ message: String, to name: String) {
		let directory = directory()
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let file = directory.appendingPathComponent("\(name).log")
		rotateIfLarge(file)

		let stamp = ISO8601DateFormatter.logStamp.string(from: Date())
		let line = "\(stamp) \(message)\n"
		guard let data = line.data(using: .utf8) else { return }

		if let handle = try? FileHandle(forWritingTo: file) {
			handle.seekToEndOfFile()
			handle.write(data)
			try? handle.close()
		} else {
			try? data.write(to: file)
		}
	}

	/// One generation back, and no further: the interesting part of a log like
	/// this is always the end of it.
	private static func rotateIfLarge(_ file: URL) {
		let manager = FileManager.default
		let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		guard size > sizeLimit else { return }
		let previous = file.appendingPathExtension("1")
		try? manager.removeItem(at: previous)
		try? manager.moveItem(at: file, to: previous)
	}
}

extension ISO8601DateFormatter {
	fileprivate static let logStamp: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime]
		formatter.timeZone = .current
		return formatter
	}()
}
