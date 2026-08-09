import Foundation

/// Drawing a `.drawio` on the web rendering surface, off-screen and headless.
///
/// The second client of `WebRenderer`, and the reason it exists as its own
/// type. The shape is `MermaidRenderer`'s: one page kept warm, a deadline on
/// every call, nothing fetched and nothing installed.
///
/// What is different is the page. draw.io's viewer defaults `STENCIL_PATH`,
/// `SHAPES_PATH`, `STYLE_PATH`, `GRAPH_IMAGE_PATH` and `mxBasePath` to
/// `https://viewer.diagrams.net/…` and loads shape libraries lazily, by style
/// prefix, at draw time. Under `WebRenderer` those fetches are cancelled and —
/// this is the part that matters — **they fail silently**: the diagram draws
/// short of its icons and looks like a diagram. All five are
/// `window.X = window.X || …` defaults, so the page declares its own before the
/// bundle loads, and `stencils.min.js` does the rest: it is not a file list but
/// an override of `mxStencilRegistry.loadStencil` that serves 42.8 MB of
/// stencil XML out of 7.6 MB held in memory. That is why no base URL and no
/// scheme handler are needed here at all.
///
/// This renderer is what `Export ▸ PNG` / `SVG` draws with. What somebody looks
/// at and edits is `DrawioEditorView`, which is draw.io's real editor in a
/// visible web view and a different thing entirely.
@MainActor
public final class DrawioRenderer {
	public static let shared = DrawioRenderer()

	/// What an exported PNG is rasterised at, for the same reason Mermaid's is:
	/// a diagram laid out in CSS pixels is soft at 1× on any screen made in the
	/// last decade, and a PNG has to choose once and for ever.
	public static let rasterScale: Double = 2

	/// Why a diagram was not drawn: the document, or everything else.
	public enum Failure: Error, Sendable {
		case fault(DiagramFault)
		case trouble(String)
	}

	private let surface = WebRenderer { DrawioRenderer.page() }

	public init() {}

	/// One page of a document, in the format asked for.
	///
	/// - Parameters:
	///   - mxfile: the `<mxfile>` element as it stands. draw.io decompresses the
	///     payload and counts the pages itself, so nothing here has to.
	///   - page: which page, counting from zero.
	///   - theme: which way round to draw it, or nil to impose nothing — which is
	///     what a document with a background of its own gets.
	public func draw(
		_ mxfile: String, page: Int = 0, format: DiagramFormat, theme: DiagramTheme? = nil,
		scale: Double = DrawioRenderer.rasterScale
	) async -> Result<Data, Failure> {
		guard mxfile.contains("<mxfile") || mxfile.contains("<mxGraphModel") else {
			return .failure(.trouble("There is no diagram here."))
		}

		let answer: Any?
		do {
			answer = try await surface.call(
				"return await abydosDrawio(xml, page, dark, paper)",
				arguments: [
					"xml": mxfile, "page": page,
					"dark": theme?.isDark ?? false,
					"paper": theme?.paper ?? "#ffffff",
				]
			)
		} catch let trouble as WebRenderer.Trouble {
			return .failure(.trouble(said(about: trouble)))
		} catch {
			return .failure(.trouble(error.localizedDescription))
		}
		guard let raw = answer as? String,
		      let reply = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
		else { return .failure(.trouble("draw.io answered with nothing this could read.")) }

		if let complaint = reply["error"] as? String {
			return .failure(.fault(DiagramFault(message: complaint, line: nil)))
		}
		guard let drawn = reply["svg"] as? String, !drawn.isEmpty else {
			return .failure(.trouble("draw.io drew nothing."))
		}

		let svg = DiagramStamp.sign(svg: drawn, tool: .drawio)
		guard format == .png else { return .success(Data(svg.utf8)) }

		let rastered: Any?
		do {
			rastered = try await surface.call(
				"return await abydosRaster(svg, scale, paper)",
				arguments: ["svg": svg, "scale": scale, "paper": theme?.paper ?? "#ffffff"]
			)
		} catch let trouble as WebRenderer.Trouble {
			return .failure(.trouble(said(about: trouble)))
		} catch {
			return .failure(.trouble(error.localizedDescription))
		}
		guard let base64 = rastered as? String, let png = Data(base64Encoded: base64), !png.isEmpty
		else { return .failure(.trouble("The drawing could not be turned into a picture.")) }
		return .success(DiagramStamp.sign(png: png, tool: .drawio))
	}

