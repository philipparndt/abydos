import Testing
@testable import AbydosKit

/// The directories above what was open, which the navigator restores expansion
/// from. The claims that matter are what it adds, and that it finishes: a path
/// it could not shorten once kept the main thread busy until the app was killed.
struct WithAncestorsTests {
	@Test func everyDirectoryAboveAPathIsAdded() {
		#expect(FilePath.withAncestors(of: ["/a/b/c"]) == ["/a/b/c", "/a/b", "/a"])
	}

	@Test func theFileSystemRootIsNotAnAncestorWorthAdding() {
		#expect(FilePath.withAncestors(of: ["/a"]) == ["/a"])
		#expect(FilePath.withAncestors(of: ["/"]) == ["/"])
	}

	@Test func whatIsNotAPathTravelsAsItIs() {
		#expect(FilePath.withAncestors(of: ["dep:x/y", "session:1"]) == ["dep:x/y", "session:1"])
	}

	@Test func aTrailingOrDoubledSlashAddsNoEmptyName() {
		#expect(FilePath.withAncestors(of: ["/a//b/"]) == ["/a//b/", "/a"])
	}

	/// The inputs `URL.deletingLastPathComponent()` may answer by growing rather
	/// than shrinking. Finishing at all is the test.
	@Test func aPathWithDotsInItFinishes() {
		#expect(FilePath.withAncestors(of: ["/a/.."]) == ["/a/..", "/a"])
		#expect(FilePath.withAncestors(of: ["/.."]) == ["/.."])
		#expect(FilePath.withAncestors(of: ["/a/./b"]) == ["/a/./b", "/a/.", "/a"])
	}
}
