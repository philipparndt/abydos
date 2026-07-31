import Foundation

/// Opening 3D models in GoSTL.
///
/// GoSTL is a separate application rather than a library — its Swift package
/// vends an executable, and an executable target cannot also be linked into
/// another app. Launching it is therefore the whole integration, and it costs
/// nothing: it already watches the file it was given, so editing a .scad here
/// updates the preview there without ideai doing anything further.
public enum ModelPreview {
	/// Extensions GoSTL can show.
	public static let previewableExtensions: Set<String> = ["stl", "3mf", "scad"]

	public static func canPreview(_ url: URL) -> Bool {
		previewableExtensions.contains(url.pathExtension.lowercased())
	}

	/// The installed GoSTL, or nil.
	///
	/// A GUI app does not inherit a login shell's PATH, so the Homebrew
	/// locations are checked directly rather than trusted to be on it.
	public static func executable() -> String? {
		let candidates = [
			"/opt/homebrew/bin/gostl",
			"/usr/local/bin/gostl",
			NSHomeDirectory() + "/.local/bin/gostl",
		]
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
	}

	public static var isAvailable: Bool { executable() != nil }
}
