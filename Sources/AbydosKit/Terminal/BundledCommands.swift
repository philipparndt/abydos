import Foundation

/// The commands this app ships for use in its own terminal.
///
/// `abydos-icat` prints a picture on the grid using the graphics protocol the
/// terminal already speaks. Nothing on a Mac ships a command that asks for
/// that: kitty's `icat` comes with kitty, and the alternatives draw with
/// blocks instead.
///
/// Put on the PATH of every shell the app starts — including the ones tmux
/// starts, since tmux inherits the environment of whatever launched the
/// server — and appended rather than prepended, so a command somebody already
/// has keeps working. Shadowing what is on somebody's PATH is not this app's
/// business.
public enum BundledCommands {
	/// Where they live inside the app, or nil when running outside a bundle.
	public static var directory: String? {
		guard let resources = Bundle.main.resourceURL else { return nil }
		let bin = resources.appendingPathComponent("bin", isDirectory: true)
		guard FileManager.default.fileExists(atPath: bin.path) else { return nil }
		return bin.path
	}

	/// The names it provides, for anything that wants to say so.
	public static let names = ["abydos-icat"]
}
