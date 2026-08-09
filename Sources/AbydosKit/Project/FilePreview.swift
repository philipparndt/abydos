import Foundation

/// How a file that has both a source and a rendered form is being shown.
public enum PreviewMode: String, Sendable, CaseIterable {
	/// The text only.
	case source
	/// The rendered form only, filling the pane.
	case preview
	/// Both, source on the left. Named for where the preview goes, matching the
	/// editor's own Split Right and Split Down.
	case splitRight
	/// Both, source on top.
	case splitDown

	public var title: String {
		switch self {
		case .source:     return "Source"
		case .preview:    return "Preview"
		case .splitRight: return "Split Right"
		case .splitDown:  return "Split Down"
		}
	}

	/// SF Symbol for the tab bar's control.
	public var symbolName: String {
		switch self {
		case .source:     return "doc.plaintext"
		case .preview:    return "eye"
		case .splitRight: return "rectangle.split.2x1"
		case .splitDown:  return "rectangle.split.1x2"
		}
	}

	public var showsSource: Bool { self != .preview }
	public var showsPreview: Bool { self != .source }

	public var isSplit: Bool { self == .splitRight || self == .splitDown }

	/// Whether the divider runs vertically, putting the panes side by side.
	public var splitsSideBySide: Bool { self == .splitRight }
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
		/// A picture. Documentation is full of them, and a project that keeps
		/// its diagrams beside its text should be able to look at them without
		/// leaving for Preview and back.
		case image
		/// A PlantUML diagram: text that describes a picture, where both halves
		/// are worth having on screen at once.
		case plantuml
		/// A Mermaid diagram, which is the same thing drawn by something else —
		/// the pane, the split and the export menu are all the same, and the
		/// only difference somebody sees is that this one needs nothing
		/// installed. See 0425.
		case mermaid

		/// Whether this kind is a diagram with an Export beside it.
		public var isDiagram: Bool { self == .plantuml || self == .mermaid }
	}

	public static func kind(for url: URL) -> Kind? {
		switch url.pathExtension.lowercased() {
		case "md", "markdown", "mdx":
			return .markdown
		case "scad", "stl", "3mf":
			return .model
		case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "ico", "icns":
			return .image
		case "svg":
			// A drawing that is also a file somebody edits, so it has both.
			return .image
		case "puml", "plantuml", "pu", "iuml", "wsd":
			return .plantuml
		case "mmd", "mermaid":
			return .mermaid
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
		switch kind(for: url) {
		case .image:
			// Opening a picture shows the picture. An SVG has text worth
			// reading and the control offers it, but nobody clicks a diagram
			// in a documentation folder hoping to see its path data.
			return .preview
		case .plantuml, .mermaid:
			// Both halves at once: the text is what is edited and the diagram
			// is what it is for, and checking one against the other is the
			// whole of the work.
			return .splitRight
		case .model:
			return hasReadableSource(url) ? .source : .preview
		case .markdown, .none:
			return .source
		}
	}

	/// Whether the file can be shown as text at all.
	///
	/// A binary mesh cannot, so the control offers no source or split for it.
	public static func hasReadableSource(_ url: URL) -> Bool {
		// A picture is pixels; an SVG is a drawing written down, and reading it
		// is a reasonable thing to want.
		if kind(for: url) == .image { return url.pathExtension.lowercased() == "svg" }
		return !["stl", "3mf"].contains(url.pathExtension.lowercased())
	}

	/// Modes worth offering for a file.
	public static func availableModes(for url: URL) -> [PreviewMode] {
		guard hasPreview(url) else { return [] }
		return hasReadableSource(url) ? PreviewMode.allCases : [.preview]
	}
}
