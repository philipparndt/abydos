import AppKit
import AbydosKit

/// `abydos://compare?a=…&b=…`: the compare page, asked for from a terminal
/// that is not one of this app's own.
///
/// Its own file rather than a method in the delegate, which is at its recorded
/// length: the delegate routes the URL here and this decides what it means.
extension AppDelegate {
	/// Opens the compare page a URL asks for, in the front window or one on
	/// whatever encloses the first path.
	func openCompareURL(_ url: URL) {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.host == "compare",
		      let a = components.queryItems?.first(where: { $0.name == "a" })?.value,
		      let b = components.queryItems?.first(where: { $0.name == "b" })?.value,
		      a.hasPrefix("/"), b.hasPrefix("/")
		else { return }
		let left = URL(fileURLWithPath: a).standardizedFileURL
		let right = URL(fileURLWithPath: b).standardizedFileURL
		let controller = frontmostController ?? open(projectAt: Project.root(containing: left))
		controller.window?.makeKeyAndOrderFront(nil)
		controller.openComparePage(left: ComparePage.source(for: left), right: ComparePage.source(for: right))
	}

}
