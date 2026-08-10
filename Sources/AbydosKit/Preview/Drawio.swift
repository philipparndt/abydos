import Compression
import Foundation

/// What a `.drawio` file is, and the pages inside it.
///
/// Unlike PlantUML and Mermaid, this is not text somebody types. It is an
/// editor's document — an `<mxfile>` of `mxGraphModel` XML, usually
/// deflate-compressed, often several pages — and the XML is a serialisation
/// nobody is meant to read. See 0426.
///
/// This type is the part with no web view in it: reading the format, counting
/// the pages, and building the page a `WKWebView` draws with. `DrawioRenderer`
/// is the part that runs, and `DrawioEditor` is the part somebody draws in.
///
/// Three things here are facts about the format that cost real time to
/// establish, and each is a trap:
///
///  * **The payload is `base64(deflateRaw(encodeURIComponent(xml)))`.**
///    Inflating and stopping there gives a string full of `%20` that parses as
///    XML and is wrong everywhere a label had a space in it.
///  * **`.drawio.svg` is a real SVG** carrying the whole `<mxfile>` in a
///    `content` attribute, in one of three encodings tried in order: raw (`<`),
///    URI-escaped (`%`), then base64.
///  * **`.drawio.png` is a real PNG** with a `tEXt` or `zTXt` chunk keyed
///    `mxfile` or `mxGraphModel`, holding URI-escaped XML — `+` for space, and
///    `zTXt` zlib-deflated on top.
public enum Drawio {
	/// What a preview asks for. A drawing has no resolution to be wrong about.
	public static let previewFormat: DiagramFormat = .svg

	/// The extensions draw.io's own tooling writes.
	///
	/// `.drawio` and `.dio` are the plain document. `.drawio.svg` and
	/// `.drawio.png` are the "editable picture" forms, and they are matched by
	/// the *name* rather than by `pathExtension` — which says `svg` for
	/// `architecture.drawio.svg` and is the one place the app's existing
	/// detection is wrong for this file type.
	public static let extensions = ["drawio", "dio"]

	/// Whether a file is a draw.io document this opens.
	///
	/// A `.drawio.svg` or `.drawio.png` is deliberately **not** one. It is a
	/// picture that GitHub renders, it previews as a picture today, and reading
	/// it as a drawing would take that away for the sake of an editor somebody
	/// can get by opening the `.drawio` beside it. What the app does read out of
	/// those two is their `<mxfile>` — see `mxfile(in:)` — so a picture this app
	/// wrote can be recognised as one of its own.
	public static func isDiagram(_ url: URL) -> Bool {
		extensions.contains(url.pathExtension.lowercased())
	}

	/// The one sentence somebody needs when the vendored files are not there.
	public static let missingBundleHint = """
		draw.io could not be loaded: its files are missing from this build of Abydos. \
		Run Scripts/vendor-drawio.sh and rebuild.
		"""

	// MARK: - What is in the file

	/// One page of a document: a `<diagram>` element with a model inside it.
	public struct Page: Equatable, Sendable {
		/// What the tab in draw.io says. Empty when the file did not name it.
		public let name: String
		/// draw.io's own identifier for the page, which is what survives a page
		/// being moved and is what a link between pages points at.
		public let id: String
		/// The `<mxGraphModel>` XML, decompressed and un-escaped.
		public let model: String
		/// Whether the payload arrived compressed, so it can be written back the
		/// way it came rather than turned into a diff nobody asked for.
		public let wasCompressed: Bool

		public init(name: String, id: String, model: String, wasCompressed: Bool) {
			self.name = name
			self.id = id
			self.model = model
			self.wasCompressed = wasCompressed
		}

		/// What the page control shows. A file draw.io made always names its
		/// pages; one written by hand may not.
		public func title(number: Int) -> String {
			name.isEmpty ? "Page \(number)" : name
		}
	}

	/// A whole document: the `<mxfile>` as it stands, and its pages.
	public struct Document: Equatable, Sendable {
		/// The `<mxfile>` element, exactly as it was in the file. This is what is
		/// handed to draw.io, which decompresses and counts pages itself.
		public let mxfile: String
		public let pages: [Page]

		public init(mxfile: String, pages: [Page]) {
			self.mxfile = mxfile
			self.pages = pages
		}

		/// Whether every page arrived compressed, which is what a file draw.io
		/// wrote looks like — all 155 of the templates draw.io ships are.
		public var isCompressed: Bool { pages.allSatisfy(\.wasCompressed) }
	}

