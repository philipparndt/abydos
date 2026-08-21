import Foundation
import Testing
@testable import AbydosKit

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

	/// The full sentence lives in `body.error.format`, not in `message`.
	///
	/// **Measured, and it is the difference between naming a fault and naming a
	/// path.** Delve refusing a launch because it is too old for the installed Go
	/// sends `message: "Failed to launch /Users/me/thing"` and
	/// `body.error.format: "Failed to launch /Users/me/thing: Version of Delve is
	/// too old for Go version go1.27.0 (maximum supported version 1.26, …)"`.
	@Test func aRefusalPrefersTheFieldMeantToBeShown() {
		let text = DAPClient.refusal(
			["message": "Failed to launch /Users/me/thing"],
			body: ["error": ["id": 3000, "format":
				"Failed to launch /Users/me/thing: Version of Delve is too old for "
				+ "Go version go1.27.0 (maximum supported version 1.26)"]]
		)
		#expect(text.contains("too old for Go version go1.27.0"))
	}

	/// No `error` object, which is most adapters most of the time.
	@Test func theShortMessageIsUsedWhenThereIsNothingBetter() {
		#expect(DAPClient.refusal(["message": "could not attach"], body: [:]) == "could not attach")
		#expect(DAPClient.refusal([:], body: [:]) == "request failed")
		// An empty format is not better than the message.
		#expect(DAPClient.refusal(
			["message": "could not attach"], body: ["error": ["format": "   "]]
		) == "could not attach")
	}
}

/// What a launch the adapter *refused* says for itself.
///
/// **A different event from going quiet**, and it used not to be told apart.
/// Measured against `dlv dap` on a project whose build fails: the adapter
/// answered `Building …`, then `Build Error:` with the compiler's own words, then
/// a `launch` response with `success: false` and a message — inside one second.
/// The response was never read, so the twenty-five second watchdog reported it,
/// quoting the first of the three, which is the adapter clearing its throat.
struct LaunchRefusalTests {
	/// What delve actually answers, quoted from a driven run.
	private let message = "Failed to launch: Build error: Check the debug console for details."
	private let printed = """
	Building /Users/me/projects/thing/app
	Build Error: go build -o /tmp/probe -gcflags all=-N -l /Users/me/projects/thing/app
	go: cannot find main module, but found .git/config in /Users/me
	"""

	@Test func theAdaptersOwnSentenceLeads() {
		let said = LaunchStall.explainRefusal("launch", message: message, lastOutput: printed)
		#expect(said.hasPrefix("The debugger would not start the program: Failed to launch"))
		// And what it printed is there too, because the message alone says
		// nothing about what was wrong.
		#expect(said.contains("cannot find main module"))
	}

	/// The console is named only when the adapter pointed at it — and once.
	@Test func theConsoleIsNamedWhenTheAdapterPointsAtIt() {
		let pointed = LaunchStall.explainRefusal("launch", message: message, lastOutput: printed)
		#expect(pointed.contains("The debug console has the whole of it."))

		let quiet = LaunchStall.explainRefusal(
			"launch", message: "exec format error", lastOutput: printed
		)
		#expect(!quiet.contains("debug console has"))
	}

	/// A message and nothing printed: the sentence stands on its own rather than
	/// heading an empty quotation.
	@Test func aMessageWithNothingPrinted() {
		let said = LaunchStall.explainRefusal("launch", message: message, lastOutput: nil)
		#expect(said.contains("Failed to launch"))
		#expect(!said.contains("What it said on the way"))
	}

	/// Output and no message, which is an adapter that refused without a word.
	@Test func printedOutputWithNoMessage() {
		let said = LaunchStall.explainRefusal("launch", message: nil, lastOutput: printed)
		#expect(said.contains("said nothing about why"))
		#expect(said.contains("cannot find main module"))
		// Not the watchdog's sentence: this one was refused, not silent.
		#expect(!said.contains("DevToolsSecurity"))
	}

	/// Neither, which should still say which of the two things failed.
	@Test func neitherOneNorTheOther() {
		let said = LaunchStall.explainRefusal("launch", message: nil, lastOutput: nil)
		#expect(said == "The debugger would not start the program, and said nothing about why.")
	}

	/// An attach is not a launch, and the sentence says which was refused.
	@Test func anAttachSaysItWasAnAttach() {
		let said = LaunchStall.explainRefusal(
			"attach", message: "could not attach to pid 8213", lastOutput: nil
		)
		#expect(said.contains("would not attach to the program"))
		#expect(said.contains("pid 8213"))
	}

	/// **The refusal never borrows the watchdog's sentence.** That message names
	/// developer-tools authorization, which is the one cause of silence and has
	/// nothing to do with an adapter that answered.
	@Test func aRefusalIsNeverTheAuthorizationMessage() {
		for output in [nil, "", printed] as [String?] {
			let said = LaunchStall.explainRefusal("launch", message: message, lastOutput: output)
			#expect(!said.contains("DevToolsSecurity"))
			#expect(!said.contains("stopped without starting"))
		}
	}
}
