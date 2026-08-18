import Foundation
import Testing
@testable import AbydosKit

/// What makes a run a driven one, and what a driven run is refused.
///
/// The app target is where the launch options live, so what can be asserted here
/// is the rule underneath them — which is the half that matters: `DrivenRun` is
/// what `Settings` and `SessionStore` ask, and neither can see `LaunchOptions`.
struct DrivenCaptureTests {
	/// The rule is "everything except the two that only say what to open",
	/// stated that way round on purpose: a list of verbs goes out of date
	/// silently, and 0534 and 0535 are both what a list that had gone out of
	/// date cost.
	///
	/// Given whole argument vectors, program name and all — `isDriven` drops the
	/// first the way `CommandLine.arguments` hands it over, and a test that
	/// forgot said a `--screenshot` run was not driven.
	@Test func onlyOpenAndFileLeaveARunUndriven() {
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--open", "/a"]) == false)
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--open", "/a", "--file", "/a/b.swift"]) == false)
		#expect(DrivenRun.isDriven(arguments: ["Abydos"]) == false)
	}

	@Test func anyOtherVerbMakesItDriven() {
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--screenshot", "out.png"]))
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--open", "/a", "--type", "C"]))
		// The capture flags that are not `--screenshot`, which is how the gate
		// came to be asked as one flag's presence.
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--open", "/a", "--sidebar-shot", "out.png"]))
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--open", "/a", "--editor-shot", "out.png"]))
	}

	/// **The refusal is the case nobody would notice**, which is why it has a
	/// test: a run that opens nothing and says why is indistinguishable, from
	/// outside, from one that opened the wrong thing quietly — unless the status
	/// says otherwise.
	@Test func aPathThatIsNotADirectoryIsNotSomethingToOpen() {
		let missing = URL(fileURLWithPath: "/nowhere/at/all")
		var isDirectory: ObjCBool = false
		#expect(!FileManager.default.fileExists(atPath: missing.path, isDirectory: &isDirectory))

		// A file is not a project root either, and the check the app makes is
		// this one — existence *and* directory-ness.
		let file = FileManager.default.temporaryDirectory
			.appendingPathComponent("driven-\(UUID().uuidString).txt")
		try? "x".write(to: file, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: file) }

		var fileIsDirectory: ObjCBool = false
		#expect(FileManager.default.fileExists(atPath: file.path, isDirectory: &fileIsDirectory))
		#expect(!fileIsDirectory.boolValue)
	}

	/// `/tmp` and `/private/tmp` are one directory, and a run that photographed
	/// the wrong copy was silent about it for an afternoon. Both spellings have
	/// to converge on one string, or the line the app prints answers nothing.
	@Test func bothSpellingsOfTheScratchDirectoryConverge() {
		let short = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path
		let long = URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path
		#expect(short == long)
	}
}