	/// How many pages a document has, according to draw.io rather than to this
	/// app's own reader — for a test that the two agree.
	public func pageCount(_ mxfile: String) async -> Int? {
		guard let answer = try? await surface.call(
			"return await abydosDrawioPages(xml)", arguments: ["xml": mxfile]
		) else { return nil }
		return (answer as? NSNumber)?.intValue
	}

	/// Which shapes in a document this build cannot draw, asked of draw.io's own
	/// registry.
	///
	/// The one question a picture cannot answer: an unresolved shape is drawn as
	/// a plain rectangle, so a diagram missing half its icons still looks like a
	/// diagram. Nil means the page could not be asked at all.
	public func missingShapes(in document: Drawio.Document) async -> [String]? {
		let names = document.pages.flatMap { Drawio.shapeNames(in: $0.model) }
		guard !names.isEmpty else { return [] }
		guard let answer = try? await surface.call(
			"return await abydosMissingStencils(names)", arguments: ["names": names]
		) as? String, let data = answer.data(using: .utf8)
		else { return nil }
		return try? JSONSerialization.jsonObject(with: data) as? [String]
	}

	/// Asks the page something directly, for a test.
	///
	/// The stencil question can only be answered from inside: whether a shape
	/// drew its icon or a plain rectangle is not visible in the reply, and
	/// "it looks like a diagram" is exactly the failure this has to catch.
	func evaluate(_ script: String) async throws -> Any? { try await surface.call(script) }

	public func stop() { surface.stop() }
	public var isWarm: Bool { surface.isWarm }

	private func said(about trouble: WebRenderer.Trouble) -> String {
		trouble.message.contains("missing from this build") ? Drawio.missingBundleHint
			: trouble.message
	}

	// MARK: - The page the bundles are loaded into

	/// Where a vendored draw.io file lives, in whichever bundle this module is.
	public static func asset(_ path: String) -> URL? {
		let folder = ("drawio/" as NSString).appendingPathComponent(
			(path as NSString).deletingLastPathComponent
		)
		let name = (path as NSString).lastPathComponent
		return Bundle.module.url(
			forResource: (name as NSString).deletingPathExtension,
			withExtension: (name as NSString).pathExtension,
			subdirectory: folder
		)
	}

	/// The directory the vendored tree sits in, which is what the editor's URL
	/// scheme serves from.
	public static var assetsRoot: URL? {
		Bundle.module.url(forResource: "drawio", withExtension: nil)
			?? asset("VERSION")?.deletingLastPathComponent()
	}

