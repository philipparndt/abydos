import AppKit
import AbydosKit

/// Every settings page, written out as rows.
///
/// This is the whole of what the app offers to change, and it is data rather
/// than layout: a `Row` says what a setting is called, what it reads and what
/// it writes, and `SettingsPaneController` turns that into controls. Adding a
/// setting is a line here.
///
/// It is kept apart from the machinery that draws it because the two are read
/// for different reasons — somebody looking for a setting is looking for a
/// sentence, and somebody changing how a checkbox is built is not.
extension SettingsPaneController {
	// MARK: - Pane definitions

	/// How code is shown and how big everything is.
	/// What the app looks like: one page for the editor and the terminal
	/// together, since they are one thing to look at.
	static func appearanceRows() -> [Row] {
		[
			.group(title: "Theme", help: nil, rows: [
				.choiceWithActions(
					title: "Theme",
					help: "Abydos is this app's own, warm. Blue is the one it started with, "
						+ "and the palette most editors' dark themes are a version of. "
						+ "Your own go in ~/.config/abydos/schemes — the folder button opens it, "
						+ "and the arrows read it again.",
					options: Appearance.families.map { ($0.title, $0.id) },
					get: { Settings.shared.themeFamily },
					set: { Settings.shared.themeFamily = $0 },
					actions: [
						(
							symbol: "arrow.triangle.2.circlepath",
							help: "Read the schemes folder again",
							action: { reloadSchemes() }
						),
						(
							symbol: "folder",
							help: "Open the folder your own schemes live in",
							action: { revealSchemes() }
						),
					]
				),
				.choice(
					title: "Light or dark",
					help: "Each theme has both. Following the system switches between them "
						+ "without changing which theme it is.",
					options: Appearance.Mode.allCases.map { ($0.title, $0.rawValue) },
					get: { Settings.shared.appearanceMode },
					set: { Settings.shared.appearanceMode = $0 }
				),
				.choice(
					title: "Terminal colours",
					help: "Same as the theme uses the palette that belongs to it. Editor colours "
						+ "paints the terminal in the editor's own background and text instead, so "
						+ "the two panes are one surface. Blue is the palette Ghostty ships with. "
						+ "All of them have a light and a dark form.",
					options: [("Same as the theme", Appearance.followsEditor)]
						+ TerminalScheme.all.map { ($0.title, $0.id) },
					// Through the identifier, so a preference still holding what
					// "Editor colours" used to be called selects the right row.
					get: { Appearance.terminalSchemeIdentifier(for: Settings.shared.terminalScheme) },
					set: { Settings.shared.terminalScheme = $0 }
				),
			]),
			.group(title: "Size", help: nil, rows: [
				.slider(
					title: "UI zoom",
					help: "Scales the whole window. Also ⌘+ / ⌘− / ⌘0.",
					// Continuous here rather than the discrete keyboard steps, since a
					// slider invites fine adjustment.
					range: 0.75...2.0, step: 0.05,
					format: { String(format: "%.0f%%", $0 * 100) },
					get: { Settings.shared.uiScale },
					set: { Settings.shared.uiScale = $0 }
				),
				.slider(
					title: "Editor font size",
					help: nil,
					range: 9...20, step: 0.5,
					format: { String(format: "%.1f pt", $0) },
					get: { Settings.shared.editorFontSize },
					set: { Settings.shared.editorFontSize = $0 }
				),
				.slider(
					title: "Editor line height",
					help: nil,
					range: 1.0...2.0, step: 0.1,
					format: { String(format: "%.1f×", $0) },
					get: { Settings.shared.editorLineHeight },
					set: { Settings.shared.editorLineHeight = $0 }
				),
				.text(
					title: "Terminal font",
					help: "Leave empty to choose automatically. Powerline prompts need a Nerd Font.",
					get: { Settings.shared.terminalFontName },
					set: { Settings.shared.terminalFontName = $0.trimmingCharacters(in: .whitespaces) }
				),
				.toggle(
					title: "Ligatures",
					help: "Draws -> and != and =~ as one shape, in the editor and the terminal "
						+ "both. Needs a font that has them — JetBrains Mono, Fira Code, "
						+ "Cascadia and Iosevka all do.",
					get: { Settings.shared.fontLigatures },
					set: { Settings.shared.fontLigatures = $0 }
				),
			]),
		]
	}

