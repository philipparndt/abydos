import CoreGraphics
import XCTest
@testable import AbydosKit

/// The sizes a drawn control and a commit row take at each zoom.
///
/// These exist because the numbers they replace were constants that were right
/// at one scale: a bezel that stops growing at about 1.4×, and a commit row
/// built with `scaled(40)` read once. Both faults are invisible at 1.0 and
/// obvious in a room, which is the worst place to find them.
final class ControlMetricsTests: XCTestCase {
	/// Every zoom the app offers, so nothing here is true only at 1× and 2×.
	private let steps: [CGFloat] = [0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

	/// A system font's line height is very nearly proportional to its size, so
	/// a test that wants "the same text at this zoom" scales the measurement
	/// the view would have taken. The proportionality is the view's business;
	/// what is checked here is that the arithmetic does not add anything that
	/// fails to scale with it.
	private func lineHeight(at scale: CGFloat, design: CGFloat = 12) -> CGFloat {
		design * 1.25 * scale
	}

	// MARK: - A control

	/// **The claim the bezel could not make.** A drawn control at 2.0 is twice
	/// the height it is at 1.0, and nothing walls it in on the way.
	func testHeightDoublesWithTheZoom() {
		let single = ControlMetrics.height(lineHeight: lineHeight(at: 1.0), scale: 1.0)
		let double = ControlMetrics.height(lineHeight: lineHeight(at: 2.0), scale: 2.0)
		XCTAssertEqual(double, single * 2, accuracy: 1, "rounding to whole points, and no more")
	}

	func testHeightRisesAtEveryStep() {
		var previous: CGFloat = 0
		for scale in steps {
			let height = ControlMetrics.height(lineHeight: lineHeight(at: scale), scale: scale)
			XCTAssertGreaterThan(height, previous, "the zoom stopped reaching the control at \(scale)")
			previous = height
		}
	}

	/// A control is always taller than the words in it. Stated as its own claim
	/// because the reported fault looks exactly like this one failing: 22-point
	/// words in a 20-point pill.
	func testTextAlwaysFitsInsideTheControl() {
		for scale in steps {
			let text = lineHeight(at: scale)
			XCTAssertGreaterThan(
				ControlMetrics.height(lineHeight: text, scale: scale), text,
				"the words did not fit at \(scale)"
			)
		}
	}

	func testWidthLeavesRoomAtBothEnds() {
		for scale in steps {
			let width = ControlMetrics.width(textWidth: 100, scale: scale)
			XCTAssertEqual(
				width, 100 + ControlMetrics.horizontalPadding * 2 * scale, accuracy: 1
			)
		}
	}

	func testEveryDimensionIsAWholeNumberOfPoints() {
		for scale in steps {
			for value in [
				ControlMetrics.height(lineHeight: lineHeight(at: scale), scale: scale),
				ControlMetrics.width(textWidth: 37.4, scale: scale),
				ControlMetrics.glyphSide(scale: scale),
				ControlMetrics.radius(scale: scale),
				ControlMetrics.gap(scale: scale),
			] {
				XCTAssertEqual(value, value.rounded(), "\(value) at \(scale) is not a whole point")
			}
		}
	}

	// MARK: - A commit row

	/// **The report.** A row is tall enough for both its lines at every step,
	/// which `scaled(40)` was not: it was chosen when the fonts were the size
	/// they are at 1.0 and never asked again.
	func testACommitRowHoldsBothItsLines() {
		for scale in steps {
			let subject = lineHeight(at: scale, design: 12)
			let detail = lineHeight(at: scale, design: 10)
			let height = CommitRowMetrics.height(
				subjectLineHeight: subject, detailLineHeight: detail, scale: scale
			)
			let bottomOfDetail = CommitRowMetrics.detailTop(
				subjectLineHeight: subject, scale: scale
			) + detail
			XCTAssertLessThanOrEqual(
				bottomOfDetail, height,
				"the short hash is clipped by the row at \(scale)"
			)
		}
	}

	/// The old constant, kept as a witness: at 1.0 the derived height is close
	/// to the 40 points that were hand-picked, so this is not a redesign of the
	/// row — it is the same row, asked at every scale instead of one.
	func testTheDerivedHeightAgreesWithTheOldConstantAtOneToOne() {
		let height = CommitRowMetrics.height(
			subjectLineHeight: lineHeight(at: 1.0, design: 12),
			detailLineHeight: lineHeight(at: 1.0, design: 10),
			scale: 1.0
		)
		XCTAssertEqual(height, 40, accuracy: 6)
	}

	func testTheRowGrowsWithTheZoom() {
		var previous: CGFloat = 0
		for scale in steps {
			let height = CommitRowMetrics.height(
				subjectLineHeight: lineHeight(at: scale, design: 12),
				detailLineHeight: lineHeight(at: scale, design: 10),
				scale: scale
			)
			XCTAssertGreaterThan(height, previous, "the row stopped growing at \(scale)")
			previous = height
		}
	}

	/// A row measured for a taller font is taller. Obvious, and worth holding:
	/// the fault being fixed is a height that ignored what it was measuring.
	func testAWiderFontMakesATallerRow() {
		let small = CommitRowMetrics.height(
			subjectLineHeight: 15, detailLineHeight: 13, scale: 1.0
		)
		let large = CommitRowMetrics.height(
			subjectLineHeight: 30, detailLineHeight: 26, scale: 1.0
		)
		XCTAssertGreaterThan(large, small)
	}
}
