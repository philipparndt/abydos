import CoreGraphics

/// How large a drawn control is at a given zoom.
///
/// **Why this is arithmetic and not a constant.** A system bezel takes its size
/// from `controlSize`, which has four values and a largest one: measured on
/// macOS 27, an `NSButton` is 20 points tall at `.small` and 28 at `.large`
/// whatever size the font inside it is. The app's zoom goes to 2.0. So a
/// bezelled control walls out at about 1.4× and then stops growing while its
/// words carry on, which is the fault reported across four panes on
/// 2026-09-01 — the bar grows, the button does not.
///
/// A control that draws itself has no wall, and the numbers it draws to belong
/// here rather than in the view: they are a function of one scale and a
/// measured line height, so they can be asked at all nine zoom steps in a test
/// without a window.
///
/// **The line height is given rather than assumed**, the way `PanelRowSnap` is
/// given the divider thickness. Measuring a font needs AppKit, and the moment
/// this file imports AppKit it stops being testable the way the rest of the kit
/// is. The view measures its own font and hands the number in; this decides
/// what to do with it.
public enum ControlMetrics {
	/// Design-time space above the text and below it, together.
	///
	/// Split evenly, so a control's text sits on its centre line — which is
	/// what makes a row of controls of different heights read as a row.
	public static let verticalPadding: CGFloat = 8
	/// Design-time space at each end of the words.
	public static let horizontalPadding: CGFloat = 10
	/// Design-time corner radius.
	public static let cornerRadius: CGFloat = 5
	/// Design-time side of a square glyph button, before its glyph.
	public static let glyphSide: CGFloat = 20

	/// The height of a control holding one line of text.
	///
	/// Rounded to whole points, like every other dimension that goes through
	/// `Theme.scaled(_:)`, so a border lands on a pixel rather than between
	/// two of them.
	public static func height(lineHeight: CGFloat, scale: CGFloat) -> CGFloat {
		(lineHeight + verticalPadding * scale).rounded()
	}

	/// The width of a control holding text of a known width.
	public static func width(textWidth: CGFloat, scale: CGFloat) -> CGFloat {
		(textWidth + horizontalPadding * 2 * scale).rounded()
	}

	/// The side of a square glyph button.
	public static func glyphSide(scale: CGFloat) -> CGFloat {
		(glyphSide * scale).rounded()
	}

	/// The corner radius at this zoom.
	///
	/// Scaled rather than fixed: a 5-point radius on a 40-point control reads
	/// as the same shape a 5-point radius on a 20-point one does not.
	public static func radius(scale: CGFloat) -> CGFloat {
		(cornerRadius * scale).rounded()
	}

	/// Space between two controls sitting side by side.
	public static func gap(scale: CGFloat) -> CGFloat {
		(6 * scale).rounded()
	}
}

/// How tall a commit row has to be for the two lines it draws.
///
/// **The number it replaces was right once.** The log page's table was built
/// with `rowHeight: Theme.current.scaled(40)`, read at the zoom in force when
/// the table was made and never again. The fonts inside the row are read as it
/// draws, so they grow; the row does not, and at a larger zoom the second line
/// — the short hash under the subject — is clipped by the row's own edge. That
/// is the screenshot: the top third of a hash and nothing else.
///
/// A bigger constant would move the fault rather than remove it. The height is
/// what the content needs, and the content is two measured lines and the
/// padding around them.
public enum CommitRowMetrics {
	/// Design-time space above the subject.
	public static let topPadding: CGFloat = 5
	/// Design-time space between the subject and the line under it.
	public static let lineGap: CGFloat = 2
	/// Design-time space below the second line.
	///
	/// Larger than the top padding on purpose: the graph's dot is drawn on the
	/// row's centre line, and a row padded evenly puts the dot between the two
	/// lines of text rather than beside the subject.
	public static let bottomPadding: CGFloat = 6

	/// The height a row needs for both its lines.
	public static func height(
		subjectLineHeight: CGFloat,
		detailLineHeight: CGFloat,
		scale: CGFloat
	) -> CGFloat {
		let padding = (topPadding + lineGap + bottomPadding) * scale
		return (subjectLineHeight + detailLineHeight + padding).rounded()
	}

	/// Where the second line's baseline box starts, from the top of the row.
	///
	/// Asked for here rather than recomputed in `draw(_:)`, so the row that is
	/// measured and the row that is drawn cannot disagree — which is how the
	/// hash came to be drawn past the bottom of a row that thought it fitted.
	public static func detailTop(subjectLineHeight: CGFloat, scale: CGFloat) -> CGFloat {
		((topPadding + lineGap) * scale + subjectLineHeight).rounded()
	}
}
