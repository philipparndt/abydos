import AppKit

/// The small coloured square carrying a project's initials.
enum ProjectBadge {
	/// IDEA's project-badge palette. Imported entries carry an
	/// `associatedIndex` from `RecentProjectColorInfo`, so a project keeps the
	/// colour the user already recognises it by.
	static let palette: [NSColor] = [
		.hex(0xA0A648), // olive
		.hex(0x4EA5A0), // teal
		.hex(0x5C73D8), // indigo
		.hex(0xB58A2B), // amber
		.hex(0xD97A6C), // salmon
		.hex(0x5AA469), // green
		.hex(0x4A8FC7), // steel blue
		.hex(0x9B6FD0), // purple
		.hex(0xC264B8), // magenta
		.hex(0xCB5F4D), // red
	]

	/// Derives initials the way IDEA does: the first letter of each of the first
	/// two separator-delimited components, so `mqtt-homekit` reads as "MH" and
	/// `basketr` as "B".
	static func initials(for name: String) -> String {
		let components = name
			.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
			.filter { !$0.isEmpty }

		guard let first = components.first else {
			return String(name.prefix(1)).uppercased()
		}
		if components.count >= 2, let second = components.dropFirst().first {
			return (String(first.prefix(1)) + String(second.prefix(1))).uppercased()
		}
		return String(first.prefix(1)).uppercased()
	}

	/// Falls back to a stable hash so a project without an imported index still
	/// gets a consistent colour across launches.
	static func color(for name: String, colorIndex: Int?) -> NSColor {
		if let index = colorIndex, index >= 0 {
			return palette[index % palette.count]
		}
		var hash: UInt64 = 5381
		for byte in name.utf8 {
			hash = (hash &* 33) &+ UInt64(byte)
		}
		return palette[Int(hash % UInt64(palette.count))]
	}

	/// Renders the badge once into an image; drawing text per-frame in a cell
	/// would be wasteful for something that never changes.
	static func image(for name: String, colorIndex: Int?, size: CGFloat = 18) -> NSImage {
		let text = initials(for: name)
		let color = color(for: name, colorIndex: colorIndex)

		let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
			let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.28, yRadius: size * 0.28)
			color.setFill()
			path.fill()

			// Size the glyphs to the count so two letters still fit legibly.
			let fontSize = text.count > 1 ? size * 0.46 : size * 0.56
			let attributes: [NSAttributedString.Key: Any] = [
				.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
				.foregroundColor: NSColor.white.withAlphaComponent(0.95),
			]
			let attributed = NSAttributedString(string: text, attributes: attributes)
			let textSize = attributed.size()
			attributed.draw(at: NSPoint(
				x: rect.midX - textSize.width / 2,
				y: rect.midY - textSize.height / 2
			))
			return true
		}
		return image
	}
}
