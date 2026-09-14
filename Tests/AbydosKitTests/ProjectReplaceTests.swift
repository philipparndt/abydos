import Foundation
import Testing
@testable import AbydosKit

/// Replacing what the project search found, in a file the pane cannot see.
///
/// The claims worth checking without a window: that a row is found in the
/// file *as it is now* rather than at the offset it had, that only the chosen
/// rows change, and that an undo refuses a span somebody has edited since.
struct ProjectReplaceTests {
	static let literal = SearchOptions()
	static let regex = SearchOptions(isRegex: true)

	private func question(_ query: String, _ options: SearchOptions = literal) -> SearchChecklist.Question {
		SearchChecklist.Question(query: query, options: options)
	}

	private func marks(in text: String, path: String, _ question: SearchChecklist.Question) -> [SearchChecklist.Mark] {
		let matches = TextSearch.matches(in: text, query: question.query, options: question.options)
		return SearchChecklist.marks(for: FileSearchResult(url: URL(fileURLWithPath: path), relativePath: path, matches: matches))
	}

	private func apply(_ edit: TextSearch.ReplaceAll?, to text: String) -> String? {
		edit.map { ProjectReplace.applying($0, to: text) }
	}

	@Test func onlyTheChosenRowsAreReplaced() throws {
		let text = "needle one\nneedle two\nneedle three\n"
		let q = question("needle")
		let all = marks(in: text, path: "a.swift", q)
		#expect(all.count == 3)
		let outcome = ProjectReplace.edit(
			in: text, path: "a.swift", question: q, template: "pin", choosing: [all[0], all[2]]
		)
		#expect(outcome.replaced == 2)
		#expect(outcome.notFound.isEmpty)
		// The middle match sits inside the span and comes through untouched.
		#expect(apply(outcome.edit, to: text) == "pin one\nneedle two\npin three\n")
	}

	@Test func nilChoosesEveryMatchInTheFile() {
		let text = "a needle, another needle"
		let outcome = ProjectReplace.edit(
			in: text, path: "a.swift", question: question("needle"), template: "pin", choosing: nil
		)
		#expect(outcome.replaced == 2)
		#expect(apply(outcome.edit, to: text) == "a pin, another pin")
	}

	/// A row found before an edit is still found after a line is typed above
	/// it: the mark follows the text, not the line number.
	@Test func aRowIsFoundAfterALineIsInsertedAboveIt() {
		let before = "needle here\n"
		let q = question("needle")
		let chosen = Set(marks(in: before, path: "a.swift", q))
		let now = "// a new first line\nneedle here\n"
		let outcome = ProjectReplace.edit(in: now, path: "a.swift", question: q, template: "pin", choosing: chosen)
		#expect(outcome.replaced == 1)
		#expect(apply(outcome.edit, to: now) == "// a new first line\npin here\n")
	}

	/// A row whose line is gone replaces nothing and says so, rather than
	/// replacing whatever now sits at its old offset.
	@Test func aRowThatIsGoneIsReportedNotFound() {
		let before = "needle here\nneedle there\n"
		let q = question("needle")
		let all = marks(in: before, path: "a.swift", q)
		let now = "needle here\nsomething else\n"
		let outcome = ProjectReplace.edit(in: now, path: "a.swift", question: q, template: "pin", choosing: Set(all))
		#expect(outcome.replaced == 1)
		#expect(outcome.notFound == [all[1]])
		#expect(apply(outcome.edit, to: now) == "pin here\nsomething else\n")
	}

	@Test func nothingFoundIsNoEditAndEveryMarkNotFound() {
		let q = question("needle")
		let mark = SearchChecklist.Mark(path: "a.swift", text: "needle", occurrence: 0)
		let outcome = ProjectReplace.edit(in: "nothing", path: "a.swift", question: q, template: "x", choosing: [mark])
		#expect(outcome.edit == nil)
		#expect(outcome.notFound == [mark])
	}

	@Test func marksOfOtherFilesAreIgnoredNotReported() {
		let text = "needle\n"
		let q = question("needle")
		let other = SearchChecklist.Mark(path: "b.swift", text: "needle", occurrence: 0)
		let outcome = ProjectReplace.edit(in: text, path: "a.swift", question: q, template: "x", choosing: [other])
		#expect(outcome.edit == nil)
		#expect(outcome.notFound.isEmpty)
	}

