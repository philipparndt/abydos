import Foundation

/// A server's prose, reduced to something an editor can draw.
///
/// `LSPHover.text(from:)` unwraps the envelope — `MarkupContent`, an array of
/// them, the deprecated `MarkedString` — and stops there, which is the right
/// place for it to stop: it answers "what did the server say", not "what does
/// that look like". What comes out is markdown, whatever the client claimed it
/// wanted, and openscad-lsp's is markdown with HTML in it. Drawn as it arrives,
/// the panel beside the completion list would show this, verbatim:
///
///     <a href="https://en.wikibooks.org/wiki/File:OpenSCAD_…" class="image"><img
///     src=https://upload.wikimedia.org/…/220px-…jpg width=176.0 height=151.2/></a>
///
/// **Plain text, deliberately, in this first pass.** Attributed runs — the code
/// fences in the editor's own font, the bold headings actually bold — are worth
/// having and are a second thing to get right; the sentence somebody is looking
/// for is the parameter table, and it survives either way. What matters more is
/// that nothing in here can fetch anything: an image is dropped, never loaded,
/// so a completion list cannot reach the network.
public enum ServerDocumentation {
	/// The prose, without the markup.
	public static func readable(_ markdown: String) -> String {
		var lines: [String] = []
		var inFence = false

		for line in markdown.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			// A fence is a marker, not content. What is *inside* one usually is
			// content — openscad-lsp puts `cube(size = [x,y,z], center =
			// true/false);` in one, which is the example somebody wants — so the
			// three backticks go and the code stays.
			if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
				inFence.toggle()
				continue
			}
			if inFence {
				lines.append(line)
				continue
			}

			// A rule between sections is a horizontal line in markdown and a row
			// of hyphens in text, which reads as a mistake rather than a divider.
			if trimmed == "---" || trimmed == "***" || trimmed == "___" {
				lines.append("")
				continue
			}

