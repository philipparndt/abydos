import Foundation

/// Which files the 3D viewer handles.
///
/// GoSTL's package now vends a library as well as its application, so the
/// viewer is hosted in a tab rather than launched as a second program. The
/// standalone app is still offered for the cases a separate window suits
/// better.
public enum ModelPreview {
	/// Extensions the viewer can show.
	public static let previewableExtensions: Set<String> = ["stl", "3mf", "scad"]

	public static func canPreview(_ url: URL) -> Bool {
		previewableExtensions.contains(url.pathExtension.lowercased())
	}

	// What a model file *opens as* is not asked here, and there is no
	// `isViewableModel` any more. There was one, and it said OpenSCAD was left
	// out because "a .scad file is source, and editing it is the point — its
	// preview is a separate tab, opened deliberately". That stopped being true
	// of the program the day `FilePreview` was written: nothing called it from
	// a110bcc onwards, so for a fortnight it was a decision with no code under
	// it, disagreeing in comments with `FilePreview.defaultMode` two files away.
	// 0483 settled the disagreement — a `.scad` now opens with the model beside
	// it — and deleted the loser rather than editing it, because a second place
	// to look up "what does this open as" is how the two came to disagree.
	//
	// This type answers one question now: can the viewer show this file. That is
	// what the navigator's context menu asks, and it is a different question.

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
