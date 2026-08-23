import Foundation
import Testing
@testable import AbydosKit

/// Reading what the java-debug bundle says about a hot code replace.
///
/// **Every shape here was read out of the bundle**, with `javap` over
/// `com.microsoft.java.debug.plugin-0.53.2.jar` and the core jar inside it,
/// rather than written from memory — which was wrong about this three times over
/// before anybody looked. `Responses$RedefineClassesResponse` carries
/// `changedClasses: String[]` and `errorMessage: String`;
/// `Events$HotCodeReplaceEvent` carries a `changeType` and a `message`.
struct JavaHotSwapEventTests {
	@Test func theStagesAreTheAdaptersOwn() {
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "STARTING"])?.stage == .starting)
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "BUILD_COMPLETE"])?.stage == .buildComplete)
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "END"])?.stage == .end)
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "ERROR"])?.stage == .error)
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "WARNING"])?.stage == .warning)
	}

	/// **A stage nobody has seen is not forced into the nearest case.** The
	/// adapter may grow one, and a new stage silently reported as an error would
	/// be a lie about somebody's session.
	@Test func anUnknownStageIsNotGuessedAt() {
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "SOMETHING_NEW"]) == nil)
		#expect(JavaDebug.HotSwap.event(from: [:]) == nil)
	}

	@Test func theMessageComesThroughAndAnEmptyOneDoesNot() {
		let said = JavaDebug.HotSwap.event(from: ["changeType": "ERROR", "message": "no can do"])
		#expect(said?.message == "no can do")
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "END", "message": ""])?.message == nil)
		#expect(JavaDebug.HotSwap.event(from: ["changeType": "END"])?.message == nil)
	}
}

/// What comes back from the request itself.
struct JavaHotSwapResultTests {
	@Test func theClassesThatWereTaken() {
		let result = JavaDebug.HotSwap.result(from: [
			"changedClasses": ["com.example.hotswap.Greeting", "com.example.hotswap.Ticker"],
		])
		#expect(result.changed == ["com.example.hotswap.Greeting", "com.example.hotswap.Ticker"])
		#expect(result.errorMessage == nil)
		#expect(result.didSwap)
	}

	@Test func aRefusalCarriesItsReasonAndNoClasses() {
		let result = JavaDebug.HotSwap.result(from: [
			"changedClasses": [],
			"errorMessage": "Add method not implemented",
		])
		#expect(result.changed.isEmpty)
		#expect(result.didSwap == false)
		#expect(result.errorMessage == "Add method not implemented")
	}

	/// A body with neither is what a swap that found nothing to do answers, and
	/// it is not a failure: nothing was recompiled, so nothing was redefined.
	@Test func nothingToDoIsNotAFailure() {
		let result = JavaDebug.HotSwap.result(from: [:])
		#expect(result.changed.isEmpty)
		#expect(result.errorMessage == nil)
	}
}

/// Telling a session that cannot swap from a change the JVM will not take.
///
/// There is no field for this — the adapter reports one `errorMessage` for both
/// — so the wording is the only evidence, and getting it wrong in one direction
/// is much worse than the other: a refusal misread as "this session cannot swap"
/// silences every later save.
struct JavaHotSwapClassificationTests {
	@Test func aVMThatCannotRedefineIsAboutTheSession() {
		#expect(JavaDebug.HotSwap.isAboutTheSession(
			"The target VM does not support hot code replace"))
		#expect(JavaDebug.HotSwap.isAboutTheSession(
			"Hot code replace is not supported by this JVM"))
		#expect(JavaDebug.HotSwap.isAboutTheSession(
			"Unsupported operation: redefineClasses"))
		#expect(JavaDebug.HotSwap.isAboutTheSession(
			"No hot code replace provider is registered"))
	}

	/// **The ordinary case, and it must not silence anything.** HotSpot replaces
	/// method bodies and nothing else, so these are what most saves produce.
	@Test func whatHotSpotRefusesIsAboutTheChange() {
		#expect(JavaDebug.HotSwap.isAboutTheSession("Add method not implemented") == false)
		#expect(JavaDebug.HotSwap.isAboutTheSession("Delete method not implemented") == false)
		#expect(JavaDebug.HotSwap.isAboutTheSession("Schema change not implemented") == false)
		#expect(JavaDebug.HotSwap.isAboutTheSession("class redefinition failed: attempted to add a field") == false)
		#expect(JavaDebug.HotSwap.isAboutTheSession("hierarchy change not implemented") == false)
	}

	/// A sentence with neither shape in it is about the change, because that is
	/// the reading whose cost is one message too many rather than none at all.
	@Test func anythingUnrecognisedIsAboutTheChange() {
		#expect(JavaDebug.HotSwap.isAboutTheSession("something went wrong") == false)
		#expect(JavaDebug.HotSwap.isAboutTheSession("") == false)
	}
}

