import Foundation

/// Finding a command-line tool.
///
/// An app launched from the Finder inherits almost no `PATH` — `/usr/bin:/bin`
/// and the two `sbin`s — while everything anybody installs lives in Homebrew's.
/// So a tool that works when the app is started from a terminal is missing when
/// it is started the way people actually start it, which reads as a feature
/// that "sometimes does not work".
public enum Executables {
	/// Where tools live when `PATH` does not say.
	///
	/// Homebrew first, on both architectures, then the system.
	public static let fallbackDirectories = [
		"/opt/homebrew/bin",
		"/usr/local/bin",
		"/usr/bin",
		"/bin",
	]

	/// The full path of a tool, or nil when it is not installed.
	public static func locate(_ name: String) -> String? {
		locate(name, path: ProcessInfo.processInfo.environment["PATH"])
	}

	/// - Parameter path: a `PATH` to search first, as the environment gives it.
	///   Separate so the search can be tested without one.
	public static func locate(_ name: String, path: String?) -> String? {
		let manager = FileManager.default
		let searched = (path?.split(separator: ":").map(String.init) ?? []) + fallbackDirectories

		for directory in searched where !directory.isEmpty {
			let candidate = directory + "/" + name
			if manager.isExecutableFile(atPath: candidate) { return candidate }
		}
		return nil
	}
}
