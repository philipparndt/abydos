import AbydosKit
import AppKit

/// Somewhere to watch a container image arrive.
///
/// `ContainerImageStore.ensure` has always taken two sinks — one sentence before
/// it starts, and the runtime's own output as it arrives — and until 0459 only
/// the devcontainer path passed the second. Everything else passed the sentence
/// alone, so choosing to build a language server on this machine showed one
/// toast and then nothing at all for the 164 seconds `rust-analyzer` takes cold.
/// Minutes of silence after a toast is indistinguishable from a feature that did
/// not work, which is the sentence that was already written over the toast this
/// replaces — written about a *pull*, which is seconds, and applied to a build,
/// which is not.
///
/// What this does is route an existing pane at an existing stream.
/// `PreparingTerminal` is the view: a tab that opens without taking the
/// keyboard and has the work written into it. The terms are the ones 0444
/// settled for a devcontainer coming up, taken rather than made again, because a
/// first build and a first container start are the same wait for the same
/// reason — **it never takes the keyboard**, the panel opens only if the work is
/// still going after three seconds, and a wait nobody could have watched takes
/// its tab away with it.
///
/// **The pane is made at the first sentence rather than when the image is asked
/// for**, and that is the one place this differs from the devcontainer route.
/// It is also the answer to "does every image get a pane": `ensure` says nothing
/// at all when the image is already on the machine, which is every use after the
/// first, so a tab made before asking would be a tab made and thrown away on
/// every project open and every diagram. The sentence is the runtime admitting
/// it has minutes of work; that is the moment there is something to watch.
@MainActor
final class ImageArrival {
	/// The tool the image carries, which is what a tab can be named after.
	/// `abydos-built/rust-analyzer:9f1c…` is not a tab title.
	private let tool: String
	/// Whether this is a build rather than a fetch, which changes every word:
	/// somebody told "fetching" during a four-minute build concludes their
	/// network is broken, which is the reason `ToolImageRecipes` has a sentence
	/// of its own.
	private let isBuild: Bool
	/// The project whose window the tab belongs in.
	private let project: URL?
	private var preparing: PreparingTerminal?
	/// Whether a pane has been asked for, which is not the same as having one:
	/// nil is an ordinary answer — no window is showing this project — and
	/// without this it would be asked for again on every line of output.
	private var asked = false

	/// Nothing here touches a window, and the callers are not all on the main
	/// actor — an export runs from wherever the menu item's task landed. What is
	/// on the main actor is everything this does *afterwards*.
	nonisolated init(image: String, tool: String, project: URL?) {
		self.tool = tool
		self.isBuild = ToolImageRecipes.isBuiltHere(image)
		self.project = project
	}

	/// What the tab is called. It says which of the two this is, because that is
	/// the difference between seconds and minutes and it is the one thing
	/// somebody glancing at a tab strip wants to know.
	nonisolated var tabTitle: String { isBuild ? "Building \(tool)" : "Fetching \(tool)" }

	/// The sinks to hand `ContainerImageStore.ensure`, and to whatever gets an
	/// image in the middle of a longer job.
	///
	/// Taken from anywhere, because that is where they are wanted: these are
	/// called on the threads reading the runtime's pipes, and the hop to the main
	/// one is inside each of them.
	///
	/// **They hold this object rather than a weak reference to it**, which is the
	/// opposite of what a closure on a view would do and is right here: a caller
	/// hands these to `ensure` and then has nothing more to do with the arrival
	/// until it is over, so a weak capture would mean the object had gone by the
	/// time the first sentence arrived and no pane would ever be made. There is
	/// no cycle to worry about — nothing this holds holds it back, and the
	/// closures die with the fetch that was given them.
	nonisolated var watch: ImageWatch {
		ImageWatch(
			// All three hop to the main thread through the main *queue* rather
			// than through a task, for `PreparingTerminal.progress`'s reason: they
			// arrive in an order that means something — the sentence, then what it
			// printed, then how it ended — and unstructured tasks hopping to the
			// main actor are not promised to run in the order they were made.
			step: { message in
				DispatchQueue.main.async { MainActor.assumeIsolated { self.begin(saying: message) } }
			},
			output: { text in
				DispatchQueue.main.async {
					MainActor.assumeIsolated { self.preparing?.output(text) }
				}
			},
			settled: { reason in
				DispatchQueue.main.async {
					MainActor.assumeIsolated {
						if let reason { self.failed(reason) } else { self.arrived() }
					}
				}
			}
		)
	}

	/// The image is here.
	///
	/// Nothing is said out loud. A tool that is ready is the ordinary case, and
	/// the pane — if anybody was shown one — keeps what the build printed with
	/// one green line under it.
	func arrived() {
		preparing?.finish(isBuild
			? "\(tool) is built. Nothing else will build it until its recipe changes."
			: "\(tool) is here.")
		preparing = nil
	}

	/// It did not arrive, and this is why.
	///
	/// **The pane is where the output is and the toast points at it**, which is
	/// the decision 0444 recorded and this takes. It differs in one way and
	/// deliberately: the sentence goes in the toast as well, because
	/// `ToolImageRecipes.explain` produces a *diagnosis* — the runtime is not
	/// running, the network was not there, the registry refused the base image,
	/// there was no room — and not a summary of the log. Somebody who reads "there
	/// was no room to build rust-analyzer" is finished; the tab is for the fifth
	/// case, where the recipe itself failed and the answer is one line somewhere
	/// in a hundred of compiler output.
	/// - Returns: the tab holding that output, when there is one, so the caller's
	///   toast can name it.
	@discardableResult
	func failed(_ reason: String) -> String? {
		defer { preparing = nil }
		// Never `refuse` into a pane that has gone: with no pane it posts a toast
		// of its own about a devcontainer, and every caller here posts its own.
		guard let preparing, preparing.isOpen else { return nil }
		preparing.refuse(reason)
		return tabTitle
	}

	/// The first sentence, which is also the moment a pane is worth having.
	private func begin(saying message: String) {
		guard !asked else {
			preparing?.step(message)
			return
		}
		asked = true
		guard let project, let watching = MainWindowController.watchImageArriving(
			project: project, title: tabTitle, subject: tool
		) else {
			// No window is showing this project, which happens: `warmUp` runs while
			// one is still being built, and an export can outlive the window that
			// asked for it. Then it is the toast that was there before.
			Toast.post(message, kind: .information)
			return
		}
		preparing = watching
		watching.step(message)
	}
}
