import AppKit
import AbydosKit

/// The strip across the top of the window: the project capsule, the three pills
/// beside it, the backdrop they sit on and the seam under it.
///
/// It is the window's `NSToolbarDelegate` — a toolbar's delegate may be any
/// object, so this one is set on the toolbar directly rather than the window
/// controller conforming and forwarding.
///
/// It owns the views and what they say. It does not own the decisions: pressing
/// the project half opens the switcher, choosing a worktree opens a project,
/// leaving a subproject rescopes the window — all of which are the window's, and
/// all of which arrive here as closures. That is the line, and it is why this
/// object has no reference to a `MainWindowController`.
///
/// The run control is the exception, and deliberately so. It sits in this
/// toolbar but everything it does belongs to running; the window builds that one
/// item and hands it over, until there is a run coordinator to build it instead.
@MainActor
final class TitlebarController: NSObject, NSToolbarDelegate {
	// What the window knows and this object asks for.
	var project: () -> Project? = { nil }
	var subprojectRoot: () -> URL? = { nil }
	var branchRead: () -> Task<GitRepository.Head?, Never>? = { nil }
	var devContainerRoot: () -> URL? = { nil }
	var devContainerChoices: () -> [DevContainerFile.Choice] = { [] }
	var choiceCarriedBy: (Any?) -> DevContainerFile.Choice? = { _ in nil }
	var scopeRoot: () -> URL? = { nil }
	/// How a container is named and marked, which the window says too.
	var containerName: (DevContainerFile.Choice?, URL) -> String = { _, _ in "" }
	var containerMark = "⬢"
	var containerTerminalTitle = "New Terminal in Container"

	// The one item that is not this object's to build.
	var makeRunItem: (NSToolbarItem.Identifier) -> NSToolbarItem? = { _ in nil }
	var relayoutRunControl: () -> Void = {}

	// What pressing something here means, which is the window's business.
	var onProjectPressed: () -> Void = {}
	var onBranchPressed: () -> Void = {}
	var onLeaveSubproject: () -> Void = {}
	var onOpenSubproject: (URL) -> Void = { _ in }
	var onOpenWorktree: (URL) -> Void = { _ in }
	var onShowAllWorktrees: () -> Void = {}
	var onOpenFile: (URL) -> Void = { _ in }

	/// Where the pills are put.
	private weak var hostWindow: NSWindow?

	init(window: NSWindow?) {
		self.hostWindow = window
		super.init()
	}

	var window: NSWindow? { hostWindow }

	/// A menu row whose action belongs to the window rather than to this object.
	@objc private func showAllWorktrees(_ sender: Any?) { onShowAllWorktrees() }
	@objc private func switchProjectItem(_ sender: Any?) { onProjectPressed() }

	/// The capsule itself, for the popovers the window anchors to it.
	var capsuleView: TitlebarCapsule? { capsule }

	/// The branch the capsule is showing, and whether it is still being read.
	func setBranch(_ name: String?, isUnborn: Bool) {
		capsule?.isReadingBranch = false
		capsule?.setBranch(name, isUnborn: isUnborn)
		layoutTitlebarPills()
	}

	var isReadingBranch: Bool {
		get { capsule?.isReadingBranch ?? false }
		set { capsule?.isReadingBranch = newValue }
	}

	func setProjectName(_ name: String) { capsule?.setProject(name: name) }

	func setSubprojectPath(_ relative: String?) { subprojectPill?.setSubproject(relative) }

	/// Re-measures the pills; the window calls this when the theme or zoom moves.
	func relayout() { layoutTitlebarPills() }

	/// The height of the strip, measured by the window and pushed down here.
	func setInset(_ inset: CGFloat) {
		titlebarBackdropHeight?.constant = inset
		if let backdrop = titlebarBackdrop {
			backdrop.superview?.addSubview(backdrop, positioned: .above, relativeTo: nil)
		}
	}

	func buildBackdrop() { buildTitlebarBackdrop() }

	func setRunState(_ state: TitlebarSeam.State) { setTitlebarRunState(state) }

	func refreshDevContainer() { refreshDevContainerPill() }

	func readWorktrees() { readWorktree() }

	/// Forgets the checkouts, for a window being pointed at another project.
	func clearWorktrees() {
		worktrees = []
		worktreePill?.setWorktree(nil)
	}

	private var titlebarBackdrop: ColoredView?

	private var titlebarBackdropHeight: NSLayoutConstraint?

	private var titlebarSeam: TitlebarSeam?

	private var capsule: TitlebarCapsule!

	private var subprojectPill: SubprojectPillButton!

	private var worktreePill: WorktreePillButton!

	private var devContainerPill: DevContainerPillButton!

	/// Every checkout of this repository, most recently worked on first, as the
	/// worktree pill's menu will offer them.
	///
	/// Kept rather than asked for when the menu opens: `readWorktree` has already
	/// run git for the pill itself, so a second listing at the moment somebody
	/// clicks would be the same answer bought again with a pause in front of it.
	private var worktrees: [GitWorktree] = []

