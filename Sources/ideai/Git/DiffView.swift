import AppKit
import IdeaiKit

/// A unified diff, rendered as coloured lines.
///
/// Hand-drawn like the code view rather than built on `NSTextView`: a diff is a
/// list of short lines with one colour each, and the same virtualised drawing
/// keeps a large one — a lockfile, a generated file — instant to open.
final class DiffView: NSView {
	private var lines: [Line] = []
	private var isStaged = false

	private struct Line {
		enum Kind { case added, removed, hunk, meta, context }
		let text: String
		let kind: Kind
	}

	private var font: NSFont = Theme.terminalFont(size: Theme.current.fontSize)
	private var lineHeight: CGFloat = 0
	private static let horizontalInset: CGFloat = 12

	override var isFlipped: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		lineHeight = (font.ascender - font.descender + font.leading).rounded() + 2
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	func setDiff(_ text: String, staged: Bool) {
		isStaged = staged
		lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
			let line = String(raw)
			return Line(text: line, kind: kind(of: line))
		}
		// A diff that is entirely header is a file with no textual changes —
		// a permission bit, or a binary file.
		if lines.allSatisfy({ $0.kind == .meta }) {
			lines.append(Line(text: "", kind: .context))
			lines.append(Line(text: "No textual changes.", kind: .context))
		}
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	private func kind(of line: String) -> Line.Kind {
		// Order matters: "+++" and "---" are headers, not content, and testing
		// for the single character first would colour them as changes.
		if line.hasPrefix("+++") || line.hasPrefix("---") { return .meta }
		if line.hasPrefix("@@") { return .hunk }
		if line.hasPrefix("diff ") || line.hasPrefix("index ")
			|| line.hasPrefix("new file") || line.hasPrefix("deleted file")
			|| line.hasPrefix("similarity ") || line.hasPrefix("rename ")
			|| line.hasPrefix("old mode") || line.hasPrefix("new mode")
			|| line.hasPrefix("Binary files") {
			return .meta
		}
		if line.hasPrefix("+") { return .added }
		if line.hasPrefix("-") { return .removed }
		return .context
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: max(CGFloat(lines.count) * lineHeight + Theme.current.scaled(16), 10)
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let top = Theme.current.scaled(8)
		// Only the rows in view are laid out, which is what keeps a huge diff
		// as cheap to scroll as a small one.
		let first = max(0, Int((dirtyRect.minY - top) / lineHeight))
		let last = min(lines.count, Int((dirtyRect.maxY - top) / lineHeight) + 1)
		guard last > first else { return }

		for index in first..<last {
			let line = lines[index]
			let y = top + CGFloat(index) * lineHeight

			if let background = background(for: line.kind) {
				background.setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			}

			guard !line.text.isEmpty else { continue }
			NSAttributedString(string: line.text, attributes: [
				.font: line.kind == .hunk
					? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
					: font,
				.foregroundColor: color(for: line.kind),
			]).draw(at: NSPoint(x: Self.horizontalInset, y: y))
		}
	}

	private func background(for kind: Line.Kind) -> NSColor? {
		switch kind {
		case .added:   return Theme.current.gitAdded.withAlphaComponent(0.13)
		case .removed: return Theme.current.gitUnversioned.withAlphaComponent(0.13)
		case .hunk:    return NSColor.white.withAlphaComponent(0.04)
		default:       return nil
		}
	}

	private func color(for kind: Line.Kind) -> NSColor {
		switch kind {
		case .added:   return Theme.current.gitAdded
		case .removed: return Theme.current.gitUnversioned
		case .hunk:    return Theme.current.gitModified
		case .meta:    return Theme.current.gitIgnored
		case .context: return Theme.current.sidebarText
		}
	}
}