	/// The document in a file's bytes, whichever of the three forms it is in.
	public static func read(_ data: Data) -> Document? {
		guard let mxfile = mxfile(in: data) else { return nil }
		return Document(mxfile: mxfile, pages: pages(in: mxfile))
	}

	/// The `<mxfile>` element in a file's bytes.
	///
	/// A plain `.drawio` holds it directly. The two picture forms carry it
	/// alongside a real picture, which is what makes them open in draw.io and
	/// render on GitHub at the same time.
	public static func mxfile(in data: Data) -> String? {
		if Array(data.prefix(8)) == DiagramStamp.pngSignature {
			return mxfileInPNG(data)
		}
		guard let text = String(data: data, encoding: .utf8) else { return nil }
		if let range = text.range(of: "<mxfile") {
			// A plain document, or an SVG whose `content` attribute holds raw XML
			// — in which case the `<` form has already been unescaped by
			// whatever wrote it, so the element is simply in the text.
			guard let end = text.range(of: "</mxfile>", range: range.lowerBound..<text.endIndex)
			else { return nil }
			return String(text[range.lowerBound..<end.upperBound])
		}
		return mxfileInSVG(text)
	}

	/// The `<mxfile>` an SVG carries in its root element's `content` attribute.
	///
	/// draw.io tries three encodings in this order, and so does this: raw XML,
	/// then URI-escaped, then base64. Anything else is somebody's own drawing.
	static func mxfileInSVG(_ text: String) -> String? {
		guard let open = text.range(of: "<svg"),
		      let close = text[open.upperBound...].firstIndex(of: ">"),
		      let raw = Mermaid.attribute("content", in: String(text[open.upperBound..<close]))
		else { return nil }
		let unescaped = raw
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#10;", with: "\n")
			.replacingOccurrences(of: "&amp;", with: "&")
		if unescaped.hasPrefix("<") { return unescaped }
		if unescaped.hasPrefix("%") { return unescaped.removingPercentEncoding }
		guard let bytes = Data(base64Encoded: unescaped) else { return nil }
		return String(data: bytes, encoding: .utf8)
	}

	/// The `<mxfile>` a PNG carries in a `tEXt` or `zTXt` chunk.
	///
	/// The key is `mxfile` or `mxGraphModel`, and the value is URI-escaped XML
	/// with `+` standing in for a space — which is `escape()`'s output rather
	/// than `encodeURIComponent`'s, and the reason the `+` has to be put back
	/// before anything is un-escaped.
	static func mxfileInPNG(_ data: Data) -> String? {
		for (key, payload) in pngTextChunks(data) where key == "mxfile" || key == "mxGraphModel" {
			guard let text = String(data: payload, encoding: .utf8) else { continue }
			let spaced = text.replacingOccurrences(of: "+", with: " ")
			guard let decoded = spaced.removingPercentEncoding ?? Optional(spaced),
			      decoded.contains("<mxfile") || decoded.contains("<mxGraphModel")
			else { continue }
			// A chunk holding a bare model rather than a whole file — draw.io
			// wrote those before pages existed — is wrapped so everything after
			// this has one shape to read.
			if decoded.contains("<mxfile") { return decoded }
			return "<mxfile><diagram>\(decoded)</diagram></mxfile>"
		}
		return nil
	}

	/// Every `tEXt` and `zTXt` chunk in a PNG, as key and payload.
	static func pngTextChunks(_ data: Data) -> [(String, Data)] {
		let bytes = [UInt8](data)
		guard bytes.count > 8, Array(bytes.prefix(8)) == DiagramStamp.pngSignature else { return [] }
		var found: [(String, Data)] = []
		var at = 8
		while at + 12 <= bytes.count {
			let length = Int(be32(bytes, at: at))
			guard length >= 0, at + 12 + length <= bytes.count else { break }
			let type = String(decoding: bytes[(at + 4)..<(at + 8)], as: UTF8.self)
			let body = Array(bytes[(at + 8)..<(at + 8 + length)])
			if type == "tEXt" || type == "zTXt", let zero = body.firstIndex(of: 0) {
				let key = String(decoding: body[0..<zero], as: UTF8.self)
				if type == "tEXt" {
					found.append((key, Data(body[(zero + 1)...])))
				} else if zero + 2 <= body.count {
					// One compression-method byte, then zlib-deflated text.
					let deflated = Data(body[(zero + 2)...])
					if let out = inflate(deflated, zlibHeader: true) { found.append((key, out)) }
				}
			}
			if type == "IEND" { break }
			at += 12 + length
		}
		return found
	}

