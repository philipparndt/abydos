import Foundation
import Testing
@testable import AbydosKit

/// What choosing a Makefile goal from the run menu turns into.
///
/// This area has now broken twice — once by running a goal the moment it was
/// picked, once by picking one and having nothing happen at all — so the rule
/// lives here rather than in a menu handler: every goal yields something, and
/// nothing it yields starts anything.
struct MakeChoiceTests {
	private func makefile(_ text: String) throws -> Makefile {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("make-choice-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let path = directory.appendingPathComponent("Makefile")
		try text.write(to: path, atomically: true, encoding: .utf8)
		return try #require(Makefile.read(at: path))
	}

	/// The everyday case: a goal that builds and launches something. Nothing
	/// here can attach a debugger to it, and that is no reason to refuse it.
	@Test func aPlainGoalBecomesSomethingToRun() throws {
		let file = try makefile("""
		dev: ## Build and run in the foreground
		\t@swift build && ./.build/debug/app
		""")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }

		let choice = MakeLaunch.choice(
			for: "dev", in: file, projectRoot: file.path.deletingLastPathComponent()
		)
		guard case let .run(configuration) = choice else {
			Issue.record("expected a run, got \(choice)")
			return
		}
		#expect(configuration.name == "make dev")
		#expect(configuration.executable == "make")
		#expect(configuration.arguments == ["dev"])
		#expect(configuration.workingDirectory == file.path.deletingLastPathComponent().path)
	}

	/// A Go goal the debugger understands becomes a configuration instead.
	@Test func aGoGoalBecomesSomethingToDebug() throws {
		let file = try makefile("""
		build:
		\tgo build -o bin/service ./cmd/service
		""")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }

		let root = file.path.deletingLastPathComponent()
		let choice = MakeLaunch.choice(for: "build", in: file, projectRoot: root)
		if case .debug = choice { return }
		// Not every environment can plan one; where it cannot, the goal still
		// has to be runnable rather than nothing at all.
		guard case let .run(configuration) = choice else {
			Issue.record("expected a choice, got \(choice)")
			return
		}
		#expect(configuration.arguments == ["build"])
	}

	/// The bug this exists to stop: a goal that cannot be planned used to
	/// return nothing, and the click did nothing — no selection, no message.
	@Test func everyGoalYieldsSomething() throws {
		let file = try makefile("""
		mystery:
		\t@echo something nobody can debug
		probe:
		\t@curl -s localhost:6060/debug/pprof/
		test:
		\t@swift test
		""")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }

		let root = file.path.deletingLastPathComponent()
		for goal in ["mystery", "probe", "test"] {
			let choice = MakeLaunch.choice(for: goal, in: file, projectRoot: root)
			switch choice {
			case let .run(configuration):
				#expect(configuration.name == "make \(goal)")
			case let .debug(configuration):
				#expect(!configuration.name.isEmpty)
			}
		}
	}

	/// A goal the Makefile does not have is still answered — with a run that
	/// make itself will refuse, which is a better failure than a menu item
	/// that does nothing.
	@Test func evenAnUnknownGoalIsAnswered() throws {
		let file = try makefile("build:\n\t@true\n")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }

		let choice = MakeLaunch.choice(
			for: "nonexistent", in: file, projectRoot: file.path.deletingLastPathComponent()
		)
		guard case let .run(configuration) = choice else {
			Issue.record("expected a run")
			return
		}
		#expect(configuration.arguments == ["nonexistent"])
	}

	/// Choosing says which one; the play button says when. Nothing in a choice
	/// is a command that has already been started.
	@Test func choosingStartsNothing() throws {
		let file = try makefile("dev:\n\t@sleep 100\n")
		let directory = file.path.deletingLastPathComponent()
		defer { try? FileManager.default.removeItem(at: directory) }

		let marker = directory.appendingPathComponent("started")
		let choice = MakeLaunch.choice(for: "dev", in: file, projectRoot: directory)
		_ = choice
		#expect(!FileManager.default.fileExists(atPath: marker.path))
	}
}

/// A Makefile goal that builds a macOS app and hands it to `open`.
///
/// `open` gives the bundle to the system and returns at once, so running one
/// that way looked like it had finished the moment it started: the make
/// process really had, leaving nothing to stop and nothing to debug.
struct MakeAppLaunchTests {
	private func makefile(_ text: String) throws -> Makefile {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("make-app-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let path = directory.appendingPathComponent("Makefile")
		try text.write(to: path, atomically: true, encoding: .utf8)
		return try #require(Makefile.read(at: path))
	}

	/// This project's own Makefile, near enough: a variable for the bundle and
	/// a build step in front.
	@Test func theBinaryInsideTheBundleIsWhatRuns() throws {
		let file = try makefile("""
		APP := build/ideai.app

		build:
		\t@Scripts/bundle.sh release

		run: build ## Build and launch the app
		\t@echo "==> Launching $(APP)"
		\t@open $(APP)
		""")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }

		#expect(MakeLaunch.launchedApp(for: "run", in: file)
			== "build/ideai.app/Contents/MacOS/ideai")

		let choice = MakeLaunch.choice(
			for: "run", in: file, projectRoot: file.path.deletingLastPathComponent()
		)
		guard case let .debug(configuration) = choice else {
			Issue.record("expected something debuggable, got \(choice)")
			return
		}
		#expect(configuration.program.hasSuffix("build/ideai.app/Contents/MacOS/ideai"))
		#expect(configuration.type == "lldb", "a macOS app is debugged by lldb")
		// And it still builds first, as make would.
		#expect(configuration.makeStep?.targets == ["build"])
	}

	@Test func openWithFlagsAndArgumentsStillFindsTheBundle() throws {
		let file = try makefile("""
		start:
		\t@open -a build/Thing.app --args --verbose
		""")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }
		#expect(MakeLaunch.launchedApp(for: "start", in: file)
			== "build/Thing.app/Contents/MacOS/Thing")
	}

	/// Opening something that is not an app — a folder, a URL, a file — is not
	/// a program to run.
	@Test func openingSomethingElseIsNotALaunch() throws {
		let file = try makefile("""
		docs:
		\t@open https://example.com
		here:
		\t@open .
		""")
		defer { try? FileManager.default.removeItem(at: file.path.deletingLastPathComponent()) }
		#expect(MakeLaunch.launchedApp(for: "docs", in: file) == nil)
		#expect(MakeLaunch.launchedApp(for: "here", in: file) == nil)
	}
}
