import Foundation

/// The questions an HTML preview has to answer before a web view is involved.
///
/// Which file a request may be served from, and what in a document points off
/// this machine. Both are pure functions over a string and a path, so both are
/// tested without a window, a web view or a network — which matters more here
/// than usual, because one of them is the thing standing between a document
/// somebody has not read and the rest of their disk.
///
/// What draws the page is `HtmlScheme` and the pane above it.
public enum HtmlPage {
	/// The scheme the previewed document and its neighbours are served under.
	///
	/// A scheme of this app's own rather than `file:`, for `DrawioEditor`'s
	/// reason and one more. A page loaded with `loadHTMLString` has no origin,
	/// so a relative stylesheet resolves against nothing; a page loaded with
	/// `loadFileURL` is the file **on disk**, so an unsaved edit is invisible
	/// and the pane would disagree with the editor beside it on every keystroke.
	/// Served under a scheme, the document is the buffer and its neighbours are
	/// the disk, which is what somebody looking at a split expects.
	///
	/// And it is the only arrangement where a refusal can be counted at all:
	/// every subresource the page asks for arrives at code this app wrote.
	public static let scheme = "abydos-html"
	/// One host for every pane. Which file is being shown is the path, and the
	/// directory it is served from belongs to the handler rather than the URL —
	/// a host carrying a path would be a second way to say the same thing.
	public static let host = "page"

	/// Where the document itself is served, given the file it came from.
	///
	/// Its own name, so that a page which refers to itself — an anchor, an
	/// `iframe`, a stylesheet named after it — resolves the way it does on disk.
	public static func address(of file: URL) -> URL? {
		var parts = URLComponents()
		parts.scheme = scheme
		parts.host = host
		parts.path = "/" + file.lastPathComponent
		return parts.url
	}

	/// Whether a served path is the document itself rather than one of its
	/// neighbours.
	public static func isDocument(path: String, of file: URL) -> Bool {
		let wanted = path.hasPrefix("/") ? String(path.dropFirst()) : path
		// An empty path is the document too: a page asking for `/` has asked for
		// the thing it is, and answering 404 there would leave a pane blank for a
		// reason nobody could see.
		return wanted.isEmpty || wanted == file.lastPathComponent
	}

	// MARK: - What may be served