	static func editorRows() -> [Row] {
		[
			.toggle(
				title: "Word wrap",
				help: "Soft-wrap long lines instead of scrolling sideways (⌥⌘Z).",
				get: { Settings.shared.wordWrap },
				set: { Settings.shared.wordWrap = $0 }
			),
			.stepper(
				title: "Tab width",
				help: "Columns a tab character advances to.",
				range: 1...16,
				get: { Settings.shared.tabWidth },
				set: { Settings.shared.tabWidth = $0 }
			),
			.toggle(
				title: "Conceal secrets",
				help: "Covers the values in .env and .dec files until the lock in the "
					+ "status bar reveals them — a shared screen does not announce "
					+ "itself first.",
				get: { Settings.shared.concealsSecrets },
				set: { Settings.shared.concealsSecrets = $0 }
			),
			.toggle(
				title: "Show problems beside the line",
				help: "The message is written after the code, dimmed. Off, only the "
					+ "squiggle and the tooltip say what is wrong.",
				get: { Settings.shared.showsInlineDiagnostics },
				set: { Settings.shared.showsInlineDiagnostics = $0 }
			),
		]
	}

	/// The terminal's own look, and how it draws.
	static func terminalRows() -> [Row] {
		// Sections rather than one long list: what the terminal looks like,
		// what it does when a window opens, and the tmux switches that only
		// mean anything together.
		var sections: [Row] = [
			.group(title: "Tab strip", help: nil, rows: [
				.choice(
					title: "Double-click on the tab strip",
					help: "What a double-click on the empty part of the strip does. The other "
						+ "two are always in the strip's menu, and the button beside it expands "
						+ "the editor whatever this says.",
					options: TabStripDoubleClick.allCases.map { ($0.label, $0.rawValue) },
					get: { Settings.shared.tabStripDoubleClick.rawValue },
					set: { Settings.shared.tabStripDoubleClick = TabStripDoubleClick(rawValue: $0) ?? .default }
				),
			]),
			.group(title: "Bell and keys", help: "Colours and fonts are on the Appearance page.", rows: [
				.choice(
					title: "Terminal bell",
					help: "VHS shakes the picture and splits its colours, like a worn tape. "
						+ "Needs GPU rendering.",
					options: [("Sound", "sound"), ("VHS", "vhs"), ("Ignore", "none")],
					get: { Settings.shared.terminalBellStyle },
					set: { Settings.shared.terminalBellStyle = $0 }
				),
				.toggle(
					title: "Option sends Meta",
					help: "Off, so Option types what your keyboard says it does — on a German "
						+ "layout that is where the braces and brackets are. On, so ⌥B and ⌥F "
						+ "move by words instead.",
					get: { Settings.shared.terminalOptionAsMeta },
					set: { Settings.shared.terminalOptionAsMeta = $0 }
				),
				.toggle(
					title: "GPU terminal rendering",
					help: "Draw the terminal with Metal. Faster when a program repaints the whole "
						+ "screen, and on by default. Turn it off to draw through CoreGraphics "
						+ "instead — the same screen either way.",
					get: { Settings.shared.terminalGPURendering },
					set: { Settings.shared.terminalGPURendering = $0 }
				),
				// The engine switch, and its help says what is missing rather
				// than leaving it to be discovered. An option that draws
				// something plausible while quietly lacking a whole category is
				// worse than no option at all: whoever notices weeks later
				// cannot tell whether it was the engine, the seam or a real bug.
				// Items 0474 and 0485.
				.toggle(
					title: "Emulate with libghostty-vt (experimental)",
					help: "Use ghostty's terminal state machine instead of ours: much faster at "
						+ "plain output, and it reflows on resize, which ours does not. Applies to "
						+ "panes opened after the change, not to open ones. Three known "
						+ "differences: `abydos <file>` typed in a pane will not open it, a program "
						+ "using xterm's older modifyOtherKeys gets ordinary bytes, and tmux's own "
						+ "prompts draw a row too high when the status bar is off. Backlog item 485.",
					get: { Settings.shared.terminalGhosttyEngine },
					set: { Settings.shared.terminalGhosttyEngine = $0 }
				),
			]),
			.group(title: "Behaviour", help: nil, rows: [
				.choice(
					title: "Terminal when a window opens",
					help: "Closed, open at its usual height, or filling the window.",
					options: [
						(label: "Closed", value: "closed"),
						(label: "Open", value: "open"),
						(label: "Filling the window", value: "full"),
					],
					get: { Settings.shared.terminalAtStartup },
					set: { Settings.shared.terminalAtStartup = $0 }
				),
				.toggle(
					title: "Follow the terminal's project",
					help: "When the terminal moves into another project, the window opens it. "
						+ "New windows start this way; each window can still be switched by hand.",
					get: { Settings.shared.followsTerminalProject },
					set: { Settings.shared.followsTerminalProject = $0 }
				),
				.toggle(
					title: "…and into folders that are in no repository",
					help: "A folder in no working copy is shown without being a project. "
						+ "Off, the window stays where it is: with no repository to say the "
						+ "walk was over, every directory would be somewhere to follow to.",
					get: { Settings.shared.followsLooseFolders },
					set: { Settings.shared.followsLooseFolders = $0 }
				),
			]),
		]

		// Offered only where there is a tmux to attach to: a switch that can do
		// nothing is worse than no switch. In the order they depend on each
		// other, each greyed while the one above it is off.
		if Executables.locate("tmux") != nil {
			sections.append(.group(
				title: "tmux",
				help: "Each of these only means anything while the one above it is on.",
				rows: [
					.toggle(
						title: "Attach the first terminal to tmux",
						help: "One session per project, so reopening it comes back to the panes it "
							+ "was left with. Terminals opened afterwards are plain shells.",
						get: { Settings.shared.startsTmux },
						set: { Settings.shared.startsTmux = $0 }
					),
					.toggle(
						title: "Tabs are tmux's windows",
						help: "The strip shows the session's windows and switching a tab switches "
							+ "tmux. One terminal, one shell: changing tabs costs nothing.",
						get: { Settings.shared.strictTmux },
						// The status bar goes with it: leaving somebody with no
						// window list at all would be this switch quietly
						// breaking their tmux.
						set: { TmuxSettings.setTabsAreTmuxWindows($0) },
						isEnabled: { Settings.shared.startsTmux }
					),
					.toggle(
						title: "Hide tmux's own status bar",
						help: "Those tabs already show this session's windows, so tmux's bar is the "
							+ "same list twice. It sets `status off` on this project's session — not "
							+ "on the server, and nothing is written to ~/.tmux.conf — so other "
							+ "sessions keep their bar. This one loses it in every terminal attached "
							+ "to it, Abydos or not, and keeps it off after Abydos quits until this "
							+ "is turned back on.",
						get: { TmuxSettings.wantsStatusBarHidden },
						set: { TmuxSettings.wantsStatusBarHidden = $0 },
						isEnabled: { TmuxSettings.tabsAreTmuxWindows }
					),
				]
			))
		}
		return sections
	}