	/// The pages of an `<mxfile>`, in the order the file has them.
	///
	/// Scanned rather than parsed with `XMLDocument`, because a `<diagram>`'s
	/// payload is base64 text that a parser would hand back re-wrapped, and
	/// because a document that is half-written must still show its first page.
	public static func pages(in mxfile: String) -> [Page] {
		var found: [Page] = []
		var from = mxfile.startIndex
		while let open = mxfile.range(of: "<diagram", range: from..<mxfile.endIndex) {
			guard let tagEnd = mxfile[open.upperBound...].firstIndex(of: ">") else { break }
			let attributes = String(mxfile[open.upperBound..<tagEnd])
			// `<diagram … />`, a page with nothing on it yet.
			if attributes.hasSuffix("/") {
				found.append(Page(
					name: unescape(Mermaid.attribute("name", in: attributes) ?? ""),
					id: Mermaid.attribute("id", in: attributes) ?? "",
					model: "", wasCompressed: false
				))
				from = mxfile.index(after: tagEnd)
				continue
			}
			let bodyStart = mxfile.index(after: tagEnd)
			guard let close = mxfile.range(of: "</diagram>", range: bodyStart..<mxfile.endIndex)
			else { break }
			let body = String(mxfile[bodyStart..<close.lowerBound])
				.trimmingCharacters(in: .whitespacesAndNewlines)
			let plain = body.hasPrefix("<")
			found.append(Page(
				name: unescape(Mermaid.attribute("name", in: attributes) ?? ""),
				id: Mermaid.attribute("id", in: attributes) ?? "",
				model: plain ? body : (decompress(body) ?? ""),
				wasCompressed: !plain && !body.isEmpty
			))
			from = close.upperBound
		}
		return found
	}

	/// Whether two documents are the same drawing, whatever their text.
	///
	/// **draw.io re-serialises a file the moment it opens it, and the result is
	/// never byte-identical.** Measured, by loading the three fixtures into the
	/// real editor and reading them back, four things differ and not one of them
	/// is something anybody did:
	///
	///  * the indentation, which belongs to whichever serialiser wrote the file;
	///  * **every element's attributes come back in alphabetical order** —
	///    `id parent style value vertex`, `height width x y as` — whatever order
	///    they were written in;
	///  * `<mxGraphModel>` arrives carrying every page setting draw.io has a
	///    default for: `gridSize`, `guides`, `tooltips`, `connect`, `arrows`,
	///    `fold`, `pageScale`, `math`, `shadow`;
	///  * `dx` and `dy` on that element, which are *the size of the window the
	///    diagram is being looked at in* and are written into the document.
	///
	/// Compared as text, therefore, every `.drawio` is edited the instant it is
	/// opened: the tab grows its dot, closing asks whether to save, and auto-save
	/// rewrites a file nobody touched. So the question asked here is about the
	/// *drawing* — the pages, their names and ids, and their models compared as
	/// XML rather than as characters.
	///
	/// **What is deliberately not forgiven.** Every cell must have exactly the
	/// same attributes with exactly the same values, in any order. Only
	/// `<mxGraphModel>` — the page's own settings, and the one element draw.io
	/// fills in — may have a setting on one side and not the other. So moving a
	/// shape, retyping a label, adding a cell or renaming a page is an edit, and
	/// there is no normalisation here that any of them survives.
	public static func isSameDrawing(_ one: String, as other: String) -> Bool {
		guard one != other else { return true }
		let left = pages(in: one), right = pages(in: other)
		guard left.count == right.count else { return false }
		return zip(left, right).allSatisfy {
			$0.name == $1.name && $0.id == $1.id && isSameModel($0.model, $1.model)
		}
	}

	/// The same question about one page's `<mxGraphModel>`.
	static func isSameModel(_ one: String, _ other: String) -> Bool {
		if one == other { return true }
		guard let left = try? XMLDocument(xmlString: one).rootElement(),
		      let right = try? XMLDocument(xmlString: other).rootElement()
		else {
			// A model half-written, or not XML at all: fall back to the text,
			// which errs towards calling it an edit.
			return one == other
		}
		return isSame(left, right)
	}

