import Foundation
import Testing
@testable import AbydosKit

/// Which files open as a player, and which honestly do not.
struct FilePreviewVideoTests {
	private func url(_ name: String) -> URL {
		URL(fileURLWithPath: "/project/\(name)")
	}

	@Test func theNativeContainersAreVideo() {
		#expect(FilePreview.kind(for: url("demo.mp4")) == .video)
		#expect(FilePreview.kind(for: url("capture.mov")) == .video)
		#expect(FilePreview.kind(for: url("clip.m4v")) == .video)
	}

	/// A container AVFoundation cannot decode stays with the notice: a player
	/// spinning over a black rectangle would be worse.
	@Test func whatTheSystemCannotPlayIsNotVideo() {
		#expect(FilePreview.kind(for: url("capture.webm")) != .video)
		#expect(FilePreview.kind(for: url("capture.mkv")) == nil)
		#expect(FilePreview.kind(for: url("capture.avi")) == nil)
	}

	/// `pathExtension` reads the last component, however many dots the name
	/// carries on the way there.
	@Test func aDottedNameIsStillItsExtension() {
		#expect(FilePreview.kind(for: url("2026-08-31.screen.recording.mov")) == .video)
	}

	@Test func aVideoOpensRendered() {
		#expect(FilePreview.defaultMode(for: url("demo.mp4")) == .preview)
		#expect(FilePreview.hasPreview(url("demo.mp4")))
	}
}
