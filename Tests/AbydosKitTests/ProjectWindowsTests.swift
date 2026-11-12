import Foundation
import Testing
@testable import AbydosKit

/// Which window is showing a project, asked before any window is given one.
struct ProjectWindowsTests {
	private func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

	@Test func theWindowOnTheProjectIsFound() {
		let roots = [url("/projects/website"), url("/projects/abydos")]
		#expect(ProjectWindows.index(showing: url("/projects/abydos"), among: roots) == 1)
	}

	@Test func aProjectNoWindowHasIsNotFound() {
		let roots = [url("/projects/website")]
		#expect(ProjectWindows.index(showing: url("/projects/abydos"), among: roots) == nil)
	}

	/// A window with nothing open, or one that is not a project window, is
	/// passed in as nil and never matches.
	@Test func aWindowWithNoProjectIsNeverTheAnswer() {
		let roots: [URL?] = [nil, url("/projects/abydos")]
		#expect(ProjectWindows.index(showing: url("/projects/abydos"), among: roots) == 1)
	}

	@Test func anotherSpellingOfTheSameDirectoryIsTheSameProject() {
		let roots = [url("/projects/./abydos/")]
		#expect(ProjectWindows.index(showing: url("/projects/abydos"), among: roots) == 0)
	}

	/// `/tmp` is a link to `/private/tmp`; both are one directory, so a project
	/// opened by one name is open by the other.
	@Test func aLinkedSpellingOfTheSameDirectoryIsTheSameProject() {
		let roots = [url("/private/tmp")]
		#expect(ProjectWindows.index(showing: url("/tmp"), among: roots) == 0)
	}

	/// A folder inside a project is not that project: a window on a package of
	/// a monorepo and a window on the monorepo are two projects.
	@Test func aFolderInsideAProjectIsNotThatProject() {
		let roots = [url("/projects/abydos")]
		#expect(ProjectWindows.index(showing: url("/projects/abydos/Sources"), among: roots) == nil)
	}
}