	/// What Claude Code is allowed to do on your behalf.
	/// Tools that can come from a container image instead of from this machine.
	///
	/// One row per tool that supports it, rather than a table of arbitrary
	/// pairs: a settings page is for the things somebody actually sets, and a
	/// free-form map of tool names invites typing one that means nothing.
	static func toolRows() -> [Row] {
		[
			.choice(
				title: "Container runtime",
				help: "Where a tool that comes from an image is run. Docker is preferred when "
					+ "nothing is said, because removing a container by name is proven against "
					+ "it and a container this app cannot remove is one it leaves running. "
					+ "Apple's needs no daemon, which is the better argument the day its "
					+ "service is reliable again. Saying which means being told when it is "
					+ "missing, rather than quietly getting the other one. Each tool below "
					+ "chooses whether it comes from an image at all.",
				options: ContainerRuntime.Preference.allCases.map { ($0.title, $0.rawValue) },
				get: { Settings.shared.containerRuntime },
				set: { Settings.shared.containerRuntime = $0 }
			),
		]
	}

	/// Which server each language uses, and where that was decided.
	///
	/// A page of its own beside the per-tool pages, because it answers the other
	/// question: those say where a tool comes from — installed here, a published
	/// image, one built here — and this says which tool answers for the language
	/// at all. Keeping them apart is the point. A project can pin an image for a
	/// server it does not use, and change its server without saying anything
	/// about where the new one comes from.
	///
	/// Every language is listed, not only the ones with something to decide. A
	/// row reading "Java: jdtls, the only one Abydos has" answers the question
	/// somebody opened this page with, and it is where a second one will appear
	/// the day there is a second one.
	static func languageServerRows() -> [Row] {
		LanguageServers.languageGroups().map { group in
			let title = group.languageIds
				.map { LanguageRegistry.shared.displayName(for: $0) }
				.joined(separator: ", ")
			let names = group.candidates.map(\.name)
			let sole = names.count == 1
			// What each candidate costs, where there is a choice to make. Two bare
			// names say what the options are called and nothing about which one
			// anybody should pick, and the difference between these two is minutes
			// and gigabytes against type checking. 0449 asked for this line and left
			// it to whoever knew the trade.
			let trades = group.candidates
				.compactMap { candidate in candidate.trade.map { "\(candidate.name) — \($0)" } }
				.joined(separator: "  ")
			return .choice(
				title: title,
				help: sole
					? "\(names.first ?? "") is the only server Abydos has for this. A project may "
						+ "still name one in .abydos/tools.json, and is told plainly when what it "
						+ "names is not here."
					: "Which server answers for this language. A project naming its own in "
						+ ".abydos/tools.json overrides this — the file wins and this is the "
						+ "default — and a named server that cannot be started says so rather than "
						+ "quietly becoming the other one."
						+ (trades.isEmpty ? "" : "  \(trades)"),
				options: [(
					label: sole
						? "\(names.first ?? "") — the only one Abydos has"
						: "Whichever Abydos has (\(names.first ?? ""))",
					value: ""
				)] + group.candidates.map { (label: $0.name, value: $0.name) },
				get: {
					let stored = Settings.shared.languageServers
					// The first id speaks for the group: they are grouped
					// *because* they have the same candidates, and every one of
					// them is written together below.
					guard let chosen = group.languageIds.first.flatMap({ stored[$0] }),
					      names.contains(chosen)
					else { return "" }
					return chosen
				},
				set: { value in
					var stored = Settings.shared.languageServers
					for languageId in group.languageIds {
						stored[languageId] = value.isEmpty ? nil : value
					}
					Settings.shared.languageServers = stored
				}
			)
		}
	}

