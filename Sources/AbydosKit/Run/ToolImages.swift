import Foundation

/// Which container image provides which tool.
///
/// Two places say so, for two different reasons.
///
/// A project says it in `.abydos/tools.json`, and that is a statement about the
/// project: these diagrams are drawn by that version of PlantUML, this code is
/// understood by that language server. It is checked in, so everybody working
/// on it gets the same answers, and a machine that has never installed the tool
/// works anyway.
///
/// Settings say it for one person across every project — somebody who would
/// rather not install a Java toolchain at all, and is happy for anything that
/// needs one to arrive in an image.
///
/// The file wins where both speak: the project knows what it needs, and a
/// personal default should not quietly change what a checked-in diagram looks
/// like.
public struct ToolImages: Equatable, Sendable {
	/// Tool name to image, as `docker pull` would name it.
	public let images: [String: String]

	public init(images: [String: String] = [:]) {
		self.images = images
	}

	public func image(for tool: String) -> String? { images[tool] }

	public var isEmpty: Bool { images.isEmpty }

	/// Where a project keeps it.
	public static func url(in root: URL) -> URL {
		AbydosFolder.url(in: root).appendingPathComponent("tools.json")
	}

	/// What a project asks for, or nothing when it asks for nothing.
	///
	/// A file that cannot be read is the same as no file: a broken one should
	/// not stop the project opening, and the pane that wanted the tool says
	/// plainly that there is none.
	public static func inProject(_ root: URL) -> ToolImages {
		guard let data = try? Data(contentsOf: url(in: root)) else { return ToolImages() }
		return parse(data)
	}

	/// Reads either shape:
	///
	///     { "plantuml": "plantuml/plantuml:1.2025.4" }
	///     { "plantuml": { "image": "plantuml/plantuml:1.2025.4" } }
	///
	/// The second because a tool will want more said about it than its image —
	/// a command, a mount — and a file written today should still parse then.
	public static func parse(_ data: Data) -> ToolImages {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return ToolImages()
		}

		var found: [String: String] = [:]
		for (tool, value) in root {
			// The other question this file answers — which server a language uses
			// — lives under a name of its own, and its keys are language ids
			// rather than tool names. Skipped by that name rather than left to
			// fall through the shapes below, because `plantuml` is both a tool
			// that comes from an image and a language a server answers for, and a
			// reader that told them apart by shape would one day get it wrong.
			guard tool != LanguageServerChoices.section else { continue }
			if let image = value as? String, !image.isEmpty {
				found[tool] = image
			} else if let table = value as? [String: Any],
			          let image = table["image"] as? String, !image.isEmpty {
				found[tool] = image
			}
		}
		return ToolImages(images: found)
	}

	/// The project's answers over the ones set for everything.
	public static func resolve(project: ToolImages, settings: ToolImages) -> ToolImages {
		ToolImages(images: settings.images.merging(project.images) { _, fromProject in fromProject })
	}
}
