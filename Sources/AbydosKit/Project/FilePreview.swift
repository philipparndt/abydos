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
		/// A draw.io document, which is the odd one out: not text that renders
		/// to a picture but an editor's document, opened in draw.io's own editor
		/// rather than shown beside a source nobody reads. See 0426.
		case drawio
		/// A PDF. A finished document rather than a source: specifications,
		/// datasheets and the paper an algorithm came from all live in a
		/// repository beside the code that implements them, and clicking one used
		/// to offer a hex dump. Shown by PDFKit, which is the same choice the
		/// owner's own scanner app made for the same job.
		case pdf

		/// Whether this kind is a diagram with an Export beside it.
		public var isDiagram: Bool {
			self == .plantuml || self == .mermaid || self == .drawio
		}
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
			//
			// `architecture.drawio.svg` lands here, and that is deliberate rather
			// than an oversight — `pathExtension` says `svg`, and the file *is* a
			// picture: it renders on GitHub, previews here as a picture and reads
			// as text. Reading it as a draw.io document instead would take the
			// picture away for the sake of an editor somebody can have by opening
			// the `.drawio` beside it. What the app does take out of one is its
			// `<mxfile>`, so an export recognises a picture it drew. See 0426.
			return .image
		case "puml", "plantuml", "pu", "iuml", "wsd":
			return .plantuml
		case "mmd", "mermaid":
			return .mermaid
		case "drawio", "dio":
			return .drawio
		case "pdf":
			return .pdf
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
		case .drawio:
			// The opposite, and for the opposite reason. A `.drawio` is not text
			// somebody types — it is an editor's document, and the XML is a
			// serialisation nobody reads. It opens in the editor, like a mesh
			// opens rendered.
			return .preview
		case .pdf:
			// A PDF is the finished document and nothing else. Its bytes are a
			// compressed object graph, so there is no source half to offer.
			return .preview
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
		// A `.drawio` has no source in the sense the control means. Its XML is
		// deflated base64 nobody can read, and — the part that matters — the
		// editor in the preview half owns the document. A split would put a text
		// editor and draw.io over the same file, each unaware of the other's
		// edits, which is the one way this feature could lose somebody's work.
		if kind(for: url) == .drawio { return false }
		// A PDF is a mesh's case exactly: deflated streams and an object graph,
		// with nothing in it a person would read as text.
		if kind(for: url) == .pdf { return false }
		return !["stl", "3mf"].contains(url.pathExtension.lowercased())
	}

	/// Modes worth offering for a file.
	public static func availableModes(for url: URL) -> [PreviewMode] {
		guard hasPreview(url) else { return [] }
		return hasReadableSource(url) ? PreviewMode.allCases : [.preview]
	}
}