	/// One tool's page: where it comes from, and what an image has to do.
	///
	/// The requirement is spelled out beside the field, because an image that
	/// does not meet it fails as an empty pane and nothing on screen would say
	/// why.
	static func rows(for tool: ToolImageCatalogue.Tool) -> [Row] {
		[
			.choice(
				title: "\(tool.title) from",
				help: "Installed on this machine is used unless an image is chosen. "
					+ "A project naming its own in .abydos/tools.json overrides both.",
				options: ToolImageCatalogue.options(for: tool),
				get: {
					ToolImageCatalogue.selection(
						for: Settings.shared.toolImages[tool.key] ?? "", tool: tool
					)
				},
				set: { value in
					var images = Settings.shared.toolImages
					switch value {
					case ToolImageCatalogue.useInstalled:
						images[tool.key] = nil
					case ToolImageCatalogue.custom:
						// Keep whatever is in the field: choosing "custom" is
						// saying "the one I typed", not clearing it.
						if images[tool.key] == nil { images[tool.key] = "" }
					default:
						images[tool.key] = value
					}
					Settings.shared.toolImages = images
				}
			),
			.text(
				title: "Custom image",
				help: tool.requirement,
				get: { Settings.shared.toolImages[tool.key] ?? "" },
				set: { image in
					var images = Settings.shared.toolImages
					let wanted = image.trimmingCharacters(in: .whitespaces)
					images[tool.key] = wanted.isEmpty ? nil : wanted
					Settings.shared.toolImages = images
				}
			),
			// **Which program, as distinct from where it comes from.** Empty on
			// nearly every machine, and it is here because the two are not the same
			// question: a tool reached by *name* goes through whatever owns that name
			// on the `PATH`, and a toolchain manager's proxy refuses to run a server
			// its pinned toolchain has not got rather than running the one installed
			// beside it. A path is the way past that. 0466.
			.text(
				title: "Executable",
				help: "The program to run, as a path — empty looks the tool's own name up "
					+ "on the PATH, which is what nearly every machine wants. ~ is expanded. "
					+ "Worth setting where the name on the PATH belongs to a toolchain manager "
					+ "rather than to the tool: ~/.cargo/bin/rust-analyzer is a symlink to "
					+ "rustup, and in a project pinning a toolchain that has no rust-analyzer "
					+ "in it the proxy refuses instead of running the copy installed beside "
					+ "it. Where the tool comes from an image this is the path inside that "
					+ "image. A project's .abydos/tools.json overrides it.",
				get: { Settings.shared.serverCommands[tool.key] ?? "" },
				set: { command in
					var commands = Settings.shared.serverCommands
					let wanted = command.trimmingCharacters(in: .whitespaces)
					commands[tool.key] = wanted.isEmpty ? nil : wanted
					Settings.shared.serverCommands = commands
				}
			),
		]
	}

