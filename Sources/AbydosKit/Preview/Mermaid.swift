import Foundation

/// Drawing Mermaid, which unlike PlantUML needs nothing installed.
///
/// Mermaid is JavaScript. Every command-line form of it is a headless browser
/// with `mermaid.js` loaded into it: `minlag/mermaid-cli` measured **2.16 GB**
/// on disk against `plantuml/plantuml`'s 314 MB, took a second per render, and
/// has no server mode to keep warm the way PlantUML's image does — so the trick
/// that took a PlantUML render from two seconds to a twentieth of one (0422)
/// does not transfer to it at all.
///
/// The bundle itself is **3.57 MB**, MIT, and one self-contained file. Loaded
/// into a `WKWebView` it draws in **0.006–0.019 s** after a first render of
/// 0.111 s — faster than the warm PlantUML server, with no container, no
/// daemon, no pull and no network. That is the whole of why this is the one
/// tool in the app that works on a machine with nothing on it. See 0425.
///
/// This type is the part with no web view in it: what a Mermaid file is, the
/// page the bundle is loaded into, and the two pieces of tidying that have to
/// happen to what `mermaid.render` gives back. `MermaidRenderer` is the part
/// that runs.
public enum Mermaid {
	/// What a preview asks for, for the same reason PlantUML's does: a drawing
	/// has no resolution to be wrong about, so it is sharp on a Retina screen
	/// and stays sharp through the app's own ⌘+.
	public static let previewFormat: DiagramFormat = .svg

	/// The extensions Mermaid's own tooling recognises.
	///
	/// `.mmd` is what `mmdc` writes and reads; `.mermaid` is what a few editors
	/// use. Neither is a Markdown file — a ```` ```mermaid ```` fence inside one
	/// is the commoner place for a diagram to live and is deliberately not
	/// handled yet, for the reasons written down in 0425.
	public static let extensions = ["mmd", "mermaid"]

	/// Whether a file is a diagram this draws.
	public static func isDiagram(_ url: URL) -> Bool {
		extensions.contains(url.pathExtension.lowercased())
	}

