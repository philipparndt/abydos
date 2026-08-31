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

/// What a look somewhere other than the file's name said about it.
///
/// Every question in `FilePreview` is a pure function over a URL, and twice now
/// that has not been enough: a `.yaml` is a 3D model when it is a go3mf recipe,
/// and a `.swift` is a 3D model when it is a source of a Cadova executable
/// target. Neither can be answered from a name — the first needs the head of the
/// file, the second needs the package manifest — and neither may be answered
/// *here*, because these functions are asked on every tab-bar refresh and a
/// refresh follows a keystroke.
///
/// So the fact is worked out once, where the file is being opened anyway, and
/// carried in. This is that value rather than a second boolean parameter,
/// deliberately: with one fact there were six call sites passing
/// `looksLikeRecipe:`, and the shape of a second one is a seventh argument at
/// every one of them and at every test — which is how the fifth call site ends
/// up being the one that forgets. A value grows without touching a caller that
/// does not care.
public struct PreviewFacts: Equatable, Sendable {
	/// A `.yaml` whose head says it is a go3mf recipe. `Go3mfRecipe.looksLikeRecipe(_:)`
	/// answers it, and the rule about who may call that is written there.
	public var looksLikeRecipe: Bool
	/// A `.swift` that is a source of a Cadova executable target.
	/// `CadovaModel.find(for:stoppingAt:)` answers it.
	public var isCadovaModel: Bool

	public init(looksLikeRecipe: Bool = false, isCadovaModel: Bool = false) {
		self.looksLikeRecipe = looksLikeRecipe
		self.isCadovaModel = isCadovaModel
	}

	/// What everything running over a tree passes: nothing was looked at, and
	/// nothing is going to be.
	public static let unknown = PreviewFacts()
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
		/// A video. Screen recordings and test captures live in repositories
		/// beside what they show, and opening one used to offer a hex dump and
		/// a Quick Look panel that belongs to no tab. Only the containers
		/// AVFoundation decodes natively: a `.webm` in this list would be a
		/// player spinning over a black rectangle, which is worse than the
		/// notice that is honest about it.
		case video
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

