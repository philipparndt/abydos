import Foundation

/// One way of naming a file, used wherever two parts of the app have to agree
/// that they mean the same one.
public enum FilePath {
	/// A path that compares equal however it was reached, and that other tools
	/// can be handed.
	///
	/// `realpath(3)` rather than `standardizedFileURL` or
	/// `resolvingSymlinksInPath`: both of Foundation's versions have a special
	/// case that rewrites a leading `/private` *back* to `/tmp`, which is the
	/// opposite of resolving. Two paths compared with them still match each
	/// other, so bookkeeping inside the app looks fine — the damage shows only
	/// when the path is handed to something outside it, which knows the file by
	/// its real name. A breakpoint keyed `/tmp/x` never matched the `/private/
	/// tmp/x` the debugger reported, so it was set and never hit.
	public static func canonical(_ url: URL) -> String {
		canonical(url.path)
	}

	public static func canonical(_ path: String) -> String {
		var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
		guard realpath(path, &buffer) != nil else {
			return (path as NSString).standardizingPath
		}
		return String(cString: buffer)
	}
}
