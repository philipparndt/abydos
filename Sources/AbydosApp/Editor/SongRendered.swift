import AppKit
import AbydosKit

/// A render a song pane is showing: where it was written, what `mat` said it
/// holds, its files and the playback of them.
///
/// Out of the pane only because the pane is at the size a file here may be.
struct SongRendered {
	let directory: URL
	let manifest: SongRender.Manifest
	/// The mix first, then a stem per layer, in the manifest's order — the same
	/// order as the playback's voices.
	let files: [URL]
	let playback: AudioPlayback
}
