import Foundation

/// The two documents draw.io's editor runs in, written here rather than
/// vendored.
///
/// draw.io ships an `index.html`, and it is deliberately not the one used. Its
/// job upstream is to decide which of a dozen builds to fetch for which host —
/// it redirects `draw.io` to `app.diagrams.net`, branches on Electron, and
/// loads `app.min.js` itself — and none of that has an answer here. What is
/// kept is the handful of globals `bootstrap.js` defines that `app.min.js`
/// reads, written out below so a reader can see the whole contract in one
/// place.
///
/// **There are two documents, and there has to be.** draw.io's embed mode is
/// not a mode you ask for, it is a mode it agrees to:
///
///     EditorUi.prototype.initializeEmbedMode = function() {
///         this.setGraphEnabled(false);
///         if ((this.embedMessageSource || window.opener || window.parent) != window && …
///
/// A top-level window has no opener and is its own `parent`, so that test fails
/// — and what it leaves behind is not "no protocol" but a **disabled graph**:
/// the editor loads, draws nothing, and cannot be clicked. So the editor is in
/// an iframe and this app talks to its host, which is what every other draw.io
/// integration does and what the protocol was written for. The two documents
/// are same-origin, so the host can also reach the `EditorUi` directly for the
/// things the protocol has no message for.
enum DrawioEditorPage {
	/// The outer document: an iframe, and the bridge between it and the app.
	static let host = """
		<!doctype html>
		<html><head><meta charset="utf-8">
		<style>
		html, body { margin:0; padding:0; height:100%; overflow:hidden; background:#fff; }
		iframe { border:0; width:100%; height:100%; display:block; }
		</style>
		<script>
		\(bridge)
		</script>
		</head>
		<body>
		<iframe id="abydos-drawio" src="editor.html?ABYDOS_PARAMETERS"></iframe>
		</body></html>
		"""

	/// The inner document: draw.io itself.
	///
	/// Only `app.min.js` is loaded here. `App.main` loads
	/// `shapes-14-6-5.min.js`, `stencils.min.js` and `extensions.min.js` itself
	/// and **will not call back until all three have arrived** — which is why
	/// all three are vendored, and why loading them from this page as well
	/// would only load them twice.
	///
	/// `App.main` is called by hand rather than by draw.io's own `main.js` for
	/// one reason: it takes a callback carrying the `EditorUi`, and `main.js`
	/// throws it away. That object is what the document is read out of and what
	/// the change listener is attached to.
	static let editor = """
		<!doctype html>
		<html><head><meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
		<link rel="stylesheet" type="text/css" href="styles/grapheditor.css">
		<style>
		html, body { margin:0; padding:0; height:100%; overflow:hidden; }
		</style>
		<script>
		\(bootstrap)
		</script>
		</head>
		<body class="geEditor">
		<script>
		const tag = document.createElement('script');
		tag.src = 'js/app.min.js';
		tag.onload = function() {
			App.main(function(ui) {
				window.abydosUi = ui;
				// Same origin, so the host reaches in directly for the things
				// the embed protocol has no message for — reading the document
				// on ⌘S, and hearing about a change the moment it happens
				// rather than on draw.io's own autosave timer.
				if (window.parent !== window && window.parent.abydosEditorReady) {
					window.parent.abydosEditorReady(ui);
				}
			});
		};
		document.head.appendChild(tag);
		</script>
		</body></html>
		"""

	/// What `bootstrap.js` provides that `app.min.js` reads, and nothing else.
	///
	/// Every path is relative, which is the point of serving the editor from a
	/// scheme of this app's own: they resolve against the page and every one of
	/// them is answered out of the application bundle.
	private static let bootstrap = """
		var urlParams = (function() {
			var result = {};
			var params = window.location.search.slice(1).split('&');
			for (var i = 0; i < params.length; i++) {
				var at = params[i].indexOf('=');
				if (at > 0) { result[params[i].substring(0, at)] = params[i].substring(at + 1); }
			}
			return result;
		})();
		window.urlParams = urlParams;
		var mxIsElectron = false;
		var isLocalStorage = false;
		var mxScriptsLoaded = false, mxWinLoaded = false;
		var t0 = new Date();
		function mxmeta(name, content, httpEquiv) {
			const tag = document.createElement('meta');
			if (name != null) { tag.setAttribute('name', name); }
			tag.setAttribute('content', content);
			if (httpEquiv != null) { tag.setAttribute('http-equiv', httpEquiv); }
			document.head.appendChild(tag);
		}
		// draw.io loads optional extras through these, and each one it asks for
		// takes a callback that it *waits on*. A stub that does nothing is not
		// harmless: `App.main` would never reach its own callback and the pane
		// would say "Opening draw.io…" for ever with nothing to say why. So
		// they behave, and a file that is not in this build fails the load
		// rather than hanging it.
		function mxscript(src, onLoad, id, dataAppKey, noWrite, onError) {
			const tag = document.createElement('script');
			tag.setAttribute('type', 'text/javascript');
			tag.setAttribute('src', src);
			if (id != null) { tag.setAttribute('id', id); }
			if (onLoad != null) { tag.onload = onLoad; }
			tag.onerror = function(happened) {
				if (onError != null) { onError('Failed to load ' + src, happened); }
				else if (onLoad != null) { onLoad(); }
			};
			document.head.appendChild(tag);
		}
		function mxinclude(src) { mxscript(src); }
		function checkAllLoaded() {}
		window.RESOURCES_PATH = 'resources';
		window.RESOURCE_BASE = 'resources/dia';
		window.STENCIL_PATH = 'stencils';
		window.SHAPES_PATH = 'shapes';
		window.STYLE_PATH = 'styles';
		window.IMAGE_PATH = 'images';
		window.GRAPH_IMAGE_PATH = 'img';
		window.CSS_PATH = 'styles';
		window.mxBasePath = 'mxgraph';
		window.mxImageBasePath = 'mxgraph/images';
		window.mxLoadStylesheets = false;
		window.mxLanguage = 'en';
		window.mxLanguages = [];
		"""

