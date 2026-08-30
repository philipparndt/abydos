import Foundation
import Testing
@testable import AbydosKit

/// The breakpoints a project has, as a list.
///
/// The ordering and the name each row carries are the whole of what can be
/// checked without a window, and they are what makes a list readable twice: the
/// same set in the same order, and a file named by the part of its path that
/// says which file it is.
struct BreakpointRowTests {
	static let root = URL(fileURLWithPath: "/p/abydos")

	static func set(_ entries: [(String, [Int])]) -> [String: [Breakpoint]] {
		var made: [String: [Breakpoint]] = [:]
		for (path, lines) in entries {
			made[path] = lines.map { Breakpoint(file: path, line: $0) }
		}
		return made
	}

	@Test func filesComeBackInPathOrder() {
		let rows = BreakpointRows.rows(
			from: Self.set([
				("/p/abydos/Sources/serve.go", [3]),
				("/p/abydos/Sources/main.go", [7]),
			]),
			in: Self.root
		)
		#expect(rows.map(\.name) == ["Sources/main.go", "Sources/serve.go"])
	}

	@Test func breakpointsInOneFileComeBackInLineOrder() {
		let rows = BreakpointRows.rows(
			from: Self.set([("/p/abydos/main.go", [42, 7, 19])]), in: Self.root
		)
		#expect(rows.map(\.line) == [7, 19, 42])
	}

	@Test func aFileInsideTheProjectIsNamedRelativeToIt() {
		let rows = BreakpointRows.rows(
			from: Self.set([("/p/abydos/Sources/AbydosKit/Debug/DAPClient.swift", [1])]), in: Self.root
		)
		#expect(rows.first?.name == "Sources/AbydosKit/Debug/DAPClient.swift")
		// The path itself is kept whole: it is what the gutter and the adapter
		// both key a breakpoint by, and the name is only what is shown.
		#expect(rows.first?.path == "/p/abydos/Sources/AbydosKit/Debug/DAPClient.swift")
	}

	/// A dependency's source, a standard library. The part that says which file
	/// it is, is all of it.
	@Test func aFileOutsideTheProjectIsNamedInFull() {
		let rows = BreakpointRows.rows(
			from: Self.set([("/usr/lib/go/src/net/http/server.go", [104])]), in: Self.root
		)
		#expect(rows.first?.name == "/usr/lib/go/src/net/http/server.go")
	}

	/// `/p/abydos-examples` is not inside `/p/abydos`, and a name made by
	/// dropping a prefix without the separator would call it `examples/main.go`.
	@Test func aSiblingSharingAPrefixIsNamedInFull() {
		let rows = BreakpointRows.rows(
			from: Self.set([("/p/abydos-examples/go-service/main.go", [19])]), in: Self.root
		)
		#expect(rows.first?.name == "/p/abydos-examples/go-service/main.go")
	}

	@Test func withNoProjectEveryNameIsThePath() {
		let rows = BreakpointRows.rows(from: Self.set([("/p/abydos/main.go", [1])]), in: nil)
		#expect(rows.first?.name == "/p/abydos/main.go")
	}

	@Test func whatEachRowCarriesComesFromTheBreakpoint() {
		var stopping = Breakpoint(file: "/p/abydos/main.go", line: 42)
		stopping.condition = "id == \"lamarzocco\""
		stopping.hitCondition = "> 5"
		stopping.isEnabled = false
		stopping.isVerified = true

		let rows = BreakpointRows.rows(from: ["/p/abydos/main.go": [stopping]], in: Self.root)
		let row = rows.first
		#expect(row?.condition == "id == \"lamarzocco\"")
		#expect(row?.hitCondition == "> 5")
		#expect(row?.isEnabled == false)
		#expect(row?.isVerified == true)
		#expect(row?.isConditional == true)
	}

	@Test func aPlainBreakpointHasNothingToAdd() {
		let rows = BreakpointRows.rows(from: Self.set([("/p/abydos/main.go", [1])]), in: Self.root)
		#expect(rows.first?.isConditional == false)
	}

	@Test func nothingSetIsNoRows() {
		#expect(BreakpointRows.rows(from: [:], in: Self.root).isEmpty)
		// A file whose breakpoints have all been taken away leaves no row either.
		#expect(BreakpointRows.rows(from: ["/p/abydos/main.go": []], in: Self.root).isEmpty)
	}
}
