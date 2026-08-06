import AppKit
import CoreText

/// Registers the fonts shipped inside the app bundle.
///
/// Bundling rather than relying on what the user has installed: prompt themes
/// like starship and powerlevel10k draw their separators with Private Use Area
/// glyphs, and on a machine without a Nerd Font those render as empty boxes.
/// Ghostty ships a font for exactly this reason.
///
/// Registration is process-scoped, so nothing is installed system-wide and
/// nothing is left behind when the app quits.
///
/// JetBrains Mono is SIL OFL 1.1, which permits bundling and redistribution,
/// and declares no Reserved Font Name — so it ships unmodified under its own
/// name with no further obligation beyond including the licence.
enum FontRegistry {
	/// Family name of the bundled font, once registered.
	static let bundledMonospaceFamily = "JetBrainsMono NFM"

	private static var didRegister = false

	static func registerBundledFonts() {
		guard !didRegister else { return }
		didRegister = true

		for url in fontURLs() {
			var error: Unmanaged<CFError>?
			// Failure is not fatal — the cascade to an installed Nerd Font, and
			// ultimately to the system monospace font, still applies.
			if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
				let description = error?.takeRetainedValue().localizedDescription ?? "unknown error"
				FileHandle.standardError.write(
					Data("font registration failed for \(url.lastPathComponent): \(description)\n".utf8)
				)
			}
		}
	}

	/// True once the bundled family is actually usable.
	///
	/// Tested by instantiating it, not by searching `availableFontFamilies`:
	/// that list is not updated for process-scoped registrations, so it reports
	/// the font as missing even when it works perfectly.
	static var isBundledFontAvailable: Bool {
		NSFont(name: bundledMonospaceFamily, size: 12) != nil
	}

	private static func fontURLs() -> [URL] {
		var directories: [URL] = []

		// Packaged app.
		if let resources = Bundle.main.resourceURL {
			directories.append(resources.appendingPathComponent("Fonts", isDirectory: true))
		}
		// Running straight from the build directory during development, where the
		// binary sits in .build and the fonts are still in the source tree.
		let sourceRelative = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()   // ideai
			.deletingLastPathComponent()   // Sources
			.deletingLastPathComponent()   // repo root
			.appendingPathComponent("Resources/Fonts", isDirectory: true)
		directories.append(sourceRelative)

		for directory in directories {
			guard let contents = try? FileManager.default.contentsOfDirectory(
				at: directory,
				includingPropertiesForKeys: nil
			) else { continue }

			let fonts = contents.filter { $0.pathExtension.lowercased() == "ttf" }
			if !fonts.isEmpty { return fonts }
		}
		return []
	}
}
