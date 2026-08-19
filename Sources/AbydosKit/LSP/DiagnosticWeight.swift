import Foundation

/// How loudly a diagnostic is drawn.
///
/// Three roles rather than four severities, because the question the editor
/// asks while drawing is not "how bad is this" but "how sure are we": an error
/// and a warning each have a colour that means *this is wrong*, and everything
/// else is drawn in the weight the editor already uses for something worth
/// knowing and not worth stopping for.
public enum DiagnosticWeight: Equatable, Sendable {
	case error
	case warning
	/// The weight `hint` and `information` are already drawn in.
	case quiet

	/// What a diagnostic is worth while the server that sent it is still
	/// preparing.
	///
	/// **A server that has said it is not ready is not to be believed at full
	/// volume.** Open a Swift package with nothing built and the first thing on
	/// screen is `No such module 'Cadova'` in red on line 1, while the model
	/// builds and renders in the pane beside it — reported as "it shows an error
	/// but works". Measured in 0501: the diagnostic arrives thirteen seconds
	/// after the file opens and is withdrawn a minute later, once eighteen
	/// targets have been prepared.
	///
	/// 0501 decided to explain rather than suppress, and every reason it gave
	/// still holds: the message cannot be matched against — `No such module` is
	/// one compiler's wording in one language — and the batch cannot be held,
	/// because a misplaced brace in the file being edited is real and arrives in
	/// the same one. **This is the axis neither of those is on.** The diagnostic
	/// is present, complete, on its line and in its own words; it is only not
	/// asserted, which is exactly what the app knows while the server says it is
	/// not ready.
	///
	/// A hint stays a hint. Preparing is a reason to be quieter and never a
	/// reason to be louder, and moving `information` up to a warning because a
	/// server was busy would be inventing a claim nobody made.
	public static func weight(
		of severity: LSPDiagnostic.Severity,
		fromPreparingServer isPreparing: Bool
	) -> DiagnosticWeight {
		guard !isPreparing else { return .quiet }
		switch severity {
		case .error: return .error
		case .warning: return .warning
		case .information, .hint: return .quiet
		}
	}
}
