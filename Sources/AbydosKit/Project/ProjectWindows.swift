import Foundation

/// Which window, of several, is showing a project.
///
/// A project is shown in one window at most. Two windows on one project write
/// one session file between them and attach two terminals to one tmux session,
/// where a tab chosen in either moves both — which is what the second window
/// File ▸ New Window used to open looked like from the desk it was reported at.
/// So every way into a project asks this first and raises the window it names.
public enum ProjectWindows {
	/// The position in `roots` of the one naming the same directory as `root`.
	///
	/// - Parameter roots: each window's project root, in the windows' order;
	///   `nil` for a window with nothing open, or one that is not a project
	///   window at all.
	///
	/// Compared with symbolic links resolved, not only standardised: `/tmp/x`
	/// and `/private/tmp/x` are one directory, and a rule that let a project in
	/// twice by its other spelling would be the rule with a hole in it.
	public static func index(showing root: URL, among roots: [URL?]) -> Int? {
		let wanted = canonical(root)
		return roots.firstIndex { $0.map(canonical) == wanted }
	}

	private static func canonical(_ url: URL) -> String {
		url.standardizedFileURL.resolvingSymlinksInPath().path
	}
}
