import Foundation

/// What a double-click on the empty part of the editor's tab strip does.
///
/// The gesture was one hard-wired line — a new scratch in the project, "the way
/// it does in the editors people arrive from" — and that is what one family of
/// editors does. In the other the same gesture maximises the editor, which the
/// strip already offers as a button and which the maintainer reaches for. Both
/// are reasonable and the strip has room for one, so it is a setting, asked for
/// on 2026-09-10, with expanding as the default and the two scratches as the
/// other values.
///
/// Stored as its raw value. A value from a build that had more or fewer of
/// these reads as the default rather than as nothing, which is what
/// `Settings.tabStripDoubleClick` does with an unknown string.
public enum TabStripDoubleClick: String, CaseIterable, Sendable {
	/// Expand the editor over the panels around it, or give them back —
	/// what the strip's maximise button does.
	case maximize
	/// A new scratch file in the project's scratch directory — what the
	/// strip did before this was a setting.
	case localScratch
	/// A new scratch file in the global scratch directory.
	case globalScratch

	public static let `default`: TabStripDoubleClick = .maximize

	/// What the settings page calls it: the thing it does, not its identifier.
	public var label: String {
		switch self {
		case .maximize:      return "Expand or collapse the editor"
		case .localScratch:  return "New scratch file in this project"
		case .globalScratch: return "New global scratch file"
		}
	}
}
