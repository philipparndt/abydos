import AppKit
import AbydosKit

/// Icons for tree rows.
///
/// Rendered from SF Symbols with a per-type tint rather than pulled from
/// `NSWorkspace`: Finder's icons are photographic and inconsistent at 16pt,
/// while a flat tinted glyph set stays legible and matches the theme.
enum FileIcon {
	private struct Spec {
		let symbol: String
		let color: NSColor
	}

	/// Keyed by spec *and* scale, so zooming does not serve stale small icons.
	private static var cache: [String: NSImage] = [:]

	/// The folder being worked on: the same glyph, in the colour the app uses
	/// for the thing in hand.
	static func subprojectFolder() -> NSImage? {
		render(key: "dir.subproject", spec: Spec(symbol: "folder.fill", color: .hex(0x6B9BD8)))
	}

	/// The plain folder glyph, for a tree whose rows are not `FileNode`s.
	///
	/// The changes pane's folders are made up out of the paths git reported and
	/// have no node behind them; a folder there that did not look like a folder
	/// in the navigator would be two ideas about the same thing in one window.
	static func folder() -> NSImage? {
		render(key: "dir", spec: Spec(symbol: "folder.fill", color: .hex(0x8A9099)))
	}

	/// The Dependencies section itself. IntelliJ's *External Libraries* uses a
	/// shelf of books for the same row, and it reads as "not your files" in a
	/// way no variation on a folder does.
	static func dependencySection() -> NSImage? {
		render(key: "dep.section", spec: Spec(symbol: "books.vertical.fill", color: .hex(0x8A9099)))
	}

	/// One package. Dimmed when its sources were never fetched — the row is
	/// still worth having, because "resolved and not downloaded" is a real
	/// state and a package missing from the list would read as one nothing
	/// depends on.
	static func dependencyPackage(fetched: Bool) -> NSImage? {
		render(
			key: fetched ? "dep.package" : "dep.package.absent",
			spec: Spec(symbol: "shippingbox.fill", color: .hex(fetched ? 0x9B8FD0 : 0x6A6E75))
		)
	}

	/// A compiler's or an SDK's own sources. Deliberately not the package box:
	/// the row sits among packages and is not one, and that difference is the
	/// whole reason it exists — nothing in this project declared these.
	static func dependencyToolchain() -> NSImage? {
		render(key: "dep.toolchain", spec: Spec(symbol: "hammer.fill", color: .hex(0x5FA8A0)))
	}

	/// A kind nothing reads yet. A question rather than a warning: nothing is
	/// wrong with the project, there is something missing from this program.
	static func dependencyNote() -> NSImage? {
		render(key: "dep.note", spec: Spec(symbol: "questionmark.circle", color: .hex(0xC7A03B)))
	}

	/// The Claude Sessions root. A clock rather than a folder or a shelf: what
	/// is under it is sorted by when, and every row of it is something that
	/// happened rather than something the project is made from.
	static func sessionSection() -> NSImage? {
		render(key: "session.section", spec: Spec(symbol: "clock.arrow.circlepath", color: .hex(0x8A9099)))
	}

	/// One session. Deliberately not the package box and not a folder: the row
	/// is a conversation that left files behind, and the files are underneath.
	static func session() -> NSImage? {
		render(key: "session.one", spec: Spec(symbol: "bubble.left.and.text.bubble.right", color: .hex(0xC08A5E)))
	}

	static func image(for node: FileNode, isExpanded: Bool) -> NSImage? {
		let key: String
		let spec: Spec

		if node.isDirectory {
			// One folder glyph regardless of state: IDEA signals expansion with
			// the disclosure triangle, not by swapping the icon. Excluded output
			// directories get the same orange IDEA marks them with.
			guard node.isExcluded else { return folder() }
			return render(key: "dir.excluded", spec: Spec(symbol: "folder.fill", color: .hex(0xC77B3B)))
		} else {
			let ext = node.url.pathExtension.lowercased()
			let file = specification(forExtension: ext, filename: node.name.lowercased())

			// A scratch belonging to no project keeps its glyph and changes its
			// colour. In a strip of tabs it is the one file that is not part of
			// what is being worked on, and a note meant to outlive this checkout
			// is easy to mistake for one of its files when the two look alike.
			if ScratchFiles.global().contains(node.url) {
				key = "file.global-scratch.\(ext)"
				spec = Spec(symbol: file.symbol, color: .hex(0x9B6FD0))
			} else {
				key = "file.\(ext)"
				spec = file
			}
		}

		return render(key: key, spec: spec)
	}

