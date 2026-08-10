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
	/// is the commoner place for a diagram to live, and it is drawn by the
	/// Markdown preview rather than here: `MarkdownFence` finds the block and
	/// `MarkdownDiagrams` draws it through this same renderer, so a fence and a
	/// file get one picture from one path.
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

	// MARK: - Which way round it is drawn

	/// What `mermaid.initialize({ theme: … })` is given for a theme of ours.
	///
	/// Two of the five Mermaid offers. `forest`, `neutral` and `base` are
	/// perfectly good and are somebody's own taste rather than an answer to "is
	/// this window light or dark", which is the only question being asked here.
	public static func themeName(_ theme: DiagramTheme) -> String {
		theme.isDark ? "dark" : "default"
	}

	/// What in a diagram states a look of its own, or nil when it says nothing.
	///
	/// Mermaid has two ways of saying it and both count:
	///
	///  * **Front matter** — a `---` block at the top of the file with a
	///    `config:` in it naming a `theme:` or `themeVariables:`.
	///  * **An init directive** — `%%{init: {'theme': 'forest'}}%%`, which is the
	///    older spelling and still the commoner one in the wild.
	///
	/// `themeVariables` counts as much as `theme` does, and that is the same rule
	/// PlantUML's background colour gets: somebody who has set the node fill and
	/// the line colour by hand has chosen how their diagram is lit, whether or
	/// not they also named one of the five.
	///
	/// It matters twice over rather than only for the notice. Mermaid's own
	/// directive wins over `initialize`, so a file that names a theme would draw
	/// in its own colours regardless — but the **paper** behind it is this app's
	/// to paint, and painting a dark one behind somebody's `forest` diagram would
	/// be this app overruling them by the back door.
	public static func statedLook(in source: String) -> String? {
		if let stated = statedInFrontMatter(source) { return stated }
		return statedInInitDirective(source)
	}

	/// `---\nconfig:\n  theme: dark\n---`, which is Mermaid's newer spelling.
	private static func statedInFrontMatter(_ source: String) -> String? {
		let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
		guard let opening = lines.firstIndex(where: {
			!$0.trimmingCharacters(in: .whitespaces).isEmpty
		}), lines[opening].trimmingCharacters(in: .whitespaces) == "---" else { return nil }

		for line in lines[(opening + 1)...] {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed == "---" { return nil }
			for key in ["theme:", "themeVariables:"] where trimmed.hasPrefix(key) {
				return "front matter \(trimmed)"
			}
		}
		return nil
	}

	/// `%%{init: {'theme': 'forest'}}%%`, anywhere in the file.
	private static func statedInInitDirective(_ source: String) -> String? {
		for raw in source.split(separator: "\n") {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard line.hasPrefix("%%{"), line.contains("init") else { continue }
			for key in ["theme", "themeVariables"] where line.contains(key) {
				return "%%{init: … \(key) … }%%"
			}
		}
		return nil
	}

	// MARK: - A layout this build does not have

	/// The layout engines that come with the bundle, which is one.
	///
	/// Mermaid's own layout — `dagre` — is inside `mermaid.min.js`. Everything
	/// else is a separate package registered at runtime, and none is vendored
	/// here: `@mermaid-js/layout-elk` is 1.6 MB of minified ESM that reaches for
	/// a second file by relative path, and this page has no origin for a relative
	/// path to be resolved against. 0425 has the numbers and the decision.
	static let layoutsHere: Set<String> = ["dagre", "default"]

	/// The layout a file asks for when this build cannot give it, or nil.
	///
	/// Worth a sentence in the pane because the failure is **silent**, which was
	/// measured rather than assumed: a flowchart with `layout: elk` in its front
	/// matter draws, and the drawing is byte for byte the one the same flowchart
	/// draws with no front matter at all. Mermaid does not complain about a
	/// layout it has no loader for; it quietly uses its own. So somebody who
	/// asked for ELK — and people ask for it to get its edge routing on a large
	/// flowchart — gets a different picture from the one they asked for and no
	/// word about why. One line under the drawing is the whole answer, and it is
	/// the same line 0429 decided a file's own theme gets.
	///
	/// Both spellings, the same two `statedLook` reads: `layout:` under `config:`
	/// in the front matter, and `layout` in an `%%{init}%%` directive.
	public static func statedLayout(in source: String) -> String? {
		guard let named = layoutInFrontMatter(source) ?? layoutInInitDirective(source),
		      !layoutsHere.contains(named.lowercased())
		else { return nil }
		return named
	}

	/// `---\nconfig:\n  layout: elk\n---`.
	private static func layoutInFrontMatter(_ source: String) -> String? {
		let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
		guard let opening = lines.firstIndex(where: {
			!$0.trimmingCharacters(in: .whitespaces).isEmpty
		}), lines[opening].trimmingCharacters(in: .whitespaces) == "---" else { return nil }

		for line in lines[(opening + 1)...] {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed == "---" { return nil }
			guard trimmed.hasPrefix("layout:") else { continue }
			let said = unquoted(trimmed.dropFirst("layout:".count)
				.trimmingCharacters(in: .whitespaces))
			return said.isEmpty ? nil : said
		}
		return nil
	}

	/// `%%{init: {"layout": "elk"}}%%`, anywhere in the file.
	private static func layoutInInitDirective(_ source: String) -> String? {
		for raw in source.split(separator: "\n") {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard line.hasPrefix("%%{"), line.contains("init"),
			      let key = line.range(of: "layout")
			else { continue }
			// The value after the key, however it was quoted: `"layout": "elk"`,
			// `'layout':'elk'` and `layout: elk` are all in the wild.
			let rest = line[key.upperBound...].drop(while: { "\"': ".contains($0) })
			let said = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." })
			return said.isEmpty ? nil : String(said)
		}
		return nil
	}

	// MARK: - What a diagram calls itself

	/// The name a diagram gives itself, or nil when it does not give one.
	///
	/// Mermaid's front matter, and **only** its front matter:
	///
	///     ---
	///     title: Ordering a shelf
	///     ---
	///     flowchart TD
	///
	/// That is the one spelling every diagram type understands — Mermaid draws it
	/// above the picture — and the one that is unambiguously a name rather than a
	/// piece of the drawing. The `title Something` *line* directive is
	/// deliberately not read: it exists in some diagram types and not others, and
	/// in a `flowchart` a line reading `title Overview` is two nodes called
	/// `title` and `Overview`. Naming a picture after that would name it after
	/// part of itself.
	///
	/// Only a key at the front matter's own indentation counts, so the `title:`
	/// somebody nests under `config:` is not mistaken for the diagram's.
	///
	/// This is what `DiagramExport` names a fence's picture after when a Markdown
	/// document holds several of them — see the naming rule there, which is where
	/// the decision is written down.
	public static func statedTitle(in source: String) -> String? {
		let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
		guard let opening = lines.firstIndex(where: {
			!$0.trimmingCharacters(in: .whitespaces).isEmpty
		}), lines[opening].trimmingCharacters(in: .whitespaces) == "---" else { return nil }

		for line in lines[(opening + 1)...] {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed == "---" { return nil }
			guard line.first != " ", line.first != "\t", trimmed.hasPrefix("title:") else { continue }
			let said = trimmed.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
			let named = unquoted(said)
			return named.isEmpty ? nil : named
		}
		return nil
	}

	/// A YAML scalar with its own quotes taken off, and nothing else done to it.
	private static func unquoted(_ value: String) -> String {
		guard value.count >= 2, let first = value.first, first == "\"" || first == "'",
		      value.last == first
		else { return value }
		return String(value.dropFirst().dropLast())
	}

	/// A drawing put on paper of its own.
	///
	/// Mermaid emits no background at all: `mermaid.render` hands back shapes on
	/// nothing, which is why the pane paints white behind it and why the canvas
	/// that rasterises a PNG fills white first. An SVG written to disk had
	/// neither, and got away with it only because a transparent drawing of dark
	/// lines happens to be legible on most viewers' white.
	///
	/// A dark one is not. So when this app has chosen the look, it says so in the
	/// file: one rectangle over the whole `viewBox`, first, under everything. A
	/// file that stated its own look gets none — which is what keeps "unchanged"
	/// literally true for it.
	public static func onPaper(_ svg: String, colour: String) -> String {
		guard let open = svg.range(of: "<svg"),
		      let close = svg[open.upperBound...].firstIndex(of: ">")
		else { return svg }
		let attributes = String(svg[open.upperBound..<close])
		// The `viewBox`'s own coordinates rather than 0,0,100%,100%: the box may
		// start anywhere, and a percentage rectangle in a translated group is not
		// where the drawing is.
		let box = Mermaid.attribute("viewBox", in: attributes) ?? "0 0 100 100"
		let numbers = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
		guard numbers.count == 4 else { return svg }
		let rect = "<rect x=\"\(number(numbers[0]))\" y=\"\(number(numbers[1]))\" "
			+ "width=\"\(number(numbers[2]))\" height=\"\(number(numbers[3]))\" "
			+ "fill=\"\(colour)\" stroke=\"none\"/>"
		let after = svg.index(after: close)
		return svg.replacingCharacters(in: after..<after, with: rect)
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
	///
	/// And one thing the page does after every render, which is `abydosInline`
	/// and is not optional — see the comment on it. Mermaid's drawing is a
	/// stylesheet with some shapes attached, and outside a browser that is a
	/// picture of black wedges.
	public static func page(bundle: String) -> String {
		"""
		<!doctype html>
		<html><head><meta charset="utf-8">
		<style>html,body{margin:0;padding:0;background:#fff}</style>
		<script>\(bundle)</script>
		<script>
		// Kept rather than passed once, because the theme changes while the page
		// stays: `mermaid.initialize` does not merge into what it was given
		// before, it replaces it — so a second call carrying only a theme would
		// quietly put `htmlLabels` back on and every exported label would become a
		// `foreignObject` again. Everything is passed every time, and only the
		// theme differs.
		const ABYDOS_OPTIONS = {
			startOnLoad: false,
			securityLevel: 'strict',
			suppressErrorRendering: true,
			htmlLabels: false,
			flowchart: { htmlLabels: false },
			class: { htmlLabels: false },
			state: { htmlLabels: false }
		};
		function abydosInit(theme) {
			const options = Object.assign({}, ABYDOS_OPTIONS);
			// No theme at all when the file states its own, which is not the same
			// as naming Mermaid's default: a diagram's own `%%{init}%%` wins over
			// this either way, and saying nothing is what keeps the picture byte
			// for byte the one this app drew before it had themes.
			if (theme) { options.theme = theme; }
			mermaid.initialize(options);
		}
		abydosInit(null);
		window.__abydosDrew = 0;
		// Every property that decides what a shape looks like, copied out of the
		// browser's own stylesheet resolution and onto the element as an
		// attribute.
		//
		// This is what makes the drawing a picture rather than a program.
		// Mermaid emits a `<style>` block and a tree of bare `<path>`s and
		// `<rect>`s, and everything an edge looks like — `fill:none` above all —
		// lives in a descendant selector inside it. A browser applies that; the
		// SVG renderer behind NSImage, Preview.app, librsvg and Inkscape do not,
		// and what they draw instead is every edge filled solid black. Seen, in
		// the preview pane, before this existed.
		const ABYDOS_PAINTED = [
			'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width',
			'stroke-opacity', 'stroke-dasharray', 'stroke-linecap', 'stroke-linejoin',
			'opacity', 'color', 'font-family', 'font-size', 'font-weight', 'font-style',
			'text-anchor', 'dominant-baseline'
		];
		// Not `marker-end` and its two neighbours, deliberately. Mermaid already
		// puts those on the element as attributes, so there is nothing in a
		// stylesheet to rescue — and the computed form is `url("#id")`, whose
		// quotes come back out of the serialiser as `&quot;` and point at
		// nothing. Copying them would take the arrowheads off every edge.
		//
		// Everything in that list but `opacity` is an *inherited* property, and
		// that distinction turns out to matter. Written onto something that draws
		// nothing itself, an inherited value is redundant — every shape below it
		// already carries its own resolved copy — and CoreSVG then applies
		// `stroke-opacity` on a `<g>` a second time, as if it were a group
		// opacity. Measured on a file of four strokes: a half-transparent stroke
		// inside a `<g stroke-opacity="0.5">` comes out at a quarter, and the same
		// stroke with no group around it comes out right. A Sankey diagram nests
		// two such groups, so its flows were drawn at an eighth of the weight the
		// browser gives them — a picture of blank paper with the node bars on it.
		// `opacity` is the one that is not inherited: on a group it means the
		// group, so it is the one thing worth writing there.
		const ABYDOS_CONTAINERS = [
			'g', 'svg', 'defs', 'switch', 'symbol', 'a', 'marker', 'clipPath',
			'mask', 'pattern', 'linearGradient', 'radialGradient', 'stop',
			'foreignObject', 'title', 'desc', 'metadata'
		];
		function abydosInline(text) {
			const holder = document.createElement('div');
			holder.style.position = 'absolute';
			holder.style.left = '-100000px';
			holder.innerHTML = text;
			document.body.appendChild(holder);
			try {
				const root = holder.querySelector('svg');
				if (!root) { return text; }
				// First, so everything below measures and paints the labels that are
				// actually going to be in the file rather than the ones a browser
				// happened to pick.
				abydosTakeThePlainBranch(root);
				// Read from every element before any of it is written, since taking
				// an inherited value off a container changes what its children
				// resolve to.
				const painted = [];
				for (const element of [root, ...root.querySelectorAll('*')]) {
					if (element.tagName === 'style') { continue; }
					const resolved = getComputedStyle(element);
					const values = {};
					for (const property of ABYDOS_PAINTED) {
						values[property] = resolved.getPropertyValue(property);
					}
					painted.push({ element: element, values: values });
				}
				for (const found of painted) {
					const draws = ABYDOS_CONTAINERS.indexOf(found.element.tagName) === -1;
					for (const property of ABYDOS_PAINTED) {
						if (!draws && property !== 'opacity') {
							// Taken *off*, not merely not added. Mermaid writes some of
							// these itself — a Sankey's links group carries its own
							// `stroke-opacity="0.5"` — and CoreSVG applies that to the
							// group as well as to the strokes inside it, which halves
							// the flows a second time. Nothing needs it: every shape
							// below has its own resolved copy by now.
							found.element.removeAttribute(property);
							continue;
						}
						const value = found.values[property];
						if (value && value !== 'none' || property === 'fill' || property === 'stroke') {
							found.element.setAttribute(property, abydosPlainReference(value));
						}
					}
				}
				abydosBakeText(root);
				abydosBakeMarkers(root);
				// The stylesheet has done its work and is now only a second,
				// contradictory answer for anything that does read CSS.
				for (const sheet of root.querySelectorAll('style')) { sheet.remove(); }
				for (const marker of root.querySelectorAll('marker')) { marker.remove(); }
				return new XMLSerializer().serializeToString(root);
			} finally {
				holder.remove();
			}
		}
		// A reference to something in the same file, written the way every
		// renderer reads it.
		//
		// `getComputedStyle` hands a paint server back as `url("#linearGradient-5")`
		// — with quotes, which the serialiser writes out as `&quot;`. WebKit
		// forgives that and CoreSVG does not: it finds no such gradient and paints
		// nothing at all, which is how a Sankey diagram lost every one of its flows
		// in the pane and in the exported SVG while the PNG rasterised from the
		// same drawing was perfect. Seen, measured at 77% of the page different
		// between the two renderers, and fixed by taking the quotes back out.
		//
		// This is the same trap the note above `marker-end` names. That one is
		// avoided by not copying the property at all, which works because Mermaid
		// writes the markers as attributes itself; a gradient stroke has no such
		// second copy, so it has to be written correctly instead.
		function abydosPlainReference(value) {
			return value.indexOf('url(') === -1 ? value
				: value.replace(/url\\(\\s*["']?([^"')]*)["']?\\s*\\)/g, 'url($1)');
		}
		/// The plain-text branch of a `<switch>`, kept, and the HTML one dropped.
		///
		/// Mermaid draws a user journey's labels with `byFo`, which puts *both*
		/// answers in the file: a `foreignObject` full of HTML and a `<text>` beside
		/// it inside a `<switch>`, for the renderer to choose between. A browser
		/// takes the first and never lays the second out — so `getNumberOfChars`
		/// on it is nought, `abydosBakeText` counted it as an empty label and
		/// removed it, and the file went out with only the branch CoreSVG cannot
		/// draw. Every label of a journey diagram was missing from the pane and
		/// from the exported SVG, with the PNG correct, which is exactly the
		/// disagreement between the two renderers this whole pass exists to end.
		///
		/// So the choice is made here instead, and made the other way: the HTML
		/// goes, the text stays, and the `switch` is unwrapped so nothing later has
		/// to understand what one means. Only when there is a `<text>` to keep — a
		/// `foreignObject` standing on its own is the only drawing of that label
		/// there is, and removing it would lose the words in the browser as well.
		///
		/// The colour comes across with it, and that is not tidiness. HTML text is
		/// painted with `color` and SVG text with `fill`, and Mermaid's own
		/// stylesheet sets both on a journey's section — `color` to a dark grey for
		/// the branch it expects to be used, and `fill` to the pale lavender the
		/// section's *rectangle* is filled with. Take the plain branch without this
		/// and the section title is written in near-white on near-white: present in
		/// the file, invisible in every renderer. So the kept text is painted the
		/// colour the browser was going to draw those words.
		function abydosTakeThePlainBranch(root) {
			for (const choice of [...root.querySelectorAll('switch')]) {
				const foreign = [...choice.children].filter(c => c.tagName === 'foreignObject');
				const plain = [...choice.children].filter(c => c.tagName !== 'foreignObject');
				if (!foreign.length || !plain.length) { continue; }
				let written = null;
				for (const html of foreign) {
					for (const piece of html.querySelectorAll('*')) {
						if (piece.textContent && piece.textContent.trim()) { written = piece; }
					}
				}
				// Read before anything is removed: a detached element has no
				// computed style to ask about.
				const ink = written ? getComputedStyle(written).color : null;
				for (const html of foreign) { html.remove(); }
				for (const kept of plain) {
					// As an inline style rather than an attribute, because the
					// stylesheet that painted it the wrong colour is still there for
					// another few lines and a presentation attribute loses to it.
					if (ink) {
						for (const words of [kept, ...kept.querySelectorAll('text')]) {
							if (words.tagName === 'text') { words.style.fill = ink; }
						}
					}
					choice.parentNode.insertBefore(kept, choice);
				}
				choice.remove();
			}
		}
		// Every run of text put where the browser actually laid it out.
		//
		// Mermaid positions a label with a `dy` on each `tspan` and a
		// `dominant-baseline`, and asks the renderer to work the rest out. A
		// browser does; CoreSVG — which is what NSImage, the preview pane and
		// Preview.app all draw an SVG with — puts every node's label above its
		// box instead. Asking the browser where each run *went* and writing that
		// down is the whole fix, and it is exact rather than a correction.
		/// Every run becomes a `<text>` of its own, at the place the browser put
		/// it.
		///
		/// It has to be a `<text>` and not a repositioned `tspan`, and that was
		/// measured rather than assumed. Mermaid writes a label as a `tspan`
		/// inside a `tspan` inside a `text`, with the position on the inner ones
		/// — and CoreSVG **ignores `x` and `y` on a `tspan` altogether**, drawing
		/// every label from the `text` element's own origin instead. Writing the
		/// positions onto the tspans moved every label half its width to the
		/// right; only promoting each run to a `text` puts it where it belongs in
		/// a browser and outside one alike.
		///
		/// Everything is measured before anything is changed, because each thing
		/// written moves what has not been read yet.
		/// The unit is the **row**, not the word, and that is the second thing
		/// this had to be told. Mermaid puts every word in a `tspan` of its own
		/// with the spaces between them as bare text nodes, so promoting each
		/// word to a `<text>` drew "Orderplaced" — the words correct, the gaps
		/// gone. A row kept whole, with its word spans left inside it as flowing
		/// content, keeps both the spacing and whatever emphasis those spans
		/// carry.
		const ABYDOS_SVG = 'http://www.w3.org/2000/svg';
		const ABYDOS_PLACED = ['x', 'y', 'dx', 'dy'];
		// And these come off everything left *inside* a row. `text-anchor` is
		// applied to a text chunk by the element the chunk starts at — which,
		// once a row's first word is its own `tspan`, is that word rather than
		// the row. A browser honours it and shifts the whole label half its own
		// width to the left; CoreSVG ignores it and does not. The two renderers
		// then draw different pictures from the same file, which was seen: the
		// pane right and the exported PNG with "Tell the customer" hanging off
		// the left edge.
		const ABYDOS_ANCHORED = ABYDOS_PLACED.concat(
			['text-anchor', 'dominant-baseline', 'alignment-baseline']
		);
		function abydosBakeText(root) {
			const jobs = [];
			const empty = [];
			for (const text of root.querySelectorAll('text')) {
				const rows = [...text.children].filter(child => child.tagName === 'tspan');
				const measured = [];
				for (const row of (rows.length ? rows : [text])) {
					try {
						if (row.getNumberOfChars() > 0) {
							const start = row.getStartPositionOfChar(0);
							measured.push({ row: row, x: start.x, y: start.y });
						}
					} catch (ignored) { /* a row with nothing in it */ }
				}
				if (measured.length) { jobs.push({ text: text, measured: measured }); }
				// A label with nothing in it draws nothing, and Mermaid emits a
				// few. Left alone it would be the one thing in the file still
				// carrying a `text-anchor` on a `tspan` — invisible, and exactly
				// the sort of leftover somebody later mistakes for the rule.
				else { empty.push(text); }
			}
			for (const nothing of empty) { nothing.remove(); }
			for (const job of jobs) {
				// The `<text>`'s own transform moves to the group that replaces
				// it: the positions above are in the space *inside* that
				// transform, which is where they have to stay.
				const holder = document.createElementNS(ABYDOS_SVG, 'g');
				const transform = job.text.getAttribute('transform');
				if (transform) { holder.setAttribute('transform', transform); }
				for (const found of job.measured) {
					const line = document.createElementNS(ABYDOS_SVG, 'text');
					for (const source of [job.text, found.row]) {
						for (const attribute of source.attributes) {
							if (attribute.name === 'transform') { continue; }
							line.setAttribute(attribute.name, attribute.value);
						}
					}
					for (const name of ABYDOS_PLACED) { line.removeAttribute(name); }
					line.removeAttribute('alignment-baseline');
					line.setAttribute('x', found.x);
					line.setAttribute('y', found.y);
					// The position above is already where the anchoring and the
					// baseline put it. Leaving either in would apply it twice.
					line.setAttribute('text-anchor', 'start');
					line.setAttribute('dominant-baseline', 'auto');
					// And said again in the `style`, because the attributes above
					// lose to one. A treemap's label carries
					// `style="text-anchor: middle; dominant-baseline: middle"` of
					// Mermaid's own, which came across with the other attributes and
					// then beat both lines above — so the browser centred a label
					// that was already centred and drew it half a line low, while
					// CoreSVG ignored the style and drew it right. Two pictures from
					// one file again, this time with the *export* the wrong one.
					for (const name of ABYDOS_ANCHORED) { line.style.removeProperty(name); }
					line.style.setProperty('text-anchor', 'start');
					line.style.setProperty('dominant-baseline', 'auto');
					// The row's own content, spaces and all, flowing from that
					// one position — with every inner position taken off, since
					// a `tspan`'s is ignored by half the renderers there are and
					// honoured by the other half.
					const inside = found.row === job.text
						? [...job.text.childNodes].map(node => node.cloneNode(true))
						: [...found.row.childNodes].map(node => node.cloneNode(true));
					for (const piece of inside) {
						if (piece.nodeType === 1) {
							for (const name of ABYDOS_ANCHORED) {
								piece.removeAttribute(name);
								piece.style.removeProperty(name);
							}
							for (const nested of piece.querySelectorAll('*')) {
								for (const name of ABYDOS_ANCHORED) {
									nested.removeAttribute(name);
									nested.style.removeProperty(name);
								}
							}
						}
						line.appendChild(piece);
					}
					holder.appendChild(line);
				}
				job.text.parentNode.replaceChild(holder, job.text);
			}
		}

		/// Every arrowhead drawn where its marker would have put it.
		///
		/// `marker-end` is a reference to a shape that a renderer is expected to
		/// place, rotate and scale along the path. CoreSVG draws nothing at all
		/// for one, so a flowchart previewed here had no arrows on it and an
		/// exported file had none anywhere outside a browser. The marker's own
		/// content is copied to the end of the line with the transform the
		/// specification describes, which is geometry every renderer can draw.
		function abydosBakeMarkers(root) {
			const ends = ['marker-start', 'marker-end'];
			for (const shape of root.querySelectorAll('[marker-start],[marker-end]')) {
				if (typeof shape.getTotalLength !== 'function') { continue; }
				let total = 0;
				try { total = shape.getTotalLength(); } catch (ignored) { continue; }
				// A line with no length at all is not a mistake to skip past.
				// `autonumber` in a sequence diagram is drawn as a line from a
				// point to itself carrying nothing but a `marker-start`, and the
				// badge is that marker's circle. Bailing out here left the
				// reference standing on a marker that is removed a moment later,
				// so every badge became white text on white paper — the numbers
				// were in the file and nowhere in the picture. The direction of a
				// line with no length is nought, which is what `atan2(0, 0)`
				// gives, so the rest of this works unchanged.
				if (!Number.isFinite(total) || total < 0) { continue; }
				const width = parseFloat(shape.getAttribute('stroke-width')) || 1;
				for (const end of ends) {
					const reference = shape.getAttribute(end);
					shape.removeAttribute(end);
					if (!reference) { continue; }
					const named = reference.match(/#([^)"']+)/);
					const marker = named && root.querySelector('marker[id="' + named[1] + '"]');
					if (!marker) { continue; }

					const atEnd = end === 'marker-end';
					const step = Math.min(1, total);
					const here = shape.getPointAtLength(atEnd ? total : 0);
					const near = shape.getPointAtLength(atEnd ? total - step : step);
					let angle = atEnd
						? Math.atan2(here.y - near.y, here.x - near.x)
						: Math.atan2(near.y - here.y, near.x - here.x);
					const orient = marker.getAttribute('orient') || '0';
					if (orient === 'auto-start-reverse' && !atEnd) { angle += Math.PI; }
					else if (orient !== 'auto' && orient !== 'auto-start-reverse') {
						angle = (parseFloat(orient) || 0) * Math.PI / 180;
					}

					const box = (marker.getAttribute('viewBox') || '').split(/[ ,]+/).map(Number);
					const drawnWidth = parseFloat(marker.getAttribute('markerWidth') || '3');
					const drawnHeight = parseFloat(marker.getAttribute('markerHeight') || '3');
					const unit = marker.getAttribute('markerUnits') === 'userSpaceOnUse' ? 1 : width;
					const sx = (box.length === 4 && box[2] ? drawnWidth / box[2] : 1) * unit;
					const sy = (box.length === 4 && box[3] ? drawnHeight / box[3] : 1) * unit;
					const refX = parseFloat(marker.getAttribute('refX') || '0');
					const refY = parseFloat(marker.getAttribute('refY') || '0');

					const drawn = document.createElementNS('http://www.w3.org/2000/svg', 'g');
					drawn.setAttribute('transform',
						'translate(' + here.x + ',' + here.y + ') '
						+ 'rotate(' + (angle * 180 / Math.PI) + ') '
						+ 'scale(' + sx + ',' + sy + ') '
						+ 'translate(' + (-refX) + ',' + (-refY) + ')');
					for (const piece of marker.children) { drawn.appendChild(piece.cloneNode(true)); }
					// After the line rather than before it, so an arrowhead sits on
					// top of whatever it points at.
					shape.parentNode.insertBefore(drawn, shape.nextSibling);
				}
			}
		}
		async function abydosDraw(source, theme) {
			const id = 'abydos-' + (window.__abydosDrew++);
			abydosInit(theme || null);
			try {
				const drawn = await mermaid.render(id, source);
				return JSON.stringify({ svg: abydosInline(drawn.svg) });
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
		async function abydosRaster(svg, scale, paper) {
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
			// lines on nothing is invisible in half the places it will be pasted —
			// and a PNG of *light* lines on white is invisible everywhere, which
			// is what a dark diagram on the old fixed white would have been.
			pen.fillStyle = paper || '#ffffff';
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