	/// Where the hook binary is, which is the string that goes in the settings.
	///
	/// Beside this app's own executable, because that is where the bundle puts
	/// it — and by its real path, because Claude Code runs hooks through `sh -c`
	/// with a minimal environment where a bare name resolves to nothing.
	static var hookCommand: String {
		let beside = Bundle.main.executableURL?
			.deletingLastPathComponent()
			.appendingPathComponent("abydos-hook")
		return (beside ?? URL(fileURLWithPath: "abydos-hook")).resolvingSymlinksInPath().path
	}

	static func agentRows() -> [Row] {
		[
			// **Read from the file, not from a preference.** These entries live
			// in `~/.claude/settings.json`, which this app does not own: another
			// tool's uninstaller can take them out — cmanager's took the whole
			// `hooks` block with it — and there was then nothing on this page
			// that said so and no way to put them back without a terminal. A
			// switch that reads the file cannot be wrong about it.
			.toggle(
				title: "Let Claude Code say what it is doing",
				help: "Registers seven hooks in ~/.claude/settings.json, so a session's progress "
					+ "shows on its terminal tab and in the tmux status line. Only the entries "
					+ "that are ours are touched, and the file is backed up first. Sessions "
					+ "already running pick it up when they are restarted.",
				get: { ClaudeHookSetup.isRegisteredForAnyCopy() },
				set: { wanted in
					do {
						let backup = try ClaudeHookSetup.setRegistered(wanted, command: hookCommand)
						Toast.post(
							wanted ? "Claude Code will report its progress" : "Claude hooks removed",
							detail: backup.map { "The file as it was: \($0.lastPathComponent)" }
								?? "~/.claude/settings.json",
							kind: .information
						)
					} catch {
						// The file belongs to somebody else and can be
						// unreadable, unwritable or not JSON at all; saying so
						// beats a switch that slides back with no explanation.
						Toast.post(
							"Could not change ~/.claude/settings.json",
							detail: error.localizedDescription,
							kind: .warning
						)
					}
				}
			),
			.choice(
				title: "What an agent may do",
				help: "A review or a fix runs Claude Code. Accepting edits keeps it from stopping "
					+ "to ask whether it may change the file it was asked to change.",
				options: [("Accept edits", "acceptEdits"), ("Ask", "ask"), ("Everything", "full")],
				get: { Settings.shared.agentPermissions },
				set: { Settings.shared.agentPermissions = $0 }
			),
		]
	}