	private static func isSame(_ one: XMLElement, _ other: XMLElement) -> Bool {
		guard one.name == other.name else { return false }
		let left = named(one), right = named(other)
		if one.name == "mxGraphModel" {
			// The window, not the drawing.
			for (key, value) in left where !["dx", "dy"].contains(key) {
				if let theirs = right[key], theirs != value { return false }
			}
			for (key, value) in right where !["dx", "dy"].contains(key) {
				if let ours = left[key], ours != value { return false }
			}
		} else if left != right {
			return false
		}
		let ours = one.children?.compactMap { $0 as? XMLElement } ?? []
		let theirs = other.children?.compactMap { $0 as? XMLElement } ?? []
		guard ours.count == theirs.count else { return false }
		return zip(ours, theirs).allSatisfy(isSame)
	}

	private static func named(_ element: XMLElement) -> [String: String] {
		var found: [String: String] = [:]
		for attribute in element.attributes ?? [] {
			guard let name = attribute.name else { continue }
			found[name] = attribute.stringValue ?? ""
		}
		return found
	}

	private static func unescape(_ text: String) -> String {
		text.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
			.replacingOccurrences(of: "&amp;", with: "&")
	}

	// MARK: - draw.io's own compression

	/// `Graph.decompress`: base64, raw deflate, and then — the part that is
	/// easy to miss — `decodeURIComponent`.
	///
	/// Skipping the last step gives XML that parses perfectly and has `%20`
	/// wherever a label had a space. It is wrong in a way nothing complains
	/// about, which is why it is written down here and tested.
	public static func decompress(_ payload: String) -> String? {
		let cleaned = payload.filter { !$0.isWhitespace }
		guard let deflated = Data(base64Encoded: cleaned),
		      let inflated = inflate(deflated, zlibHeader: false),
		      let escaped = String(data: inflated, encoding: .utf8)
		else { return nil }
		return escaped.removingPercentEncoding ?? escaped
	}

	/// `Graph.compress`, the other way about.
	public static func compress(_ xml: String) -> String? {
		guard let escaped = xml.addingPercentEncoding(withAllowedCharacters: Self.unreserved),
		      let deflated = deflate(Data(escaped.utf8))
		else { return nil }
		return deflated.base64EncodedString()
	}

	/// Exactly what `encodeURIComponent` leaves alone: the unreserved set plus
	/// `!~*'()`. Anything wider produces a payload draw.io reads back with the
	/// wrong characters in it.
	private static let unreserved: CharacterSet = {
		var set = CharacterSet.alphanumerics
		set.insert(charactersIn: "-_.!~*'()")
		return set
	}()

	// MARK: - Deflate, both ways

	static func inflate(_ data: Data, zlibHeader: Bool) -> Data? {
		// Apple's COMPRESSION_ZLIB is RFC 1951 — raw deflate, no header — which
		// is what `deflateRaw` produces. A zlib stream has two bytes in front of
		// that and four behind, and dropping them is the whole difference.
		var body = data
		if zlibHeader {
			guard data.count > 6 else { return nil }
			body = data.subdata(in: 2..<(data.count - 4))
		}
		return stream(body, operation: COMPRESSION_STREAM_DECODE)
	}

	static func deflate(_ data: Data) -> Data? {
		stream(data, operation: COMPRESSION_STREAM_ENCODE)
	}

	private static func stream(
		_ data: Data, operation: compression_stream_operation
	) -> Data? {
		guard !data.isEmpty else { return Data() }
		let pointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
		defer { pointer.deallocate() }
		guard compression_stream_init(pointer, operation, COMPRESSION_ZLIB)
			== COMPRESSION_STATUS_OK else { return nil }
		defer { compression_stream_destroy(pointer) }

		let chunk = 64 * 1024
		let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
		defer { buffer.deallocate() }

		var out = Data()
		var failed = false
		data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
			guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
			pointer.pointee.src_ptr = base
			pointer.pointee.src_size = data.count
			repeat {
				pointer.pointee.dst_ptr = buffer
				pointer.pointee.dst_size = chunk
				let status = compression_stream_process(pointer, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
				out.append(buffer, count: chunk - pointer.pointee.dst_size)
				if status == COMPRESSION_STATUS_END { return }
				if status != COMPRESSION_STATUS_OK { failed = true; return }
			} while true
		}
		return failed ? nil : out
	}