	/// A diagram that says nothing yet.
	///
	/// Mermaid answers an empty document with "No diagram type detected", which
	/// is true and is not worth drawing at somebody who has just made the file.
	/// A `%%` comment is not a diagram either, and a file that opens with a
	/// couple of them is how people head a diagram they have not written yet.
	public static func hasDiagram(_ text: String) -> Bool {
		for line in text.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }
			return true
		}
		return false
	}

	/// The one sentence somebody needs when the bundle is not in the app.
	///
	/// It should be impossible — the file is a resource of this module — but a
	/// build assembled by hand can leave a resource out, and a preview pane that
	/// is simply blank tells nobody that.
	public static let missingBundleHint = """
		Mermaid could not be loaded: mermaid.min.js is missing from this build of \
		Abydos. Run Scripts/vendor-mermaid.sh and rebuild.
		"""

	// MARK: - The page the bundle is loaded into

	/// Where the vendored bundle lives, in whichever bundle this module is in.
	public static var bundleURL: URL? {
		Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "mermaid")
			?? Bundle.module.url(forResource: "mermaid.min", withExtension: "js")
	}

	/// The vendored bundle's version, as `Scripts/vendor-mermaid.sh` wrote it.
	public static var version: String? {
		guard let url = Bundle.module.url(forResource: "VERSION", withExtension: nil, subdirectory: "mermaid")
			?? Bundle.module.url(forResource: "VERSION", withExtension: nil),
			let text = try? String(contentsOf: url, encoding: .utf8)
		else { return nil }
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	/// The document the web view loads, with the bundle inlined into it.
	///
	/// Inlined rather than fetched, and that is the point: a `loadHTMLString`
	/// page has no origin, so a `<script src=…>` at a `file:` URL would be a
	/// cross-origin request and would be refused. There is also nothing to serve
	/// it from and nothing that should be listening on this machine to serve it.
	///
	/// Three settings are decisions rather than defaults:
	///
	///  * **`htmlLabels: false`** everywhere it can be set. Mermaid's default
	///    puts every label in a `foreignObject` full of HTML, which a browser
	///    draws and Preview.app, `librsvg`, Inkscape and a `<canvas>` do not —
	///    so with it on, an exported SVG is a picture of empty boxes outside a
	///    browser and a PNG cannot be rasterised at all. Off, the labels are
	///    `<text>` and the file is a picture everywhere.
	///  * **`securityLevel: 'strict'`**, which is Mermaid's own default and
	///    means click handlers and raw HTML in labels are not honoured. A
	///    diagram is a document somebody is reading, not a program.
	///  * **`suppressErrorRendering: true`**, so a diagram that will not parse
	///    throws and nothing else. Without it Mermaid also glues a picture of a
	///    bomb into the page, which the next render would find already there.
	public static func page(bundle: String) -> String {
		"""
		<!doctype html>
		<html><head><meta charset="utf-8">
		<style>html,body{margin:0;padding:0;background:#fff}</style>
		<script>\(bundle)</script>
		<script>
		mermaid.initialize({
			startOnLoad: false,
			securityLevel: 'strict',
			suppressErrorRendering: true,
			htmlLabels: false,
			flowchart: { htmlLabels: false },
			class: { htmlLabels: false },
			state: { htmlLabels: false }
		});
		window.__abydosDrew = 0;
		async function abydosDraw(source) {
			const id = 'abydos-' + (window.__abydosDrew++);
			try {
				const drawn = await mermaid.render(id, source);
				return JSON.stringify({ svg: drawn.svg });
			} catch (thrown) {
				const said = String((thrown && thrown.message) || thrown);
				const where = thrown && thrown.hash;
				// `hash.loc.first_line` and `hash.line` disagree — 3 and 2 for the
				// same fault — and it is `loc.first_line` that matches the line the
				// message itself names. Measured on two diagrams.
				const line = (where && where.loc && where.loc.first_line)
					|| (where && where.line != null ? where.line + 1 : null);
				return JSON.stringify({ error: said, line: line });
			}
		}
		async function abydosRaster(svg, scale) {
			// Through an <img> and a <canvas> rather than through a snapshot of
			// the page: an off-screen web view with no window attached snapshots
			// blank, and this needs no window at all.
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
			// Paper. A drawing has a transparent background and a PNG of black
			// lines on nothing is invisible in half the places it will be pasted.
			pen.fillStyle = '#ffffff';
			pen.fillRect(0, 0, canvas.width, canvas.height);
			pen.drawImage(picture, 0, 0, canvas.width, canvas.height);
			return canvas.toDataURL('image/png').split(',')[1];
		}
		</script></head><body></body></html>
		"""
	}

	// MARK: - Tidying what comes back

	/// A drawing with a size of its own, out of one that has none.
	///
	/// `mermaid.render` returns `<svg width="100%" style="max-width: 282px">`,
	/// which is right for a page and wrong for a file. An SVG with no intrinsic
	/// size is drawn by a browser into its default 300×150 box: the first PNG
	/// rasterised from one came back **172×300** instead of 564×982. Preview.app
	/// and every other viewer have the same problem in their own way.
	///
	/// So the root element is given the `viewBox`'s own width and height in
	/// pixels, and the `max-width` that was standing in for them is taken off.
	/// Nothing else in the document is touched.
	public static func sized(_ svg: String) -> String {
		guard let open = svg.range(of: "<svg"),
		      let close = svg[open.upperBound...].firstIndex(of: ">")
		else { return svg }
		let attributes = String(svg[open.upperBound..<close])
		guard let box = viewBox(in: attributes) else { return svg }

		var kept = attributes
		for name in ["width", "height"] { kept = removing(attribute: name, from: kept) }
		kept = withoutMaxWidth(kept)
		let rewritten = "<svg width=\"\(number(box.width))\" height=\"\(number(box.height))\""
			+ kept + ">"
		return svg.replacingCharacters(in: open.lowerBound...close, with: rewritten)
	}

	/// The width and height a `viewBox="minX minY width height"` declares.
	static func viewBox(in attributes: String) -> (width: Double, height: Double)? {
		guard let value = attribute("viewBox", in: attributes) else { return nil }
		let numbers = value.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
		guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
		return (numbers[2], numbers[3])
	}

	/// The value of one attribute in a tag's attribute text, double-quoted —
	/// which is what every SVG serialiser this side ever sees emits.
	static func attribute(_ name: String, in attributes: String) -> String? {
		guard let range = span(of: name, in: attributes) else { return nil }
		let text = attributes[range]
		guard let first = text.firstIndex(of: "\""),
		      let last = text.lastIndex(of: "\""), first < last
		else { return nil }
		return String(text[text.index(after: first)..<last])
	}

	private static func removing(attribute name: String, from attributes: String) -> String {
		guard let range = span(of: name, in: attributes) else { return attributes }
		return attributes.replacingCharacters(in: range, with: "")
	}

	/// `max-width` is what Mermaid puts the real width in, and it is a lie once
	/// the element has a width of its own: it would cap the drawing at its own
	/// size and stop it being scaled up.
	private static func withoutMaxWidth(_ attributes: String) -> String {
		guard let style = attribute("style", in: attributes) else { return attributes }
		let kept = style
			.split(separator: ";")
			.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("max-width") }
			.joined(separator: ";")
		if kept.trimmingCharacters(in: .whitespaces).isEmpty {
			return removing(attribute: "style", from: attributes)
		}
		guard let range = span(of: "style", in: attributes) else { return attributes }
		return attributes.replacingCharacters(in: range, with: " style=\"\(kept)\"")
	}

	/// Where ` name="…"` sits in a tag's attribute text.
	///
	/// Matched with the space in front of it so that `width` does not find
	/// `stroke-width`, which is the bug this shape exists to avoid.
	private static func span(of name: String, in attributes: String) -> Range<String.Index>? {
		var from = attributes.startIndex
		while let found = attributes.range(of: "\(name)=\"", range: from..<attributes.endIndex) {
			let before = attributes.index(before: found.lowerBound)
			let isOwnWord = found.lowerBound == attributes.startIndex
				|| attributes[before].isWhitespace
			if isOwnWord, let end = attributes[found.upperBound...].firstIndex(of: "\"") {
				let start = found.lowerBound == attributes.startIndex ? found.lowerBound : before
				return start..<attributes.index(after: end)
			}
			from = found.upperBound
		}
		return nil
	}

	/// A length written the way an SVG attribute wants it: no exponent, and no
	/// trailing zeros on a number that happens to be whole.
	static func number(_ value: Double) -> String {
		let rounded = (value * 1000).rounded() / 1000
		if rounded == rounded.rounded() { return String(Int(rounded)) }
		return String(rounded)
	}

	// MARK: - What Mermaid says is wrong

	/// Mermaid's complaint, cut down to a sentence somebody would read.
	///
	/// What it throws is four lines and up to twenty-seven expected tokens:
	///
	///     Parse error on line 3:
	///     ...otavalidline ??? %%%
	///     -----------------------^
	///     Expecting '()', 'SOLID_OPEN_ARROW', … 27 more …, got 'NEWLINE'
	///
	/// The first three lines are the line number — which arrives separately and
	/// more reliably — and a copy of the source with a caret under it, and
	/// neither survives being put in a one-line notice. What is left is the last
	/// line, with the list of what it wanted cut to three so that the part that
	/// says what it *got* is still on screen.
	///
	/// The other shape has no line at all and everything on the first one:
	///
	///     No diagram type detected matching given configuration for text: …
	///
	/// with the whole document after the colon, which is somebody's own file
	/// read back at them. The sentence ends at the colon.
	public static func fault(message: String, line: Int?) -> DiagramFault {
		let lines = message
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		let header = lines.first ?? message
		let isParseError = header.hasPrefix("Parse error")

		var said = isParseError ? (lines.last ?? message) : header
		if !isParseError, let colon = said.range(of: "for text:") {
			said = String(said[said.startIndex..<colon.lowerBound]) + "for this text."
		}
		said = shortenExpectations(in: said)
		if said.count > 240 { said = String(said.prefix(237)) + "…" }
		return DiagramFault(message: said, line: line ?? lineNamed(in: header, isParseError))
	}

	/// The number in "Parse error on line 3:", for the case where the thrown
	/// object carried no `hash` to read it from.
	///
	/// Only out of that header. Any other message may have the word "line" in it
	/// for its own reasons, and a line number invented from one would point
	/// somewhere real and be wrong.
	private static func lineNamed(in header: String, _ isParseError: Bool) -> Int? {
		guard isParseError, let after = header.range(of: "line ") else { return nil }
		let digits = header[after.upperBound...].prefix { $0.isNumber }
		return Int(digits)
	}

	/// `Expecting 'A', 'B', 'C', …, got 'X'` out of a list of twenty-seven.
	private static func shortenExpectations(in said: String) -> String {
		guard said.hasPrefix("Expecting "), let got = said.range(of: ", got ") else { return said }
		let wanted = said[said.index(said.startIndex, offsetBy: "Expecting ".count)..<got.lowerBound]
		let tokens = wanted.components(separatedBy: ", ")
		guard tokens.count > 3 else { return said }
		return "Expecting " + tokens.prefix(3).joined(separator: ", ") + ", … or "
			+ (tokens.count - 3 == 1 ? "1 other" : "\(tokens.count - 3) others")
			+ said[got.lowerBound...]
	}
}