	/// The file a request names, or nil when it is not under the directory the
	/// document lives in.
	///
	/// **The document's own directory, not the project's root.** A `docs/`
	/// folder's page must reach its own `style.css`, and no page may be a way to
	/// read the rest of a repository by writing `../../` into an `img` tag.
	///
	/// Symlinks are resolved on both sides before the comparison, so a link
	/// planted in the directory cannot point out of it — and so that a document
	/// under `/tmp` is not refused its own neighbours because the directory
	/// resolved to `/private/tmp` and the file did not.
	public static func file(at path: String, under directory: URL) -> URL? {
		let wanted = path.hasPrefix("/") ? String(path.dropFirst()) : path
		guard !wanted.isEmpty else { return nil }
		let root = directory.standardizedFileURL.resolvingSymlinksInPath()
		let candidate = root.appendingPathComponent(wanted)
			.standardizedFileURL.resolvingSymlinksInPath()
		guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
			return nil
		}
		return candidate
	}

	// MARK: - What points off this machine

	/// What a document asks for that this pane will not fetch.
	public struct RemoteReferences: Equatable, Sendable {
		public let count: Int
		/// The first of them, as it is written in the document.
		public let first: String?

		public init(count: Int, first: String?) {
			self.count = count
			self.first = first
		}

		public static let none = RemoteReferences(count: 0, first: nil)

		/// The line the pane says, or nil when there is nothing to say.
		///
		/// A page built on a CDN renders unstyled, and a pane that showed that
		/// without a word would look broken rather than careful. Naming the first
		/// address is what turns "this looks wrong" into "this wanted the
		/// network".
		public var said: String? {
			guard count > 0, let first else { return nil }
			let shown = first.count > 60 ? first.prefix(57) + "…" : first[...]
			return count == 1
				? "1 remote reference was not loaded — \(shown)"
				: "\(count) remote references were not loaded — the first is \(shown)"
		}
	}

	/// The remote addresses written into a document.
	///
	/// **A count of what the file says, not of what WebKit refused.** The
	/// blocking is a content rule list, which drops a request silently, so an
	/// exact tally would mean rewriting every remote URL in the document to this
	/// app's own scheme so that they arrived here to be counted. That buys an
	/// exact number with a page that lies: a script reading its own `src`, or
	/// building a URL from one, would see an address that does not exist. A
	/// number that is honest about being a count of *references written in the
	/// file* is worth more.
	///
	/// So a URL a script builds while the page runs is refused and not counted,
	/// which is the known edge of this. `design.md` says what the honest fix
	/// would be, and it is a report from WebKit rather than a cleverer parse.
	public static func remoteReferences(in source: String) -> RemoteReferences {
		var count = 0
		var first: String?
		for address in fetchedAddresses(in: source) where isRemote(address) {
			count += 1
			if first == nil { first = address }
		}
		return RemoteReferences(count: count, first: first)
	}

	/// Whether an address as written points off this machine.
	///
	/// `//cdn.example.com/x.js` counts: a protocol-relative URL inherits the
	/// page's scheme in a browser, which here would be this app's own, but it is
	/// written to be fetched and reads as remote to anybody looking at the file.
	static func isRemote(_ address: String) -> Bool {
		let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("//") { return true }
		guard let colon = trimmed.firstIndex(of: ":") else { return false }
		// A scheme is letters, digits, `+`, `-` and `.`, and anything else before
		// the colon means this was a path with a colon in it rather than a URL.
		let scheme = trimmed[trimmed.startIndex..<colon].lowercased()
		guard !scheme.isEmpty, scheme.allSatisfy({
			$0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "."
		}) else { return false }
		// The three that are already on this machine. `data:` and `blob:` fetch
		// nothing, and a page's own scheme is served from beside it.
		return !["data", "blob", "about", "javascript", "mailto", "tel", Self.scheme]
			.contains(scheme)
	}

	/// The addresses in a document that a browser would fetch on its own.
	///
	/// **An `<a href>` is not one of them.** Nearly every page links somewhere,
	/// and counting a link as something that failed to load would put a number
	/// on the pane for a page where nothing was refused at all. What is counted
	/// is what the page fetches without being clicked.
	///
	/// A scan rather than a parser: this runs once per render, on a document of
	/// whatever size somebody hand-edits, and a tag soup parser to find two
	/// attribute names would be a great deal of code standing between a
	/// keystroke and a pane.
	static func fetchedAddresses(in source: String) -> [String] {
		var found: [String] = []
		var index = source.startIndex
		while let open = source[index...].firstIndex(of: "<") {
			let afterOpen = source.index(after: open)
			guard afterOpen < source.endIndex else { break }
			// A comment is not a reference. A CDN tag somebody commented out is
			// the likeliest thing in a page to be sitting behind `<!--`, and a
			// pane saying a reference was refused when the document does not ask
			// for one is worse than saying nothing.
			if source[afterOpen...].hasPrefix("!--") {
				guard let end = source.range(of: "-->", range: afterOpen..<source.endIndex) else {
					break
				}
				index = end.upperBound
				continue
			}
			guard let close = source[afterOpen...].firstIndex(of: ">") else { break }
			let tag = source[afterOpen..<close]
			index = source.index(after: close)
			guard let name = tagName(of: tag), fetchingTags.contains(name) else { continue }
			let written = attributes(of: tag)
			for attribute in fetchingAttributes {
				if let value = written[attribute] { found.append(value) }
			}
		}
		return found
	}

	/// The tags that fetch something of their own accord. `a`, `area` and `form`
	/// are missing on purpose: they go somewhere when somebody acts.
	private static let fetchingTags: Set<String> = [
		"link", "script", "img", "iframe", "source", "video", "audio", "embed",
		"object", "track", "input", "image", "use", "base", "frame",
	]

	/// `srcset` is one attribute holding several addresses; the first of them is
	/// enough to say the page wanted the network, and splitting it into four
	/// would say the page wanted it four times.
	private static let fetchingAttributes = ["src", "href", "data", "poster", "srcset"]

	private static func tagName(of tag: Substring) -> String? {
		var name = ""
		for character in tag {
			if character == "/" && name.isEmpty { continue }
			if character.isWhitespace || character == ">" { break }
			name.append(character)
		}
		return name.isEmpty ? nil : name.lowercased()
	}

	/// The attributes written in one tag, by their lowercased names, with their
	/// values in the document's own hand.
	///
	/// One pass over the tag rather than one pass per attribute name, and over
	/// the original rather than a lowercased copy of it: an address is
	/// case-sensitive after its host, and the pane names it as the file does.
	/// The name is compared without case and the value is not touched, which is
	/// exactly the asymmetry HTML itself has.
	///
	/// The first of a repeated attribute wins, which is what a browser does with
	/// a duplicate.
	private static func attributes(of tag: Substring) -> [String: String] {
		var written: [String: String] = [:]
		var index = tag.startIndex
		let end = tag.endIndex
		// Past the tag's own name; what follows is attributes.
		while index < end, !tag[index].isWhitespace { index = tag.index(after: index) }

		func skipWhitespace() {
			while index < end, tag[index].isWhitespace { index = tag.index(after: index) }
		}

		while index < end {
			skipWhitespace()
			guard index < end else { break }
			let nameStart = index
			while index < end, !tag[index].isWhitespace, tag[index] != "=" {
				index = tag.index(after: index)
			}
			let name = tag[nameStart..<index].lowercased()
			skipWhitespace()
			// No `=` at all: a boolean attribute, and the next name starts here.
			guard index < end, tag[index] == "=" else { continue }
			index = tag.index(after: index)
			skipWhitespace()
			guard index < end else { break }
			let quote = tag[index]
			let value: Substring
			if quote == "\"" || quote == "'" {
				let valueStart = tag.index(after: index)
				guard let valueEnd = tag[valueStart...].firstIndex(of: quote) else { break }
				value = tag[valueStart..<valueEnd]
				index = tag.index(after: valueEnd)
			} else {
				let valueStart = index
				while index < end, !tag[index].isWhitespace { index = tag.index(after: index) }
				value = tag[valueStart..<index]
			}
			guard !name.isEmpty, written[name] == nil else { continue }
			written[name] = String(value)
		}
		return written
	}

	// MARK: - What a file is served as

	/// The media type a file's name says it is.
	///
	/// A page is not draw.io's asset folder: it loads fonts, its own modules and
	/// pictures in formats that came along after `DrawioAssetScheme`'s list was
	/// written. A type this does not know is served as bytes, which a browser
	/// treats as a download rather than as content — so anything a page relies
	/// on being *interpreted* has to be named here.
	public static func mediaType(for extension: String) -> String {
		switch `extension`.lowercased() {
		case "html", "htm", "xhtml": return "text/html"
		case "js", "mjs", "cjs": return "application/javascript"
		case "css": return "text/css"
		case "json", "map": return "application/json"
		case "xml", "xsl": return "application/xml"
		case "txt", "text": return "text/plain"
		case "csv": return "text/csv"
		case "svg": return "image/svg+xml"
		case "png": return "image/png"
		case "gif": return "image/gif"
		case "jpg", "jpeg": return "image/jpeg"
		case "webp": return "image/webp"
		case "avif": return "image/avif"
		case "bmp": return "image/bmp"
		case "ico": return "image/x-icon"
		case "woff": return "font/woff"
		case "woff2": return "font/woff2"
		case "ttf": return "font/ttf"
		case "otf": return "font/otf"
		case "mp4", "m4v": return "video/mp4"
		case "webm": return "video/webm"
		case "mp3": return "audio/mpeg"
		case "wav": return "audio/wav"
		case "pdf": return "application/pdf"
		default: return "application/octet-stream"
		}
	}
}
