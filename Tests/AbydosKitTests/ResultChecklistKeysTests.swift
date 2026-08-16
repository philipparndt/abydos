import AppKit
import Testing
@testable import AbydosKit

/// The keys that tick a result off, and the one that must go on doing nothing.
///
/// The list itself is in `AbydosApp`, which the suite cannot reach, so its
/// evidence is the `--search-steps` and `--usages-steps` transcripts in items
/// 470 and 505. This is the part with an answer that can be wrong on its own,
/// and it is the part that matters: ⌘⌫ moves a file to the trash in the pane
/// next door, so what this rule lets through is the whole of the hazard.
struct ResultChecklistKeysTests {
	private func marksDone(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> Bool {
		ResultChecklistKeys.marksDone(keyCode: keyCode, modifiers: modifiers)
	}

	/// ␣ is what it has always been, and ⌫ now says the same thing — the key
	/// hands coming from IntelliJ press first.
	@Test func spaceAndBackspaceBothMarkDone() {
		#expect(marksDone(ResultChecklistKeys.space))
		#expect(marksDone(ResultChecklistKeys.backspace))
	}

	/// The one this rule exists for. ⌘⌫ trashes the selected file in the project
	/// tree, and the results list is the same list-shaped thing full of file
	/// names — so it is not marking, not unmarking, and not consumed here.
	@Test func commandBackspaceIsNotMarking() {
		#expect(!marksDone(ResultChecklistKeys.backspace, .command))
	}

	/// And the rest of the modifiers with it: only a bare press ticks, so
	/// anything else stays available to whoever wants it later.
	@Test func aModifiedPressIsNeverMarking() {
		for modifier: NSEvent.ModifierFlags in [.command, .option, .control] {
			#expect(!marksDone(ResultChecklistKeys.space, modifier))
			#expect(!marksDone(ResultChecklistKeys.backspace, modifier))
		}
		#expect(!marksDone(ResultChecklistKeys.backspace, [.command, .option]))
	}

	/// ⇧ is not one of the three. A shifted press comes from a selection being
	/// built with ⇧↓ and the thumb still down, and it means the same thing.
	@Test func shiftStillMarks() {
		#expect(marksDone(ResultChecklistKeys.space, .shift))
		#expect(marksDone(ResultChecklistKeys.backspace, .shift))
	}

	/// The keys the list answers itself — ⏎ and ⇥ — are not marking, and neither
	/// is anything else.
	@Test func otherKeysAreNotMarking() {
		for keyCode: UInt16 in [36, 48, 53, 117, 125, 126] {
			#expect(!marksDone(keyCode))
		}
	}
}
