import Foundation

/// A position in a document, as the protocol counts.
///
/// Zero-based lines, and characters counted in UTF-16 units — which is what
/// LSP means by "character" unless a server negotiates otherwise. The editor
/// counts the same way, so nothing is converted in between.
public struct LSPPosition: Equatable, Sendable, Codable {
	public var line: Int
	public var character: Int

	public init(line: Int, character: Int) {
		self.line = line
		self.character = character
	}

	public var json: [String: Any] { ["line": line, "character": character] }

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let line = dictionary["line"] as? Int,
		      let character = dictionary["character"] as? Int
		else { return nil }
		self.init(line: line, character: character)
	}
}

public struct LSPRange: Equatable, Sendable, Codable {
	public var start: LSPPosition
	public var end: LSPPosition

	public init(start: LSPPosition, end: LSPPosition) {
		self.start = start
		self.end = end
	}

	public var json: [String: Any] { ["start": start.json, "end": end.json] }

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let start = LSPPosition(json: dictionary["start"]),
		      let end = LSPPosition(json: dictionary["end"])
		else { return nil }
		self.init(start: start, end: end)
	}
}

/// Something a server has to say about a document.
public struct LSPDiagnostic: Equatable, Sendable {
	public enum Severity: Int, Sendable, Comparable {
		case error = 1, warning = 2, information = 3, hint = 4

		public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
	}

	public var range: LSPRange
	public var severity: Severity
	public var message: String
	/// Which tool said so — `swiftc`, `gopls`, a linter behind the server.
	public var source: String?
	public var code: String?

	public init(
		range: LSPRange,
		severity: Severity = .error,
		message: String,
		source: String? = nil,
		code: String? = nil
	) {
		self.range = range
		self.severity = severity
		self.message = message
		self.source = source
		self.code = code
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let range = LSPRange(json: dictionary["range"]),
		      let message = dictionary["message"] as? String
		else { return nil }

		// Missing severity means the server did not say; an error is the
		// assumption that gets looked at rather than ignored.
		let severity = (dictionary["severity"] as? Int).flatMap(Severity.init(rawValue:)) ?? .error
		let code = dictionary["code"].map { value -> String in
			if let text = value as? String { return text }
			if let number = value as? Int { return String(number) }
			return ""
		}

		self.init(
			range: range,
			severity: severity,
			message: message,
			source: dictionary["source"] as? String,
			code: (code?.isEmpty == true) ? nil : code
		)
	}
}

/// Somewhere a symbol is defined, or referenced.
public struct LSPLocation: Equatable, Sendable {
	public var uri: String
	public var range: LSPRange

	public init(uri: String, range: LSPRange) {
		self.uri = uri
		self.range = range
	}

	/// The file it names, if it is a file at all.
	public var url: URL? { URL(string: uri) }

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any] else { return nil }

		// Three shapes mean the same thing: Location, LocationLink, and the
		// LocationLink a server sends when it also knows what was clicked.
		if let uri = dictionary["uri"] as? String, let range = LSPRange(json: dictionary["range"]) {
			self.init(uri: uri, range: range)
			return
		}
		if let uri = dictionary["targetUri"] as? String {
			let range = LSPRange(json: dictionary["targetSelectionRange"])
				?? LSPRange(json: dictionary["targetRange"])
			guard let range else { return nil }
			self.init(uri: uri, range: range)
			return
		}
		return nil
	}

	/// Locations from a `definition` reply, which may be one, many, or none.
	public static func list(from result: Any?) -> [LSPLocation] {
		if let single = LSPLocation(json: result) { return [single] }
		guard let array = result as? [Any] else { return [] }
		return array.compactMap { LSPLocation(json: $0) }
	}
}

/// What a server says about the thing under the pointer.
public struct LSPHover: Equatable, Sendable {
	/// Already flattened to text: servers send markdown, plain strings, arrays
	/// of either, and the old `MarkedString` shape, and the view wants one
	/// string whichever it was.
	public var contents: String
	public var range: LSPRange?

	public init(contents: String, range: LSPRange? = nil) {
		self.contents = contents
		self.range = range
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any] else { return nil }
		let text = Self.text(from: dictionary["contents"])
		guard !text.isEmpty else { return nil }
		self.init(contents: text, range: LSPRange(json: dictionary["range"]))
	}

	static func text(from contents: Any?) -> String {
		switch contents {
		case let string as String:
			return string.trimmingCharacters(in: .whitespacesAndNewlines)
		case let dictionary as [String: Any]:
			// { kind, value } for MarkupContent, { language, value } for the
			// deprecated MarkedString — the value is what is wanted either way.
			return (dictionary["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		case let array as [Any]:
			return array
				.map { text(from: $0) }
				.filter { !$0.isEmpty }
				.joined(separator: "\n\n")
		default:
			return ""
		}
	}
}

/// A completion a server offers.
public struct LSPCompletion: Equatable, Sendable {
	public var label: String
	/// What to insert, which is not always what is shown.
	public var insertText: String
	public var detail: String?
	public var documentation: String?
	public var kind: Int?
	/// What the server wants it sorted by, which is rarely alphabetical.
	public var sortText: String?

	public init(
		label: String,
		insertText: String? = nil,
		detail: String? = nil,
		documentation: String? = nil,
		kind: Int? = nil,
		sortText: String? = nil
	) {
		self.label = label
		self.insertText = insertText ?? label
		self.detail = detail
		self.documentation = documentation
		self.kind = kind
		self.sortText = sortText
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let label = dictionary["label"] as? String
		else { return nil }

		// A textEdit says exactly what to put in and wins over insertText,
		// which is a hint the server may not have thought hard about.
		let edit = (dictionary["textEdit"] as? [String: Any])?["newText"] as? String
		self.init(
			label: label,
			insertText: edit ?? dictionary["insertText"] as? String ?? label,
			detail: dictionary["detail"] as? String,
			documentation: LSPHover.text(from: dictionary["documentation"]),
			kind: dictionary["kind"] as? Int,
			sortText: dictionary["sortText"] as? String
		)
	}

	/// Completions from a reply, which is either a list or a wrapper round one.
	public static func list(from result: Any?) -> [LSPCompletion] {
		if let array = result as? [Any] {
			return array.compactMap { LSPCompletion(json: $0) }
		}
		guard let dictionary = result as? [String: Any],
		      let items = dictionary["items"] as? [Any]
		else { return [] }
		return items.compactMap { LSPCompletion(json: $0) }
	}
}