	/// The strip the toolbar sits on.
	///
	/// The window is `fullSizeContentView`, so the area behind the titlebar is
	/// ours to paint; with a transparent titlebar this is what shows there.
	private func buildTitlebarBackdrop() {
		guard let contentView = window?.contentView else { return }
		// Always drawn, so the titlebar is one strip across the whole window:
		// the panes below run up behind it and their edges would otherwise
		// show through, with the sidebar's colour meeting the editor's part
		// way along a row that belongs to neither.
		let backdrop = ColoredView(color: Theme.current.windowBackground)
		backdrop.actsAsTitlebar = true
		backdrop.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(backdrop, positioned: .above, relativeTo: nil)

		let height = backdrop.heightAnchor.constraint(equalToConstant: 0)
		NSLayoutConstraint.activate([
			backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
			backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			height,
		])
		titlebarBackdrop = backdrop
		titlebarBackdropHeight = height

		// The line along the bottom of the strip, which is both the boundary
		// under the titlebar and the only thing in the window that says a run is
		// happening.
		let seam = TitlebarSeam()
		seam.translatesAutoresizingMaskIntoConstraints = false
		backdrop.addSubview(seam)
		NSLayoutConstraint.activate([
			seam.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
			seam.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
			seam.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
			seam.heightAnchor.constraint(equalToConstant: TitlebarSeam.height),
		])
		titlebarSeam = seam
	}

	/// Says what the run is doing, on the line under the titlebar.
	private func setTitlebarRunState(_ state: TitlebarSeam.State) {
		guard let backdrop = titlebarBackdrop else { return }
		// Everything added since sits above it, so it is raised each time
		// rather than once.
		backdrop.superview?.addSubview(backdrop, positioned: .above, relativeTo: nil)
		titlebarSeam?.set(state)
	}

	/// Re-measures the pills after their content changes, so the toolbar item
	/// grows to fit a longer project name or a branch that arrived late.
	private func layoutTitlebarPills() {
		// The height is a constraint rather than an intrinsic size, because that
		// is the only part of a toolbar item's size the toolbar reads, so the
		// zoom has to be pushed into it by hand.
		capsule?.updateHeight()
		capsule?.invalidateIntrinsicContentSize()
		subprojectPill?.invalidateIntrinsicContentSize()
		worktreePill?.invalidateIntrinsicContentSize()
		devContainerPill?.invalidateIntrinsicContentSize()
		// The run strip measures itself from the theme's scale, so it has to be
		// asked again — otherwise zooming the window leaves the one control
		// that is always on screen at the old size.
		relayoutRunControl()
		// The symbol carries its colour and its size in the image, so a zoom or
		// a theme change has to make it again — the same reason the navigator's
		// header buttons are remade in `restyle`.
		refreshMaximizeButton()

	}

	/// Names the window after the repository, and fills the pill that says which
	/// of its checkouts this is.
	///
	/// A linked worktree is another checkout of the same project, so
	/// `ideai/.claude/worktrees/titlebar-capsule` is still ideai — naming it
	/// after its folder would name the checkout and lose the project. The pill
	/// beside the name says which checkout it is, and opens the list of them.
	///
	/// **The whole list is kept, and 0490 is why.** This asked git for every
	/// checkout, found the one containing this window and threw the rest away, so
	/// the titlebar could say which worktree it was on and offer no way to any
	/// other — and on the primary it said nothing at all, because "primary" was
	/// read as "nothing to say". That is the report: `~/dev/abydos` showed
	/// `abydos | main` and no sign that fifty other checkouts existed.
	///
	/// Asked of git rather than read off the path: a worktree can be created
	/// anywhere, including outside the repository it belongs to.
	private func readWorktree() {
		guard let project = project() else { return }
		let root = project.root

		Task { @MainActor [weak self] in
			let listed = await GitWorktrees.list(in: root)
			// Another project may have been opened while git was answering.
			guard let self, self.project()?.root == root else { return }

			// The window may be opened at the worktree itself or somewhere
			// inside it, so the deepest one containing this root is the one.
			//
			// Deepest matters more than it looks here: an agent harness puts its
			// checkouts under `<the primary>/.claude/worktrees/`, so the primary
			// contains them by path and a shallower match would name every one of
			// those windows after the wrong checkout.
			let containing = listed
				.filter { root.path == $0.path.path || root.path.hasPrefix($0.path.path + "/") }
				.max { $0.path.path.count < $1.path.path.count }

			// Ordered once, here, so the menu is not sorting seventy-four entries
			// in front of somebody who has just clicked. Most recently worked on
			// first, from mtimes rather than from git — the same estimate, and the
			// same reasoning, the project switcher's scan uses.
			self.worktrees = GitWorktrees.byRecentActivity(listed)

			if let primary = listed.first(where: { $0.isPrimary }), containing?.isPrimary == false {
				self.capsule?.setProject(name: primary.name)
			}

			// One checkout is not a choice, and a repository nobody has added a
			// worktree to should not carry a control explaining that it has one.
			let primaryName = listed.first { $0.isPrimary }?.name ?? root.lastPathComponent
			self.worktreePill?.setWorktree(
				listed.count > 1 ? containing.map {
					// The words are whatever the capsule beside it has not
					// already said — which on the primary, and on a worktree
					// named after the branch showing a foot to the left, is
					// nothing at all.
					WorktreePillButton.State(
						name: GitWorktrees.qualifier(for: $0, primaryName: primaryName),
						full: $0.name,
						isPrimary: $0.isPrimary
					)
				} : nil,
				count: listed.count
			)
			self.layoutTitlebarPills()
		}
	}

