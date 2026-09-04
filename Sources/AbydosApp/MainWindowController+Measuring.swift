import AppKit
import AbydosKit

/// What the window measures about itself, when a driven run asks.
///
/// **A subject rather than a seam.** These three answer "how long did it take",
/// and each of them says the load average beside the number, because a duration
/// written down without what the machine was doing is a duration nobody can
/// argue with afterwards. They left `+Driving2` when it went over the length
/// limit, and this is the one part of it that names a topic instead of a half.
extension MainWindowController {
	/// Everything 0428 asks a running window for, printed in one place.
	///
	/// One report rather than a flag per number, because these have to be read
	/// together: a "time to something usable" of four seconds means one thing
	/// beside a tree of 400 rows and another beside a tree of 40,000, and the
	/// load average has to sit next to both or neither can be argued with later.
	func scaleReportForTesting(typing presses: Int) {
		// First, and the whole path. Driving this app with `--open` has come up
		// on something from the recent list before now, and a set of timings
		// labelled "platform" that were taken on whatever was open last is
		// worse than no timings: they look like an answer. A harness can refuse
		// to believe the rest of this report unless this line names what it
		// asked for.
		print("OPEN project \(project?.root.path ?? "nothing")")
		for line in LaunchClock.report() { print(line) }
		for line in navigator.scaleReportForTesting() { print(line) }
		// Beside the watcher's batches, because the pair is the finding: before
		// 0446 these were the same number, and the whole of the fix is the
		// distance between them.
		let runs = RunCoordinator.runConfigurationTallyForTesting
		print(String(format: "OPEN %-24s %8d asked, %d skipped, %d coalesced, %d walked",
			("run configurations" as NSString).utf8String!,
			runs.asked, runs.skipped, runs.coalesced, runs.walked))

		if presses > 0 {
			let costs = editor.measureTypingForTesting(presses: presses)
			if costs.isEmpty {
				print("OPEN keystroke                no file open")
			} else {
				let walls = costs.map { $0.wall }.sorted()
				let cpus = costs.map { $0.cpu }.sorted()
				// Median and worst, not the mean. The mean of a hundred
				// keystrokes hides the one that took 300 ms, and the one that
				// took 300 ms is the entire complaint.
				func at(_ values: [TimeInterval], _ fraction: Double) -> Double {
					values[min(values.count - 1, Int(Double(values.count) * fraction))] * 1000
				}
				print(String(format: "OPEN keystroke wall       %8.2f ms median, %.2f ms p90, %.2f ms worst",
					at(walls, 0.5), at(walls, 0.9), walls.last! * 1000))
				print(String(format: "OPEN keystroke cpu        %8.2f ms median, %.2f ms p90, %.2f ms worst",
					at(cpus, 0.5), at(cpus, 0.9), cpus.last! * 1000))
			}
		}

		// The main thread going away is what "usable" fails to be, so the worst
		// of them are printed with the numbers rather than left in the log.
		for stall in StallWatch.worst(limit: 8) { print("OPEN stall \(stall.line)") }
	}

