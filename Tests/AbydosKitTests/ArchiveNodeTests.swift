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

	/// The selection survives a rebuild by name, and a file has a name too.
	///
	/// `foldKey` answers for directories alone, which is right for what is
	/// *open* — a file cannot be. What is *selected* is a file far more often
	/// than not, and that is the row whose highlight went out on every
	/// filesystem event.
	@Test func aSelectedRowIsRememberedByItsPathInsideTheArchive() {
		let root = ArchiveRoot(url: URL(fileURLWithPath: "/p/chart-0.1.0.tgz"))
		root.set(index: index())
		let key = "archive:deploy/chart-0.1.0.tgz"

		let values = root.node(forPath: "chart/values.yaml")
		#expect(values?.selectionKey(archiveKey: key) == "\(key)!chart/values.yaml")
		// The directory answers as well, and with the same key its fold uses.
		let templates = root.node(forPath: "chart/templates")
		#expect(templates?.selectionKey(archiveKey: key) == templates?.foldKey(archiveKey: key))

		// And the key finds the row again, which is the whole of putting a
		// selection back.
		let inside = (values?.selectionKey(archiveKey: key) ?? "")
			.dropFirst(key.count + 1)
		#expect(root.node(forPath: String(inside)) === values)
	}

	/// Nothing to find afterwards, so nothing is kept.
	@Test func aNoteRowHasNoSelectionKey() {
		let root = ArchiveRoot(url: URL(fileURLWithPath: "/p/x.zip"))
		root.set(failure: "This is not an archive this app can read.")
		#expect(root.children[0].selectionKey(archiveKey: "archive:x.zip") == nil)
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
