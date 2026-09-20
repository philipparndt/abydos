import Foundation
import Testing
@testable import AbydosKit

struct SongBlockMuteTests {
	private static let song = "track drums\n  instrument kit\n  play kicks x4\n  play beat x28   # the groove\n  rest 2\n"

	private func applied(_ edit: SongBlockMute.Edit, to text: String) -> String {
		(text as NSString).replacingCharacters(
			in: NSRange(location: edit.range.lowerBound, length: edit.range.count), with: edit.text
		)
	}

	@Test func aPlayLineIsMutedAtTheEndOfWhatItSays() throws {
		let edit = try #require(SongBlockMute.toggle(atLine: 3, in: Self.song))
		#expect(edit.muted)
		#expect(applied(edit, to: Self.song).contains("  play kicks x4 mute\n  play beat"))
	}

	@Test func theCommentAndTheSpaceBeforeItAreLeftAlone() throws {
		let edit = try #require(SongBlockMute.toggle(atLine: 4, in: Self.song))
		#expect(applied(edit, to: Self.song).contains("  play beat x28 mute   # the groove\n"))
	}

	@Test func mutingTwiceIsTheSongAsItWas() throws {
		for line in [3, 4] {
			let once = applied(try #require(SongBlockMute.toggle(atLine: line, in: Self.song)), to: Self.song)
			let back = try #require(SongBlockMute.toggle(atLine: line, in: once))
			#expect(!back.muted)
			#expect(applied(back, to: once) == Self.song)
		}
	}

	@Test func muteIsFoundWhereverItIsAmongTheOptions() throws {
		let text = "  play beat mute x4 vel=0.8\n"
		let edit = try #require(SongBlockMute.toggle(atLine: 1, in: text))
		#expect(!edit.muted)
		#expect(applied(edit, to: text) == "  play beat x4 vel=0.8\n")
	}

	@Test func onlyAPlayLineIsToggled() {
		#expect(SongBlockMute.toggle(atLine: 1, in: Self.song) == nil)
		#expect(SongBlockMute.toggle(atLine: 5, in: Self.song) == nil)
		#expect(SongBlockMute.toggle(atLine: 9, in: Self.song) == nil)
		#expect(SongBlockMute.toggle(atLine: 1, in: "# play beat\n") == nil)
		// A pattern called `mute` is a pattern, not the option.
		#expect(SongBlockMute.toggle(atLine: 1, in: "play mute")?.muted == true)
	}

	@Test func anAudioTracksPlayAndWindowsLineEndings() throws {
		let text = "track loop\r\n  play bars=17-24 x2\r\n"
		let edit = try #require(SongBlockMute.toggle(atLine: 2, in: text))
		#expect(applied(edit, to: text) == "track loop\r\n  play bars=17-24 x2 mute\r\n")
	}

	@Test func theRangeIsInUTF16() throws {
		// 🎹 is two UTF-16 units and one character.
		let text = "# 🎹\n  play keys\n"
		let edit = try #require(SongBlockMute.toggle(atLine: 2, in: text))
		#expect(applied(edit, to: text) == "# 🎹\n  play keys mute\n")
	}
}
