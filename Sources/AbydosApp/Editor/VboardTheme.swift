import AppKit

/// The colours a board tab hands vboard, so its page sits in this app's theme.
enum VboardTheme {
	/// vboard's colours from this app's theme: its grounds from the editor's,
	/// its navy from the selection, and its blues from the accent.
	static func tokens(_ theme: Theme) -> [String: String] {
		let accent = theme.caret.css
		return [
			"--background": theme.editorBackground.css,
			"--foreground": theme.editorText.css,
			"--muted-foreground": theme.gitIgnored.css,
			"--dialog-background": theme.sidebarBackground.css,
			"--popover": theme.sidebarBackground.css,
			"--popover-foreground": theme.editorText.css,
			"--card": theme.sidebarBackground.css,
			"--accent": theme.currentLineBackground.css,
			"--border": theme.separator.css,
			"--ring": accent,
			"--interactive-border": accent,
			"--hyperlink": accent,
			"--v-brand-blue-200": accent,
			"--v-brand-blue-400": accent,
			"--vb-canvas": theme.editorBackground.css,
			"--vb-grid-dot": theme.indentGuide.css,
			"--vb-frame-surface": theme.sidebarBackground.css,
			"--vb-frame-surface-alt": theme.toolbarBackground.css,
			"--vb-frame-border": theme.separator.css,
			"--vb-frame-title": theme.sidebarText.css,
			"--vb-shape-fill": theme.sidebarBackground.css,
			"--vb-navy": theme.selectionActive.css,
			"--vb-navy-80": theme.selectionActive.css,
			"--vb-logo-bg": theme.selectionActive.css,
			"--vb-notice-bg": theme.selectionActive.css,
			"--vb-notice-text": theme.editorText.css,
			"--vb-notice-border": theme.separator.css,
			"--vb-access-public": accent,
			"--vb-chart": accent,
			// The classic design paints from its own palette, not the names above;
			// they are the same colours under the names it reads.
			"--bg": theme.editorBackground.css,
			"--canvas": theme.editorBackground.css,
			"--surface": theme.sidebarBackground.css,
			"--surface-2": theme.toolbarBackground.css,
			"--grid-dot": theme.indentGuide.css,
			"--text": theme.editorText.css,
			"--text-muted": theme.gitIgnored.css,
			"--text-faint": theme.gitIgnored.css,
			"--border-strong": theme.separator.css,
			"--hover": theme.currentLineBackground.css,
			"--frame-surface": theme.sidebarBackground.css,
			"--frame-surface-alt": theme.toolbarBackground.css,
			"--frame-border": theme.separator.css,
			"--frame-title": theme.sidebarText.css,
			"--shape-fill": theme.sidebarBackground.css,
			"--navy": theme.selectionActive.css,
			"--navy-80": theme.selectionActive.css,
			"--strong-bg": theme.selectionActive.css,
			"--strong-bg-2": theme.selectionActive.css,
			"--logo-bg": theme.selectionActive.css,
			"--indigo-soft": theme.selectionActive.css,
			"--notice-bg": theme.selectionActive.css,
			"--notice-text": theme.editorText.css,
			"--notice-border": theme.separator.css,
			"--indigo": accent,
			"--indigo-dark": accent,
			"--indigo-text": accent,
			"--selection": accent,
			"--chart-1": accent,
		]
	}
}

private extension NSColor {
	/// The colour as CSS, in sRGB, with its alpha.
	var css: String {
		let c = usingColorSpace(.sRGB) ?? self
		let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
		return c.alphaComponent < 1
			? String(format: "rgba(%d, %d, %d, %.3f)", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent), c.alphaComponent)
			: String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
	}
}