	/// Two identical lines are told apart by which one they are, so choosing
	/// the second changes the second.
	@Test func twoIdenticalLinesWithOneChosen() {
		let text = "return needle\nkeep\nreturn needle\n"
		let q = question("needle")
		let all = marks(in: text, path: "a.swift", q)
		#expect(all[0].occurrence == 0 && all[1].occurrence == 1)
		let outcome = ProjectReplace.edit(in: text, path: "a.swift", question: q, template: "pin", choosing: [all[1]])
		#expect(apply(outcome.edit, to: text) == "return needle\nkeep\nreturn pin\n")
	}

	@Test func aCaptureTemplateWorksAcrossTheChosenRows() {
		let text = "user_id\norder_id\nitem_id\n"
		let q = question("(\\w+)_id", Self.regex)
		let all = marks(in: text, path: "a.swift", q)
		let outcome = ProjectReplace.edit(in: text, path: "a.swift", question: q, template: "$1Id", choosing: [all[0], all[2]])
		#expect(apply(outcome.edit, to: text) == "userId\norder_id\nitemId\n")
	}

	@Test func aTemplateThePatternCannotUseIsNoEdit() {
		let text = "user_id\n"
		let q = question("(\\w+)_id", Self.regex)
		let outcome = ProjectReplace.edit(in: text, path: "a.swift", question: q, template: "$7", choosing: nil)
		#expect(outcome.edit == nil)
	}

	@Test func theUnmatchedTextBetweenChosenRowsIsByteForByteWhatItWas() throws {
		let text = "needle\r\nkeep \t this exactly\r\nneedle"
		let q = question("needle")
		let all = marks(in: text, path: "a.swift", q)
		let outcome = ProjectReplace.edit(in: text, path: "a.swift", question: q, template: "pin", choosing: Set(all))
		#expect(apply(outcome.edit, to: text) == "pin\r\nkeep \t this exactly\r\npin")
	}

	// MARK: - The record

	@Test func anUndoPutsTheSpanBackWhenItStillReadsTheReplacement() {
		let file = ProjectReplace.Record.File(
			url: URL(fileURLWithPath: "/a.swift"), relativePath: "a.swift",
			start: 5, before: "needle x needle", after: "pin x pin", wasOpen: false
		)
		let now = "keep pin x pin tail"
		let edit = ProjectReplace.reversal(of: file, in: now, forward: false)
		#expect(edit?.utf16Range == 5..<14)
		#expect(edit.map { ProjectReplace.applying($0, to: now) } == "keep needle x needle tail")
	}

	@Test func anUndoRefusesASpanThatHasBeenEditedSince() {
		let file = ProjectReplace.Record.File(
			url: URL(fileURLWithPath: "/a.swift"), relativePath: "a.swift",
			start: 5, before: "needle", after: "pin", wasOpen: false
		)
		#expect(ProjectReplace.reversal(of: file, in: "keep PIN tail", forward: false) == nil)
		#expect(ProjectReplace.reversal(of: file, in: "kee", forward: false) == nil)
	}

	@Test func aRedoIsTheSameCheckTheOtherWayRound() {
		let file = ProjectReplace.Record.File(
			url: URL(fileURLWithPath: "/a.swift"), relativePath: "a.swift",
			start: 0, before: "needle", after: "pin", wasOpen: true
		)
		let edit = ProjectReplace.reversal(of: file, in: "needle tail", forward: true)
		#expect(edit.map { ProjectReplace.applying($0, to: "needle tail") } == "pin tail")
		#expect(ProjectReplace.reversal(of: file, in: "pin tail", forward: true) == nil)
	}

	// MARK: - Disk

	@Test func aBinaryOrNonUTF8FileIsNotRead() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("project-replace-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let binary = directory.appendingPathComponent("bin.dat")
		try Data([0x6e, 0x00, 0x65]).write(to: binary)
		#expect(ProjectReplace.readText(at: binary) == nil)

		let latin = directory.appendingPathComponent("latin.txt")
		try Data([0x6e, 0xe9, 0x65]).write(to: latin)
		#expect(ProjectReplace.readText(at: latin) == nil)

		let plain = directory.appendingPathComponent("plain.txt")
		try ProjectReplace.write("needle\n", to: plain)
		#expect(ProjectReplace.readText(at: plain) == "needle\n")
	}
}
