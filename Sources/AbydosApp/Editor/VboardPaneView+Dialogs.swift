import AppKit
import WebKit

// MARK: - Downloads and the page's dialogs

/// What the page asks of the app that is not about where it goes: a download,
/// an alert, a file to put on the board. None of it depends on whether the tab
/// is a file's board or a server's.
extension VboardPaneView {
	/// Downloads the page offers — its own `.vboard` download, an export —
	/// go where a browser puts them, never into the project.
	func download(
		_ download: WKDownload,
		decideDestinationUsing response: URLResponse,
		suggestedFilename: String,
		completionHandler: @escaping @MainActor (URL?) -> Void
	) {
		let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		var candidate = folder.appendingPathComponent(suggestedFilename)
		let stem = candidate.deletingPathExtension().lastPathComponent
		let ext = candidate.pathExtension
		var number = 2
		while FileManager.default.fileExists(atPath: candidate.path) {
			candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
			number += 1
		}
		completionHandler(candidate)
	}

	func downloadDidFinish(_ download: WKDownload) {
		Toast.post("Downloaded from the board", detail: "In your Downloads folder.", kind: .information)
	}

	func webView(
		_ webView: WKWebView,
		runJavaScriptAlertPanelWithMessage message: String,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor () -> Void
	) {
		let alert = NSAlert()
		alert.messageText = message
		alert.runModal()
		completionHandler()
	}

	func webView(
		_ webView: WKWebView,
		runJavaScriptConfirmPanelWithMessage message: String,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor (Bool) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = message
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		completionHandler(alert.runModal() == .alertFirstButtonReturn)
	}

	func webView(
		_ webView: WKWebView,
		runJavaScriptTextInputPanelWithPrompt prompt: String,
		defaultText: String?,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor (String?) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = prompt
		let field = NSTextField(string: defaultText ?? "")
		field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
		alert.accessoryView = field
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
	}

	/// A picture or a PDF added to the board from disk.
	func webView(
		_ webView: WKWebView,
		runOpenPanelWith parameters: WKOpenPanelParameters,
		initiatedByFrame frame: WKFrameInfo,
		completionHandler: @escaping @MainActor ([URL]?) -> Void
	) {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = parameters.allowsMultipleSelection
		panel.canChooseDirectories = parameters.allowsDirectories
		panel.canChooseFiles = true
		completionHandler(panel.runModal() == .OK ? panel.urls : nil)
	}
}