	/// What switching to another project costs, in the one number that matters:
	/// how long the main thread is gone.
	///
	/// The complaint is not that a large project takes a while to finish
	/// arriving — it is that the window stops answering while it does, so
	/// switching between projects "feels like it crashed" and the terminal
	/// stops drawing with it. The wall time around `switchProject` *is* that
	/// number: it runs on the main thread, so nothing else can happen inside it.
	///
	/// The stalls are printed beside it because the total says a switch was
	/// slow and `StallWatch` says which part of it was, which is the difference
	/// between a number and a lead.
	func measureProjectSwitchForTesting(to root: URL) {
		StallWatch.clear()
		let before = Date()
		switchProject(to: root)
		let elapsed = Date().timeIntervalSince(before) * 1000

		print(String(format: "SWITCH main thread held    %8.2f ms", elapsed))
		// The load beside the number, which the house rules ask for: a timing
		// without it cannot be told from a regression.
		var average = [Double](repeating: 0, count: 3)
		getloadavg(&average, 3)
		print(String(format: "SWITCH load                %.2f %.2f %.2f",
			average[0], average[1], average[2]))

		// After the run loop has turned a few times: the work this is about
		// finishing off the main thread is exactly the work that would not show
		// up in a reading taken the instant the call returned.
		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
			for stall in StallWatch.worst(limit: 8) { print("SWITCH stall \(stall.line)") }
			// What arrived after the switch returned. The point of moving the
			// walks off the main thread is that these land *later*, so a reading
			// that did not check them would be measuring the app forgetting to
			// do the work rather than doing it elsewhere.
			print("SWITCH deps \(self.navigator.dependencyReportForTesting().joined(separator: " | "))")
			print("SWITCH settled")
			// Flushed, because stdout to a pipe is block-buffered and a harness
			// that kills the app when it has seen enough would otherwise lose
			// every line written after the last flush — which is all of these.
			fflush(stdout)
		}
	}

	/// Asks the language server a real question, over and over, until it answers.
	///
	/// 0428's missing number — *time until Java answers* — and the reason it went
	/// missing twice over. Once because the app was burning eight cores beside
	/// the server, so any figure would have described the app rather than the
	/// server; 0446 fixed that. And once because there was no way to ask: every
	/// other driver flag puts one question at a fixed delay, which can only tell
	/// you whether the delay happened to be long enough. On a Tycho reactor the
	/// honest answer is minutes, and a twelve-second `--lsp-wait` reports silence
	/// from a server that was working perfectly well.
	///
	/// Three questions rather than one, because they become answerable at
	/// different moments and the distance between them is the finding. An outline
	/// of the open file needs only that file parsed; completion and
	/// go-to-definition need the classpath, which for jdtls means the reactor
	/// imported. A server that answers the first at once and the last at four
	/// minutes is a very different thing to wait for than one that answers
	/// nothing until it is ready.
	///
	/// **And two more, for the debugger**, which is 0452's question and could not
	/// be asked either: whether the adapter inside the server is listening, and
	/// whether the import has got far enough to say what a launch would *run*.
	/// Taken on the same run as the file questions on purpose — one machine, one
	/// load — so that "the adapter was ready at fifty seconds while completion
	/// was still silent at eleven minutes" is a comparison rather than two
	/// readings from two afternoons.
	///
	/// **In a loop of their own, and that is not tidiness.** The first reading
	/// taken here put all five in one round and reported the adapter at 50.6
	/// seconds — five milliseconds after the outline, in the same round, which is
	/// the shape of a number bounded by its neighbours rather than measured. A
	/// round is as slow as the slowest question in it, `completion` was timing out
	/// at thirty seconds a go, and the adapter had very likely been listening for
	/// most of that. Two loops, one request each, and the two figures are then
	/// about the two things.
	///
	/// The file questions are asked together each round so a round costs one
	/// request timeout rather than three, and the granularity of every figure
	/// below is therefore the round — a second, plus however long the server took
	/// to refuse.
	func measureFirstAnswerForTesting(line: Int, character: Int, deadline: TimeInterval) {
		guard let project else {
			print("ANSWER no project")
			fflush(stdout)
			return
		}
		let position = LSPPosition(line: line, character: character)

		func say(_ what: String, _ detail: String) {
			let at = Date().timeIntervalSince(LaunchClock.processStart)
			print(String(format: "ANSWER %-16s %8.0f ms  %@  (%@)",
				(what as NSString).utf8String!, at * 1000,
				detail as NSString, LaunchClock.loadSaid as NSString))
			fflush(stdout)
		}

		func silence(_ what: String, _ waited: TimeInterval) {
			print(String(format: "ANSWER %-16s      —     still silent at %.0f s",
				(what as NSString).utf8String!, waited))
			fflush(stdout)
		}

		/// The file on screen, once the editor has finished opening it. On a large
		/// project the window arrives before the file does.
		func onScreen() -> (url: URL, languageId: String)? {
			guard let url = editor.activeGroup?.activeTabURL,
			      let languageId = editor.activeGroup?.activeDocument?.languageId
			else { return nil }
			return (url, languageId)
		}

		// What the editor asks for.
		Task { @MainActor in
			var outline = false, completion = false, definition = false
			while !(outline && completion && definition),
			      Date().timeIntervalSince(LaunchClock.processStart) < deadline {
				guard let (url, languageId) = onScreen() else {
					try? await Task.sleep(nanoseconds: 500_000_000)
					continue
				}

				let service = LanguageService.shared
				// The file's own root, not the scope. Measuring against the
				// scope would time a server that was never going to answer
				// about this file — which is the fault this verb is being used
				// to check, measured wrongly.
				let root = service.root(for: url, languageId: languageId, project: project.root)
				async let symbols = service.documentSymbols(url: url, languageId: languageId, project: root)
				async let completions = service.completions(
					url: url, position: position, languageId: languageId, project: root)
				async let locations = service.definition(
					url: url, position: position, languageId: languageId, project: root)
				let (foundSymbols, foundCompletions, foundLocations) =
					await (symbols, completions, locations)

				if !outline, !foundSymbols.isEmpty {
					outline = true
					say("outline", "\(foundSymbols.count) symbols in \(url.lastPathComponent)")
				}
				if !completion, !foundCompletions.isEmpty {
					completion = true
					say("completion", "\(foundCompletions.count) suggestions")
				}
				if !definition, let first = foundLocations.first {
					definition = true
					say("definition", first.url?.lastPathComponent ?? "somewhere")
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}

			// Silence is a result and has to be printed as one. A missing line
			// reads as a harness that crashed; "still silent at 300 s" is the
			// answer to the question that was asked.
			let waited = Date().timeIntervalSince(LaunchClock.processStart)
			for (what, answered) in [
				("outline", outline), ("completion", completion), ("definition", definition),
			] where !answered { silence(what, waited) }
			print(String(format: "ANSWER done               %8.0f ms  %@", waited * 1000,
				LaunchClock.loadSaid as NSString))
			fflush(stdout)
		}

		// What the debugger asks for, on its own clock.
		Task { @MainActor in
			var adapter = false, classpath = false
			while !(adapter && classpath),
			      Date().timeIntervalSince(LaunchClock.processStart) < deadline {
				guard let open = onScreen() else {
					try? await Task.sleep(nanoseconds: 500_000_000)
					continue
				}
				// A file that is open and is not Java: nothing here hosts an
				// adapter, so these are not questions this project can be asked.
				// Left unsaid rather than reported as silence, which would put two
				// lines about a debugger at the end of every run that was not
				// about Java.
				guard open.languageId == "java" else { return }
				let url = open.url
				let ready = await LanguageService.shared
					.javaDebugReadinessForTesting(
						url: url,
						project: LanguageService.shared.root(
							for: url, languageId: open.languageId, project: project.root
						)
					)
				if !adapter, let port = ready.port {
					adapter = true
					say("debug adapter", "listening on port \(port)")
				}
				// An answer with nothing in it is an answer, and it is reported as
				// one. jdtls does that on a Tycho bundle — promptly, and for ever —
				// and a harness that counted it as silence would report a wait that
				// was never going to end as a wait.
				if !classpath, let count = ready.classPaths {
					classpath = true
					say("debug classpath", count == 0
						? "answered, and empty — nothing to launch a JVM with"
						: "\(count) entries")
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}

			let waited = Date().timeIntervalSince(LaunchClock.processStart)
			for (what, answered) in [("debug adapter", adapter), ("debug classpath", classpath)]
			where !answered { silence(what, waited) }
		}
	}
}
