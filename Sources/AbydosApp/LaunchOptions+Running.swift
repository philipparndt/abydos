import AppKit
import AbydosKit

/// What a driven run does with the running-sessions list.
///
/// Together rather than six flags scattered through an alphabetical list,
/// because they are used together: a run opens the list, types into its filter,
/// presses keys in it and says which tab it ended on, and reading any one of
/// them alone tells you nothing about the sequence.
extension LaunchOptions {
	struct Running {
		/// Say what the panel's pill counts and its list holds:
		/// `--running-sessions 6,9`.
		var at: [Double] = []
		/// Click the pill, and say what came up: `--running-sessions-menu 6`.
		var menuAt: Double?
		/// Open the same list the way ⇧⌘A does, over the window, and say what
		/// came up and where it sits: `--running-sessions-palette 6`. More than
		/// one time presses the key more than once, which is how "and again
		/// puts it away" is asked: `--running-sessions-palette 4,6`.
		var paletteAt: [Double] = []
		/// Type this into the list's filter once it is open:
		/// `--running-sessions-filter screen`.
		var filter: String?
		/// Keys to press in the open list:
		/// `--running-sessions-keys down+down+up+up`.
		var keys: String?
		/// Choose the first row shown, as ⏎ in the filter does, and say which
		/// tab the panel then has in front: `--running-sessions-choose 7`.
		var chooseAt: Double?
	}
}
