import Foundation

/// Where the things somebody keeps of their own live.
///
/// `$XDG_CONFIG_HOME`, or `~/.config` when it is not set — a path you already
/// back up, already have in a dotfiles repository, and can reach with `cd`.
/// Not Application Support, where macOS would put it: a folder nobody visits is
/// a folder nobody notices going missing, and everything under here is meant to
/// be edited by hand.
public enum UserConfiguration {
	public static var directory: URL {
		if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
			return URL(fileURLWithPath: xdg, isDirectory: true)
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".config", isDirectory: true)
	}

	/// A folder under it, named for the app.
	public static func folder(_ name: String) -> URL {
		directory.appendingPathComponent("abydos/\(name)", isDirectory: true)
	}
}
