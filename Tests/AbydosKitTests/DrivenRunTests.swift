import Foundation
import Testing
@testable import AbydosKit

/// Telling a run somebody is driving from a run somebody is using, and keeping
/// the first away from the second's preferences. Item 0522.
struct DrivenRunTests {
	// MARK: - Which runs are driven

	/// The two ways a person opens something are not driving, and neither is a
	/// bare path — which is what `Scripts/abydos` and LaunchServices send.
	@Test func openingSomethingIsNotDriving() {
		#expect(!DrivenRun.isDriven(arguments: ["Abydos"]))
		#expect(!DrivenRun.isDriven(arguments: ["Abydos", "/dev/thing"]))
		#expect(!DrivenRun.isDriven(arguments: ["Abydos", "--open", "/dev/thing"]))
		#expect(!DrivenRun.isDriven(arguments: ["Abydos", "--file", "/dev/thing/a.swift"]))
		#expect(!DrivenRun.isDriven(
			arguments: ["Abydos", "--open", "/dev/thing", "--file", "a.swift", "--file", "b.swift"]
		))
	}

	/// The single-dash arguments the system adds are not verbs.
	@Test func theSystemsOwnArgumentsAreNotDriving() {
		#expect(!DrivenRun.isDriven(arguments: ["Abydos", "-psn_0_123456"]))
		#expect(!DrivenRun.isDriven(arguments: ["Abydos", "-NSDocumentRevisionsDebugMode", "YES"]))
	}

	/// Every verb that caused an incident, and none of them sets a screenshot
	/// path — which is why `isScreenshotRun` could not have been extended to do
	/// this job.
	@Test func theVerbsThatCausedTheIncidentsAreDriving() {
		for verb in ["--type", "--emacs-nav", "--switch-appearance", "--run-config", "--snippet", "--comment"] {
			#expect(DrivenRun.isDriven(arguments: ["Abydos", "--open", "/dev/thing", verb, "x"]),
			        "\(verb) should be a driven run")
		}
	}

	/// The rule is "anything that is not one of the two", so a verb nobody has
	/// written yet is already covered.
	@Test func averbNobodyHasWrittenYetIsDriving() {
		#expect(DrivenRun.isDriven(arguments: ["Abydos", "--a-verb-invented-tomorrow"]))
	}

	// MARK: - Where a driven run's preferences go

	/// The point of the whole item: what a driven run writes goes nowhere the
	/// real app can read it.
	///
	/// Nothing here creates a preferences domain to check against, because a
	/// test that leaves a plist in somebody's `~/Library/Preferences` to prove
	/// that runs leave nothing behind would be its own counterexample. The
	/// process's own store is the witness instead, and it is asked before and
	/// after.
	@Test func adrivenRunWritesNothingIntoTheRealDomain() {
		let key = "abydos.driven.probe.\(UUID().uuidString)"
		#expect(UserDefaults.standard.object(forKey: key) == nil)

		let volatileDefaults = VolatileDefaults(copying: [key: "dracula"])
		volatileDefaults.set("light", forKey: key)

		#expect(volatileDefaults.string(forKey: key) == "light")
		#expect(UserDefaults.standard.object(forKey: key) == nil)
	}

	/// Seeded rather than empty: a driven run is a run of the app somebody
	/// actually has.
	@Test func adrivenRunStartsFromTheRealSettings() {
		let volatileDefaults = VolatileDefaults(copying: [
			"appearance": "dracula",
			"editorFontSize": 15.5,
			"fontLigatures": true,
			"excludedDirectories": ["node_modules", "target"],
		])

		#expect(volatileDefaults.string(forKey: "appearance") == "dracula")
		#expect(volatileDefaults.double(forKey: "editorFontSize") == 15.5)
		#expect(volatileDefaults.bool(forKey: "fontLigatures"))
		#expect(volatileDefaults.stringArray(forKey: "excludedDirectories") == ["node_modules", "target"])
	}

	/// The typed accessors are overridden rather than trusted to be sugar over
	/// `object(forKey:)`, and this is what says so: every one of them reads and
	/// writes the dictionary in memory.
	@Test func everyTypedAccessorStaysInMemory() {
		let volatileDefaults = VolatileDefaults(copying: [:])

		volatileDefaults.set(true, forKey: "flag")
		volatileDefaults.set(7, forKey: "count")
		volatileDefaults.set(1.25, forKey: "scale")
		volatileDefaults.set("abydos-light", forKey: "palette")
		volatileDefaults.set(["a", "b"], forKey: "list")
		volatileDefaults.set(["k": "v"], forKey: "map")
		volatileDefaults.set(Data([1, 2, 3]), forKey: "bytes")
		volatileDefaults.set(URL(fileURLWithPath: "/tmp/x"), forKey: "place")

		#expect(volatileDefaults.bool(forKey: "flag"))
		#expect(volatileDefaults.integer(forKey: "count") == 7)
		#expect(volatileDefaults.double(forKey: "scale") == 1.25)
		#expect(volatileDefaults.string(forKey: "palette") == "abydos-light")
		#expect(volatileDefaults.stringArray(forKey: "list") == ["a", "b"])
		#expect(volatileDefaults.dictionary(forKey: "map")?["k"] as? String == "v")
		#expect(volatileDefaults.data(forKey: "bytes") == Data([1, 2, 3]))
		#expect(volatileDefaults.url(forKey: "place")?.path == "/tmp/x")

		// And none of it is in the real store, which is the claim under all of
		// the above.
		for key in ["flag", "count", "scale", "palette", "list", "map", "bytes", "place"] {
			#expect(UserDefaults.standard.object(forKey: key) == nil, "\(key) escaped")
		}
	}

	/// A missing answer is the one the real `UserDefaults` gives, because that
	/// is what every caller in `Settings` is written against.
	@Test func amissingValueAnswersAsTheRealOneDoes() {
		let volatileDefaults = VolatileDefaults(copying: [:])
		#expect(volatileDefaults.object(forKey: "nothing") == nil)
		#expect(!volatileDefaults.bool(forKey: "nothing"))
		#expect(volatileDefaults.integer(forKey: "nothing") == 0)
		#expect(volatileDefaults.double(forKey: "nothing") == 0)
		#expect(volatileDefaults.string(forKey: "nothing") == nil)
		#expect(volatileDefaults.stringArray(forKey: "nothing") == nil)
	}

	/// `register(defaults:)` is a fallback and not a value, which is the
	/// distinction `Settings.init` turns on: a registered answer must not look
	/// like one somebody chose.
	@Test func registeredDefaultsAnswerButAreNotStored() {
		let volatileDefaults = VolatileDefaults(copying: [:])
		volatileDefaults.register(defaults: ["tabWidth": 4])

		#expect(volatileDefaults.integer(forKey: "tabWidth") == 4)
		volatileDefaults.set(2, forKey: "tabWidth")
		#expect(volatileDefaults.integer(forKey: "tabWidth") == 2)
		volatileDefaults.removeObject(forKey: "tabWidth")
		#expect(volatileDefaults.integer(forKey: "tabWidth") == 4)
	}

	/// The two domain writers are the way to the real store that does not go
	/// through `set`, so they do nothing at all.
	@Test func adrivenRunCannotWriteAnotherDomainEither() {
		let name = "de.rnd7.abydos.tests.\(UUID().uuidString)"
		let volatileDefaults = VolatileDefaults(copying: [:])

		volatileDefaults.setPersistentDomain(["appearance": "light"], forName: name)
		volatileDefaults.removePersistentDomain(forName: name)
		#expect(UserDefaults.standard.persistentDomain(forName: name) == nil)
	}

	// MARK: - The session

	/// The half of 0522 that would have prevented all three incidents on its
	/// own: what a driven run shows is what it was given, so there is nothing on
	/// screen for a typing verb to land in that somebody else put there.
	@Test func adrivenRunRestoresNoSession() throws {
		let root = try scratchProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let left = ProjectSession(
			files: [ProjectSession.OpenFile(path: root.appendingPathComponent("main.swift").path)],
			activePath: root.appendingPathComponent("main.swift").path
		)
		try SessionStore.write(left, in: root, driven: false)

		#expect(SessionStore.read(in: root, driven: false)?.files.count == 1)
		#expect(SessionStore.read(in: root, driven: true) == nil)
	}

	/// And it leaves nothing where it was pointed — not a session file, and for
	/// a project that has none, not an `.abydos` folder to put one in.
	@Test func adrivenRunWritesNoSessionAndMakesNoFolder() throws {
		let root = try scratchProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let session = ProjectSession(
			files: [ProjectSession.OpenFile(path: root.appendingPathComponent("main.swift").path)]
		)
		try SessionStore.write(session, in: root, driven: true)

		#expect(!FileManager.default.fileExists(atPath: AbydosFolder.url(in: root).path))
		#expect(SessionStore.read(in: root, driven: false) == nil)
	}

	private func scratchProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-0522-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		try "print(1)\n".write(
			to: root.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8
		)
		return root
	}

	/// And `Settings` handed one writes into it rather than into the machine.
	@Test func settingsOnAVolatileStoreLeavesTheMachineAlone() {
		let volatileDefaults = VolatileDefaults(copying: ["appearance": "abydos-light"])
		let settings = Settings(defaults: volatileDefaults)

		#expect(settings.appearance == "abydos-light")
		settings.appearance = "dracula"
		#expect(settings.appearance == "dracula")
		#expect(volatileDefaults.string(forKey: "appearance") == "dracula")

		// The real domain of the app under test was never opened for writing.
		#expect(UserDefaults.standard.object(forKey: "appearance") == nil)
	}
}
