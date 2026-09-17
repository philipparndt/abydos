import AppKit
import AbydosKit

/// A reading of a sound file and the picture of its spectrum, made together.
///
/// The picture is two million pixels computed one at a time, which is a third
/// of a second in a debug build — nothing, once, off the main thread, and a
/// stalled app when it is done for every lane on the main thread each time one
/// lane's reading lands. So whoever reads a file makes its picture in the same
/// place, and the canvas is handed both.
///
/// `@unchecked` because a `CGImage` is immutable once made and is only ever
/// read after this: it is safe to hand between threads, and the type does not
/// say so.
struct SpectrumPicture: @unchecked Sendable {
	let reading: AudioOverview
	let image: CGImage?

	/// Nil for a reading that failed, so a caller can wrap a `try?` directly.
	init?(of reading: AudioOverview?) {
		guard let reading else { return nil }
		self.reading = reading
		image = AudioCanvas.makeSpectrumImage(of: reading)
	}
}
