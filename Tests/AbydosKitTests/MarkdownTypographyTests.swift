import Foundation
import Testing
@testable import AbydosKit

/// The proportions a rendered markdown page is set in — the arithmetic half of
/// the preview, which is the half a test can reach. What the page looks like is
/// the driven screenshot's job.
struct MarkdownTypographyTests {
	/// Every size is a ratio of the body, so doubling the body doubles the page.
	@Test func everySizeFollowsTheBody() {
		let one = MarkdownTypography(body: 14)
		let two = MarkdownTypography(body: 28)
		#expect(two.heading(1) == one.heading(1) * 2)
		#expect(two.code == one.code * 2)
		#expect(two.lineHeight == one.lineHeight * 2)
		#expect(two.panelPadding == one.panelPadding * 2)
		#expect(two.pillPaddingX == one.pillPaddingX * 2)
		#expect(two.listIndent == one.listIndent * 2)
		#expect(two.insetX == one.insetX * 2)
	}

	/// GitHub's ratios: the title is twice the body, and the levels step down
	/// to a level six that is smaller than the body.
	@Test func headingsStepDownFromTwiceTheBody() {
		let type = MarkdownTypography(body: 16)
		#expect(type.heading(1) == 32)
		#expect(type.heading(2) == 24)
		#expect(type.heading(3) == 20)
		#expect(type.heading(4) == 16)
		#expect(type.heading(5) == 14)
		#expect(type.heading(6) == 13.6)
		// Past six is six, and nought is one; neither is a crash.
		#expect(type.heading(9) == type.heading(6))
		#expect(type.heading(0) == type.heading(1))
	}

	/// A heading belongs to what follows it.
	@Test func aHeadingHasMoreAboveThanBelow() {
		let type = MarkdownTypography(body: 14)
		#expect(type.headingSpaceAbove > type.headingSpaceBelow)
		#expect(type.lineHeight == 21)
		#expect(type.code < type.body)
	}

	/// Every shipped theme's text clears its floor on the current-line ground,
	/// which is what a code panel in the preview is painted in.
	@Test func everyBundledThemeReadsOnItsCodePanel() {
		let library = SchemeLibrary(personal: nil, logsProblems: false)
		let onPanel = SchemeContrast.appShortfalls(in: library).filter { $0.ground == "currentLineBackground" }
		let list = onPanel.map { "  \($0)" }.joined(separator: "\n")
		#expect(onPanel.isEmpty, Comment(rawValue: "\(onPanel.count) under the floor on the panel:\n\(list)"))
	}
}
