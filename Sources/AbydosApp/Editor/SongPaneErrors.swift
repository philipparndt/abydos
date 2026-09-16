import AppKit
import AbydosKit

/// What went wrong with a render, and what the pane last said about one.
///
/// Its own object for the reason the other halves of the pane are: the pane is
/// at the size a file in this repository may be, and this is state — the last
/// complaint, the diagnostics behind it, and the line the header shows — rather
/// than drawing.
@MainActor
final class SongPaneErrors {
	/// The first line of what `mat` last said, when it failed.
	private(set) var complaint: String?
	/// The errors behind it, for the strip's click.
	private(set) var diagnostics: [SongRender.Diagnostic] = []
	/// What the header was last told about the render, without the song's name
	/// in front of it — which is added or dropped as the file beside it moves.
	var said = ""

	func failed(with complaint: String, diagnostics: [SongRender.Diagnostic]) {
		self.complaint = complaint
		self.diagnostics = diagnostics
	}

	func worked() {
		complaint = nil
		diagnostics = []
	}

	/// The first line, which is what the strip shows.
	var firstLine: String? {
		complaint.map { $0.split(whereSeparator: \.isNewline).first.map(String.init) ?? $0 }
	}

	/// Where the first error is, for a click on the strip.
	var firstPlace: SongRender.Diagnostic? { diagnostics.first }

	/// What the header says about a render: the tempo, the meter, how many
	/// stems, and the peak out of `mat`'s own summary line.
	static func info(of manifest: SongRender.Manifest, rendered: String?) -> String {
		var parts = ["\(Int(manifest.tempo.rounded())) bpm"]
		if manifest.meter.count == 2 { parts.append("\(manifest.meter[0])/\(manifest.meter[1])") }
		parts.append("\(manifest.layers.count) stem\(manifest.layers.count == 1 ? "" : "s")")
		if let rendered, let peak = rendered.range(of: "peak ") {
			let rest = rendered[peak.upperBound...]
			if let end = rest.range(of: ",") { parts.append("peak " + rest[..<end.lowerBound]) }
		}
		return parts.joined(separator: " · ")
	}
}
