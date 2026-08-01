import Foundation

/// Rules for naming a new file or folder.
///
/// Checked before touching the file system so a rejection is a sentence rather
/// than a POSIX error code, and kept out of the view so the rules can be tested
/// without a window.
public enum EntryName {
	public enum Kind {
		case file, folder

		var noun: String {
			switch self {
			case .file: return "file"
			case .folder: return "folder"
			}
		}

		var plural: String {
			switch self {
			case .file: return "files"
			case .folder: return "folders"
			}
		}
	}

	/// Why a name is unusable, or nil when it is fine.
	///
	/// `showingHiddenFiles` is passed in rather than read from settings so the
	/// rules stay a pure function of their inputs.
	public static func problem(_ name: String, kind: Kind, showingHiddenFiles: Bool) -> String? {
		if name.isEmpty { return "A \(kind.noun) needs a name." }
		if name == "." || name == ".." { return "That name is reserved." }
		if name.contains("/") { return "A \(kind.noun) name cannot contain a slash." }
		// Legal on APFS but not in a POSIX path, and Finder shows it as one.
		if name.contains(":") { return "A \(kind.noun) name cannot contain a colon." }
		if name.unicodeScalars.contains(where: { $0.value == 0 }) {
			return "A \(kind.noun) name cannot contain a null character."
		}

		// Allowed, but worth saying: the tree hides dotfiles by default, so the
		// entry would be created and then apparently vanish.
		if name.hasPrefix("."), !showingHiddenFiles {
			return "Hidden \(kind.plural) are not shown. "
				+ "Turn on “Show hidden files” in Settings first."
		}
		return nil
	}
}

/// The old name, kept so nothing that only makes folders has to change.
public enum FolderName {
	public static func problem(_ name: String, showingHiddenFiles: Bool) -> String? {
		EntryName.problem(name, kind: .folder, showingHiddenFiles: showingHiddenFiles)
	}
}
