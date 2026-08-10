import Foundation

/// Which way round a diagram is drawn.
///
/// Two, and no more. Every one of the three tools has a much larger vocabulary
/// — PlantUML ships forty-odd `!theme`s, Mermaid has five, draw.io has a
/// stylesheet — and none of that is what this is for. The app has a palette and
/// the palette is light or it is dark, so that is the only question a diagram is
/// asked, and an export is asked the same one.
///
/// The rule this whole type exists to serve is written down in 0429 and is the
/// owner's: **the file wins; the app's theme is the default.** A diagram that
/// states a look of its own has been given it on purpose, and everything here is
/// suppressed for it — which is what `nil` means everywhere a `DiagramTheme?` is
/// taken. Nil is not "either one"; it is "impose nothing at all", and a picture
/// drawn under it is byte for byte the picture this app drew before any of this
/// existed.
public enum DiagramTheme: String, Sendable, CaseIterable {
	case light
	case dark

	public var isDark: Bool { self == .dark }

	/// The paper a diagram of this theme is drawn on.
	///
	/// One colour for all three tools rather than each tool's own, and it is
	/// PlantUML's: `--dark-mode` paints an actual `<rect fill="#1B1B1B">` into
	/// the drawing, which is the one background this app cannot choose. Mermaid
	/// and draw.io are painted *for*, so they are painted the same, and three
	/// diagrams open side by side in one window are on one colour of paper
	/// instead of three.
	///
	/// A hex string rather than a colour, because two of the three places this
	/// is used are inside JavaScript.
	public var paper: String {
		switch self {
		case .light: return "#ffffff"
		case .dark:  return "#1b1b1b"
		}
	}

	/// What to call the other one, for a menu item that offers it.
	public var other: DiagramTheme { self == .light ? .dark : .light }

	/// How it reads in a menu: `PNG (Dark)`.
	public var title: String { self == .light ? "Light" : "Dark" }
}

/// Whether a diagram file states a look of its own, and what to say about it.
///
/// "Does this file state a theme?" is a question about a *language*, so the
/// answer to it lives beside each renderer — `PlantUML.statedLook`,
/// `Mermaid.statedLook`, `Drawio.statedLook` — and each has its own tests. What
/// is here is only the two things they share: the shape of the answer, and the
/// one sentence said about it, so that three tools do not end up saying the same
/// thing three ways.
public enum DiagramLook {
	/// The sentence a pane shows when the file's own look won.
	///
	/// It has to exist, and 0429 says why: somebody whose diagram stays light in
	/// a dark window must be able to see that their own file asked for it, or
	/// they report the bug again. The register is `Drawio.clipartNotice`'s — one
	/// sentence, what the app did, and the words out of their own file that
	/// caused it.
	///
	/// - Parameter stated: the phrase in the file that decided it, quoted back
	///   as they wrote it.
	public static func notice(stated: String) -> String {
		"This diagram sets its own look (\(stated)), so it is drawn that way rather than in "
			+ "the app's theme."
	}

	/// The sentence a pane shows when the file asked for a layout this build has
	/// no engine for.
	///
	/// The same register and the same reason as the one above, for a failure that
	/// is quieter still: Mermaid does not complain about a layout it cannot load,
	/// it draws with its own and says nothing. Somebody who wrote `layout: elk`
	/// and got Mermaid's own layout would otherwise have to guess whether the
	/// app read their file at all.
	public static func layoutNotice(wanted: String) -> String {
		"This diagram asks to be laid out by “\(wanted)”, which is not in this build, so it is "
			+ "drawn with Mermaid's own layout."
	}

	/// The same, for the line a completed export leaves behind.
	public static func exportNotice(for name: String, stated: String) -> String {
		"\(name) sets its own look (\(stated)), so the picture was drawn that way rather than "
			+ "in the theme that was asked for."
	}

	/// The same again, for a document whose diagrams did not all agree.
	///
	/// A Markdown file holds several diagrams and a look is stated one at a time,
	/// so a document can be half in the app's theme and half in its own. That is
	/// the rule working rather than a fault, and it is only obvious to somebody
	/// who is told: asking for Dark and finding `README-2.png` — light, and under
	/// a name with no `-dark` in it — is otherwise a bug report waiting to happen.
	public static func exportNotice(for name: String, chose: Int, of total: Int) -> String {
		"\(chose) of the \(total) diagrams in \(name) set their own look, so those were drawn "
			+ "that way rather than in the theme that was asked for, and their pictures keep the "
			+ "plain name."
	}
}
