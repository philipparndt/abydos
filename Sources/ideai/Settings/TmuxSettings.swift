import AppKit
import IdeaiKit

/// The two tmux switches, and the one rule that ties them together.
///
/// Hiding tmux's status bar only makes sense while the panel's tabs are showing
/// the same window list. So the tick is a *wish* — kept whether or not it can
/// be granted right now — and what actually happens to somebody's tmux is the
/// wish and the tabs switch together. Without that, turning the tabs off and on
/// again would quietly forget that the bar was meant to be hidden.
///
/// Both the settings checkboxes and the test harness come through here, so what
/// is verified is what a click does.
@MainActor
enum TmuxSettings {
	/// Whether the panel's tabs are tmux's windows.
	static var tabsAreTmuxWindows: Bool {
		Settings.shared.strictTmux && Settings.shared.startsTmux
	}

	/// Whether somebody has asked for tmux's own bar to be out of the way.
	static var wantsStatusBarHidden: Bool {
		get { Settings.shared.hidesTmuxStatus }
		set {
			Settings.shared.hidesTmuxStatus = newValue
			apply(announcing: true)
		}
	}

	/// Turns the tabs mode on or off, and takes the status bar with it.
	static func setTabsAreTmuxWindows(_ on: Bool) {
		Settings.shared.strictTmux = on
		apply(announcing: false)
		NotificationCenter.default.post(name: .ideaiSettingsChanged, object: nil)
	}

	/// Whether tmux's bar should be out of the way right now.
	static var shouldHideStatusBar: Bool {
		wantsStatusBarHidden && tabsAreTmuxWindows
	}

	/// Tells the sessions this app is attached to.
	///
	/// A session option rather than a line in somebody's config: nothing is
	/// written to `~/.tmux.conf`, every other session keeps its bar, and so
	/// does every other terminal attached to one of those. It applies the
	/// moment it is set, and the panels do it again whenever they attach.
	static func apply(announcing: Bool) {
		NotificationCenter.default.post(name: .ideaiSettingsChanged, object: nil)
		guard announcing else { return }
		Toast.post(
			shouldHideStatusBar
				? "tmux's status bar is off in this project's session"
				: "tmux's status bar is back",
			detail: "A session option, set as it is attached — nothing was written to "
				+ "~/.tmux.conf, and other sessions keep their bar.",
			kind: .information
		)
	}

	/// Takes out the block an earlier version wrote, once.
	///
	/// That version turned the bar off for the whole server, which took it away
	/// from every session and every other terminal too. This one asks per
	/// session, so the old line is not only unnecessary — it is wrong.
	static func migrateAwayFromConfigEdit() {
		guard TmuxConfig.isStatusHidden() else { return }
		// The backup it made is not offered anywhere: this is taking out a line
		// this app wrote itself, not touching anything the user put there.
		_ = try? TmuxConfig.setStatusHidden(false)
		Settings.shared.hidesTmuxStatus = true
	}
}
