import Foundation
import Testing
@testable import AbydosKit

/// A project's container and what it can run, kept together. 0438's second
/// fault.
///
/// **What this is a regression test for.** The session was kept when a
/// project's servers stopped — on purpose, so that switching away and back is
/// instant — and the list of language servers the container carries was dropped
/// on the same line. Switching back found the session, so nothing re-ran the
/// start that fills the list, so the guard on it failed, and every language in
/// the project was told its server was not in the container. It was; the app
/// had merely forgotten.
struct DevContainerAttachmentTests {
	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	/// A container that is up, as `DevContainers` hands one over.
	private func makeSession(named name: String, for project: URL) throws -> DevContainers.Session {
		let configuration = try #require(
			DevContainerFile.parse(
				Data(#"{"name": "python-language-server", "image": "python:3.12"}"#.utf8),
				project: project
			).configuration
		)
		return DevContainers.Session(
			name: name, configuration: configuration, runtime: .docker("/usr/bin/docker")
		)
	}

	/// **The one this item exists for.** Switch away from a project, switch back,
	/// and the server still starts in the container.
	///
	/// The three steps are exactly the app's: the container comes up and is asked
	/// what it has; the project's servers are stopped, which is what switching
	/// away does and what leaves the container running; and then something opens
	/// a `.py` file again and asks whether pyright can be started in there.
	@Test func switchingAwayAndBackKeepsWhatTheContainerCarries() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		var attachments = DevContainerAttachments()

		attachments.attach(
			try makeSession(named: "abydos-devcontainer-1", for: project),
			providing: ["pyright-langserver"],
			to: project
		)
		#expect(attachments.carries("pyright-langserver", for: project) == true)

		// Switching away. The container is left up deliberately — somebody's
		// shell may be in it — and so is everything known about it.
		attachments.letGo(project)

		// Switching back. The session is found, so nothing starts a container and
		// nothing re-asks what is inside it; the answer has to have survived.
		#expect(attachments[project] != nil)
		#expect(attachments.carries("pyright-langserver", for: project) == true)
	}

	/// "The image does not have it" and "nobody has asked yet" are different
	/// answers, and the strip above the file says different things about them.
	@Test func aProjectWithNoContainerIsNotAProjectWhoseContainerLacksTheServer() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		var attachments = DevContainerAttachments()

		#expect(attachments.carries("pyright-langserver", for: project) == nil)

		attachments.attach(
			try makeSession(named: "abydos-devcontainer-1", for: project),
			providing: ["gopls"],
			to: project
		)
		#expect(attachments.carries("pyright-langserver", for: project) == false)
		#expect(attachments.carries("gopls", for: project) == true)
	}

	/// What *was* about to happen is dropped, and that half of letting go is not
	/// an oversight: a language waiting for a container it is no longer going to
	/// get would leave the strip saying a server is on its way for ever.
	@Test func lettingGoDropsWhatWasWaitingAndHandsItBack() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		var attachments = DevContainerAttachments()

		attachments.wait(for: "python", in: project)
		attachments.wait(for: "go", in: project)
		#expect(attachments.letGo(project) == ["python", "go"])
		#expect(attachments.letGo(project).isEmpty)
	}

	/// The container really going is the one thing that takes an attachment
	/// away — stopped by hand from the list of running tools, or swept up on the
	/// way out. It goes whole, for the same reason it arrived whole.
	@Test func aContainerThatIsStoppedTakesEverythingKnownAboutItWithIt() throws {
		let project = try makeProject()
		let other = try makeProject()
		defer {
			try? FileManager.default.removeItem(at: project)
			try? FileManager.default.removeItem(at: other)
		}
		var attachments = DevContainerAttachments()

		attachments.attach(
			try makeSession(named: "abydos-devcontainer-1", for: project),
			providing: ["pyright-langserver"], to: project
		)
		attachments.attach(
			try makeSession(named: "abydos-devcontainer-2", for: other),
			providing: ["gopls"], to: other
		)

		attachments.containersStopped(keeping: ["abydos-devcontainer-2"])
		#expect(attachments[project] == nil)
		#expect(attachments.carries("gopls", for: other) == true)
	}

	/// **Moving a project's servers to another of its containers is the one thing
	/// that is not letting go**, and 0444's part 2 is why the two have to be
	/// different calls.
	///
	/// `letGo` keeps the attachment because the project is coming back to the same
	/// container. Here it is being pointed at a different one, and an attachment
	/// left standing is what the warm-up that follows would find: it would decide
	/// the project already has a container and start the servers straight back up
	/// in the one somebody has just asked to leave. A switch that leaves the old
	/// container's servers running is 0427's fault with a gesture behind it.
	@Test func movingToAnotherContainerDropsTheClaimOnTheOldOne() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		var attachments = DevContainerAttachments()

		attachments.attach(
			try makeSession(named: "abydos-devcontainer-1", for: project),
			providing: ["pyright-langserver"], to: project
		)

		// Letting go is not this: coming back to the same container has to find it.
		attachments.letGo(project)
		#expect(attachments[project] != nil)

		attachments.detach(project)
		// Nothing is claimed, so the next thing that asks starts a container rather
		// than reusing the one that was left.
		#expect(attachments[project] == nil)
		#expect(attachments.carries("pyright-langserver", for: project) == nil)
	}

	/// The same checkout reached two ways is one project — `/var` is a symlink to
	/// `/private/var`, and every scratch project this suite makes lives under it.
	@Test func aProjectReachedThroughASymlinkHasTheSameContainer() throws {
		let through = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: through) }
		let real = URL(fileURLWithPath: FilePath.canonical(through), isDirectory: true)
		try #require(real.path != through.path, "this machine has no symlink to prove it with")

		var attachments = DevContainerAttachments()
		attachments.attach(
			try makeSession(named: "abydos-devcontainer-1", for: real),
			providing: ["pyright-langserver"], to: real
		)
		#expect(attachments.carries("pyright-langserver", for: through) == true)
	}
}
