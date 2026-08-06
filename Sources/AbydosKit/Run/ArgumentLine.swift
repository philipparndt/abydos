import Foundation

/// Turning a typed command line into arguments, and back.
///
/// A configuration stores arguments as a list, but nobody wants to edit a list
/// — they want to type what they would have typed in a shell. Splitting that
/// has to respect quotes, or a path with a space in it silently becomes two
/// arguments and the program is handed something that does not exist.
public enum ArgumentLine {
	public static func split(_ line: String) -> [String] {
		var arguments: [String] = []
		var current = ""
		var quote: Character?
		var escaped = false
		var hasContent = false

		for character in line {
			if escaped {
				current.append(character)
				escaped = false
				continue
			}
			if character == "\\" {
				escaped = true
				hasContent = true
				continue
			}
			if let open = quote {
				if character == open {
					quote = nil
				} else {
					current.append(character)
				}
				continue
			}
			if character == "\"" || character == "'" {
				quote = character
				// An empty quoted string is still an argument.
				hasContent = true
				continue
			}
			if character == " " || character == "\t" {
				if hasContent { arguments.append(current) }
				current = ""
				hasContent = false
				continue
			}
			current.append(character)
			hasContent = true
		}
		if hasContent { arguments.append(current) }
		return arguments
	}

	/// The list as somebody would type it, quoting only what needs it.
	public static func join(_ arguments: [String]) -> String {
		arguments.map { argument -> String in
			guard argument.isEmpty || argument.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" })
			else { return argument }
			return "\"" + argument.replacingOccurrences(of: "\"", with: "\\\"") + "\""
		}
		.joined(separator: " ")
	}
}

/// Environment variables as `KEY=value` lines.
///
/// How everybody writes them, and a table with two rows in it would be worse
/// to use than a text box.
public enum EnvironmentLines {
	public static func parse(_ text: String) -> [String: String] {
		var environment: [String: String] = [:]
		for line in text.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			// A blank line is spacing, and `#` is how anybody comments one out.
			guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
			guard let separator = trimmed.firstIndex(of: "=") else { continue }

			let key = String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
			guard !key.isEmpty else { continue }

			var value = String(trimmed[trimmed.index(after: separator)...])
			// Quotes around a value are how a shell keeps its spaces, and are
			// not part of what the program should receive.
			if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
				value = String(value.dropFirst().dropLast())
			}
			environment[key] = value
		}
		return environment
	}

	public static func format(_ environment: [String: String]) -> String {
		environment
			.sorted { $0.key < $1.key }
			.map { "\($0.key)=\($0.value)" }
			.joined(separator: "\n")
	}
}
