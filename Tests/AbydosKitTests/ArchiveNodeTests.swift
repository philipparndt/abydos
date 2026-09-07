import Foundation
import Testing
@testable import AbydosKit

/// The rows the tree makes of an archive.
struct ArchiveNodeTests {
	private func index() -> ArchiveIndex {
		let entries = [
			ArchiveEntry(path: "chart/values.yaml", member: .regular, size: 57, source: .tar(offset: 0)),
			ArchiveEntry(path: "chart/templates/deployment.yaml", member: .regular, size: 17, source: .tar(offset: 512)),
			ArchiveEntry(path: "chart/Chart.yaml", member: .regular, size: 42, source: .tar(offset: 1024)),
			ArchiveEntry(path: "chart/link", member: .symlink(to: "values.yaml"), size: 0, source: .tar(offset: 1536)),
		]
		return ArchiveIndex(url: URL(fileURLWithPath: "/p/chart-0.1.0.tgz"), kind: .tarGzip, key: .init(size: 1, modified: .distantPast), entries: entries, bytes: Data())
	}

	@Test func theRowsAreFoldersFirstThenNamesWithSizesInTheGreyHalf() {
		let root = ArchiveRoot(url: URL(fileURLWithPath: "/p/chart-0.1.0.tgz"))
		root.set(index: index())
		#expect(root.children.map(\.name) == ["chart"])
		let chart = root.children[0]
		#expect(chart.isExpandable)
		#expect(chart.children.map(\.name) == ["templates", "Chart.yaml", "link", "values.yaml"])
		#expect(chart.children[3].subtitle == "57 B")
		#expect(chart.children[2].subtitle == "→ values.yaml")
		#expect(chart.children[2].isOpenable == false)
		#expect(chart.children[3].isOpenable)
		#expect(chart.children[0].subtitle == nil)
	}

	@Test func aRowKnowsWhereItCameFromAndItsFoldKey() {
		let root = ArchiveRoot(url: URL(fileURLWithPath: "/p/chart-0.1.0.tgz"))
		root.set(index: index())
		let templates = root.node(forPath: "chart/templates")
		#expect(templates?.foldKey(archiveKey: "archive:deploy/chart-0.1.0.tgz") == "archive:deploy/chart-0.1.0.tgz!chart/templates")
		let values = root.node(forPath: "chart/values.yaml")
		#expect(values?.origin == ArchiveOrigin(archive: URL(fileURLWithPath: "/p/chart-0.1.0.tgz"), entryPath: "chart/values.yaml"))
		#expect(values?.origin?.said == "inside chart-0.1.0.tgz")
		#expect(values?.foldKey(archiveKey: "x") == nil)
	}

	@Test func beforeTheIndexArrivesTheRootIsReadingAndAFailureIsARow() {
		let root = ArchiveRoot(url: URL(fileURLWithPath: "/p/x.zip"))
		#expect(root.isReading)
		root.set(failure: "This is not an archive this app can read.")
		#expect(!root.isReading)
		#expect(root.children.map(\.name) == ["This is not an archive this app can read."])
		#expect(root.children[0].isExpandable == false)
	}
}
