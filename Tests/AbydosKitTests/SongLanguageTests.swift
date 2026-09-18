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

	/// Coloured by musik-as-text's own grammar: headers, names, notes, numbers
	/// and comments each get a colour, and a half-typed last line leaves the
	/// rest coloured rather than blank.
	@Test func aSongIsColoured() throws {
		let source = """
		# a verse
		tempo 132
		instrument lead synth
		  osc saw
		  filter lowpass cutoff=0.4
		pattern verse
		  A4:q A4:e [D3 F4]:w@80 r |
		pattern beat grid=1/16
		  kick X...x...X...x...
		track melody
		  instrument lead
		  play verse x2
		  sidechai
		"""
		let engine = try #require(SyntaxEngine(languageId: "song"), "no grammar for song")
		let rope = Rope(source)
		engine.parse(rope: rope)
		let highlights = engine.highlights(rope: rope, byteRange: 0..<source.utf8.count)
		// The source is ASCII, so a character offset is a byte offset.
		func kind(of word: String, after anchor: String = "") -> HighlightKind? {
			let text = source as NSString
			let from = anchor.isEmpty ? 0 : NSMaxRange(text.range(of: anchor))
			let found = text.range(of: word, range: NSRange(location: from, length: text.length - from))
			guard found.location != NSNotFound else { return nil }
			return highlights.first { $0.range.contains(found.location) }?.kind
		}
		#expect(kind(of: "# a verse") == .comment)
		#expect(kind(of: "tempo") == .keyword)
		#expect(kind(of: "pattern") == .keyword)
		#expect(kind(of: "132") == .number)
		#expect(kind(of: "verse", after: "pattern ") == .function, "a pattern's name where it is defined")
		#expect(kind(of: "A4") == .constant, "a note")
		#expect(kind(of: "kick", after: "grid=1/16") == .constant, "a drum")
		#expect(kind(of: "cutoff") == .property)
		#expect(kind(of: "verse", after: "play ") == .variable, "a pattern's name where it is played")
	}
}
