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

	/// How many characters of one line this covers, or nothing when it covers
	/// more than one.
	///
	/// For jumping to a place and *showing* it: a symbol is only as wide as its
	/// name where the range stays on a line, and a range that spans lines is a
	/// server being generous about what it points at — the same judgement
	/// `UsageResults` already makes about a selection. Nothing wide is the honest
	/// answer there, and it reads as "a place" rather than as a span (item 533).
	public var widthOnOneLine: Int {
		guard end.line == start.line else { return 0 }
		return max(0, end.character - start.character)
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
	/// The diagnostic exactly as the server sent it, where it came from one.
	///
	/// **Because it has to go back.** Asking what a server offers about a line
	/// carries the diagnostics under it, and a server matches those against its
	/// own — jdtls by the `data` it hung on them, several others by fields this
	/// type has no idea about. A diagnostic rebuilt from the five fields read
	/// here is a different object to the server that sent it, and the quick fix
	/// that would have been offered is not.
	///
	/// Not part of what makes two diagnostics equal: one made in a test and one
	/// read off the wire are the same diagnostic when they say the same thing.
	public var raw: LSPRawJSON?

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
		raw = LSPRawJSON(dictionary)
	}

	/// What to send when this has to travel back to the server it came from.
	///
	/// The original where there is one, and otherwise the fields this type
	/// keeps — which is what a diagnostic invented by the editor amounts to.
	public var json: [String: Any] {
		if let original = raw?.value as? [String: Any] { return original }
		var dictionary: [String: Any] = [
			"range": range.json,
			"severity": severity.rawValue,
			"message": message,
		]
		if let source { dictionary["source"] = source }
		if let code { dictionary["code"] = code }
		return dictionary
	}

	/// Equal when they say the same thing. The bytes a server happened to send
	/// are not part of that.
	public static func == (lhs: LSPDiagnostic, rhs: LSPDiagnostic) -> Bool {
		lhs.range == rhs.range && lhs.severity == rhs.severity && lhs.message == rhs.message
			&& lhs.source == rhs.source && lhs.code == rhs.code
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

/// A symbol a server knows about: a function, a type, a variable.
public struct LSPSymbol: Equatable, Sendable {
	/// What the protocol calls the kinds, which are numbers on the wire.
	public enum Kind: Int, Sendable {
		case file = 1, module, namespace, package, `class`, method, property, field,
		     constructor, `enum`, interface, function, variable, constant, string,
		     number, boolean, array, object, key, null, enumMember, `struct`,
		     event, `operator`, typeParameter

		/// A word for it, for showing beside the name.
		public var label: String {
			switch self {
			case .class: return "class"
			case .struct: return "struct"
			case .enum: return "enum"
			case .interface: return "interface"
			case .function: return "func"
			case .method: return "method"
			case .constructor: return "init"
			case .property, .field: return "property"
			case .variable: return "var"
			case .constant: return "const"
			case .enumMember: return "case"
			case .module, .namespace, .package: return "module"
			case .typeParameter: return "type"
			default: return ""
			}
		}
	}

	public var name: String
	public var kind: Kind
	/// Where it is.
	public var location: LSPLocation
	/// What it belongs to — the type a method is on, usually.
	public var container: String?

	public init(name: String, kind: Kind, location: LSPLocation, container: String? = nil) {
		self.name = name
		self.kind = kind
		self.location = location
		self.container = container
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let name = dictionary["name"] as? String
		else { return nil }

		let kind = (dictionary["kind"] as? Int).flatMap(Kind.init(rawValue:)) ?? .variable

		// Two shapes again: SymbolInformation carries a location, while
		// WorkspaceSymbol may carry only a uri and fill the range in later.
		if let location = LSPLocation(json: dictionary["location"]) {
			self.init(
				name: name, kind: kind, location: location,
				container: dictionary["containerName"] as? String
			)
			return
		}
		guard let uri = (dictionary["location"] as? [String: Any])?["uri"] as? String else { return nil }
		self.init(
			name: name,
			kind: kind,
			location: LSPLocation(
				uri: uri,
				range: LSPRange(
					start: LSPPosition(line: 0, character: 0),
					end: LSPPosition(line: 0, character: 0)
				)
			),
			container: dictionary["containerName"] as? String
		)
	}

	/// Symbols from a reply, flattening the nested `DocumentSymbol` shape.
	///
	/// A document's symbols come back as a tree, and a list of everything in
	/// the file is what a "go to" needs — nesting is for an outline.
	public static func list(from result: Any?, uri: String) -> [LSPSymbol] {
		guard let array = result as? [Any] else { return [] }
		var symbols: [LSPSymbol] = []

		for entry in array {
			guard let dictionary = entry as? [String: Any] else { continue }

			// The nested shape has a selectionRange rather than a location.
			if let range = LSPRange(json: dictionary["selectionRange"])
				?? LSPRange(json: dictionary["range"]),
				dictionary["location"] == nil {
				guard let name = dictionary["name"] as? String else { continue }
				let kind = (dictionary["kind"] as? Int).flatMap(Kind.init(rawValue:)) ?? .variable
				symbols.append(LSPSymbol(
					name: name,
					kind: kind,
					location: LSPLocation(uri: uri, range: range),
					container: dictionary["detail"] as? String
				))
				symbols += list(from: dictionary["children"], uri: uri)
			} else if let symbol = LSPSymbol(json: dictionary) {
				symbols.append(symbol)
			}
		}
		return symbols
	}
}

/// What a server says about the call the caret is inside.
///
/// The answer to "what goes here" for a language whose server has it — driven
/// against sourcekit-lsp, `extruded(height: Double, topEdge: EdgeProfile) -> any
/// Geometry3D` with `activeParameter: 1` and the parameter at characters 25 to 45
/// of that label. Nothing here reformats the signature: the server wrote it, and
/// the offsets it sends index the string it sent.
public struct LSPSignatureHelp: Equatable, Sendable {
	public struct Parameter: Equatable, Sendable {
		/// Where this parameter is in the signature's label.
		///
		/// The protocol allows a parameter to name itself with a *string*
		/// instead, which then has to be found in the label — and finding it
		/// means matching the first occurrence, which for `f(a: Int, b: Int)`
		/// picks the wrong `Int`. Both shapes are read; where the server sent a
		/// string this is the first range that matches it, and nothing at all
		/// if it does not appear.
		public var range: Range<Int>?
		public var documentation: String?

		public init(range: Range<Int>?, documentation: String? = nil) {
			self.range = range
			self.documentation = documentation
		}
	}

	public struct Signature: Equatable, Sendable {
		public var label: String
		public var documentation: String?
		public var parameters: [Parameter]
		/// Which parameter of *this* signature is being filled in, where the
		/// server said so per-signature rather than once for the whole reply.
		public var activeParameter: Int?

		public init(
			label: String,
			documentation: String? = nil,
			parameters: [Parameter] = [],
			activeParameter: Int? = nil
		) {
			self.label = label
			self.documentation = documentation
			self.parameters = parameters
			self.activeParameter = activeParameter
		}
	}

	public var signatures: [Signature]
	public var activeSignature: Int
	public var activeParameter: Int?

	public init(signatures: [Signature], activeSignature: Int = 0, activeParameter: Int? = nil) {
		self.signatures = signatures
		self.activeSignature = activeSignature
		self.activeParameter = activeParameter
	}

	/// The one signature worth drawing, and which of its parameters is being
	/// typed into.
	///
	/// The per-signature `activeParameter` wins over the reply's, which is what
	/// the protocol says and what sourcekit-lsp relies on — it sends several
	/// overloads at once, each with its own active parameter, and nothing at the
	/// top level.
	public var active: (signature: Signature, parameter: Parameter?)? {
		guard signatures.indices.contains(activeSignature) else { return nil }
		let signature = signatures[activeSignature]
		guard let index = signature.activeParameter ?? activeParameter,
		      signature.parameters.indices.contains(index)
		else { return (signature, nil) }
		return (signature, signature.parameters[index])
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let array = dictionary["signatures"] as? [Any]
		else { return nil }

		let signatures: [Signature] = array.compactMap { entry in
			guard let item = entry as? [String: Any],
			      let label = item["label"] as? String
			else { return nil }

			let parameters = (item["parameters"] as? [Any] ?? []).map { parameter -> Parameter in
				let fields = parameter as? [String: Any]
				let documentation = LSPHover.text(from: fields?["documentation"])
				return Parameter(
					range: Self.range(of: fields?["label"], in: label),
					documentation: documentation.isEmpty ? nil : documentation
				)
			}

			let documentation = LSPHover.text(from: item["documentation"])
			return Signature(
				label: label,
				documentation: documentation.isEmpty ? nil : documentation,
				parameters: parameters,
				activeParameter: item["activeParameter"] as? Int
			)
		}

		guard !signatures.isEmpty else { return nil }
		self.init(
			signatures: signatures,
			activeSignature: dictionary["activeSignature"] as? Int ?? 0,
			activeParameter: dictionary["activeParameter"] as? Int
		)
	}

	/// Where a parameter is in the signature, from either shape the protocol
	/// allows.
	static func range(of label: Any?, in signature: String) -> Range<Int>? {
		if let offsets = label as? [Any], offsets.count == 2,
		   let start = offsets[0] as? Int, let end = offsets[1] as? Int, start <= end {
			let length = signature.utf16.count
			guard start <= length else { return nil }
			return start..<min(end, length)
		}
		guard let text = label as? String, !text.isEmpty else { return nil }
		let units = Array(signature.utf16)
		let needle = Array(text.utf16)
		guard needle.count <= units.count else { return nil }
		for start in 0...(units.count - needle.count) where Array(units[start..<(start + needle.count)]) == needle {
			return start..<(start + needle.count)
		}
		return nil
	}
}

/// A completion a server offers.
public struct LSPCompletion: Equatable, Sendable {
	public var label: String
	/// What to insert, which is not always what is shown.
	public var insertText: String
	/// What the typed word should be matched against, which is a third thing
	/// again.
	///
	/// **Neither server driven here labels an item with its name.** openscad-lsp
	/// sends `label: "cube(size, center=false)"` with `filterText: "cube"`, and
	/// sourcekit-lsp sends whole signatures — `withUnsafeCurrentTask(body:
	/// (UnsafeCurrentTask?) throws -> T) rethrows` with `filterText:
	/// "withUnsafeCurrentTask(body:)"`. Matching on the label keeps the items
	/// whose signature happens to start with the typed word and silently drops
	/// the rest, which is why a Swift completion list was so much shorter than
	/// the server's answer.
	public var filterText: String?
	public var detail: String?
	public var documentation: String?
	public var kind: Int?
	/// What the server wants it sorted by, which is rarely alphabetical.
	public var sortText: String?
	/// Whether `insertText` is a snippet rather than plain text.
	///
	/// `insertTextFormat: 2` in the protocol. Ignored, it is the difference
	/// between `union() ` with the caret in the right place and the literal
	/// text `union() $0` in somebody's file.
	public var isSnippet: Bool

	public init(
		label: String,
		insertText: String? = nil,
		filterText: String? = nil,
		detail: String? = nil,
		documentation: String? = nil,
		kind: Int? = nil,
		sortText: String? = nil,
		isSnippet: Bool = false
	) {
		self.isSnippet = isSnippet
		self.label = label
		self.insertText = insertText ?? label
		self.filterText = filterText
		self.detail = detail
		self.documentation = documentation
		self.kind = kind
		self.sortText = sortText
	}

	/// What the typed word is matched against: what the server asked for, or
	/// the label when it asked for nothing.
	public var matchText: String { filterText ?? label }

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let label = dictionary["label"] as? String
		else { return nil }

		// A textEdit says exactly what to put in and wins over insertText,
		// which is a hint the server may not have thought hard about.
		let edit = (dictionary["textEdit"] as? [String: Any])?["newText"] as? String
		// Empty is nothing, not an empty document: the panel beside the list is
		// drawn only where there is something to put in it, and an empty string
		// would open a blank one — which reads as "there is nothing to know
		// about this" rather than as "the server said nothing".
		let documentation = LSPHover.text(from: dictionary["documentation"])
		self.init(
			label: label,
			insertText: edit ?? dictionary["insertText"] as? String ?? label,
			filterText: dictionary["filterText"] as? String,
			detail: dictionary["detail"] as? String,
			documentation: documentation.isEmpty ? nil : documentation,
			kind: dictionary["kind"] as? Int,
			sortText: dictionary["sortText"] as? String,
			isSnippet: (dictionary["insertTextFormat"] as? Int) == 2
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