	/// The vendored version, as `Scripts/vendor-drawio.sh` wrote it.
	public static var version: String? {
		guard let url = asset("VERSION"),
		      let text = try? String(contentsOf: url, encoding: .utf8)
		else { return nil }
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	/// The document the off-screen web view loads.
	///
	/// Two bundles inlined rather than fetched, for the reason `Mermaid.page`
	/// gives: a `loadHTMLString` page has no origin, so a `<script src=…>` at a
	/// `file:` URL is a cross-origin request and is refused.
	///
	/// The asset globals go **before** them, because every one of draw.io's is a
	/// `window.X = window.X || …` and the first assignment wins. They are set to
	/// a path that cannot resolve on purpose: nothing should be fetched, and a
	/// path that quietly worked would hide a missing bundle until somebody
	/// opened a diagram on a train.
	static func page() -> String? {
		// Three bundles, and the third is not optional. draw.io's shapes come in
		// two kinds: stencils, which are XML and come out of `stencils.min.js`,
		// and shapes *implemented in JavaScript*, which the viewer would fetch
		// one file at a time from `SHAPES_PATH`. Without them a diagram using
		// an AWS resource icon draws a plain rectangle and says nothing — the
		// same silent gap the stencils would have, one layer up. 1.5 MB.
		let names = ["js/viewer-static.min.js", "js/stencils.min.js", "js/shapes-14-6-5.min.js"]
		var bundles: [String] = []
		for name in names {
			guard let url = asset(name),
			      let source = try? String(contentsOf: url, encoding: .utf8)
			else { return nil }
			bundles.append("<script>\(source)</script>")
		}

		return """
			<!doctype html>
			<html><head><meta charset="utf-8">
			<style>html,body{margin:0;padding:0;background:#fff;overflow:hidden}</style>
			<script>
			\(assetGlobals)
			</script>
			\(bundles.joined(separator: "\n"))
			<script>
			\(drawScript)
			</script>
			</head><body></body></html>
			"""
	}

	/// Every path draw.io would otherwise fetch from `viewer.diagrams.net`,
	/// pointed at nothing, plus the two flags that stop mxGraph fetching its own
	/// resources and stylesheets at load.
	static let assetGlobals = """
		window.urlParams = {};
		window.mxLoadResources = false;
		window.mxLoadStylesheets = false;
		window.mxForceIncludes = false;
		window.isLocalStorage = false;
		window.STENCIL_PATH = 'abydos-none/stencils';
		window.SHAPES_PATH = 'abydos-none/shapes';
		window.STYLE_PATH = 'abydos-none/styles';
		window.IMAGE_PATH = 'abydos-none/images';
		window.GRAPH_IMAGE_PATH = 'abydos-none/img';
		window.RESOURCES_PATH = 'abydos-none/resources';
		window.mxBasePath = 'abydos-none/mxgraph';
		window.mxImageBasePath = 'abydos-none/mxgraph/images';
		window.DRAW_MATH_URL = 'abydos-none/math';
		window.PROXY_URL = 'abydos-none/proxy';
		"""

	/// Colours a renderer that is not a browser can read.
	///
	/// This is the second half of the same lesson `foEnabled` is the first half
	/// of, and it cost a picture to find. Recent draw.io writes every colour
	/// twice — the plain value as a `fill` attribute, and
	/// `style="fill: light-dark(rgb(237,113,0), rgb(216,109,12))"` beside it —
	/// so that one file follows the reader's own light or dark theme. WebKit
	/// understands `light-dark()`, so the pane and the rasterised PNG were both
	/// correct; **CoreSVG does not**, and rather than falling back to the
	/// attribute it paints the element black. The exported SVG of an AWS diagram
	/// opened in Preview.app as five solid black boxes with the labels gone.
	///
	/// `mxUtils.lightDarkColorSupported` is the switch draw.io tests before
	/// emitting any of it, and it is a plain flag. Turned off, every colour is
	/// written once, as itself.
	///
	/// It is written here rather than fixed up in the serialised output because
	/// a search-and-replace over somebody's diagram is a worse thing to own than
	/// a flag draw.io provides for exactly this.
	///
	/// **A theme does not undo this, and that is the whole of how draw.io is
	/// drawn dark here.** The flag is what decides the *form* the colour is
	/// written in; the second flag beside it, `mxUtils.preferDarkColor`, decides
	/// *which of the pair* is written when the form is a single value. Read out
	/// of draw.io's own SVG export, which does exactly this and nothing else:
	///
	///     if ("light" == theme || "dark" == theme) {
	///         mxUtils.lightDarkColorSupported = false;
	///         mxUtils.preferDarkColor = ("dark" == theme);
	///     }
	///
	/// So dark mode here is `preferDarkColor = true` with `lightDarkColorSupported`
	/// staying false — every colour still written once, as itself, and CoreSVG
	/// still able to read all of it. `EditorUi.setDarkMode` would have been the
	/// obvious thing to reach for and is a **no-op** with the flag off: its whole
	/// body is inside `mxUtils.lightDarkColorSupported && (…)`.
	static let plainColours = """
		mxUtils.lightDarkColorSupported = false;
		Graph.defaultAdaptiveColors = 'none';
		"""

	/// Drawing one page, and turning a drawing into a picture.
	///
	/// `mxSvgCanvas2D.prototype.foEnabled = false` is the one line here that is
	/// a decision rather than plumbing, and it is Mermaid's `htmlLabels: false`
	/// again for exactly the same reason. mxGraph's default puts every label in
	/// a `foreignObject` full of HTML, which a browser draws and Preview.app,
	/// CoreSVG and a `<canvas>` do not — so with it on, an exported SVG is a
	/// picture of empty boxes outside a browser and the PNG rasterises blank.
	/// Off, the labels are `<text>` and the file is a picture everywhere.
	static let drawScript = """
		mxSvgCanvas2D.prototype.foEnabled = false;
		mxClient.NO_FO = true;
		\(plainColours)

		function abydosViewer(xml, page, dark) {
			const holder = document.createElement('div');
			holder.style.position = 'absolute';
			holder.style.left = '-100000px';
			holder.style.width = '2000px';
			holder.style.height = '2000px';
			document.body.appendChild(holder);
			// The document as an element, not as a string. `GraphViewer.init`
			// builds its graph inside `if (xmlNode != null)` and does nothing at
			// all without one — `graphConfig.xml` is read by the static helpers
			// that parse it first, not by the constructor.
			const parsed = mxUtils.parseXml(xml).documentElement;
			const viewer = new GraphViewer(holder, parsed, {
				page: page || 0, border: 0, 'auto-fit': false,
				resize: false, nav: false, toolbar: null, lightbox: false,
				'toolbar-nohide': true, highlight: null, 'check-visible-state': false,
				'dark-mode': dark ? 'dark' : 'light'
			});
			return { viewer: viewer, holder: holder };
		}

		async function abydosDrawio(xml, page, dark, paper) {
			let made = null;
			// Set before the viewer is built, because the stylesheet is resolved
			// while it is built. Put back in the `finally`: this page is kept warm
			// and draws every diagram somebody opens, so a flag left on would make
			// the *next* light diagram dark — which is precisely the kind of fault
			// that reads as intermittent.
			const wasDark = mxUtils.preferDarkColor;
			const wasEditorDark = Editor.darkMode;
			mxUtils.preferDarkColor = !!dark;
			Editor.darkMode = !!dark;
			try {
				made = abydosViewer(xml, page, dark);
				const graph = made.viewer.graph;
				// Everything laid out before anything is measured. The viewer draws
				// synchronously, but a stencil arriving from the registry replaces a
				// shape after the fact, so the view is revalidated once more.
				graph.view.validate();
				// The document's own background first, which is the file having
				// chosen — and the paper this app picked only when it has not.
				const drawn = graph.getSvg(
					graph.background || paper || '#ffffff', 1, 4, false, null, true,
					null, null, null, null, null, null, null
				);
				return JSON.stringify({ svg: new XMLSerializer().serializeToString(drawn) });
			} catch (thrown) {
				return JSON.stringify({ error: String((thrown && thrown.message) || thrown) });
			} finally {
				mxUtils.preferDarkColor = wasDark;
				Editor.darkMode = wasEditorDark;
				// `GraphViewer` has no teardown of its own — the graph does, and
				// it is the thing holding listeners on the document. Tidying is
				// not optional here: this page is kept warm and draws every
				// diagram somebody opens, so a viewer left behind is a leak that
				// accumulates for as long as the app runs.
				if (made) {
					try { made.viewer.graph.destroy(); } catch (ignored) { }
					made.holder.remove();
				}
			}
		}

		/// Which of these shapes this build cannot draw.
		///
		/// The answer to "is the offline asset set complete", asked of the
		/// registry rather than guessed from the picture. A shape that does not
		/// resolve is drawn as a plain rectangle, which looks like a diagram.
		async function abydosMissingStencils(names) {
			const missing = [];
			for (const name of names) {
				if (mxCellRenderer.defaultShapes[name] != null) { continue; }
				if (mxStencilRegistry.getStencil(name) != null) { continue; }
				missing.push(name);
			}
			return JSON.stringify(missing);
		}

		async function abydosDrawioPages(xml) {
			const parsed = mxUtils.parseXml(xml).documentElement;
			if (parsed.nodeName === 'mxfile') {
				return parsed.getElementsByTagName('diagram').length;
			}
			return 1;
		}

		async function abydosRaster(svg, scale, paper) {
			// Through an <img> and a <canvas> rather than a snapshot of the page:
			// an off-screen web view with no window attached snapshots blank.
			const source = 'data:image/svg+xml;base64,'
				+ btoa(String.fromCharCode(...new TextEncoder().encode(svg)));
			const picture = new Image();
			await new Promise((ok, no) => {
				picture.onload = ok;
				picture.onerror = () => no(new Error('the drawing could not be rasterised'));
				picture.src = source;
			});
			const canvas = document.createElement('canvas');
			canvas.width = Math.max(1, Math.round(picture.naturalWidth * scale));
			canvas.height = Math.max(1, Math.round(picture.naturalHeight * scale));
			const pen = canvas.getContext('2d');
			// Paper: a PNG of black lines on nothing is invisible half the places
			// it will be pasted. `getSvg` has already painted the background into
			// the drawing, so this is only the belt to that pair of braces — but a
			// white one under a dark drawing would show at every rounded corner.
			pen.fillStyle = paper || '#ffffff';
			pen.fillRect(0, 0, canvas.width, canvas.height);
			pen.drawImage(picture, 0, 0, canvas.width, canvas.height);
			return canvas.toDataURL('image/png').split(',')[1];
		}
		"""
}
