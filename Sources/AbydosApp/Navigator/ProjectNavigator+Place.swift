import AppKit
import AbydosKit

/// Where the tree is scrolled, kept across a rebuild.
///
/// `reloadData()` collapses every row, so for a moment the tree is a handful of
/// rows and the clip view — which cannot scroll past the end of a short
/// document — is pulled to the top. The expansion is then put back and the
/// document is long again, but nothing put the scroll back, so the tree sat at
/// the top. Reported on 2026-09-09 as the project view scrolling up "randomly"
/// while somebody read a session's files: a running session rebuilds the
/// sessions root on every hook event that changes it, and a session taking
/// screenshots does that every few seconds.
///
/// The place is the row at the top of the view and its offset within that row,
/// by the same keys `expandedPaths()` uses, so a row inserted or removed above
/// the reader does not move what they were reading. A pixel offset is the
/// fallback for a top row that is gone, clamped to the new length.
extension ProjectNavigatorViewController {
	struct TreePlace {
		/// The top visible row's key, or nil for a tree with no rows.
		let topKey: String?
		/// How far into that row the top edge of the view was.
		let offsetInRow: CGFloat
		/// The clip view's offset, for when the row is gone.
		let y: CGFloat
	}

	/// Where the tree is scrolled now. Taken beside `expandedPaths()`.
	func rememberPlace() -> TreePlace {
		let y = outlineView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
		let row = outlineView.row(at: NSPoint(x: 1, y: y + 1))
		guard row >= 0, let key = placeKey(for: outlineView.item(atRow: row)) else {
			return TreePlace(topKey: nil, offsetInRow: 0, y: y)
		}
		return TreePlace(topKey: key, offsetInRow: y - outlineView.rect(ofRow: row).minY, y: y)
	}

	/// Puts the tree back where `rememberPlace()` found it. After the expansion
	/// and the selection, because the row has to exist to be scrolled to.
	func restore(place: TreePlace) {
		guard let scroll = outlineView.enclosingScrollView else { return }
		outlineView.layoutSubtreeIfNeeded()
		var target = place.y
		if let key = place.topKey, let row = row(forPlaceKey: key) {
			target = outlineView.rect(ofRow: row).minY + place.offsetInRow
		}
		let clip = scroll.contentView
		let furthest = max(0, outlineView.frame.height - clip.bounds.height)
		clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(0, target), furthest)))
		scroll.reflectScrolledClipView(clip)
	}

	/// The key `expandedPaths()` would give this row, or nil for a row of a
	/// kind that has none.
	func placeKey(for item: Any?) -> String? {
		switch item {
		case let node as FileNode: return node.url.path
		case let node as DependencyNode: return "dep:" + node.identity
		case let node as SessionNode: return "session:" + node.identity
		default: return nil
		}
	}

	private func row(forPlaceKey key: String) -> Int? {
		(0..<outlineView.numberOfRows).first { placeKey(for: outlineView.item(atRow: $0)) == key }
	}

	// MARK: - Driving

	/// The tree's last row, brought into view — how a driven run gets a tree
	/// scrolled without a wheel.
	func scrollToEndForTesting() {
		guard outlineView.numberOfRows > 0 else { return }
		outlineView.scrollRowToVisible(outlineView.numberOfRows - 1)
	}

	/// Where the tree is scrolled, as a line: the offset, the top row, and the
	/// rows in view. Two of these either side of a rebuild are the claim that
	/// the place was kept.
	var scrollReportForTesting: String {
		let place = rememberPlace()
		let visible = outlineView.rows(in: outlineView.visibleRect)
		let top = place.topKey.map { ($0 as NSString).lastPathComponent } ?? "none"
		// The count of session rebuilds beside the place, because two `place`
		// lines that agree prove nothing unless something was rebuilt between
		// them. A run whose event never arrived prints the same two lines as a
		// run whose rebuild kept the place, and only this number tells them
		// apart — which is how the first run of the reported case read as a
		// pass while its tree had not been touched.
		return String(
			format: "y=%.0f top=%@ offset=%.0f rows=%d visible=%d…%d rebuilds=%d",
			place.y, top, place.offsetInRow, outlineView.numberOfRows,
			visible.location, max(visible.location, NSMaxRange(visible) - 1),
			sessionRebuildsForTesting
		)
	}
}
