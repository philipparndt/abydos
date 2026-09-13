import Foundation
import Testing
@testable import AbydosKit

/// Which files open as a sound player, and which honestly do not.
struct FilePreviewAudioTests {
	private func url(_ name: String) -> URL {
		URL(fileURLWithPath: "/project/\(name)")
	}

	/// Every container Core Audio's file reader decodes natively.
	@Test func theNativeContainersAreAudio() {
		for name in ["take.wav", "song.mp3", "voice.m4a", "stream.aac", "loop.aif",
		             "loop.aiff", "master.flac", "bounce.caf", "TAKE.WAV"] {
			#expect(FilePreview.kind(for: url(name)) == .audio, "\(name)")
		}
	}

	/// What the system cannot decode keeps the notice: a player that never
	/// starts would be worse than a notice that says what the file is.
	@Test func whatTheSystemCannotPlayIsNotAudio() {
		for name in ["voice.ogg", "voice.opus", "old.wma"] {
			#expect(FilePreview.kind(for: url(name)) == nil, "\(name)")
		}
	}

	/// Space on the row plays a sound or a video; Quick Look is not offered for
	/// anything whose tab already shows it.
	@Test func whatPlaysAndWhatHasItsOwnViewer() {
		#expect(FilePreview.isPlayable(url("take.wav")))
		#expect(FilePreview.isPlayable(url("demo.mp4")))
		#expect(!FilePreview.isPlayable(url("photo.png")))
		for name in ["take.wav", "demo.mp4", "photo.png", "spec.pdf"] {
			#expect(FilePreview.hasDedicatedViewer(url(name)), "\(name)")
		}
		for name in ["deck.key", "font.ttf", "main.swift", "voice.ogg"] {
			#expect(!FilePreview.hasDedicatedViewer(url(name)), "\(name)")
		}
	}

	@Test func soundOpensAsThePlayerWithNoSource() {
		#expect(FilePreview.defaultMode(for: url("take.wav")) == .preview)
		#expect(FilePreview.hasPreview(url("take.wav")))
		#expect(!FilePreview.hasReadableSource(url("song.mp3")))
		#expect(FilePreview.availableModes(for: url("song.mp3")) == [.preview])
	}
}
