import Foundation
import Testing
@testable import AbydosKit

/// A `.song` is a language here: named for its server, commented with `#`,
/// answered for by `mat lsp`.
struct SongLanguageTests {
	@Test func aSongFileIsTheSongLanguage() {
		#expect(LanguageRegistry.shared.languageId(for: URL(fileURLWithPath: "/songs/neon.song")) == "song")
		#expect(LanguageRegistry.shared.allLanguageIds.contains("song"))
	}

	@Test func aSongIsCommentedWithAHash() {
		#expect(CommentSyntax.byLanguage["song"] == .line("#"))
	}

	/// The renderer is the server: the same `mat` the song pane renders with,
	/// run as `mat lsp`, found the way every tool is.
	@Test func matIsTheSongsLanguageServer() throws {
		let definition = try #require(LanguageServers.definition(forLanguage: "song", choosing: .none))
		#expect(definition.command == "mat")
		#expect(definition.arguments == ["lsp"])
		#expect(definition.rootMarkers.isEmpty)
		#expect(definition.installHint.contains("cargo install"))
	}
}
