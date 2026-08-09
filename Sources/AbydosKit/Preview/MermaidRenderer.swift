import Foundation

/// Drawing Mermaid on the web rendering surface, and the only client of it.
///
/// The same shape as `PlantUMLServers` and for the same reason: what is
/// expensive is starting the thing, not drawing with it. Loading the 3.6 MB
/// bundle costs 0.16–0.28 s and the first render 0.111 s; every render after
/// that is **0.006–0.019 s**, which is faster than the warm PlantUML container
/// and fast enough to redraw as somebody types.
///
/// Where it differs from the PlantUML server, and each difference is why this
/// was chosen over a container at all (0425):
///
///  * **Nothing has to be installed and nothing is fetched.** No runtime, no
///    daemon, no image, no network. A `.mmd` file draws on a machine with
///    nothing on it, and on one with no network at all.
///  * **There is nothing to leave behind.** A container that outlives the app
///    is 0406's whole problem; a web view dies with the process that made it.
///  * **It is on the main actor**, because `WKWebView` is. Every wait here is
///    an `await` on WebKit rather than on a pipe, so the main thread is not
///    held while a diagram is drawn.
@MainActor
public final class MermaidRenderer {
	public static let shared = MermaidRenderer()

	/// What an exported PNG is rasterised at.
	///
	/// Twice the drawing's own size. A Mermaid diagram is laid out in CSS
	/// pixels, so a 1× PNG of one is soft the moment it is put on any screen
	/// made in the last decade — that is exactly the fault the PlantUML preview
	/// had, an image sized in points on a 2× display with half the pixels it
	/// needed. Unlike the preview, which is a drawing and has no resolution to
	/// be wrong about, a PNG has to choose once and for ever.
	public static let rasterScale: Double = 2

	/// Why a diagram was not drawn: the diagram itself, or everything else.
	///
	/// The same split `DiagramExport` already makes for PlantUML, because the
	/// export makes the same decision on it — a fault names a line and is the
	/// author's to fix, and trouble is this app's.
	public enum Failure: Error, Sendable {
		case fault(DiagramFault)
		case trouble(String)
	}

	private let surface = WebRenderer {
		guard let url = Mermaid.bundleURL,
		      let bundle = try? String(contentsOf: url, encoding: .utf8)
		else { return nil }
		return Mermaid.page(bundle: bundle)
	}

	public init() {}

	/// The picture, in the format asked for.
	///
	/// The format is asked for rather than taken from whatever is on screen: the
	/// pane draws SVG because a drawing stays sharp at any zoom, and
	/// `Export ▸ PNG` has to mean a PNG. That was the bug in the first version of
	/// the PlantUML export and it is not being reintroduced here.
	///
	/// Everything waits for the render to *finish*. `mermaid.render` is a
	/// promise, and a caller that did not wait for it would write a nought-byte
	/// file and report success — which is the trap 0424's export rules exist to
	/// close, and it is easier to fall into with a promise than with a pipe.
	///
	/// - Parameter theme: which way round to draw it, or nil to impose nothing —
	///   which is what a file stating its own look gets, and what makes the
	///   picture identical to the one this drew before it had themes.
	public func draw(
		_ source: String, format: DiagramFormat, theme: DiagramTheme? = nil,
		scale: Double = MermaidRenderer.rasterScale
	) async -> Result<Data, Failure> {
		guard Mermaid.hasDiagram(source) else {
			return .failure(.trouble("There is no diagram here yet."))
		}

		let answer: Any?
		do {
			answer = try await surface.call(
				"return await abydosDraw(source, theme)",
				arguments: ["source": source, "theme": theme.map(Mermaid.themeName) ?? ""]
			)
		} catch let trouble as WebRenderer.Trouble {
			return .failure(.trouble(said(about: trouble)))
		} catch {
			return .failure(.trouble(error.localizedDescription))
		}
		guard let raw = answer as? String,
		      let reply = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
		else { return .failure(.trouble("Mermaid answered with nothing this could read.")) }

		if let complaint = reply["error"] as? String {
			return .failure(.fault(Mermaid.fault(message: complaint, line: reply["line"] as? Int)))
		}
		guard let drawn = reply["svg"] as? String, !drawn.isEmpty else {
			return .failure(.trouble("Mermaid drew nothing."))
		}

		// Sized before anything else looks at it: a drawing with no size of its
		// own rasterises into a 300×150 box, and is written to disk as a file
		// every viewer guesses the size of differently.
		// Paper goes into the drawing itself, and only when this app chose the
		// look. Mermaid emits no background, so a dark drawing written out with
		// none is light lines on whatever the reader's viewer happens to paint —
		// which for every viewer there is is white.
		var svg = Mermaid.sized(drawn)
		if let theme { svg = Mermaid.onPaper(svg, colour: theme.paper) }
		svg = DiagramStamp.sign(svg: svg, tool: .mermaid)
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
		guard let base64 = rastered as? String, let png = Data(base64Encoded: base64),
		      !png.isEmpty
		else { return .failure(.trouble("The drawing could not be turned into a picture.")) }
		return .success(DiagramStamp.sign(png: png, tool: .mermaid))
	}

	/// Tears the web view down now, for a test and for anybody who wants the
	/// WebContent process gone without waiting out the idle timeout.
	public func stop() { surface.stop() }

	/// Whether one is loaded, for a test.
	public var isWarm: Bool { surface.isWarm }

	/// The surface's own sentence about a missing page, said in this feature's
	/// terms — "the page is missing" means nothing to somebody looking at a
	/// `.mmd` file.
	private func said(about trouble: WebRenderer.Trouble) -> String {
		trouble.message.contains("missing from this build") ? Mermaid.missingBundleHint
			: trouble.message
	}
}
