import AppKit
import AbydosKit

/// The verbs about more than one window: a second one opened, a terminal walked
/// into the other's project, a tmux client sent to the other's session, File ▸
/// New Window's list. See `project-windows`.
///
/// Every tmux these reach is whatever `tmux` the run's `PATH` finds first, so a
/// run that is not to touch somebody's server puts a shim there that names a
/// scratch one — `-f /dev/null -S <socket>` — and never the bare command.
extension AppDelegate {
	@MainActor
	func driveTheWindows(_ options: LaunchOptions) {
		if let path = options.secondWindow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
				let opened = self.openInNewWindow(projectAt: url, attachingTo: options.secondWindowSession)
				print("SECOND WINDOW on \(opened.project?.name ?? "nothing"); \(self.windowsForTesting)")
				fflush(stdout)
			}
		}

		if let path = options.walkInto {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
				guard let walking = self.windowControllers.last else { return }
				let before = walking.project?.name ?? "nothing"
				let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
				walking.follow(reported: url)
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					print("WALKED the window on \(before) into \(url.lastPathComponent): "
						+ "it is on \(walking.project?.name ?? "nothing"); \(self.windowsForTesting)")
					print("SAID \(walking.toasts.saidForTesting.last ?? "nothing")")
					fflush(stdout)
				}
			}
		}

		if let targets = options.switchClient {
			// One or several, comma-separated, four seconds apart: a second
			// `C-b w` after the first has been answered.
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
				self.reportTmuxForTesting("before")
				Task { @MainActor in
					for target in targets.split(separator: ",").map(String.init) {
						guard let panel = self.windowControllers.last?.bottomPanel, let tty = panel.tmuxClientTTY else {
							print("SWITCH-CLIENT: the last window has no tmux client")
							break
						}
						await TmuxMirror.switchClient(onTTY: tty, to: target)
						print("SWITCH-CLIENT \(target)")
						try? await Task.sleep(nanoseconds: 3_000_000_000)
						self.reportTmuxForTesting("after \(target)")
						try? await Task.sleep(nanoseconds: 1_000_000_000)
					}
					fflush(stdout)
				}
			}
		}

		if options.newWindowPicker {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				self.newWindow(nil)
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
					for row in ProjectSwitcherPopover.rowsForTesting() { print("PICKER \(row)") }
					fflush(stdout)
				}
			}
		}
	}
}
