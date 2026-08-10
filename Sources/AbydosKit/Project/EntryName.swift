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

	/// What the field on a brand-new row opens with.
	///
	/// The Finder's two words, and for the same reason: a field that starts
	/// empty commits to nothing if Return is pressed straight away, so the
	/// gesture has to end in an error message to say so. A draft name means the
	/// shortest possible path through this — New, Return — makes a file, and the
	/// name is selected so typing over it costs nothing either.
	public static func draftName(kind: Kind) -> String {
		switch kind {
		case .file: return "untitled"
		case .folder: return "untitled folder"
		}
	}

	/// How much of a name is the part somebody meant to type over.
	///
	/// The stem for a file — `main` of `main.py` — so that typing replaces the
	/// name and keeps the extension, which is the Finder's rule and the reason a
	/// `.swift` does not get typed over by accident. The whole of it for a
	/// folder, which has no extension to protect.
	///
	/// A dotfile is a whole name rather than a stem and an extension:
	/// `.gitignore` is not "an entry of kind gitignore", so all of it is
	/// selected. `NSString.pathExtension` already answers that way; this states
	/// it rather than relying on it.
	///
	/// In UTF-16 units, which is what a field editor's selected range is
	/// measured in.
	public static func stemLength(of name: String, kind: Kind) -> Int {
		let text = name as NSString
		guard kind == .file, !name.hasPrefix(".") else { return text.length }
		let stem = text.deletingPathExtension as NSString
		return stem.length
	}
}

/// The old name, kept so nothing that only makes folders has to change.
public enum FolderName {
	public static func problem(_ name: String, showingHiddenFiles: Bool) -> String? {
		EntryName.problem(name, kind: .folder, showingHiddenFiles: showingHiddenFiles)
	}
}