	static func savingRows() -> [Row] {
		[
			.toggle(
				title: "Auto save",
				help: "Write changes to disk automatically after a pause in typing.",
				get: { Settings.shared.autoSaveEnabled },
				set: { Settings.shared.autoSaveEnabled = $0 }
			),
			.slider(
				title: "Delay",
				help: "Idle time before writing. Long, so file watchers are not set off mid-word; "
					+ "switching away and running both save regardless.",
				range: 1...60, step: 1,
				format: { String(format: "%.0f s", $0) },
				get: { Settings.shared.autoSaveDelay },
				set: { Settings.shared.autoSaveDelay = $0 }
			),
			.toggle(
				title: "Save on focus loss",
				help: "Also write when Abydos goes to the background.",
				get: { Settings.shared.saveOnFocusLoss },
				set: { Settings.shared.saveOnFocusLoss = $0 }
			),
		]
	}

	/// What this app is allowed to run, and where that was decided.
	///
	/// **A list of folders rather than a switch.** Trust is granted per project
	/// in the window's own strip, which is where somebody is looking at the
	/// project they are deciding about; this page is where the decisions are
	/// read back and taken away — the one thing a strip cannot do, since the
	/// project it was about may not be open any more.
	/// What the Finder opens with this editor, and the terminal it can offer.
	static func systemRows() -> [Row] {
		let opened = DefaultEditor.typesThisAppOpens().count
		let declared = DefaultEditor.declaredTypes.count
		return [
			.group(
				title: "The Finder",
				help: "Abydos is offered under Open With for the files it can read — that is in "
					+ "the bundle and claims nothing. This makes it the one that opens when you "
					+ "double-click them.",
				rows: [
					.toggle(
						title: "Open source files with Abydos",
						help: opened == 0
							? "Currently \(declared) kinds of file open with something else."
							: "Currently \(opened) of \(declared) kinds open with Abydos. "
								+ "macOS decides this one and may ask you again in its own words.",
						// Read from Launch Services rather than from what this
						// app once asked for: another editor can take a kind
						// back, and the page is read at exactly that moment.
						get: { DefaultEditor.isDefaultForEverythingDeclared },
						set: { wanted in
							Task { @MainActor in
								if wanted {
									await DefaultEditor.makeDefault()
								} else {
									await DefaultEditor.handBack()
								}
							}
						}
					),
				]
			),
			.group(
				title: "The Finder's terminal",
				help: "Right-click a folder and choose Services ▸ New Terminal Here to open it "
					+ "in this app's terminal. The Finder's own Open in Terminal belongs to "
					+ "Terminal.app and cannot be pointed at another application — macOS offers "
					+ "that to nobody. A keyboard shortcut for the service is set in System "
					+ "Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services.",
				rows: []
			),
		]
	}

