import Foundation

/// What a diagram is written out as, whichever tool drew it.
///
/// Two formats and no more, because they are the two a menu can offer without
/// becoming a dialogue: SVG for anything that will be looked at or scaled, PNG
/// for anything that has to be pasted into something that cannot read a
/// drawing.
///
/// One type across PlantUML and Mermaid rather than one each. The menus are the
/// same menu — `Export ▸ PNG`, `Export ▸ SVG`, in the preview and in the tree —
/// and two enumerations behind them would eventually be two menus.
public enum DiagramFormat: String, Sendable, CaseIterable {
	case png
	case svg
}

/// What PlantUML says is wrong with a diagram.
///
/// It never fails on one: a diagram it cannot parse comes back as a *picture of
/// the complaint*, in the format that was asked for, with the ordinary exit
/// status on the HTTP route and a 400 on the other. That is exactly right for a
/// preview — the picture names the line — and exactly wrong for an export,
/// which would write `diagram.png`, report success, and leave somebody with a
/// picture of an error message in their repository.
///
/// So both routes are asked for the complaint rather than only for the picture,
/// and both have one: the server puts it in headers of its own, and `-pipe`
/// prints it on standard error and exits 200.
public struct DiagramFault: Equatable, Sendable {
	/// PlantUML's own sentence: "Syntax Error? (Assumed diagram type: sequence)".
	public let message: String
	/// Which line it is about, counting from one, when PlantUML said.
	public let line: Int?

	public init(message: String, line: Int?) {
		self.message = message
		self.line = line
	}

	/// From the server's headers, which are the same two on both formats.
	///
	/// The line is one-based there — measured against the image, not assumed.
	public init?(errorHeader: String?, lineHeader: String?) {
		guard let errorHeader, !errorHeader.isEmpty else { return nil }
		self.message = errorHeader
		self.line = lineHeader.flatMap(Int.init)
	}

	/// From what `-pipe` printed on standard error.
	///
	/// Three lines, after whatever the JVM had to say for itself first:
	///
	///     ERROR
	///     4
	///     Syntax Error? (Assumed diagram type: sequence)
	///
	/// The number is the offending line counted from *zero*, which the server's
	/// header for the same diagram reports as five. Measured on two diagrams
	/// rather than assumed, and it is added to here so that one export reports
	/// one line number whichever route drew it.
	public init?(standardError: String) {
		let lines = standardError
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
		guard let marker = lines.firstIndex(of: "ERROR") else { return nil }
		let rest = lines[(marker + 1)...].filter { !$0.isEmpty }
		guard !rest.isEmpty else { return nil }
		if let counted = Int(rest[rest.startIndex]) {
			self.line = counted + 1
			let said = rest.dropFirst().joined(separator: " ")
			self.message = said.isEmpty ? "PlantUML could not parse the diagram." : said
		} else {
			self.line = nil
			self.message = rest.joined(separator: " ")
		}
	}

	/// The one sentence somebody needs: which file, which line, what is wrong.
	///
	/// - Parameter offset: how many lines above this diagram's `@start` the file
	///   begins — nothing for a file with one diagram in it, and the block's
	///   place in the file when there are several, since PlantUML counts from
	///   the start of what it was given.
	public func sentence(for name: String, offset: Int = 0) -> String {
		guard let line else {
			return "\(name) could not be drawn: \(message)"
		}
		return "\(name) line \(line + offset): \(message)"
	}
}
