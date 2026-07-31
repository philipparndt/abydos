import Foundation

/// How a file that has both a source and a rendered form is being shown.
public enum PreviewMode: String, Sendable, CaseIterable {
	/// The text only.
	case source
	/// The rendered form only, filling the pane.
	case preview
	/// Both, side by side.
	case split

	public var title: String {
		switch self {
		case .source:  return "Source"
		case .preview: return "Preview"
		case .split:   return "Split"
		}
	}

	/// SF Symbol for the tab bar's control.
	public var symbolName: String {
		switch self {
		case .source:  return "doc.plaintext"
		case .preview: return "eye"
		case .split:   return "rectangle.split.2x1"
		}
	}

	public var showsSource: Bool { self != .preview }
	public var showsPreview: Bool { self != .source }
}

/// What a file's rendered form is, when it has one.
///
/// One place deciding this, rather than each feature testing extensions of its
/// own: a file either has a preview or it does not, and the tab bar, the menu
/// and the editor all need the same answer.
public enum FilePreview {
	public enum Kind: Equatable, Sendable {
		/// Rendered markdown.
		case markdown
		/// A 3D model, either a mesh or a script that produces one.
		case model
	}

	public static func kind(for url: URL) -> Kind? {
		switch url.pathExtension.lowercased() {
		case "md", "markdown", "mdx":
			return .markdown
		case "scad", "stl", "3mf":
			return .model
		default:
			return nil
		}
	}

	public static func hasPreview(_ url: URL) -> Bool { kind(for: url) != nil }

	/// The mode a file opens in.
	///
	/// A mesh has no source worth reading — an STL is a list of triangles — so
	/// it opens rendered. Anything written by hand opens as what it is, and the
	/// preview is asked for.
	public static func defaultMode(for url: URL) -> PreviewMode {
		switch url.pathExtension.lowercased() {
		case "stl", "3mf": return .preview
		default:           return .source
		}
	}

	/// Whether the file can be shown as text at all.
	///
	/// A binary mesh cannot, so the control offers no source or split for it.
	public static func hasReadableSource(_ url: URL) -> Bool {
		!["stl", "3mf"].contains(url.pathExtension.lowercased())
	}

	/// Modes worth offering for a file.
	public static func availableModes(for url: URL) -> [PreviewMode] {
		guard hasPreview(url) else { return [] }
		return hasReadableSource(url) ? PreviewMode.allCases : [.preview]
	}
}
