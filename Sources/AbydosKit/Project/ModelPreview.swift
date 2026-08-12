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

	/// Whether the viewer can show this file, from its name alone.
	///
	/// Costs nothing, so this is the one to ask about more than one file.
	public static func canPreview(_ url: URL) -> Bool {
		previewableExtensions.contains(url.pathExtension.lowercased())
	}

	/// Whether the viewer can show this file, having looked at it.
	///
	/// The same split `DiagramExport` has between `isDiagram` and `holdsADiagram`,
	/// and for the same reason: `canPreview` is a question about the name and this
	/// is a question about the contents. A go3mf recipe is a `.yaml`, and a
	/// repository's `.yaml` is nearly always a workflow, so the name cannot decide
	/// it and offering the viewer on all of them would be wrong far more often than
	/// right.
	///
	/// **Reads at most `Go3mfRecipe.inspectedBytes` of one file**, and only when the
	/// name is a `.yaml` or `.yml`. Ask it about the row somebody right-clicked;
	/// never about the rows around it.
	public static func holdsAModel(_ url: URL) -> Bool {
		canPreview(url) || Go3mfRecipe.looksLikeRecipe(url)
	}

	/// Extensions that open *as* a model rather than as text.
	///
	/// OpenSCAD is left out: a .scad file is source, and editing it is the
	/// point — its preview is a separate tab, opened deliberately.
	public static func isViewableModel(_ url: URL) -> Bool {
		["stl", "3mf"].contains(url.pathExtension.lowercased())
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