	static func trustRows() -> [Row] {
		let folders = ProjectTrust.shared.folders.sorted { $0.path < $1.path }
		var rows: [Row] = [
			.group(
				title: "Trusted folders",
				help: folders.isEmpty
					? "Nothing is trusted yet. A project is trusted from the strip at the top "
						+ "of its window, and until it is, nothing in it runs: no run or debug "
						+ "configuration, no build, no devcontainer, no language server, no "
						+ "terminal in its directory, and none of the environment its files "
						+ "ask for. Reading it is unaffected."
					: "Trust is remembered by folder, in this app's own support directory and "
						+ "never inside the project — a project that could grant itself trust "
						+ "would be the whole hole. A folder trusted with everything under it "
						+ "covers every checkout inside it.",
				rows: folders.map { folder in
					.button(
						title: Project.abbreviate(URL(fileURLWithPath: folder.path))
							+ (folder.coversChildren ? " and everything in it" : ""),
						label: "Withdraw",
						action: {
							ProjectTrust.shared.withdraw(path: folder.path)
							// Every window says what it now is: a project whose
							// trust has just gone is untrusted while it is open.
							for controller in NSApp.windows.compactMap({
								$0.windowController as? MainWindowController
							}) {
								controller.refreshTrustBanner()
							}
						}
					)
				}
			),
		]
		let remotes = ProjectTrust.shared.remotes.sorted { $0.said < $1.said }
		if !remotes.isEmpty {
			rows.append(.group(
				title: "Trusted remotes",
				help: "Every clone that says it came from one of these is trusted. Weaker than a "
					+ "folder, deliberately: a repository's remote is what its own .git/config "
					+ "claims, so this trusts anything that claims to come from there. Worth it "
					+ "for a server nobody outside your company can reach, or for one "
					+ "organisation — never for the whole of github.com.",
				rows: remotes.map { remote in
					.button(title: remote.said, label: "Withdraw", action: {
						ProjectTrust.shared.withdraw(remoteHost: remote.host, owner: remote.owner)
						for controller in NSApp.windows.compactMap({
							$0.windowController as? MainWindowController
						}) {
							controller.refreshTrustBanner()
						}
					})
				}
			))
		}
		rows.append(.group(
			title: "What trust means",
			help: "Trusting a project lets it run on this machine — its configurations, its "
				+ "build and test commands, its devcontainer, the language servers its tree "
				+ "provides, the environment its files ask for, a terminal in its directory "
				+ "and its git hooks. It is not a sandbox: a trusted project's build does what "
				+ "builds do. Trust a project only if you would run its code from a terminal "
				+ "yourself.",
			rows: []
		))
		return rows
	}

	static func gitRows() -> [Row] {
		[
			.toggle(
				title: "Draft conventional commit messages",
				help: "The Draft button asks for a Conventional Commits subject — "
					+ "feat(scope): …, fix:, refactor: and the rest — which is the format "
					+ "changelog and release tooling reads. Off, it asks for a message in "
					+ "this repository's own voice, seeded by its recent subjects.",
				get: { Settings.shared.conventionalCommitDrafts },
				set: { Settings.shared.conventionalCommitDrafts = $0 }
			),
			.toggle(
				title: "Rebase when pulling",
				help: "Your commits are replayed on top rather than merged, so the history stays "
					+ "a line. A repository with pull.rebase in its own config overrules this and "
					+ "says so in the dialog.",
				get: { Settings.shared.pullRebases },
				set: { Settings.shared.pullRebases = $0 }
			),
			.toggle(
				title: "Stash and reapply when pulling",
				help: "Puts the working copy aside for the pull and back afterwards, rather than "
					+ "stopping to tell you it is in the way.",
				get: { Settings.shared.pullStashes },
				set: { Settings.shared.pullStashes = $0 }
			),
			.slider(
				title: "Keep backups for",
				help: "Anything that could lose work leaves a branch under backup/ first. A ref "
					+ "holds its commits against gc, which is the point of it and the cost. Zero "
					+ "keeps them for ever.",
				range: 0...180, step: 1,
				format: { $0 < 1 ? "for ever" : String(format: "%.0f days", $0) },
				get: { Double(Settings.shared.backupsKeptDays) },
				set: { Settings.shared.backupsKeptDays = Int($0) }
			),
		]
	}

	static func navigatorRows() -> [Row] {
		[
			.toggle(
				title: "Open projects in a new window",
				help: "Off, choosing another project changes this window. On, it opens beside it.",
				get: { Settings.shared.opensProjectsInNewWindow },
				set: { Settings.shared.opensProjectsInNewWindow = $0 }
			),
			.toggle(
				title: "Show hidden files",
				help: "Files and folders beginning with a dot.",
				get: { Settings.shared.showHiddenFiles },
				set: { Settings.shared.showHiddenFiles = $0 }
			),
			.text(
				title: "Excluded folders",
				help: "Comma-separated. Tinted as build output. Press Return to apply.",
				get: { Settings.shared.excludedDirectories.joined(separator: ", ") },
				set: { value in
					Settings.shared.excludedDirectories = value
						.components(separatedBy: ",")
						.map { $0.trimmingCharacters(in: .whitespaces) }
						.filter { !$0.isEmpty }
				}
			),
			.button(title: "", label: "Restore Defaults") {
				Settings.shared.resetToDefaults()
			},
		]
	}
}
