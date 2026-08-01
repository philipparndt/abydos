import Foundation
import Testing
@testable import IdeaiKit

/// Arranging a profile for looking at.
struct FlameGraphTests {
	/// A stack, as the profile would report it: leaf first.
	private func sample(_ frames: [UInt64], _ value: Int64) -> PprofProfile.Sample {
		PprofProfile.Sample(locationIDs: frames, values: [value])
	}

	/// main → work → hash, and main → work → compare.
	private func profile() -> PprofProfile {
		let names = ["main", "work", "hash", "compare"]
		var locations: [UInt64: PprofProfile.Location] = [:]
		var functions: [UInt64: PprofProfile.Function] = [:]
		for (index, name) in names.enumerated() {
			let id = UInt64(index + 1)
			locations[id] = PprofProfile.Location(id: id, functionIDs: [id])
			functions[id] = PprofProfile.Function(id: id, name: name, fileName: "x.go")
		}
		return PprofProfile(
			valueTypes: [PprofProfile.ValueType(kind: "cpu", unit: "nanoseconds")],
			samples: [
				sample([3, 2, 1], 300),
				sample([4, 2, 1], 100),
				sample([2, 1], 50),
			],
			locations: locations,
			functions: functions
		)
	}

	@Test func buildsATreeFromTheOutsideIn() {
		let graph = FlameGraph.build(from: profile())

		#expect(graph.total == 450)
		#expect(graph.root.children.map(\.name) == ["main"])

		let main = graph.root.children[0]
		#expect(main.value == 450)
		#expect(main.children.map(\.name) == ["work"])

		// Widest first, so the graph reads left to right in order of cost.
		let work = main.children[0]
		#expect(work.children.map(\.name) == ["hash", "compare"])
		#expect(work.children.map(\.value) == [300, 100])
		#expect(work.selfValue == 50)
	}

	@Test func attributesFlatTimeToTheLeaf() {
		let graph = FlameGraph.build(from: profile())
		let byName = Dictionary(uniqueKeysWithValues: graph.functions.map { ($0.name, $0) })

		#expect(byName["hash"]?.flat == 300)
		#expect(byName["main"]?.flat == 0)
		#expect(byName["work"]?.flat == 50)

		#expect(byName["main"]?.cumulative == 450)
		#expect(byName["work"]?.cumulative == 450)
		#expect(byName["compare"]?.cumulative == 100)
	}

	/// The table is read from the top, so the heaviest function is there.
	@Test func ordersFunctionsByWhatTheyCost() {
		let graph = FlameGraph.build(from: profile())
		#expect(graph.functions.first?.name == "hash")
	}

	/// A recursive stack must not count its own time once per level.
	@Test func countsRecursionOnce() {
		var locations: [UInt64: PprofProfile.Location] = [:]
		var functions: [UInt64: PprofProfile.Function] = [:]
		for id in UInt64(1)...2 {
			locations[id] = PprofProfile.Location(id: id, functionIDs: [id])
			functions[id] = PprofProfile.Function(
				id: id, name: id == 1 ? "main" : "recurse", fileName: "x.go"
			)
		}
		let profile = PprofProfile(
			valueTypes: [PprofProfile.ValueType(kind: "cpu", unit: "nanoseconds")],
			samples: [sample([2, 2, 2, 1], 90)],
			locations: locations,
			functions: functions
		)

		let graph = FlameGraph.build(from: profile)
		let recurse = try? #require(graph.functions.first { $0.name == "recurse" })
		#expect(recurse?.cumulative == 90)
		#expect(recurse?.flat == 90)
		#expect(graph.total == 90)
	}

	@Test func ignoresSamplesWorthNothing() {
		let profile = PprofProfile(
			valueTypes: [PprofProfile.ValueType(kind: "cpu", unit: "nanoseconds")],
			samples: [sample([1], 0)],
			locations: [1: PprofProfile.Location(id: 1, functionIDs: [1])],
			functions: [1: PprofProfile.Function(id: 1, name: "idle", fileName: "x.go")]
		)
		#expect(FlameGraph.build(from: profile).total == 0)
		#expect(FlameGraph.build(from: profile).root.children.isEmpty)
	}

	/// The whole point of the thing: a real profile, read end to end.
	@Test func readsARealProfile() throws {
		let url = try #require(Bundle.module.url(
			forResource: "cpu", withExtension: "pprof", subdirectory: "Fixtures"
		))
		let graph = FlameGraph.build(from: try PprofDecoder.decode(try Data(contentsOf: url)))

		#expect(graph.unit == "nanoseconds")
		#expect(graph.total > 0)
		#expect(graph.functions.first?.name == "main.fibonacci")
		#expect(graph.root.depth > 3)
	}
}

/// Numbers as a profiler writes them.
struct ProfileValueTests {
	@Test func writesDurations() {
		#expect(ProfileValue.format(1_500_000_000, unit: "nanoseconds") == "1.5s")
		#expect(ProfileValue.format(340_000_000, unit: "nanoseconds") == "340ms")
		#expect(ProfileValue.format(1_200, unit: "nanoseconds") == "1.2µs")
		#expect(ProfileValue.format(999, unit: "nanoseconds") == "999ns")
	}

	@Test func writesSizes() {
		#expect(ProfileValue.format(2_147_483_648, unit: "bytes") == "2GB")
		#expect(ProfileValue.format(1_536, unit: "bytes") == "1.5kB")
		#expect(ProfileValue.format(12, unit: "bytes") == "12B")
	}

	@Test func writesCountsPlainly() {
		#expect(ProfileValue.format(42, unit: "count") == "42")
	}

	/// A share too small to round to a digit is still not none.
	@Test func writesShares() {
		#expect(ProfileValue.percentage(50, of: 100) == "50%")
		#expect(ProfileValue.percentage(15, of: 1000) == "1.5%")
		#expect(ProfileValue.percentage(1, of: 10_000) == "<1%")
		#expect(ProfileValue.percentage(0, of: 10) == "0%")
		#expect(ProfileValue.percentage(5, of: 0) == "0%")
	}
}
