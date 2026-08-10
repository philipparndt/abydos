import Foundation

/// The commands this app ships for use in its own terminal.
///
/// `abydos` opens a project or a file. Typed in one of this app's own panes it
/// opens the file in *that window's* editor rather than going round through
/// LaunchServices, which is a distinction only the pty can make.
///
/// `abydos-icat` prints a picture on the grid using the graphics protocol the
/// terminal already speaks. Nothing on a Mac ships a command that asks for
/// that: kitty's `icat` comes with kitty, and the alternatives draw with
/// blocks instead.
///
/// `abydos-bench` fills the screen as fast as it can and says how many frames
/// it managed, which is the question to ask when the terminal feels slow. It
/// ships with the app so it can be run against the build that is installed
/// rather than against a checkout somebody still has to find.
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

	/// The app bundle this is running out of, when it is running out of one.
	///
	/// `abydos` falls back to `open -a` when its escape reaches nobody, and the
	/// app it should open is the one somebody is looking at. Left to itself the
	/// command opens `/Applications/Abydos.app`, which for anybody running a
	/// checkout is a different build — or nothing at all.
	public static var appBundle: String? {
		let path = Bundle.main.bundleURL.path
		guard path.hasSuffix(".app") else { return nil }
		return path
	}

	/// What this terminal calls itself, in `TERM_PROGRAM`.
	///
	/// Every terminal sets it and `abydos <file>` reads it, which is how the
	/// command tells "typed in one of our panes" — where an escape opens the
	/// file in the window it was typed in — from "typed in Ghostty", where
	/// `open -a` is still the right answer.
	public static let termProgram = "Abydos"

	/// The names it provides, for anything that wants to say so.
	///
	/// `abydos` is here as well as in `/usr/local/bin`, so that a pane has it
	/// without anybody having run `make install-cli` — which is the whole point
	/// of this directory, and it matters more for `abydos` than for the other
	/// two, since a pane is exactly where it does something a shell elsewhere
	/// cannot.
	///
	/// Appended to the PATH rather than prepended, the same rule the other two
	/// follow: shadowing a command somebody already has is not this app's
	/// business. The cost is worth saying out loud — an `abydos` installed from
	/// an older checkout wins over the bundled one, and an old enough copy has
	/// no escape in it at all, so a file typed in a pane would quietly open
	/// through LaunchServices instead. Reinstalling fixes it, and preferring our
	/// own copy would mean deciding that this app knows better than somebody's
	/// PATH, which is a bigger claim than the bug is worth.
	public static let names = ["abydos", "abydos-icat", "abydos-bench"]
}