	/// Everything this app adds, and it all lives in the host: the relay, and
	/// the four things the pane asks the editor to do.
	private static let bridge = """
		window.abydosErrors = [];
		window.onerror = function(said, where, line) {
			window.abydosErrors.push(said + ' (' + where + ':' + line + ')');
			abydosPost({ event: 'abydosTrouble', message: String(said) });
		};

		function abydosPost(message) {
			try {
				window.webkit.messageHandlers.abydos.postMessage(JSON.stringify(message));
			} catch (ignored) { /* not hosted by the app, which is a test */ }
		}

		function abydosFrame() {
			const frame = document.getElementById('abydos-drawio');
			return frame != null ? frame.contentWindow : null;
		}

		// draw.io's embed protocol posts to `window.opener || window.parent`,
		// which from inside the iframe is this document. Everything it says
		// arrives here and is handed on; everything the app says is posted the
		// other way, and arrives there with `source` equal to this window,
		// which is what draw.io checks before it will listen.
		window.addEventListener('message', function(happened) {
			if (happened.source !== abydosFrame()) { return; }
			let decoded = null;
			try { decoded = JSON.parse(happened.data); } catch (ignored) { return; }
			if (decoded && decoded.event != null) { abydosPost(decoded); }
		});

		function abydosSend(json) {
			const frame = abydosFrame();
			if (frame != null) { frame.postMessage(json, '*'); }
		}

		let abydosUi = null;
		let abydosPending = null;

		/// Called by the editor document once `App.main` has built its `EditorUi`.
		function abydosEditorReady(ui) {
			abydosUi = ui;
			abydosPlainColours();
			// Every change to the model, and every change to the set of pages,
			// which is not a model change. Both funnel into one place, debounced
			// only enough that dragging a shape across the canvas is one report
			// rather than sixty.
			//
			// `mxEvent` is the *iframe's*, not this document's. draw.io is not
			// loaded here and never will be, and reaching for a bare `mxEvent`
			// throws a ReferenceError that takes the rest of this function with
			// it — leaving an editor that works and an app that never hears
			// about a single change.
			const frame = abydosFrame();
			ui.editor.graph.model.addListener(frame.mxEvent.CHANGE, abydosChanged);
			for (const named of ['pageRenamed', 'pageMoved', 'pagesUpdated',
			                     'pageFormatChanged', 'fileMerged']) {
				ui.addListener(named, abydosChanged);
			}
		}

		/// Colours a renderer that is not a browser can read.
		///
		/// draw.io writes every colour twice — the plain value and
		/// `light-dark(…)` beside it — so one file follows the reader's theme.
		/// WebKit understands it and CoreSVG does not: it paints the element
		/// black rather than falling back, so an exported SVG opened in
		/// Preview.app is a page of solid black boxes. Off, every colour is
		/// written once, as itself.
		function abydosPlainColours() {
			const frame = abydosFrame();
			if (frame == null) { return; }
			frame.mxUtils.lightDarkColorSupported = false;
			frame.Graph.defaultAdaptiveColors = 'none';
			// And on the graph itself, which answers from its own
			// `adaptiveColors` before it falls back to the class's.
			if (abydosUi != null) { abydosUi.editor.graph.adaptiveColors = 'none'; }
		}

		/// Which way round the editor is drawn.
		///
		/// **Not `EditorUi.setDarkMode`**, and that is the whole reason this
		/// exists. Its entire body is inside
		/// `mxUtils.lightDarkColorSupported && (…)`, and that flag is off here on
		/// purpose (above) — so calling it does nothing at all, silently. What it
		/// would have done is written out instead, as the two independent things
		/// it actually is:
		///
		///  * **`chrome`** — the toolbars, the panels and the canvas's own paper.
		///    That is a `geDarkMode` class and a `color-scheme`, and the browser
		///    resolves draw.io's `light-dark()` stylesheet from it. It follows the
		///    app, always: a light toolbar in a dark window is not the diagram
		///    stating anything, it is a pane that did not get the message.
		///  * **`colours`** — which half of every `light-dark()` pair is written
		///    into the shapes. That is `mxUtils.preferDarkColor`, and it follows
		///    the app only when the document has not stated a background of its
		///    own. This is the file winning, and it is the only half of dark mode
		///    that is the author's business.
		function abydosSetDark(chrome, colours) {
			const frame = abydosFrame();
			if (frame == null || abydosUi == null) { return; }
			frame.mxUtils.preferDarkColor = !!colours;
			frame.Editor.darkMode = !!chrome;
			// `color-scheme` on the container as well as on the document, and that
			// is not belt and braces: draw.io's own start-up sets an inline
			// `color-scheme: light` on the container, and an inline property on a
			// nearer element beats one on the root — so the panels built from a
			// plain `light-dark()` with no `.geDarkMode` rule behind them stayed
			// light while everything with a class rule went dark. Seen: a dark
			// editor with a white format panel down the right of it.
			const containers = [frame.document.body, abydosUi.container,
			                    abydosUi.editor.graph.container];
			for (const element of containers) {
				if (element == null) { continue; }
				if (chrome) { element.classList.add('geDarkMode'); }
				else { element.classList.remove('geDarkMode'); }
				element.style.colorScheme = chrome ? 'dark' : 'light';
			}
			frame.document.documentElement.style.colorScheme = chrome ? 'dark' : 'light';
			const graph = abydosUi.editor.graph;
			graph.defaultPageBackgroundColor = frame.Editor.getDefaultPageBackgroundColor();
			graph.refresh();
			graph.view.validate();
			try { abydosUi.fireEvent(new frame.mxEventObject('darkModeChanged')); }
			catch (ignored) { /* nothing is listening in embed mode */ }
		}

		function abydosChanged() {
			if (abydosPending != null) { window.clearTimeout(abydosPending); }
			abydosPending = window.setTimeout(function() {
				abydosPending = null;
				const xml = abydosFileData();
				if (xml != null) { abydosPost({ event: 'abydosChanged', xml: xml }); }
			}, 120);
		}

		/// The document as it stands, in the encoding it arrived in.
		function abydosFileData() {
			if (abydosUi == null) { return null; }
			try { return abydosUi.getFileData(true); }
			catch (thrown) { return null; }
		}

		/// A file that arrived compressed is written back compressed, and a
		/// plain one plain. `Editor.defaultCompressed` is what `getFileData`
		/// reads when it is not told, and draw.io's own default is *plain* —
		/// which would rewrite every file draw.io itself wrote into a diff
		/// thousands of lines long the first time somebody moved a box.
		function abydosAfterLoad(compressed) {
			const frame = abydosFrame();
			if (frame == null || frame.Editor == null) { return; }
			frame.Editor.defaultCompressed = compressed;
			frame.Editor.compressXml = compressed;
		}

		/// A picture of what is on screen, through draw.io's own drawing.
		///
		/// `foEnabled` is turned off around the export and put back afterwards.
		/// mxGraph's default puts every label in a `foreignObject` full of HTML,
		/// which a browser draws and Preview.app, CoreSVG and a `<canvas>` do
		/// not — so with it on the exported SVG is a picture of empty boxes
		/// outside a browser and the PNG rasterises blank. On screen it stays
		/// on, because on screen there is a browser.
		async function abydosExport(format) {
			const frame = abydosFrame();
			if (abydosUi == null || frame == null) { return null; }
			const graph = abydosUi.editor.graph;
			const was = frame.mxSvgCanvas2D.prototype.foEnabled;
			let drawn = null;
			try {
				frame.mxSvgCanvas2D.prototype.foEnabled = false;
				drawn = graph.getSvg(graph.background || '#ffffff', 1, 4, false,
					null, true, null, null, null, null, null, null, null);
			} finally {
				frame.mxSvgCanvas2D.prototype.foEnabled = was;
			}
			const svg = new XMLSerializer().serializeToString(drawn);
			if (format !== 'png') { return svg; }
			return await abydosRaster(svg, 2);
		}

		async function abydosRaster(svg, scale) {
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
			pen.fillStyle = '#ffffff';
			pen.fillRect(0, 0, canvas.width, canvas.height);
			pen.drawImage(picture, 0, 0, canvas.width, canvas.height);
			return canvas.toDataURL('image/png').split(',')[1];
		}
		"""
}
