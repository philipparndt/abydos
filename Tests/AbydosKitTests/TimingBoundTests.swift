import Testing
import Foundation

/// That no test puts an upper bound on a duration without asking whether it may.
///
/// **Flaky tests are worse than no tests**, and every flake this suite has had
/// is the same one: a number chosen from what somebody watched fail. 0435 is
/// seven suites with seven different waits; 0472 is one assertion going red four
/// times in a day on the same commit and the same machine. The answer was
/// `MachineLoad` and `Stopwatch.maySay` — a bound on how long something took is
/// asserted only in a run that asked for one, on a machine quiet enough for the
/// number to mean anything, and printed with the load either way.
///
/// The machinery worked. What it lacked was anything to stop the next one being
/// written without it, and three were: two in `DebugRefusalLiveTests` and one in
/// `PerformanceTests`, sitting beside three neighbours that were guarded
/// properly. So this is `NamedSuiteTests` for the other rule, and for the same
/// reason that one gives — it needs saying somewhere that fails, not in a
/// comment.
///
/// **Only upper bounds.** `#expect(waited >= 1)` is load-immune: a busy machine
/// can only make it more true. It is the assertions that say something was
/// *fast enough* that stop being about the code.
///
/// **Two bounds are not performance claims but still need the load guard.** A
/// clock can be used to tell two *mechanisms* apart — a one-second deadline
/// from a program's own `sleep 120` — and any number between them says that.
/// Those take `Stopwatch.mayClassify`, which asks about the load without
/// needing `make timing`, and this accepts either. Both went red at 27 runnable
/// threads a core with the deadlines working perfectly, which is why a
/// classification is not exempt from the load question, only from `make
/// timing`'s.
struct TimingBoundTests {
	/// The names a measured duration goes by here.
	///
	/// `timeIntervalSince(` is in the list because a duration does not have to
	/// be given a name to be one: `#expect(Date().timeIntervalSince(began) < 30)`
	/// is the same assertion written inline, and it is the one this check missed
	/// on its first outing — found by a suite run at 27 runnable threads a core
	/// rather than by reading.
	///
	/// `timeIntervalSince1970` and `timeIntervalSinceNow` are deliberately not
	/// here. Those are questions about *when* something is, not about how long
	/// work took: a decoder checking a parsed date against a known epoch, or a
	/// test checking a recorded timestamp is recent. Load does not move them.
	private static let durations = [
		"took", "elapsed", "waited", "duration", "timeIntervalSince(",
	]

	/// How far above an `#expect` a guard may sit and still be its guard.
	///
	/// A handful of lines, because that is what the guarded ones look like: the
	/// guard is written immediately above the assertion it protects, usually
	/// with the print of the measurement between them.
	private static let guardWindow = 8

	@Test func noUpperBoundOnADurationIsAssertedUnguarded() throws {
		let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let names = try FileManager.default.contentsOfDirectory(atPath: tests.path)
			.filter { $0.hasSuffix(".swift") && $0 != "TimingBoundTests.swift" }
			.sorted()

		var offenders: [String] = []
		for name in names {
			let lines = try String(
				contentsOf: tests.appendingPathComponent(name), encoding: .utf8
			).components(separatedBy: "\n")

			for (index, line) in lines.enumerated() {
				guard line.contains("#expect("), Self.boundsADuration(line) else { continue }
				let from = max(0, index - Self.guardWindow)
				let nearby = lines[from...index].joined(separator: "\n")
				guard !nearby.contains("Stopwatch.maySay"),
				      !nearby.contains("Stopwatch.mayClassify")
				else { continue }
				offenders.append("\(name):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
			}
		}

		#expect(offenders.isEmpty, """
			An upper bound on a duration, asserted whatever the machine was doing. \
			Put it behind `Stopwatch.maySay` — which is what `make timing` is for — or, \
			if the clock is only telling two mechanisms apart, `Stopwatch.mayClassify`. \
			Print `MachineLoad.said` beside the number either way, so a run that \
			declined the bound still leaves the evidence:

			\(offenders.joined(separator: "\n"))
			""")
	}

	/// Whether this line puts an *absolute* ceiling on a measured duration.
	///
	/// **Relative comparisons are left alone, and that is the whole subtlety.**
	/// `#expect(firstAt.timeIntervalSince(started) < took)` and
	/// `#expect(Date().timeIntervalSince(secondBegan) < waited / 2)` are claims
	/// that one measurement is smaller than another, and a loaded machine moves
	/// both — the first says output arrived before the run ended, the second
	/// that a cached answer beat an uncached one. Neither becomes false because
	/// the machine is busy. It is a ceiling of *this many seconds* that stops
	/// being about the code, so that is what this looks for: a numeric literal
	/// on the right.
	///
	/// Deliberately crude otherwise: it reads test sources, not Swift. A false
	/// positive costs whoever writes it a guard they did not strictly need,
	/// which is the cheaper way to be wrong — the expensive way is a red suite
	/// on somebody else's busy afternoon.
	static func boundsADuration(_ line: String) -> Bool {
		guard let expect = line.range(of: "#expect(") else { return false }
		let condition = line[expect.upperBound...]
		// `>=` and `>` are load-immune: a slow machine only makes them truer.
		guard let less = condition.range(of: "<") else { return false }
		let subject = condition[condition.startIndex..<less.lowerBound]
		guard durations.contains(where: { subject.contains($0) }) else { return false }
		return startsWithANumber(condition[less.upperBound...])
	}

	/// Whether what is being compared against is a plain number.
	static func startsWithANumber(_ text: Substring) -> Bool {
		let rest = text.drop { $0 == " " }
		guard let first = rest.first else { return false }
		return first.isNumber
	}
}
