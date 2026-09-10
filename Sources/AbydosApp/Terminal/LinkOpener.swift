import AppKit

/// Hands an address to the browser — or, on a driven run, says that it would.
///
/// **A driven run never opens a browser.** The run that proves ⌘-click opens the
/// right address would otherwise open forty tabs on the machine it runs on, and
/// the apply step of the compare page is refused on a driven run for the same
/// shape of reason. What is printed is the claim: the address, exactly as the
/// click would have handed it over.
@MainActor
enum LinkOpener {
	/// What a driven run was asked to open, in order.
	static var openedForTesting: [URL] = []

	static func open(_ url: URL) {
		guard !LaunchOptions.parse().isDrivenRun else {
			openedForTesting.append(url)
			print("LINK would open \(url.absoluteString)")
			fflush(stdout)
			return
		}
		NSWorkspace.shared.open(url)
	}
}