			lines.append(inline(stripped(trimmed)))
		}

		return collapsed(lines).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// What the prose says about one named parameter, or nothing.
	///
	/// **For the servers with no signature help**, which is where the question
	/// that started this was asked: openscad-lsp advertises no
	/// `signatureHelpProvider` and does not answer the request at all, so the
	/// only thing that knows `size` is a number or a three-value array is the
	/// documentation of the completion that was taken. The stop being filled in
	/// is `${1:size}`, whose default text is `size`, and the prose has a heading
	/// of exactly that.
	///
	/// **Exact, or nothing.** A near match — the first paragraph, the closest
	/// heading — would put a neighbouring parameter's type under the caret, and
	/// a wrong answer here is worse than none because it will be believed.
	///
	/// Read from the markdown rather than from `readable(_:)`'s output, because
	/// a heading is only recognisable while it still has its `**` on.
	public static func description(ofParameter name: String, in markdown: String) -> String? {
		guard !name.isEmpty else { return nil }
		let lines = markdown.components(separatedBy: .newlines)
		guard let start = lines.firstIndex(where: { entry(in: $0)?.name == name }) else { return nil }

		// The inline form carries its description on the same line, after the
		// colon; the heading form has nothing there and the description starts
		// on the next line.
		var collected: [String] = []
		if let rest = entry(in: lines[start])?.rest, !rest.isEmpty {
			collected.append(inline(stripped(rest)))
		}

		for line in lines.dropFirst(start + 1) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			// The next parameter, or an example — either way this one's
			// description has ended.
			if entry(in: line) != nil || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { break }
			if trimmed.isEmpty { continue }
			collected.append(inline(stripped(trimmed)))
		}

		let text = collected
			.filter { !$0.isEmpty }
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return text.isEmpty ? nil : text
	}

	/// A line that names a parameter, and whatever it says about it on the same
	/// line.
	///
	/// **openscad-lsp writes this two ways in the same server**, which is worth
	/// naming because a rule that reads one of them looks right until the second
	/// is tried. `cube` puts each name on a line of its own:
	///
	///     **size**
	///
	///     single value, cube with all sides this length
	///
	/// and `cylinder` puts the name and its description on one line, separated
	/// by a non-breaking space and a colon:
	///
	///     **h** : height of the cylinder or cone
	///
	/// Both are a bold run at the start of a line with either nothing or a colon
	/// after it. **A bold run followed by anything else is not a parameter** —
	/// `**false** (default), 1st (positive) octant` is part of what `center`
	/// takes, and treating it as a new entry would leave `center` with no
	/// description at all.
	static func entry(in line: String) -> (name: String, rest: String)? {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard trimmed.hasPrefix("**") else { return bareHeading(trimmed) }
		let afterOpen = trimmed.dropFirst(2)
		guard let close = afterOpen.range(of: "**") else { return nil }

		let name = String(afterOpen[..<close.lowerBound])
		guard !name.isEmpty, !name.contains("*") else { return nil }

		var rest = String(afterOpen[close.upperBound...]).trimmingCharacters(in: .whitespaces)
		if rest.isEmpty { return (name, "") }
		guard rest.hasPrefix(":") else { return nil }
		rest.removeFirst()
		return (name, rest.trimmingCharacters(in: .whitespaces))
	}

	/// A name on a line by itself with no markup at all, for a server that
	/// writes its documentation that way.
	private static func bareHeading(_ trimmed: String) -> (name: String, rest: String)? {
		guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.hasSuffix(":") else { return nil }
		guard trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }) else {
			return nil
		}
		return (trimmed, "")
	}

	/// Everything between a `<` and its `>` removed.
	///
	/// Tables, anchors and images all go this way and their text is left behind,
	/// which for openscad-lsp's deprecation table is exactly what is wanted: the
	/// cells say `child()` and `children(0)`, and those are the answer.
	///
	/// A `<` with no `>` after it is left alone — `a < b` is prose, and eating
	/// the rest of the line for it would be a worse mistake than leaving one
	/// stray tag in.
	static func stripped(_ line: String) -> String {
		var out = ""
		var depth = 0
		var pending = ""

		for character in line {
			if character == "<" {
				depth += 1
				pending = "<"
				continue
			}
			if character == ">", depth > 0 {
				depth -= 1
				pending = ""
				continue
			}
			if depth > 0 {
				pending.append(character)
				continue
			}
			out.append(character)
		}
		// An unclosed `<` was prose after all, so give back what was swallowed.
		return (out + pending).trimmingCharacters(in: .whitespaces)
	}

	/// The markup that lives inside a line, taken off the words it wraps.
	static func inline(_ line: String) -> String {
		var text = line

		// A link is its text. The address is not readable and not clickable
		// here, and half the links in a wiki page point at pictures.
		text = replacingLinks(in: text)

		// Longest first, or `**bold**` loses one asterisk to the italic rule and
		// keeps the other.
		//
		// **Underscores are left alone on purpose**, though markdown emphasises
		// with them too. A pair of them in this prose is nearly always one
		// identifier — `is_file_revealing_enabled`, `MAX_SIZE` — and turning
		// that into `isfilerevealingenabled` is a worse thing to do to a
		// documentation panel than leaving an underscore where somebody meant
		// italics.
		for marker in ["***", "**", "*", "`"] {
			text = removingPairs(of: marker, in: text)
		}

		// A heading is a line of prose with hashes in front of it.
		while text.hasPrefix("#") { text.removeFirst() }
		return text.trimmingCharacters(in: .whitespaces)
	}

	/// `[text](url)` becomes `text`, and an image `![alt](url)` becomes nothing
	/// at all — an alt text on its own line reads as a caption for a picture
	/// that is not there.
	private static func replacingLinks(in line: String) -> String {
		var out = ""
		var rest = Substring(line)

		while let open = rest.firstIndex(of: "[") {
			let isImage = open > rest.startIndex && rest[rest.index(before: open)] == "!"
			guard let close = rest[open...].firstIndex(of: "]") else { break }
			let after = rest.index(after: close)
			guard after < rest.endIndex, rest[after] == "(",
			      let end = rest[after...].firstIndex(of: ")")
			else {
				// A bracket that is not a link — a `[x, y, z]` vector, which
				// this documentation is full of — stays exactly as written.
				out += rest[..<after]
				rest = rest[after...]
				continue
			}

			let text = rest[rest.index(after: open)..<close]
			out += rest[..<(isImage ? rest.index(before: open) : open)]
			if !isImage { out += text }
			rest = rest[rest.index(after: end)...]
		}

		return out + rest
	}

	/// A marker taken off, but only where it is a pair.
	///
	/// A single `*` in a line of prose is a multiplication sign or somebody's
	/// footnote, and taking it out changes what the line says.
	private static func removingPairs(of marker: String, in line: String) -> String {
		let pieces = line.components(separatedBy: marker)
		guard pieces.count >= 3 else { return line }
		// One fewer marker than there are pieces. An odd count means the last
		// one never closes, so it is prose and keeps its marker; the rest are
		// pairs and go.
		guard (pieces.count - 1) % 2 == 1 else { return pieces.joined() }
		return pieces.dropLast().joined() + marker + (pieces.last ?? "")
	}

	/// Runs of blank lines become one, so a page written with a blank line
	/// between every heading does not arrive as mostly nothing.
	private static func collapsed(_ lines: [String]) -> String {
		var out: [String] = []
		for line in lines {
			if line.isEmpty, out.last?.isEmpty ?? true { continue }
			out.append(line)
		}
		return out.joined(separator: "\n")
	}
}
