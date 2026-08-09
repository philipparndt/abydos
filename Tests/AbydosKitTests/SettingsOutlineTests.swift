import Foundation
import Testing
@testable import AbydosKit

/// Folding a settings sidebar that is a flat list underneath.
///
/// The shape the real one has: seven sections, the last of which — Tools — has
/// eight pages under it, which is more than half the list.
struct SettingsOutlineTests {
	private let sidebar = [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]
	private var tools: Int { 6 }

	@Test func showsEverythingWhenNothingIsFolded() {
		#expect(SettingsOutline.visible(depths: sidebar, collapsed: []) == Array(0..<15))
	}

	/// The point of the whole thing: eight rows out of fifteen fold away, and
	/// the row they fold into stays.
	@Test func foldingToolsLeavesTheSevenSections() {
		#expect(SettingsOutline.visible(depths: sidebar, collapsed: [tools]) == Array(0...6))
	}

	/// Only a row with something under it can be folded, and folding a leaf is
	/// not an error — it simply hides nothing.
	@Test func onlyARowWithChildrenHasATriangle() {
		#expect(SettingsOutline.hasChildren(depths: sidebar, at: tools))
		#expect(!SettingsOutline.hasChildren(depths: sidebar, at: 0))
		#expect(!SettingsOutline.hasChildren(depths: sidebar, at: 7))
		// The last row: nothing follows it, so nothing is under it.
		#expect(!SettingsOutline.hasChildren(depths: sidebar, at: 14))
		#expect(SettingsOutline.visible(depths: sidebar, collapsed: [2]) == Array(0..<15))
	}

	/// A child knows which row it folds into, which is how selecting one keeps
	/// its parent open.
	@Test func aChildKnowsWhereItSits() {
		#expect(SettingsOutline.parent(depths: sidebar, of: 9) == tools)
		#expect(SettingsOutline.parent(depths: sidebar, of: tools) == nil)
		#expect(SettingsOutline.ancestors(depths: sidebar, of: 14) == [tools])
		#expect(SettingsOutline.ancestors(depths: sidebar, of: 0).isEmpty)
	}

	/// Deeper than this sidebar goes, since the arithmetic should not care: a
	/// folded row takes everything under it, however far down, and a fold
	/// inside a fold is not counted twice.
	@Test func aFoldTakesEverythingUnderIt() {
		let deep = [0, 1, 2, 2, 1, 0]
		#expect(SettingsOutline.visible(depths: deep, collapsed: [0]) == [0, 5])
		#expect(SettingsOutline.visible(depths: deep, collapsed: [1]) == [0, 1, 4, 5])
		#expect(SettingsOutline.visible(depths: deep, collapsed: [0, 1]) == [0, 5])
		#expect(SettingsOutline.parent(depths: deep, of: 3) == 1)
		#expect(SettingsOutline.ancestors(depths: deep, of: 3) == [0, 1])
	}

	/// Nothing to fold at all, which is what an empty list and a one-row list
	/// both are.
	@Test func holdsUpWithNothingInIt() {
		#expect(SettingsOutline.visible(depths: [], collapsed: []).isEmpty)
		#expect(SettingsOutline.visible(depths: [0], collapsed: [0]) == [0])
		#expect(!SettingsOutline.hasChildren(depths: [], at: 0))
		#expect(SettingsOutline.parent(depths: [0], of: 0) == nil)
	}
}
