import Foundation

/// What a drag carrying files means, decided without a window.
///
/// The reading of a pasteboard is AppKit's and stays in the editor; what is
/// *decided* about the URLs it yields is here, because those decisions are the
/// ones worth asserting and a drop is otherwise only checkable by driving.
public enum DroppedFiles {
	/// The file URLs among them, in the order given.
	///
	/// **A drag can carry a URL that is not a file.** A browser will happily put
	/// an `https:` one on the board and `NSURL` reads it perfectly well; opening
	/// a tab for it would name a file that does not exist. Anything that is not
	/// a file URL is dropped, so the drag springs back rather than opening
	/// something empty.
	public static func filesOnly(_ urls: [URL]) -> [URL] {
		urls.filter(\.isFileURL)
	}

	/// Which are folders and which are files.
	///
	/// A folder means a project everywhere else in this app — `abydos <dir>`,
	/// the Dock icon, the switcher — so a drag holding both is not a case to
	/// invent behaviour for: each does what it would have done alone.
	///
	/// Something that is not there at all is neither, and is left out rather
	/// than opened as an empty tab.
	public static func separate(
		_ urls: [URL],
		isDirectory: (URL) -> Bool? = DroppedFiles.directoryCheck
    ) -> (folders: [URL], files: [URL]) {
		var folders: [URL] = []
		var files: [URL] = []
		for url in urls {
			guard let directory = isDirectory(url) else { continue }
			if directory { folders.append(url) } else { files.append(url) }
		}
		return (folders, files)
	}

	/// Nil where there is nothing at that path. Separate so the separation can
	/// be asserted without making files.
	public static func directoryCheck(_ url: URL) -> Bool? {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
		else { return nil }
		return isDirectory.boolValue
	}
}
