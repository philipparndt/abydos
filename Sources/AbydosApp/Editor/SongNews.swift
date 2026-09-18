import AppKit
import AbydosKit

extension Notification.Name {
	/// A song's playhead moved: `song` (URI), `seconds` (absent when there is
	/// none), `marking`.
	static let abydosSongPlayhead = Notification.Name("abydos.songPlayhead")
	/// A song stopped on a breakpoint or went on: `song` (URI), `file` (URI)
	/// and `line`, absent when it goes on.
	static let abydosSongStopped = Notification.Name("abydos.songStopped")
}

/// What a song pane says to the tabs of the files its song includes.
///
/// Since includes (mat e72d7e5) a song's lines are in several files, each
/// possibly open in any tab of any group, and each carrying its own timeline
/// with the song's URI in it. The pane cannot know those tabs; every editor
/// group listens and lights the ones whose timeline is this song's.
@MainActor
enum SongNews {
	static func playhead(song: String, seconds: Double?, marking: Bool) {
		var info: [String: Any] = ["song": song, "marking": marking]
		if let seconds { info["seconds"] = seconds }
		NotificationCenter.default.post(name: .abydosSongPlayhead, object: nil, userInfo: info)
	}

	static func stopped(song: String, file: String, line: Int?) {
		var info: [String: Any] = ["song": song, "file": file]
		if let line { info["line"] = line }
		NotificationCenter.default.post(name: .abydosSongStopped, object: nil, userInfo: info)
	}
}

extension EditorViewController {
	@objc func songPlayheadMoved(_ notification: Notification) {
		guard let song = notification.userInfo?["song"] as? String else { return }
		let seconds = notification.userInfo?["seconds"] as? Double
		let marking = notification.userInfo?["marking"] as? Bool ?? false
		for tab in tabs {
			guard let codeView = tab.codeView, let timeline = codeView.timeline,
			      Self.same(timeline.song, song) else { continue }
			codeView.setSongPlayhead(seconds, marking: marking)
		}
	}

	@objc func songStopped(_ notification: Notification) {
		guard let song = notification.userInfo?["song"] as? String,
		      let file = notification.userInfo?["file"] as? String else { return }
		let line = notification.userInfo?["line"] as? Int
		for tab in tabs {
			guard let codeView = tab.codeView, let timeline = codeView.timeline,
			      Self.same(timeline.song, song) else { continue }
			let here = Self.same(LanguageService.shared.uri(for: tab.url), file)
			codeView.setSongStoppedLine(here ? line : nil)
		}
	}

	/// Two file URIs for one file, however they were spelled.
	static func same(_ one: String?, _ other: String) -> Bool {
		guard let one, let a = URL(string: one), let b = URL(string: other) else { return false }
		return FilePath.canonical(a) == FilePath.canonical(b)
	}
}