	/// Rendered through `Theme.symbol`, so a row's icon obeys the same optical
	/// weight as every other symbol in the window: at 2× a fixed `.regular`
	/// makes `text.alignleft` four thick bars rather than four lines of text,
	/// and a folder of markdown becomes a column of blue dashes beside the tree.
	private static func render(key: String, spec: Spec) -> NSImage? {
		let scale = Theme.current.scale
		let scaledKey = "\(key)@\(scale)"
		if let cached = cache[scaledKey] { return cached }
		guard let image = Theme.symbol(spec.symbol, size: 13 * scale, color: spec.color) else {
			return nil
		}
		cache[scaledKey] = image
		return image
	}

	private static func specification(forExtension ext: String, filename: String) -> Spec {
		// Well-known filenames first — they read better than their extension.
		switch filename {
		case "package.json", "package-lock.json":
			return Spec(symbol: "shippingbox.fill", color: .hex(0xCB3837))
		case "dockerfile", "docker-compose.yml", "docker-compose.yaml":
			return Spec(symbol: "shippingbox.fill", color: .hex(0x2496ED))
		case "makefile":
			return Spec(symbol: "hammer.fill", color: .hex(0x9AA0A6))
		case ".gitignore", ".gitattributes":
			return Spec(symbol: "nosign", color: .hex(0x7A7E85))
		case "license", "license.md", "license.txt":
			return Spec(symbol: "text.justify.left", color: .hex(0x9AA0A6))
		case "readme.md":
			return Spec(symbol: "arrow.down.doc.fill", color: .hex(0x4C7EE0))
		default:
			break
		}

		switch ext {
		// Source
		case "swift":                return Spec(symbol: "swift", color: .hex(0xF05138))
		case "rs":                   return Spec(symbol: "gearshape.fill", color: .hex(0xCE8B5A))
		case "ts", "tsx":            return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0x3178C6))
		case "js", "jsx", "mjs", "cjs":
			return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0xF7DF1E))
		case "py":                   return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0x4B8BBE))
		case "go":                   return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0x00ADD8))
		case "java", "kt", "kts":    return Spec(symbol: "cup.and.saucer.fill", color: .hex(0xE8BF6A))
		case "c", "h":               return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0x6E9ECF))
		case "cpp", "cc", "hpp", "cxx":
			return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0x9B6FD0))
		// Odin's own blue, and Zig's orange: a project of either is all one
		// extension, so the icon is what tells the tree apart at a glance.
		case "odin":                 return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0x3882D2))
		case "zig", "zon":           return Spec(symbol: "chevron.left.forwardslash.chevron.right", color: .hex(0xF7A41D))
		case "svelte":               return Spec(symbol: "flame.fill", color: .hex(0xFF3E00))
		case "sh", "bash", "zsh":    return Spec(symbol: "terminal.fill", color: .hex(0x6AAB73))

		// 3D / CAD — prominent in this user's projects
		case "scad":                 return Spec(symbol: "cube.fill", color: .hex(0xE8BF6A))
		case "stl", "3mf", "obj", "step", "stp":
			return Spec(symbol: "cube.transparent", color: .hex(0x9AA0A6))
		case "gcode":                return Spec(symbol: "scribble", color: .hex(0x5AA469))

		// Data / config
		case "json":                 return Spec(symbol: "curlybraces", color: .hex(0xB58A2B))
		case "yaml", "yml":          return Spec(symbol: "list.bullet.indent", color: .hex(0xC77DBB))
		case "toml", "ini", "cfg", "conf", "properties", "env":
			return Spec(symbol: "slider.horizontal.3", color: .hex(0x9AA0A6))
		case "xml", "plist":         return Spec(symbol: "chevron.left.slash.chevron.right", color: .hex(0xE07B53))
		case "sql":                  return Spec(symbol: "cylinder.split.1x2.fill", color: .hex(0x4EA5A0))

		// Markup / docs
		case "md", "markdown":       return Spec(symbol: "text.alignleft", color: .hex(0x4C7EE0))
		case "html", "htm":          return Spec(symbol: "chevron.left.slash.chevron.right", color: .hex(0xE34F26))
		case "css", "scss", "sass":  return Spec(symbol: "paintbrush.fill", color: .hex(0x2965F1))
		case "txt", "log":           return Spec(symbol: "doc.text", color: .hex(0x9AA0A6))
		case "pdf":                  return Spec(symbol: "doc.richtext.fill", color: .hex(0xCB5F4D))

		// Media
		case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic":
			return Spec(symbol: "photo.fill", color: .hex(0x5AA469))
		case "mp4", "mov", "avi":    return Spec(symbol: "film.fill", color: .hex(0x9B6FD0))
		case "mp3", "wav", "flac":   return Spec(symbol: "music.note", color: .hex(0xC264B8))
		case "zip", "gz", "tar", "7z":
			return Spec(symbol: "archivebox.fill", color: .hex(0xB58A2B))

		default:
			return Spec(symbol: "doc", color: .hex(0x9AA0A6))
		}
	}
}
