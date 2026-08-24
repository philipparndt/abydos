import Testing
import Foundation
@testable import AbydosKit

/// What a line of typing in the palette means.
///
/// **These are mostly regression tests for something that was already true.**
/// Files were added to the unprefixed list, and the risk in doing that is not
/// that files fail to appear — that is visible the moment anybody types — but
/// that `>` or `:` quietly starts doing something else. Nothing here is new
/// behaviour; it is the old behaviour, written down.
struct PaletteScopeTests {
	// MARK: - The prefixes, unchanged

	@Test func angleBracketMeansActions() {
		#expect(PaletteScope.of(">warn") == .commands("warn"))
		// The space people type after the bracket is not part of the query.
		#expect(PaletteScope.of("> warn") == .commands("warn"))
		#expect(PaletteScope.of(">") == .commands(""))
	}

	@Test func colonMeansALine() {
		#expect(PaletteScope.of(":42") == .line(42))
		#expect(PaletteScope.of(": 42") == .line(42))
		#expect(PaletteScope.of(":") == .line(nil))
		// Not a number is not a line, and must not fall through to a search.
		#expect(PaletteScope.of(":abc") == .line(nil))
	}

	@Test func anythingElseSearchesEverything() {
		#expect(PaletteScope.of("mvnw") == .everything("mvnw"))
		#expect(PaletteScope.of("") == .everything(""))
	}

	/// Lower-cased once, here, so nothing downstream has to remember to.
	@Test func theQueryIsCaseFolded() {
		#expect(PaletteScope.of("GitRepo") == .everything("gitrepo"))
		#expect(PaletteScope.of(">Toggle Warnings") == .commands("toggle warnings"))
	}

	/// A prefix in the middle is not a prefix. `a > b` is a search.
	@Test func aPrefixOnlyCountsAtTheStart() {
		#expect(PaletteScope.of("a > b") == .everything("a > b"))
		#expect(PaletteScope.of("Foo:12") == .everything("foo:12"))
	}

	// MARK: - Where files are offered

	/// The claim the file search rests on: files are in the unprefixed list and
	/// nowhere else.
	@Test func filesAreOfferedOnlyToAnUnprefixedQuery() {
		#expect(PaletteScope.of("mvnw").offersFiles)
		#expect(!PaletteScope.of(">mvnw").offersFiles, "`>` is actions, and was before files existed")
		#expect(!PaletteScope.of(":42").offersFiles)
		#expect(!PaletteScope.of(":").offersFiles)
	}

	/// Every file in the project under an empty query is not a list, it is the
	/// project — and the unfiltered palette is a menu of projects and actions.
	@Test func nothingTypedOffersNoFiles() {
		#expect(!PaletteScope.of("").offersFiles)
		#expect(!PaletteScope.of("   ").offersFiles)
	}
}
