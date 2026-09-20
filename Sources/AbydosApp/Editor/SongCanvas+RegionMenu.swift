import AbydosKit
import AppKit

/// What a right-click on a region offers: the block off or on, and the two
/// places it comes from.
///
/// Asked for 2026-09-20: "Context menu would be nice as we can also add other
/// actions there like jumping to the source. currently we auto select the line
/// that calls that function and not the individual code." A click goes to the
/// `play` line and ⌥-click to the pattern, which nobody finds by trying; here
/// both are said. It is also where what is done to a block goes from now on.
extension SongCanvas {
	override func menu(for event: NSEvent) -> NSMenu? {
		guard showsNotes, let (_, region) = region(at: convert(event.locationInWindow, from: nil)) else { return nil }
		return regionMenu(for: region)
	}

	func regionMenu(for region: SongArrangement.Region) -> NSMenu {
		let menu = NSMenu()
		// Every item is the canvas's own and always there to be chosen.
		menu.autoenablesItems = false
		func add(_ title: String, _ action: Selector) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.representedObject = region
			menu.addItem(item)
		}
		add(region.isMuted ? "Unmute Block" : "Mute Block", #selector(toggleRegionMute(_:)))
		menu.addItem(.separator())
		add("Go to Play Line", #selector(revealRegionPlay(_:)))
		if !region.isAudio, region.patternLine != nil {
			add("Go to Pattern “\(region.name)”", #selector(revealRegionPattern(_:)))
		}
		return menu
	}

	@objc private func toggleRegionMute(_ sender: NSMenuItem) {
		guard let region = sender.representedObject as? SongArrangement.Region else { return }
		onToggleRegionMute?(region)
	}

	@objc private func revealRegionPlay(_ sender: NSMenuItem) {
		guard let region = sender.representedObject as? SongArrangement.Region else { return }
		onRegionClicked?(region, false)
	}

	@objc private func revealRegionPattern(_ sender: NSMenuItem) {
		guard let region = sender.representedObject as? SongArrangement.Region else { return }
		onRegionClicked?(region, true)
	}

	/// The menu of the region at fractions of the canvas, and with `choose` the
	/// item whose title begins so chosen: a driven run's right-click.
	func regionMenuForTesting(at x: Double, _ y: Double, choose: String?) -> String {
		guard showsNotes, let (track, region) = region(at: NSPoint(x: bounds.width * x, y: bounds.height * y)) else {
			return "no region"
		}
		let menu = regionMenu(for: region)
		let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
		var said = "\(track.name)/\(region.name)@\(region.line)\(region.isMuted ? " muted" : "") [\(titles.joined(separator: " | "))]"
		if let choose, let index = menu.items.firstIndex(where: { $0.title.hasPrefix(choose) }) {
			menu.performActionForItem(at: index)
			said += " chose=\(menu.items[index].title)"
		}
		return said
	}
}
