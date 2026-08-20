import Foundation
import Testing
@testable import AbydosKit

/// A place in the code, written down and read back.
///
/// Both directions, because both happen: this writes what an assistant is
/// handed, and it reads what arrives from a stack trace, a grep, or one of its
/// own references pasted back in. The round trip is the claim that those are the
/// same shape.
struct CodePlaceTests {
	@Test func aLineIsPathAndNumber() {
		let place = CodePlace(path: "Sources/AbydosApp/Editor/CodeView.swift", line: 2324)
		#expect(place.text == "Sources/AbydosApp/Editor/CodeView.swift:2324")
		#expect(place.lineCount == 1)
	}

	/// **The wrong answer this exists to prevent**: eight lines selected, one
	/// line handed back.
	@Test func aSelectionIsARange() {
		let place = CodePlace(path: "a/b.swift", line: 12, endLine: 18)
		#expect(place.text == "a/b.swift:12-18")
		#expect(place.lineCount == 7)
	}

	/// A range of one line is a line, so that two references to the same place
	/// cannot be unequal.
	@Test func aRangeOfOneLineIsALine() {
		#expect(CodePlace(path: "a.swift", line: 12, endLine: 12).text == "a.swift:12")
		#expect(CodePlace(path: "a.swift", line: 12, endLine: 12) == CodePlace(path: "a.swift", line: 12))
		// And a nonsense range — the end before the start — is not carried.
		#expect(CodePlace(path: "a.swift", line: 12, endLine: 4).text == "a.swift:12")
	}

	// MARK: - Relative to the project

	@Test func aPathIsRelativeToTheProject() {
		let project = URL(fileURLWithPath: "/tmp/probe")
		let file = URL(fileURLWithPath: "/tmp/probe/Sources/App/Main.swift")
		#expect(CodePlace.path(of: file, in: project) == "Sources/App/Main.swift")
	}

	/// A file outside keeps its absolute path: a `../../..` chain means nothing
	/// without knowing where it was written.
	///
	/// Compared against the canonical spelling rather than the literal, because
	/// `/tmp` is a symlink on this machine and an absolute path that came out of
	/// here is resolved. Writing `/tmp/…` in the expectation would be asserting
	/// that it is *not*, which is a different claim and a false one.
	@Test func aFileOutsideTheProjectKeepsItsWholePath() {
		let project = URL(fileURLWithPath: "/tmp/probe")
		let file = URL(fileURLWithPath: "/tmp/elsewhere/Main.swift")
		#expect(CodePlace.path(of: file, in: project)
			== FilePath.canonicalEvenIfMissing("/tmp/elsewhere/Main.swift"))
	}

	/// A project whose name is a prefix of another's. `/tmp/probe-2` is not
	/// inside `/tmp/probe`, and a prefix test without the separator says it is.
	@Test func aSiblingWhoseNameStartsTheSameIsNotInside() {
		let project = URL(fileURLWithPath: "/tmp/probe")
		let file = URL(fileURLWithPath: "/tmp/probe-2/Main.swift")
		#expect(CodePlace.path(of: file, in: project)
			== FilePath.canonicalEvenIfMissing("/tmp/probe-2/Main.swift"))
	}

	@Test func noProjectMeansTheWholePath() {
		#expect(CodePlace.path(of: URL(fileURLWithPath: "/tmp/a.swift"), in: nil)
			== FilePath.canonicalEvenIfMissing("/tmp/a.swift"))
	}

	/// A space in a path is a path with a space in it, and nothing else: no
	/// quoting, no escaping. Whoever pastes it into a shell can quote it, and
	/// everything else this is pasted into wants the name.
	@Test func aSpaceInThePathIsLeftAlone() {
		let project = URL(fileURLWithPath: "/tmp/probe")
		let file = URL(fileURLWithPath: "/tmp/probe/My Notes/a b.swift")
		let place = CodePlace(url: file, in: project, line: 3)
		#expect(place.text == "My Notes/a b.swift:3")
		#expect(CodePlace.parse(place.text) == place)
	}

	// MARK: - Reading one back

	@Test func readsWhatAStackTraceSays() {
		#expect(CodePlace.parse("Sources/App/Main.swift:42")
			== CodePlace(path: "Sources/App/Main.swift", line: 42))
	}

	/// grep's column, dropped: a column is not something this can act on.
	@Test func readsGrepsColumnAndDropsIt() {
		#expect(CodePlace.parse("a/b.swift:42:7") == CodePlace(path: "a/b.swift", line: 42))
	}

	@Test func readsARange() {
		#expect(CodePlace.parse("a/b.swift:12-18") == CodePlace(path: "a/b.swift", line: 12, endLine: 18))
	}

	/// **A colon is legal in a file name.** `notes:hello` names a file, and a
	/// path that is not followed by digits is not a reference at all.
	@Test func aPathThatIsNotFollowedByANumberIsNotAReference() {
		#expect(CodePlace.parse("notes:hello") == nil)
		#expect(CodePlace.parse("a/b.swift") == nil)
		#expect(CodePlace.parse("") == nil)
		#expect(CodePlace.parse(":12") == nil)
		#expect(CodePlace.parse("a/b.swift:0") == nil)
		#expect(CodePlace.parse("a/b.swift:12 ") == CodePlace(path: "a/b.swift", line: 12))
	}

	/// **Shape alone cannot tell these apart, and grep wins.**
	/// `a.swift:12:42` is grep saying line 12, column 42. `notes:12:42` could be
	/// a file genuinely called `notes:12` at line 42 — a colon is legal in a
	/// file name — and there is no way to know without asking the disk, which
	/// this cannot do and `Scripts/abydos` can: it opens `path:line` only when
	/// the path without the number exists and the path with it does not.
	///
	/// So the commoner reading is taken, and written down here rather than left
	/// as a surprise: two trailing numbers are a line and a column.
	@Test func twoTrailingNumbersAreALineAndAColumnRatherThanAStrangeFileName() {
		#expect(CodePlace.parse("notes:12:42") == CodePlace(path: "notes", line: 12))
		// One trailing number is unambiguous: the file keeps its colon.
		#expect(CodePlace.parse("notes:12") == CodePlace(path: "notes", line: 12))
	}

	@Test func theRoundTripHolds() {
		for place in [
			CodePlace(path: "a.swift", line: 1),
			CodePlace(path: "deep/nested/path/File.swift", line: 9999),
			CodePlace(path: "a/b.swift", line: 12, endLine: 18),
			CodePlace(path: "/absolute/elsewhere/File.swift", line: 7),
		] {
			#expect(CodePlace.parse(place.text) == place, "\(place.text)")
		}
	}

	@Test func theFileItPointsAt() {
		let project = URL(fileURLWithPath: "/tmp/probe")
		#expect(CodePlace(path: "a/b.swift", line: 2).url(in: project).path == "/tmp/probe/a/b.swift")
		// An absolute reference ignores the project, which is what makes one
		// worth writing.
		#expect(CodePlace(path: "/tmp/other/c.swift", line: 2).url(in: project).path == "/tmp/other/c.swift")
	}
}
