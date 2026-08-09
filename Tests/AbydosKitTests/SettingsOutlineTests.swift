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

	// MARK: - The arrow keys

	private func fold(
		_ key: SettingsOutline.Fold, at selected: Int, collapsed: Set<Int> = [],
		in depths: [Int]? = nil
	) -> SettingsOutline.FoldState {
		SettingsOutline.fold(
			depths: depths ?? sidebar, collapsed: collapsed, selected: selected, key
		)
	}

	/// Right opens what is folded, and stays on the row it opened: what somebody
	/// wanted to see is now under the selection rather than instead of it.
	@Test func rightOpensAFoldedParent() {
		#expect(fold(.open, at: tools, collapsed: [tools])
			== SettingsOutline.FoldState(collapsed: [], selected: tools))
	}

	/// Right again steps inside, onto the first child.
	@Test func rightOnAnOpenParentStepsIntoIt() {
		#expect(fold(.open, at: tools)
			== SettingsOutline.FoldState(collapsed: [], selected: 7))
	}

	/// Right on a leaf is not an error and not a beep-worthy mistake — there is
	/// simply nowhere further in to go.
	@Test func rightOnALeafDoesNothing() {
		#expect(fold(.open, at: 9) == SettingsOutline.FoldState(collapsed: [], selected: 9))
		#expect(fold(.open, at: 0) == SettingsOutline.FoldState(collapsed: [], selected: 0))
	}

	/// Left folds an open parent, and stays on it — the row is still there, and
	/// the eight under it are not.
	@Test func leftFoldsAnOpenParent() {
		#expect(fold(.close, at: tools)
			== SettingsOutline.FoldState(collapsed: [tools], selected: tools))
	}

	/// Left on a child steps out to the row it folds into, which is the other
	/// half of what a triangle does.
	@Test func leftOnAChildStepsOutToItsParent() {
		#expect(fold(.close, at: 11) == SettingsOutline.FoldState(collapsed: [], selected: tools))
	}

	/// Left on a parent that is *already* folded steps out too, rather than
	/// folding what is folded: the row behaves like any other closed thing.
	@Test func leftOnAFoldedParentStepsOut() {
		let deep = [0, 1, 2, 2, 1, 0]
		#expect(fold(.close, at: 1, collapsed: [1], in: deep)
			== SettingsOutline.FoldState(collapsed: [1], selected: 0))
		// And at the top of the list there is nothing to step out to.
		#expect(fold(.close, at: tools, collapsed: [tools])
			== SettingsOutline.FoldState(collapsed: [tools], selected: tools))
		#expect(fold(.close, at: 0) == SettingsOutline.FoldState(collapsed: [], selected: 0))
	}

	/// Right then Left, and the list is where it started — which is the property
	/// somebody's hands rely on when they are looking for a page.
	@Test func rightThenLeftComesBack() {
		let opened = fold(.open, at: tools, collapsed: [tools])
		let closed = SettingsOutline.fold(
			depths: sidebar, collapsed: opened.collapsed, selected: opened.selected, .close
		)
		#expect(closed == SettingsOutline.FoldState(collapsed: [tools], selected: tools))
	}

	/// A row that is not in the list at all — an empty sidebar, or an index left
	/// over from a shorter one — is left alone.
	@Test func anArrowOnNothingIsNotACrash() {
		#expect(fold(.open, at: 99) == SettingsOutline.FoldState(collapsed: [], selected: 99))
		#expect(SettingsOutline.fold(depths: [], collapsed: [], selected: 0, .close)
			== SettingsOutline.FoldState(collapsed: [], selected: 0))
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