/// The stack moving under somebody.
struct JavaHotSwapFrameTests {
	/// The provider carries `attemptDropToFrame` and `attemptStepIn`, so a
	/// session stopped in a method it just swapped is somewhere else afterwards.
	@Test func aSwapWhileStoppedMovesTheStack() {
		let ended = JavaDebug.HotSwap.Event(stage: .end, message: nil)
		#expect(JavaDebug.HotSwap.movedTheStack(ended, wasStopped: true))
		#expect(JavaDebug.HotSwap.movedTheStack(ended, wasStopped: false) == false)
	}

	@Test func nothingIsSaidAboutTheStackBeforeTheSwapLands() {
		for stage in [JavaDebug.HotSwap.Stage.starting, .buildComplete, .error, .warning] {
			let event = JavaDebug.HotSwap.Event(stage: stage, message: nil)
			#expect(JavaDebug.HotSwap.movedTheStack(event, wasStopped: true) == false)
		}
	}
}

/// The mode, which is the adapter's setting and not this app's.
struct JavaHotSwapModeTests {
	@Test func theThreeTheAdapterHas() {
		#expect(JavaDebug.HotSwap.Mode.auto.rawValue == "AUTO")
		#expect(JavaDebug.HotSwap.Mode.manual.rawValue == "MANUAL")
		#expect(JavaDebug.HotSwap.Mode.never.rawValue == "NEVER")
	}

	/// **A JSON string and not an object**, the same as `classpathOptions`.
	/// Passing a dictionary reached the server and stopped there — `Parameters
	/// for userSettings must be json string: {hotCodeReplace=AUTO}` on jdtls's
	/// stderr and nothing in the app, so the setting silently did not take.
	@Test func theSettingIsPreEncoded() throws {
		let said = JavaDebug.HotSwap.settings(mode: .auto)
		let read = try #require(
			JSONSerialization.jsonObject(with: Data(said.utf8)) as? [String: String]
		)
		#expect(read["hotCodeReplace"] == "AUTO")
		#expect(JavaDebug.HotSwap.settings(mode: .never).contains("\"NEVER\""))
	}

	/// **Carried whether or not anybody asked for it.** The server merges this
	/// into its settings and then parses `logLevel` unconditionally, so a
	/// settings update that omits it ends in a `NullPointerException` inside
	/// `LogUtils.configLogLevel` — on jdtls's stderr, and nowhere the app would
	/// notice.
	@Test func theLogLevelIsThereBecauseTheServerParsesItRegardless() throws {
		let read = try #require(JSONSerialization.jsonObject(
			with: Data(JavaDebug.HotSwap.settings(mode: .auto).utf8)
		) as? [String: String])
		#expect(read["logLevel"] == "WARNING")
	}

	/// **The build command wants one too, and did not get one.** A bare `false`
	/// threw `ClassCastException: Boolean cannot be cast to String` inside the
	/// server, into a `try?` that dropped it — so the compile a launch depends
	/// on had never run. Encoded, jdtls answers `Time cost for ECJ: 1ms`.
	@Test func theBuildCommandIsPreEncodedToo() throws {
		let read = try #require(JSONSerialization.jsonObject(
			with: Data(JavaDebug.buildOptions().utf8)
		) as? [String: Bool])
		#expect(read["isFullBuild"] == false)
		#expect(JavaDebug.buildOptions(fullBuild: true).contains("true"))
	}

	@Test func theCommandsAreTheOnesTheBundleRegisters() {
		#expect(JavaDebug.settingsCommand == "vscode.java.updateDebugSettings")
		#expect(JavaDebug.HotSwap.command == "redefineClasses")
		#expect(JavaDebug.HotSwap.event == "hotcodereplace")
	}
}
