import Foundation

/// Where a search's matches are after the text under them was edited.
///
/// **Nothing used to ask.** The matches a find produced were UTF-16 offsets into
/// the text as it was when the search ran, and no edit anywhere re-ran it — so a
/// file searched for a path and then edited to take that path off eight of its
/// ten lines went on drawing eight bands of the old length at the old offsets,
/// sliding across words that matched nothing. Those ranges do not only draw: the
/// view sets a caret from the current one, which is `stepMatch`'s own complaint
/// about "a document that never produced that range", arriving from the same
/// file at a different moment.
///
/// The true answer is to search again, and that is what the editor does — on the
/// debounce it already searches on. This is what the matches are in the meantime:
/// the ones the edit did not touch, moved to where their text now is. Without it
/// the highlights blink off and on for a tenth of a second on every keystroke,
/// which is worse for anybody who types with find open than the bug being fixed.
public enum MatchesAfterEdit {
	/// The matches that survive an edit, and which of them is current.
	///
	/// A match wholly before the edit is untouched, one wholly after it moves by
	/// what the edit added or took away, and one the edit reached into is gone —
	/// its text is not what was matched any more, and guessing at how much of it
	/// survived would be inventing an answer the next search is about to give.
	///
	/// Only `utf16Range` is moved. A match's line and its line's text are stale
	/// the moment anything above it changes, and there is no honest way to
	/// recompute them without the text — which this deliberately does not take,
	/// because the caller has already scheduled the search that will. Nothing
	/// draws from them: the bands are placed from `utf16Range` against the
	/// document's own lines.
	public static func adjusted(
		_ matches: [SearchMatch],
		current: Int?,
		replacing edited: Range<Int>,
		insertedLength: Int
	) -> (matches: [SearchMatch], current: Int?) {
		guard !matches.isEmpty else { return ([], nil) }

		let delta = insertedLength - edited.count
		var kept: [SearchMatch] = []
		kept.reserveCapacity(matches.count)
		/// The new index of the match that was current, once it is known to have
		/// one.
		var stillCurrent: Int?
		/// The first survivor at or after the edit, for when the current match
		/// was the one the edit destroyed: the nearest thing to where the person
		/// is typing.
		var firstAfterEdit: Int?

		for (index, match) in matches.enumerated() {
			var moved = match
			if match.utf16Range.upperBound <= edited.lowerBound {
				// Before the edit: untouched, and the common case while somebody
				// types at the bottom of a file.
			} else if match.utf16Range.lowerBound >= edited.upperBound {
				moved.utf16Range = (match.utf16Range.lowerBound + delta)..<(match.utf16Range.upperBound + delta)
			} else {
				continue
			}

			if index == current { stillCurrent = kept.count }
			if firstAfterEdit == nil, moved.utf16Range.lowerBound >= edited.lowerBound {
				firstAfterEdit = kept.count
			}
			kept.append(moved)
		}

		guard !kept.isEmpty else { return ([], nil) }
		// The one that was current, the nearest one after the edit, or the last
		// one left — in that order, so ⌘G after typing goes on from where the
		// person is rather than back to the top of the file.
		return (kept, stillCurrent ?? firstAfterEdit ?? kept.count - 1)
	}
}