	/// One entry offering a shell in one container, or the grey generic one.
	///
	/// The choice travels on the item, because with several of them the title is
	/// not enough to act on — what is clicked has to name the file it meant, or
	/// the second entry would open the first entry's container.
	/// One entry offering a shell in one container, built by the window because
	/// opening a terminal in a container is the window's to do.
	var containerMenuItem: (DevContainerFile.Choice?) -> NSMenuItem = { _ in NSMenuItem() }

	/// The container the pill is naming, so its menu acts on exactly what the
	/// words on it say rather than on whichever container is preferred.
	private var pilledContainer: DevContainerFile.Choice?

	private var maximizeButton: NSButton?

	/// Whether the editor has the window, which decides which way the arrows go.
	var isEditorMaximized: () -> Bool = { false }
	/// Pressing it is the window's gesture; this only draws it.
	var onToggleEditorMaximized: () -> Void = {}

	/// Two arrows apart to take the window, two arrows together to give it back.
	///
	/// The icon *is* the state. A button that looked the same either way would
	/// leave somebody in a maximised window with no way of knowing that the
	/// thing they were looking for was the same button they had just pressed —
	/// which is what a maximised editor with no visible way out amounts to.
	func refreshMaximizeButton() {
		let symbol = isEditorMaximized()
			? "arrow.down.right.and.arrow.up.left"
			: "arrow.up.left.and.arrow.down.right"
		maximizeButton?.image = Theme.symbol(
			symbol, size: Theme.current.scaled(12),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		maximizeButton?.toolTip = isEditorMaximized()
			? "Give the tree and the terminal back"
			: "Give the editor the whole window"
	}

	@objc private func pressedMaximize(_ sender: Any?) { onToggleEditorMaximized() }

	/// Says in the titlebar which devcontainer this project is being worked on
	/// inside — or, dimmed, which one it has and is not using.
	///
	/// **Two states rather than one, which is 0438's third fault.** 0433 made this
	/// pill say *running*, and took it away for both declines; the way back out of
	/// a decline lives in this pill's menu, so the gesture that most needed
	/// undoing was the one that removed its own undo. The strip above a file
	/// carries a button too, but only over a file whose server is missing, so
	/// somebody who declined and then worked on something else had nothing on
	/// screen at all — which is how it was reported: gone for good.
	///
	/// So the pill is now about the `devcontainer.json`, which is what
	/// `hasDevContainer` has always been about, and its two states are the
	/// difference 0433 was right to insist on. Lit with the `⬢`: this project's
	/// tools are in that container. Dimmed without it: there is one and they are
	/// not. It never claims a container is in use when it is not, which was the
	/// whole of the old rule.
	private func refreshDevContainerPill() {
		guard let pill = devContainerPill else { return }
		guard let root = devContainerRoot() else {
			pilledContainer = nil
			pill.setContainer(nil)
			pill.toolTip = nil
			layoutTitlebarPills()
			return
		}
		let choices = devContainerChoices()
		let consent = LanguageService.shared.devContainerConsent(for: root)
		Task { @MainActor in
			// Only a project that said yes has its tools in there. A container left
			// running with somebody's shell in it, under a project whose servers
			// were put on this machine, is a container this project is not using.
			let running = consent == .container
				? await DevContainers.shared.existingSessions(for: root)
				: []
			// Still the same project by the time the actor answered: a window that
			// switched project meanwhile must not be labelled with the old one's.
			guard self.devContainerRoot() == root else { return }
			// **The one this project's tools belong in, not the first one that is
			// up.** A project may have two containers running at once — the one it
			// was switched away from is deliberately left going, because somebody's
			// shell may be in it — so "whichever sorts first" would leave the pill
			// naming the container the project moved *off*, which is what it did
			// until it was watched doing it. What the project's servers are in is
			// what was written down, and this lights only once that one is really up.
			//
			// Named from the menu's own choices, so the pill, the tab in the same
			// container and the menu item that opens one cannot come to disagree
			// about what it is called.
			let wanted = LanguageService.shared.containerChoice(for: root)
			let inUse = wanted.flatMap { choice in
				running.contains {
					FilePath.canonical($0.configuration.file) == FilePath.canonical(choice.file)
				} ? choice : nil
			}
			self.pilledContainer = inUse ?? wanted ?? choices.first
			let name = containerName(self.pilledContainer, root)
			pill.setContainer(containerMark, inUse: inUse != nil)
			// **The tool tip carries the name in both states now**, because the pill
			// no longer does — 0444's part 3. It said nothing at all while a
			// container was in use, which was right when the name was written across
			// the titlebar and is not right now that hovering is one of the two
			// places the name is.
			// Green once this project's servers are answering, and the tool tip
			// says so in words — a colour on its own is a thing to learn, and
			// somebody hovering to find out what it means should be told.
			let readiness = LanguageService.shared.readiness(project: root)
			pill.setLanguageReady(readiness == .ready)

			let state = inUse != nil
				? DevContainerConsent.pillInUse(container: name)
				: self.devContainerStateSentence(for: root, container: name, consent: consent)
			pill.toolTip = [state, Self.languageSentence(for: readiness)]
				.compactMap { $0 }
				.joined(separator: "\n")
			self.layoutTitlebarPills()
		}
	}

	/// What state a container that is not in use is in, in one sentence.
	///
	/// **"It is starting" is only true while it is.** The answer stays on file
	/// when a start fails — somebody did say yes and has not changed their mind —
	/// so the consent alone cannot tell the gap between the answer and the
	/// container from a container that will never arrive, and the pill said
	/// "starting" for the rest of the session. Seen while watching a
	/// `postCreateCommand` fail in the pane 0444's part 4 added.
	private func devContainerStateSentence(
		for root: URL, container: String, consent: DevContainerConsent?
	) -> String {
		if consent == .container, LanguageService.shared.devContainerFailedToStart(for: root) {
			return DevContainerConsent.pillCouldNotStart(container: container)
		}
		return DevContainerConsent.pillState(consent, container: container)
	}

	@objc fileprivate func showDevContainerMenuItem(_ sender: Any?) { showDevContainerMenu() }

	/// What the pill offers: the file it came from, and the way out of it.
	///
	/// **Not a rebuild.** Throwing the image away and building it again is a real
	/// gesture and it is not here: nothing in this app removes an image yet, and
	/// a "Rebuild" that only restarted the container would be a button that looks
	/// like it did the expensive thing and did not.
	@objc func showDevContainerMenu() {
		guard devContainerPill?.hasContainer == true else { return }
		let anchor: NSView? = devContainerPill ?? capsule
		devContainerPillMenu().popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: (anchor?.bounds.maxY ?? 0) + Theme.current.scaled(4)),
			in: anchor
		)
	}

	/// The menu itself, built rather than shown, so that what it offers can be
	/// read by something other than an eye.
	func devContainerPillMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		guard let root = devContainerRoot() else { return menu }

		let inUse = devContainerPill?.isInUse == true
		let container = containerName(pilledContainer, root)

		// **The state line is in both states now**, which 0444's part 3 makes
		// necessary rather than merely tidy: the pill has stopped saying the
		// container's name, so this menu and the tool tip are the two places it is
		// said, and a menu that dropped out of a pill saying nothing but `⬢` and
		// then said nothing itself would leave a project of ten subprojects unable
		// to say which container it means.
		let state = NSMenuItem(
			title: inUse
				? DevContainerConsent.pillInUse(container: container)
				: devContainerStateSentence(
					for: root,
					container: container,
					consent: LanguageService.shared.devContainerConsent(for: root)
				),
			action: nil,
			keyEquivalent: ""
		)
		state.isEnabled = false
		menu.addItem(state)
		menu.addItem(.separator())

		// **The choice of container, which is 0444's parts 1 and 2 arriving.** The
		// question that starts a container stays three answers however many there
		// are — a devcontainer's name is a sentence, and a button per container is
		// a wall in the corner of the screen — so it names the one it would use and
		// *which* is asked here, where there is room, where somebody is already
		// looking when they think about the container, and where the answer is
		// reversible without reopening the project.
		//
		// **The words differ between the two states because the gesture does.**
		// Nothing running: every entry starts something and says so, which is
		// 0438's "Use <container>" grown from one to one-per-container. One
		// running: the entries are which of them it is, with a mark on the one it
		// is, and clicking another moves the servers there.
		let choices = devContainerChoices()
		if inUse {
			// A single ticked entry repeating the sentence above it is noise; the
			// list is only worth having where there is something to choose.
			if choices.count > 1 {
				for choice in choices {
					let item = NSMenuItem(
						title: choice.name,
						action: #selector(useDevContainerFromMenu(_:)),
						keyEquivalent: ""
					)
					item.representedObject = choice.file
					item.target = self
					item.isEnabled = true
					item.state = choice.file == pilledContainer?.file ? .on : .off
					item.toolTip = item.state == .on
						? nil
						: "Move \(root.lastPathComponent)'s language servers into \(choice.name). "
							+ "The ones in \(container) are stopped first."
					menu.addItem(item)
				}
				menu.addItem(.separator())
			}
		} else {
			for choice in choices {
				let use = NSMenuItem(
					title: DevContainerConsent.offerTitle(container: choice.name),
					action: #selector(useDevContainerFromMenu(_:)),
					keyEquivalent: ""
				)
				use.representedObject = choice.file
				use.target = self
				use.isEnabled = true
				use.toolTip = "Run \(root.lastPathComponent)'s language servers inside "
					+ "\(choice.name). The first start builds or downloads its image."
				menu.addItem(use)
			}
			if !choices.isEmpty { menu.addItem(.separator()) }
		}

		// **"New Terminal", not "New Terminal in <the container> ⬢".** The View
		// menu's item and the chevron's beside the panel both have to name the
		// container, because they are read a long way from anything that says
		// which one is meant. This menu drops out of a pill with the name written
		// on it, so repeating it says nothing and leaves three entries that all
		// read as the same length of noise.
		let terminal = containerMenuItem(pilledContainer ?? devContainerChoices().first)
		terminal.title = "New Terminal"
		terminal.target = self
		terminal.isEnabled = true
		menu.addItem(terminal)

		if let file = pilledContainer?.file {
			// The path and not the container's name, because this one is about a
			// file and the tab it opens will be called `devcontainer.json` — a
			// project with two of them has two identical tabs otherwise.
			let open = NSMenuItem(
				title: "Open \(file.deletingLastPathComponent().lastPathComponent)"
					+ "/\(file.lastPathComponent)",
				action: #selector(openDevContainerFile(_:)),
				keyEquivalent: ""
			)
			open.target = self
			open.isEnabled = true
			menu.addItem(open)
		}

		// Only while it is in use. Offering to move onto this machine a project
		// that is already on this machine is a switch with nothing on the other
		// side of it, and the state line above has already said so.
		if devContainerPill?.isInUse == true {
			menu.addItem(.separator())

			// Named as the sentence it is rather than as a switch being thrown:
			// this changes which toolchain the code on screen is checked against,
			// and "Disable" would say nothing about what happens instead.
			let here = NSMenuItem(
				title: "Work on This Machine Instead",
				action: #selector(workOnThisMachineFromMenu(_:)),
				keyEquivalent: ""
			)
			here.target = self
			here.isEnabled = true
			here.toolTip = "Run \(root.lastPathComponent)'s language servers on this machine. "
				+ "The container is left running — a terminal may be in it."
			menu.addItem(here)
		}

		return menu
	}

	@objc private func openDevContainerFile(_ sender: Any?) {
		guard let file = pilledContainer?.file else { return }
		onOpenFile(file)
	}

	@objc private func workOnThisMachineFromMenu(_ sender: Any?) {
		guard let root = devContainerRoot() else { return }
		LanguageService.shared.workOnThisMachine(for: root)
	}

	/// The way in, and the way from one container to another.
	///
	/// One selector for both because it is one sentence — "this project's language
	/// servers belong in that container" — and the three states it can be said
	/// from differ only in what has to be stopped first, which is
	/// `LanguageService.move`'s business and not this menu's. The container
	/// travels on the item, the way the terminal entries' does: with several of
	/// them the title is not something an action can act on.
	@objc private func useDevContainerFromMenu(_ sender: Any?) {
		guard let root = devContainerRoot() else { return }
		guard let choice = choiceCarriedBy(sender) else {
			LanguageService.shared.useDevContainer(for: root)
			return
		}
		LanguageService.shared.useDevContainer(choice, for: root)
	}

	/// What the pill says, for the harness — a menu cannot be photographed while
	/// it is open, and neither can the absence of a pill be told from a window
	/// that has not finished loading.
	func devContainerPillForTesting() -> String {
		// The scope beside it, because "no pill" has two causes that look
		// identical from outside — this project has no devcontainer, or the window
		// is not pointed at the part of it that has one — and telling them apart
		// is most of what a switched-back window has to be checked for.
		let where_ = " [scope=\(scopeRoot()?.lastPathComponent ?? "-")"
			+ " container=\(devContainerRoot()?.lastPathComponent ?? "-")]"
		guard let pill = devContainerPill, pill.hasContainer else { return "PILL: (none)\(where_)" }
		// **What it shows and what it means, separately**, since 0444 made them
		// two different things: the pill is the mark alone, and the name it stands
		// for is only in the tool tip and the menu. A dump that printed the name as
		// though it were on the pill would be recording the thing that was
		// deliberately taken off it.
		return "PILL: shows=\(pill.isInUse ? containerMark : "(icon only)")"
			+ " name=\(devContainerPillTitleForTesting)"
			+ " tip=\(pill.toolTip ?? "-")"
			+ where_
	}

	private var devContainerPillTitleForTesting: String {
		containerName(pilledContainer, devContainerRoot() ?? URL(fileURLWithPath: "/"))
	}

	/// What the pill's menu offers, for the harness: a menu cannot be
	/// photographed while it is open, and the way back out of a decline is the
	/// whole of 0438's third fault.
	func devContainerMenuForTesting() -> String {
		guard devContainerPill?.hasContainer == true else { return "PILLMENU: (no pill)" }
		let menu = devContainerPillMenu()
		return "PILLMENU: " + menu.items.map { item in
			guard !item.isSeparatorItem else { return "—" }
			// The tick as well as the words: with several containers listed, which
			// one is marked is the whole of what the list says.
			return (item.state == .on ? "✓" : "")
				+ item.title
				+ (item.isEnabled ? "" : " (disabled)")
		}.joined(separator: " | ")
	}

	/// What the worktree pill says, for the harness.
	///
	/// Absence is the interesting reading and the one a screenshot cannot give:
	/// a repository with one checkout should have no pill at all, and an empty
	/// stretch of toolbar looks exactly like one that has not finished loading.
	/// On the primary the pill is deliberately wordless, so what it *shows* and
	/// what it *is* are printed separately — a dump that read the name off the
	/// drawing would record nothing on the very window the report was about.
	func worktreePillForTesting() -> String {
		guard let pill = worktreePill, pill.hasWorktrees else {
			return "WORKTREE: (none) [listed=\(worktrees.count)]"
		}
		let state = pill.worktree
		return "WORKTREE: shows=\(state?.name ?? "(icon only)")"
			+ " of=\(state?.full ?? "-")"
			+ " at=\(state.map { $0.isPrimary ? "primary" : "linked" } ?? "-")"
			+ " listed=\(worktrees.count)"
			+ " tip=\((pill.toolTip ?? "-").replacingOccurrences(of: "\n", with: " / "))"
	}

	/// What the worktree menu offers, for the harness — including how much of it
	/// went behind `More…`, which is the whole claim on a repository with
	/// seventy-four checkouts.
	func worktreeMenuForTesting() -> String {
		guard worktreePill?.hasWorktrees == true else { return "WORKTREEMENU: (no pill)" }
		func describe(_ items: [NSMenuItem]) -> String {
			items.map { item in
				guard !item.isSeparatorItem else { return "—" }
				let submenu = item.submenu.map { " { \(describe($0.items)) }" } ?? ""
				return (item.state == .on ? "✓" : "") + item.title + submenu
			}.joined(separator: " | ")
		}
		return "WORKTREEMENU: " + describe(worktreeMenu().items)
	}

	/// What the toolbar is showing, and what it has put away.
	func reportToolbarForTesting() {
		guard let toolbar = window?.toolbar else { return }
		let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier.rawValue))
		let all = toolbar.items.map(\.itemIdentifier.rawValue)
		let hidden = all.filter { !visible.contains($0) && !$0.hasPrefix("NSToolbar") }
		print("TOOLBAR visible=\(visible.filter { !$0.hasPrefix("NSToolbar") }.sorted()) hidden=\(hidden)")

		for item in toolbar.items where !visible.contains(item.itemIdentifier.rawValue) {
			let menu = item.menuFormRepresentation
			print("  put away: \(item.itemIdentifier.rawValue) menu=\(menu?.title ?? "none") "
				+ "submenu=\(menu?.submenu?.items.map(\.title).prefix(4) ?? [])")
		}

		if let capsule {
			print("  capsule height=\(capsule.frame.height) in row=\(capsule.superview?.frame.height ?? 0)")
		}
	}

	func highlightPillsForTesting() {
		capsule?.isMenuOpen = true
	}

	// These identifiers keep their old spelling for the same reason the window
	// autosave names do: AppKit stores a toolbar's arrangement under them, and
	// renaming would rebuild everybody's toolbar from the default.
	private static let capsuleItem = NSToolbarItem.Identifier("abydos.capsule")

	private static let subprojectItem = NSToolbarItem.Identifier("abydos.subproject")

	private static let worktreeItem = NSToolbarItem.Identifier("abydos.worktree")

	private static let devContainerItem = NSToolbarItem.Identifier("abydos.devcontainer")

	private static let runItem = NSToolbarItem.Identifier("abydos.run")
	private static let maximizeItem = NSToolbarItem.Identifier("abydos.maximize")

	/// Next to the traffic lights, where a window says what it is.
	///
	/// Centred was tried and reads as decoration: the eye starts at the top left
	/// of a window, and putting the one thing that answers "where am I" anywhere
	/// else makes it something to go looking for.
	/// The devcontainer beside the subproject, in that order, because that is the
	/// order the sentence goes in: this project, this corner of it, and the
	/// machine that corner's tools are on.
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		// The worktree pill next to the capsule and before the subproject, because
		// it qualifies the same thing the capsule's left half names — which
		// checkout — where the subproject qualifies which corner of it and the
		// devcontainer qualifies what it is built with. Reading left to right
		// then goes from the widest question to the narrowest.
		// The window-shape button last, at the trailing edge: it is about the
		// window rather than about the project or what is running in it, and
		// that is where a window's own controls live.
		[
			Self.capsuleItem, Self.worktreeItem, Self.subprojectItem, Self.devContainerItem,
			.flexibleSpace, Self.runItem, Self.maximizeItem,
		]
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarDefaultItemIdentifiers(toolbar)
	}

	func toolbar(
		_ toolbar: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar flag: Bool
	) -> NSToolbarItem? {
		switch identifier {
		case Self.capsuleItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let capsule = TitlebarCapsule()
			capsule.onProject = { [weak self] in self?.onProjectPressed() }
			capsule.onBranch = { [weak self] in self?.onBranchPressed() }
			if let project = project() { capsule.setProject(name: project.name) }
			// Whatever the current read of the repository says, whenever it
			// says it: this item may be built before or after git answers.
			if let read = branchRead() {
				Task { @MainActor in
					let head = await read.value
					capsule.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
				}
			}
			self.capsule = capsule
			item.view = capsule

			// What the overflow menu shows when the window is too narrow to
			// hold this. Without it AppKit drops the item and says nothing.
			let menu = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
			menu.submenu = {
				let submenu = NSMenu()
				submenu.addItem(menuItem("Switch Project…", #selector(switchProjectItem(_:))))
				submenu.addItem(menuItem("Branch…", #selector(showBranchMenuItem(_:))))
				return submenu
			}()
			item.menuFormRepresentation = menu
			// The switcher is also in the menu bar, so this is the first thing
			// that can go when there is no room.
			item.visibilityPriority = .standard
			return item

		case Self.maximizeItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let button = NSButton(image: NSImage(), target: self, action: #selector(
				pressedMaximize(_:)
			))
			button.isBordered = false
			button.bezelStyle = .shadowlessSquare
			button.imagePosition = .imageOnly
			// Nothing in the titlebar should take the keyboard from the editor.
			button.refusesFirstResponder = true
			maximizeButton = button
			refreshMaximizeButton()
			item.view = button

			// `toggleEditorMaximized` rather than this object's `@objc`: an
			// overflow row is found through the responder chain, which reaches
			// the window controller and not this.
			let menu = NSMenuItem(
				title: "Maximize Editor", action: Selector(("toggleEditorMaximized:")),
				keyEquivalent: ""
			)
			item.menuFormRepresentation = menu
			// It goes before the run strip does: this is a convenience for a
			// gesture that is also a double-click on a tab.
			item.visibilityPriority = .standard
			return item

		case Self.runItem:
			// Everything this item does belongs to running, so the window builds it.
			return makeRunItem(identifier)

		case Self.subprojectItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = SubprojectPillButton()
			pill.onClick = { [weak self] in self?.showSubprojectMenu() }
			pill.onLeave = { [weak self] in self?.onLeaveSubproject() }
			pill.setSubproject(
				subprojectRoot().flatMap { url in
					project().map { Subprojects.relativePath(url, to: $0.root) }
				}
			)
			subprojectPill = pill
			item.view = pill
			item.menuFormRepresentation = menuItem("Subproject", #selector(showSubprojectMenuItem(_:)))
			item.visibilityPriority = .low
			return item

		case Self.worktreeItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = WorktreePillButton()
			pill.onClick = { [weak self] in self?.showWorktreeMenu() }
			pill.setWorktree(nil)
			worktreePill = pill
			item.view = pill
			item.menuFormRepresentation = menuItem("Worktree", #selector(showWorktreeMenuItem(_:)))
			item.visibilityPriority = .low
			// The toolbar builds its items when it chooses, which may be long
			// after git answered — so the reading is taken again rather than
			// waited for. Same reason the devcontainer pill does it below.
			readWorktree()
			return item

		case Self.devContainerItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = DevContainerPillButton()
			pill.onClick = { [weak self] in self?.showDevContainerMenu() }
			pill.setContainer(nil)
			devContainerPill = pill
			item.view = pill
			item.menuFormRepresentation = menuItem(
				"Devcontainer", #selector(showDevContainerMenuItem(_:))
			)
			item.visibilityPriority = .low
			// The item is built when the toolbar chooses, which may be after the
			// project was loaded and its container asked about.
			refreshDevContainerPill()
			return item

		default:
			return nil
		}
	}

	/// A menu item pointing back at this window.
	private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	@objc fileprivate func showBranchMenuItem(_ sender: Any?) { onBranchPressed() }

	@objc fileprivate func showSubprojectMenuItem(_ sender: Any?) { showSubprojectMenu() }

	/// The projects inside this one, so moving between them is a menu rather
	/// than a hunt through the tree.
	@objc func showSubprojectMenu() {
		guard let project = project() else { return }
		let menu = NSMenu()

		let whole = NSMenuItem(
			title: project.name, action: #selector(leaveSubprojectFromMenu), keyEquivalent: ""
		)
		whole.target = self
		whole.state = subprojectRoot() == nil ? .on : .off
		menu.addItem(whole)

		let found = Subprojects.find(in: project.root)
		if !found.isEmpty { menu.addItem(.separator()) }
		for url in found {
			let relative = Subprojects.relativePath(url, to: project.root)
			let item = NSMenuItem(
				title: relative, action: #selector(openSubprojectFromMenu(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = url
			item.state = url.path == subprojectRoot()?.path ? .on : .off
			menu.addItem(item)
		}

		let anchor: NSView? = subprojectPill ?? capsule
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: (anchor?.bounds.maxY ?? 0) + Theme.current.scaled(4)),
			in: anchor
		)
	}

	@objc fileprivate func showWorktreeMenuItem(_ sender: Any?) { showWorktreeMenu() }

	/// How many checkouts the menu shows before the rest go behind `More…`.
	///
	/// Ten is a menu somebody reads. This repository answers seventy-four —
	/// about fifty from `abydos-backlog start` and twenty an agent harness left
	/// under `.claude/worktrees/` — and a flat list of those is a wall the eye
	/// slides off, which is the same as not being there.
	private static let worktreesShown = 10

	/// The checkouts of this repository, so moving between them is a menu rather
	/// than a hunt through the file system.
	///
	/// The primary is always here and always first, because it is the way back
	/// and the pill would otherwise be a door that only opens outward. So is the
	/// one this window is on, ticked, even when the ordering would have put it
	/// past the cap — a menu whose tick is not in it reads as being nowhere.
	@objc func showWorktreeMenu() {
		let anchor: NSView? = worktreePill ?? capsule
		worktreeMenu().popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: (anchor?.bounds.maxY ?? 0) + Theme.current.scaled(4)),
			in: anchor
		)
	}

	/// Built apart from being shown, so the harness can read it: a menu cannot be
	/// photographed while it is open, and the interesting claim about this one is
	/// what it does with seventy-four entries.
	private func worktreeMenu() -> NSMenu {
		let menu = NSMenu()
		let current = project()?.root.standardizedFileURL.path

		// The directory is gone, so the one thing a row here can do would fail.
		// They stay in the branches pane, where removing one is the point.
		let present = worktrees.filter { !$0.isMissing }

		var shown = Array(present.prefix(Self.worktreesShown))
		if let here = present.first(where: { $0.path.path == current }),
		   !shown.contains(where: { $0.path.path == here.path.path }) {
			shown.append(here)
		}
		let rest = present.filter { entry in !shown.contains { $0.path.path == entry.path.path } }

		// What every other row is named against, so a folder that only repeats
		// its branch can be told from one somebody chose.
		let primaryName = present.first { $0.isPrimary }?.name ?? project()?.name ?? ""

		for worktree in shown {
			menu.addItem(worktreeItem(worktree, current: current, primaryName: primaryName))
		}

		if !rest.isEmpty {
			menu.addItem(.separator())
			let more = NSMenuItem(title: "More — \(rest.count) older", action: nil, keyEquivalent: "")
			let submenu = NSMenu()
			for worktree in rest {
				submenu.addItem(worktreeItem(worktree, current: current, primaryName: primaryName))
			}
			more.submenu = submenu
			menu.addItem(more)
		}

		// Adding, removing and revealing a checkout all live in the branches
		// pane already, with a filter field in front of them. The titlebar is
		// for going somewhere; this is the way through to the rest.
		menu.addItem(.separator())
		menu.addItem(menuItem("Show All Worktrees…", #selector(showAllWorktrees(_:))))
		return menu
	}

	/// The longest a row is allowed to be before the tail is dropped.
	///
	/// A branch here is named after a backlog item, and a backlog item's branch
	/// carries most of its title — `backlog/0479-toggle-comment-answers-to-a-key-
	/// nobody-asked-for-on-a`. Ten of those side by side is a menu as wide as the
	/// display, which is not a menu somebody reads either. The tail goes rather
	/// than the middle because what tells these apart is at the front: the
	/// number.
	private static let worktreeTitleLimit = 52

	/// One checkout: what is checked out there, and its folder name when that
	/// says something the branch does not.
	///
	/// The branch is on the item rather than only in the tool tip, because the
	/// folder name is a decision somebody made months ago and the branch is what
	/// they are looking for. `GitWorktree.summary` says it in all three of the
	/// states 0477 settled — a branch, one with nothing on it, and a commit
	/// checked out directly — so a detached worktree reads as `detached at
	/// abc1234` here rather than as a bare folder name.
	private func worktreeItem(
		_ worktree: GitWorktree, current: String?, primaryName: String
	) -> NSMenuItem {
		let label = GitWorktrees.label(for: worktree, primaryName: primaryName)
		let item = NSMenuItem(
			title: label.count > Self.worktreeTitleLimit
				? label.prefix(Self.worktreeTitleLimit - 1) + "…"
				: label,
			action: #selector(openWorktreeFromMenu(_:)),
			keyEquivalent: ""
		)
		item.target = self
		item.representedObject = worktree.path
		item.state = worktree.path.path == current ? .on : .off
		// The whole of it, which the title may have dropped the tail of, and the
		// directory — the one thing a row never shows and the thing somebody
		// needs when two branches read alike.
		item.toolTip = [
			label,
			worktree.path.path,
			worktree.isPrimary ? "The checkout this repository was cloned into" : nil,
		].compactMap { $0 }.joined(separator: "\n")
		return item
	}

	@objc private func openWorktreeFromMenu(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL,
		      url.standardizedFileURL.path != project()?.root.standardizedFileURL.path
		else { return }
		// Through the delegate rather than `switchProject`, the way a worktree
		// opened from a backlog card or the project switcher goes: this window or
		// a new one, whichever the setting says, and a checkout already open in
		// another window is raised rather than opened twice. That last part is
		// what makes the arrangement 0454 relies on — a card's work in a worktree
		// while another window sits on the primary — survive being clicked at.
		onOpenWorktree(url)
	}

	@objc private func openSubprojectFromMenu(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL else { return }
		onOpenSubproject(url)
	}

	@objc private func leaveSubprojectFromMenu() { onLeaveSubproject() }

	/// Clicks the branch pill, for measuring what opening it costs.

	/// What a language server is doing, for the pill's tooltip.
	private static func languageSentence(for readiness: LanguageService.Readiness) -> String? {
		switch readiness {
		case .none:      nil
		case .preparing: "Language servers are still starting — definitions and completion are not ready."
		case .failed:    "A language server could not start; the editor is working without it."
		case .ready:     "Language servers are ready."
		}
	}
}