	private static func be32(_ bytes: [UInt8], at index: Int) -> UInt32 {
		(UInt32(bytes[index]) << 24) | (UInt32(bytes[index + 1]) << 16)
			| (UInt32(bytes[index + 2]) << 8) | UInt32(bytes[index + 3])
	}

	// MARK: - The asset this build does not carry

	/// What draw.io asks for that this build deliberately does not carry.
	///
	/// Both are answered 404 by the editor's scheme handler and written down, so
	/// that a *fourth* thing going missing — which would be a vendoring mistake
	/// rather than a decision — is the difference between a passing test and a
	/// failing one.
	///
	///  * `img/lib/` — 5.9 MB of clipart that `shape=image` cells reference by
	///    path. A diagram using one draws a gap, so `clipartNotice` says so.
	///  * `math4/` — 3.3 MB of MathJax, asked for on every load and used only by
	///    a diagram that typesets LaTeX. One that does draws its formulas as the
	///    text they are written as.
	public static let notCarried = ["img/lib/", "math4/"]

	/// Whether a document draws clipart that is not in this build, and which.
	///
	/// `img/lib/` is 5.9 MB of pictures that `shape=image` cells reference by
	/// path, and it is the one part of draw.io's offline set this app does not
	/// ship. Without this, a diagram using one would draw a gap where a picture
	/// goes and say nothing at all — which is exactly the silent failure 0426
	/// warned about for the stencils, and the answer chosen there was to make it
	/// speak rather than to carry the megabytes.
	public static func missingClipart(in document: Document) -> Int {
		var count = 0
		for page in document.pages {
			var from = page.model.startIndex
			while let found = page.model.range(
				of: "img/lib/", range: from..<page.model.endIndex
			) {
				count += 1
				from = found.upperBound
			}
		}
		return count
	}

	/// Every draw.io shape a page names, whether by `shape=` or by `resIcon=`.
	///
	/// A shape is `mxgraph.<library>.<name>`, and it is either a stencil out of
	/// `stencils.min.js` or a JavaScript shape out of `shapes-14-6-5.min.js`. It
	/// matters that both resolve, because when one does not the cell is drawn as
	/// a plain rectangle and nothing says so — the file still looks like a
	/// diagram, which is what makes it the worst kind of failure.
	public static func shapeNames(in model: String) -> [String] {
		var found: Set<String> = []
		var word = ""
		for character in model + " " {
			if character.isLetter || character.isNumber || character == "." || character == "_"
				|| character == "-" {
				word.append(character)
				continue
			}
			if word.hasPrefix("mxgraph."), word.count > "mxgraph.".count { found.insert(word) }
			word = ""
		}
		return found.sorted()
	}

	// MARK: - Which way round it is drawn

	/// What in a document states a look of its own, or nil when it says nothing.
	///
	/// draw.io has no `!theme` and no front matter: a `.drawio` is an editor's
	/// document, and the one thing in it that is a decision about how the whole
	/// picture is lit is the page's own background — `<mxGraphModel
	/// background="#000000">`, which is what somebody sets in Format ▸ Diagram ▸
	/// Background. Everything else in the file is a colour on a shape, which is
	/// the same as PlantUML's `sequenceArrowColor`: colouring a thing rather than
	/// choosing a light.
	///
	/// It is also exactly the value the renderer already reads — `graph.background`
	/// is this attribute — so the file that has chosen is the file whose own
	/// background is painted, and the two can never disagree.
	public static func statedLook(in document: Document) -> String? {
		for page in document.pages {
			guard let open = page.model.range(of: "<mxGraphModel"),
			      let close = page.model[open.upperBound...].firstIndex(of: ">"),
			      let value = Mermaid.attribute(
			      	"background", in: String(page.model[open.upperBound..<close])
			      )
			else { continue }
			let stated = value.trimmingCharacters(in: .whitespaces)
			guard !stated.isEmpty, stated.lowercased() != "none", stated.lowercased() != "default"
			else { continue }
			return "a page background of \(stated)"
		}
		return nil
	}

	/// The sentence for the above, or nil when nothing is missing.
	public static func clipartNotice(for document: Document) -> String? {
		let count = missingClipart(in: document)
		guard count > 0 else { return nil }
		return count == 1
			? "One shape in this diagram is draw.io clipart, which this build does not carry, "
				+ "so it draws as an empty box."
			: "\(count) shapes in this diagram are draw.io clipart, which this build does not "
				+ "carry, so they draw as empty boxes."
	}
}
