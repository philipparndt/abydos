import AppKit

/// What a double-click on a titlebar does.
///
/// The system decides, in Settings ▸ Desktop & Dock — zoom, minimise, or
/// nothing — and a window that answers with its own idea is a window that
/// behaves differently from every other one on the machine. So the setting is
/// read rather than assumed.
///
/// This exists because the strip across the top of this app's window is a view
/// of its own, drawn where the titlebar would be. A view swallows a
/// double-click, so the gesture did nothing here while doing something in every
/// other window — which reads as the window being stuck rather than as a click
/// going nowhere.
public enum TitlebarDoubleClick {
	/// What the setting says, by its name in the global domain.
	public enum Action: String {
		case zoom = "Maximize"
		case minimise = "Minimize"
		case nothing = "None"
	}

	/// Zoom unless told otherwise: that is the default a Mac ships with, and
	/// an unset key means nobody has changed it.
	public static func action(
		from defaults: UserDefaults = .standard
	) -> Action {
        guard let name = defaults.string(forKey: "AppleActionOnDoubleClick") else { return .zoom }
		return Action(rawValue: name) ?? .zoom
	}

	/// Does to a window what a double-click on its titlebar would.
	@MainActor
	public static func perform(on window: NSWindow?, action: Action? = nil) {
		guard let window else { return }
		switch action ?? self.action() {
		case .zoom:
			// `performZoom` rather than `zoom`: it is what the green button and
			// the titlebar both call, so a window that refuses to zoom refuses
			// here too rather than growing in a way nothing else would.
			window.performZoom(nil)
		case .minimise:
			window.performMiniaturize(nil)
		case .nothing:
			break
		}
	}
}
