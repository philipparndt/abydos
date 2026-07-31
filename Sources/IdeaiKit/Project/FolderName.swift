import Foundation

/// Rules for naming a new folder.
///
/// Checked before touching the file system so a rejection is a sentence rather
/// than a POSIX error code, and kept out of the view so the rules can be tested
/// without a window.
public enum FolderName {
	/// Why a name is unusable, or nil when it is fine.
	///
	/// `showingHiddenFiles` is passed in rather than read from settings so the
	/// rules stay a pure function of their inputs.
	public static func problem(_ name: String, showingHiddenFiles: Bool) -> String? {
		if name.isEmpty { return "A folder needs a name." }
		if name == "." || name == ".." { return "That name is reserved." }
		if name.contains("/") { return "A folder name cannot contain a slash." }
		// Legal on APFS but not in a POSIX path, and Finder shows it as one.
		if name.contains(":") { return "A folder name cannot contain a colon." }
		if name.unicodeScalars.contains(where: { $0.value == 0 }) {
			return "A folder name cannot contain a null character."
		}

		// Allowed, but worth saying: the tree hides dotfiles by default, so the
		// folder would be created and then apparently vanish.
		if name.hasPrefix("."), !showingHiddenFiles {
			return "Hidden folders are not shown. Turn on “Show hidden files” in Settings first."
		}
		return nil
	}
}
