import Foundation
import Testing
@testable import AbydosKit

/// Which project a place belongs to, which is the question behind whose
/// breakpoints a window is holding.
///
/// A debug session outlives the project switch that leaves it running, and the
/// window has to be able to say that the pane still reporting breakpoints is
/// the *other* project's — otherwise they are drawn in this project's gutter
/// and written into this project's session file as its own. Which is how a
/// `screencasts` checkout that has never been debugged came to hold breakpoints
/// in a Java application and in a Go example.
struct ProjectContainmentTests {
	@Test func aProjectIsInsideItself() {
		let root = URL(fileURLWithPath: "/p/abydos")
		#expect(FilePath.isInside(root, of: root))
	}

	@Test func aSubprojectIsInsideTheRepository() {
		#expect(FilePath.isInside(
			URL(fileURLWithPath: "/p/abydos/Sources/AbydosKit"),
			of: URL(fileURLWithPath: "/p/abydos")
		))
	}

	/// The separator is part of the question. Without it `abydos-examples` is
	/// inside `abydos`, and the two projects this was found between are named
	/// exactly that way.
	@Test func aSiblingSharingAPrefixIsNot() {
		#expect(!FilePath.isInside(
			URL(fileURLWithPath: "/p/abydos-examples/go-service"),
			of: URL(fileURLWithPath: "/p/abydos")
		))
	}

	@Test func anUnrelatedProjectIsNot() {
		#expect(!FilePath.isInside(
			URL(fileURLWithPath: "/p/almplus"),
			of: URL(fileURLWithPath: "/p/vehub/screencasts")
		))
	}

	/// Canonical on both sides, or the answer is about spelling: a Mac's `/tmp`
	/// is `/private/tmp`, and a comparison that does not know it says a
	/// directory is outside the very project it is in.
	@Test func spellingDoesNotDecideIt() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("containment-\(UUID().uuidString)")
		let inner = root.appendingPathComponent("Sources")
		try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(FilePath.isInside(inner, of: URL(fileURLWithPath: root.path)))
		#expect(FilePath.isInside(
			URL(fileURLWithPath: FilePath.canonical(inner)),
			of: root
		))
	}
}
