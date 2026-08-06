import Foundation
import Testing
@testable import AbydosKit

/// Watching a Go program's heap.
///
/// The fixture is what `/debug/vars` actually prints: `memstats` beside
/// whatever else the program publishes, with far more fields than are wanted.
struct GoMemoryWatchTests {
	private let vars = """
	{
	"cmdline": ["/tmp/service"],
	"requests": 4213,
	"memstats": {
		"Alloc": 4194304, "TotalAlloc": 88080384, "Sys": 24117248,
		"HeapAlloc": 4194304, "HeapSys": 16777216, "HeapInuse": 6291456,
		"HeapObjects": 12034, "NumGC": 7, "PauseTotalNs": 412000
	}
	}
	"""

	@Test func readsTheNumbersAChartNeeds() {
		let now = Date(timeIntervalSince1970: 1_750_000_000)
		let sample = GoMemoryWatch.parse(Data(vars.utf8), at: now)

		#expect(sample?.heapAlloc == 4_194_304)
		#expect(sample?.heapInuse == 6_291_456)
		#expect(sample?.sys == 24_117_248)
		#expect(sample?.collections == 7)
		#expect(sample?.at == now)
		#expect(sample?.uptime == nil, "most programs publish none")
	}

	/// A program that publishes when it started gets an x-axis that really is
	/// "since it started" rather than "since this was opened".
	@Test func aPublishedStartTimeBecomesUptime() {
		let now = Date(timeIntervalSince1970: 1_750_000_000)
		let text = "{\"start_time\": 1749999400, \"memstats\": {\"HeapAlloc\": 1}}"
		let sample = GoMemoryWatch.parse(Data(text.utf8), at: now)
		#expect(sample?.uptime == 600)
	}

	@Test func milliseconentsAreUnderstoodToo() {
		let now = Date(timeIntervalSince1970: 1_750_000_000)
		let text = "{\"startTime\": 1749999400000, \"memstats\": {\"HeapAlloc\": 1}}"
		#expect(GoMemoryWatch.parse(Data(text.utf8), at: now)?.uptime == 600)
	}

	/// Anything that is not a Go program with expvar on: an HTML page, a 404
	/// body, a JSON object with no memstats in it.
	@Test func somethingElseIsNotASample() {
		#expect(GoMemoryWatch.parse(Data("<html>404</html>".utf8), at: Date()) == nil)
		#expect(GoMemoryWatch.parse(Data("{\"requests\": 1}".utf8), at: Date()) == nil)
	}

	@Test func expvarSitsBesidePprof() {
		let base = URL(string: "http://localhost:6060/debug/pprof")!
		#expect(GoMemoryWatch.varsURL(for: base)?.absoluteString
			== "http://localhost:6060/debug/vars")
	}

	// MARK: - The series

	private func sample(_ heap: Int, _ seconds: TimeInterval) -> GoMemoryWatch.Sample {
		GoMemoryWatch.Sample(
			at: Date(timeIntervalSince1970: 1_750_000_000 + seconds),
			heapAlloc: heap, heapInuse: heap + 1024, sys: heap * 2, collections: 1
		)
	}

	@Test func aSeriesKnowsItsPeakAndItsSpan() {
		var series = GoMemoryWatch.Series()
		series.append(sample(1000, 0))
		series.append(sample(5000, 10))
		series.append(sample(2000, 20))

		#expect(series.peak == 5000 + 1024)
		#expect(series.span == 20)
		#expect(series.latest?.heapAlloc == 2000)
	}

	/// An hour of readings at one a second is enough to see a leak; keeping
	/// them all would be a leak of its own.
	@Test func theOldestReadingsAreDropped() {
		var series = GoMemoryWatch.Series(limit: 3)
		for index in 0..<5 { series.append(sample(index, TimeInterval(index))) }
		#expect(series.samples.count == 3)
		#expect(series.samples.first?.heapAlloc == 2, "the first two went")
	}

	/// A heap wanders by a few per cent between collections; calling that
	/// growth would cry wolf on every program.
	@Test func onlyRealGrowthCounts() {
		var steady = GoMemoryWatch.Series()
		for index in 0..<10 { steady.append(sample(1000 + index % 3, TimeInterval(index))) }
		#expect(!steady.isGrowing)

		var climbing = GoMemoryWatch.Series()
		for index in 0..<10 { climbing.append(sample(1000 + index * 200, TimeInterval(index))) }
		#expect(climbing.isGrowing)
	}

	@Test func bytesAreReadable() {
		#expect(GoMemoryWatch.format(bytes: 512) == "512 B")
		#expect(GoMemoryWatch.format(bytes: 4 * 1024 * 1024) == "4.0 MB")
		#expect(GoMemoryWatch.format(bytes: 1536 * 1024 * 1024) == "1.5 GB")
	}
}

/// The fallback for the many Go programs that have pprof but never imported
/// `expvar`: the same numbers, printed at the foot of a text heap profile.
struct GoMemoryWatchProfileFooterTests {
	private let profile = """
	heap profile: 3: 786432 [7: 2359296] @ heap/1048576
	1: 524288 [1: 524288] @ 0x104a1c8b4 0x104a4f0d4
	#	0x104a1c8b3	main.main.func2+0x33

	# runtime.MemStats
	# Alloc = 231570320
	# TotalAlloc = 233394128
	# Sys = 244988216
	# HeapAlloc = 231570320
	# HeapInuse = 232300544
	# NumGC = 7
	# PauseNs = [124000 89000 0]
	# DebugGC = false
	"""

	@Test func theFooterHasEverythingTheChartNeeds() {
		let now = Date(timeIntervalSince1970: 1_750_000_000)
		let sample = GoMemoryWatch.parseMemStatsText(profile, at: now)

		#expect(sample?.heapAlloc == 231_570_320)
		#expect(sample?.heapInuse == 232_300_544)
		#expect(sample?.totalAlloc == 233_394_128)
		#expect(sample?.collections == 7)
	}

	/// The lines that are not plain numbers — the pause histogram, the flags —
	/// are stepped over rather than read as zero.
	@Test func onlyTheNumbersAreRead() {
		let sample = GoMemoryWatch.parseMemStatsText(profile, at: Date())
		#expect(sample?.sys == 244_988_216)
	}

	@Test func aProfileWithoutMemStatsIsNotASample() {
		#expect(GoMemoryWatch.parseMemStatsText("heap profile: 0: 0 [0: 0]", at: Date()) == nil)
	}
}