	/// What a file's rendered form is.
	///
	/// - Parameter facts: what a look somewhere other than the name said, for the
	///   cases a name cannot decide. Defaults to `.unknown`, so everything that
	///   runs over a tree keeps asking the question that costs nothing.
	public static func kind(for url: URL, facts: PreviewFacts = .unknown) -> Kind? {
		if facts.looksLikeRecipe, Go3mfRecipe.hasRecipeExtension(url) { return .model }
		// A Cadova model is source that makes a shape, so it is the `.scad` case
		// with a different way of getting the mesh — which is what 0499 is. The
		// name it comes under is `.swift` and says nothing, so the fact has to
		// have been worked out already; see `CadovaModel`.
		if facts.isCadovaModel, url.pathExtension.lowercased() == "swift" { return .model }
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
		case "mp4", "mov", "m4v":
			return .video
		default:
			return nil
		}
	}

	public static func hasPreview(_ url: URL, facts: PreviewFacts = .unknown) -> Bool {
		kind(for: url, facts: facts) != nil
	}

	/// The mode a file opens in.
	///
	/// A mesh has no source worth reading — an STL is a list of triangles — so
	/// it opens rendered. Something written by hand opens as what it is, unless
	/// the rendered half is what the writing is *for*, in which case it opens
	/// with both: a `.puml`, a `.mmd` and a `.scad` are all being checked against
	/// the picture they make. A `.md` is not — it is read as well as rendered —
	/// so it opens as itself and the preview is asked for.
	///
	/// A go3mf recipe is the exception that proves the rule rather than breaking
	/// it: it is checked against the picture too, but whether the file *is* a
	/// recipe was decided by reading the head of it, and a default that starts a
	/// build off a guess about contents is a default that makes opening a `.yaml`
	/// feel dangerous. So it stays asked for — see 0482.
	public static func defaultMode(for url: URL, facts: PreviewFacts = .unknown) -> PreviewMode {
		switch kind(for: url, facts: facts) {
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
		case .video:
			// A picture's case at twenty-five frames a second: nothing to edit,
			// no source to read.
			return .preview
		case .model where facts.looksLikeRecipe && Go3mfRecipe.hasRecipeExtension(url):
			// A go3mf recipe opens as its text, and the model is *asked for*. Not
			// the same answer a `.scad` gets, and the difference is deliberate
			// rather than inherited (0482 beside 0483):
			//
			//  * A `.scad` is one thing whose whole purpose is one shape, and
			//    opening it renders that shape. A recipe is an assembly — it names
			//    a `.scad` per part, so its model is *every* part's render and then
			//    a `go3mf build` on top, which is the slowest preview in the app by
			//    a wide margin.
			//  * And a `.scad` is a `.scad`. Whether a `.yaml` is a recipe at all
			//    was decided by reading the head of it, and a default that starts
			//    minutes of rendering off the back of a guess about a file's
			//    contents is a default that makes opening YAML feel dangerous.
			//
			// So the preview control offers Preview and both splits, and nothing
			// happens until somebody picks one.
			return .source
		case .model:
			// A mesh has nothing to read, so there is nothing to put beside it.
			guard hasReadableSource(url) else { return .preview }
			// A `.scad` is the PlantUML case exactly, and 0483 is the argument:
			// source somebody types whose whole purpose is the shape it makes, so
			// checking one against the other is the work.
			//
			// What used to be written against this lived in
			// `ModelPreview.isViewableModel` — "a .scad file is source, and
			// editing it is the point — its preview is a separate tab, opened
			// deliberately" — and it had had no caller since this file was
			// written, so it described a decision nothing enforced. It is gone
			// rather than left to argue with the case above it.
			//
			// The reason this took measuring rather than deciding is what the
			// default costs: a `.scad` is rendered by running OpenSCAD, where a
			// picture is read off the disk. On the corpus it was measured against
			// that is 200 ms, against the 0.4 s PlantUML spends starting a JVM for
			// the split two cases up — so the cheaper of the two defaults is this
			// one. What made it safe anyway is that the pane's viewer is built
			// lazily, so a walk down a directory of models renders none of them:
			// `ModelContainerView` is where that is, and why.
			//
			// A Cadova model — a `.swift`, so it can only be here because
			// `facts.isCadovaModel` said so — opens the same way, and 0499 is the
			// argument. It is *more* affordable than the `.scad` rather than less,
			// which was the surprise: OpenSCAD renders on the main actor, so those
			// 200 ms are 200 ms of window that does not draw, where `swift run` is
			// a subprocess and costs no frames however long it takes. What it does
			// cost instead is SwiftPM's lock on `.build`, which is somebody else's
			// terminal waiting — see `CadovaPreviewView`.
			return .splitRight
		case .markdown, .none:
			return .source
		}
	}

	/// The mode a file comes back in, given whatever a session remembered.
	///
	/// Two things are deliberately not `.source`. A session written before modes
	/// were recorded remembers nothing, and nothing means the kind's own default:
	/// read as `.source` instead, every `.puml` and every picture anybody had open
	/// would come back as text exactly once, on the day this shipped. And a mode
	/// the file cannot be shown in — `splitRight` against a `.swift`, or against a
	/// `.drawio`, whose editor owns the document and has no source half — is a
	/// note about a file that has since changed its name or its kind, so it is
	/// dropped rather than obeyed.
	public static func restoredMode(
		_ remembered: PreviewMode?, for url: URL, facts: PreviewFacts = .unknown
	) -> PreviewMode {
		guard let remembered,
		      availableModes(for: url, facts: facts).contains(remembered)
		else {
			return defaultMode(for: url, facts: facts)
		}
		return remembered
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
	public static func availableModes(for url: URL, facts: PreviewFacts = .unknown) -> [PreviewMode] {
		guard hasPreview(url, facts: facts) else { return [] }
		return hasReadableSource(url) ? PreviewMode.allCases : [.preview]
	}
}
