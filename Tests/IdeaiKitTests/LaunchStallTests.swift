import Foundation
import Testing
@testable import IdeaiKit

/// What a launch that produced no event says for itself.
///
/// The message this replaces named one cause whatever had happened, and that
/// cost real time: a Go build failing with `cannot find main module` was
/// reported as a permissions problem, so the next hour went to
/// `DevToolsSecurity` and macOS privacy settings rather than to a missing
/// `go.mod`. The adapter had already said why, in the console, unread.
struct LaunchStallTests {
	@Test func repeatsWhatTheAdapterSaid() {
		let message = LaunchStall.explain(lastOutput: """
		Build Error: go build -o /tmp/__debug_bin /Users/me/project
		go: cannot find main module, but found .git/config in /Users/me/project
		""")

		#expect(message.contains("cannot find main module"))
		// And does not send anybody to a permissions setting about a build.
		#expect(!message.contains("DevToolsSecurity"))
	}

	/// Silence is the case the old message was written for, and the only one it
	/// fits: the debuggee is held before it can say anything.
	@Test func fallsBackToAuthorizationOnlyWhenNothingWasSaid() {
		for nothing in [nil, "", "   ", "\n\n"] as [String?] {
			let message = LaunchStall.explain(lastOutput: nothing)
			#expect(message.contains("DevToolsSecurity"))
			#expect(message.contains("said nothing about why"))
		}
	}

	/// The tail, because the reason is at the end: a build prints its command
	/// first and its complaint last, and keeping the head keeps the wrong half.
	@Test func keepsTheEndOfWhatWasSaid() {
		var kept: String?
		for index in 1...100 {
			kept = LaunchStall.remember("line \(index)\n", after: kept)
		}

		let message = LaunchStall.explain(lastOutput: kept)
		#expect(message.contains("line 100"))
		#expect(!message.contains("line 50"))
		// Bounded, so a program that logged for an hour does not arrive whole.
		#expect((kept ?? "").split(separator: "\n").count <= LaunchStall.keptLines + 1)
	}

	/// Output arrives in pieces that are not lines — Delve ends "Building …"
	/// without a newline — so joining must not invent one.
	@Test func joinsPiecesThatAreNotWholeLines() {
		var kept = LaunchStall.remember("Building /tmp/thing", after: nil)
		kept = LaunchStall.remember(" (exit status 1)\n", after: kept)
		#expect(kept.contains("Building /tmp/thing (exit status 1)"))
	}
}
