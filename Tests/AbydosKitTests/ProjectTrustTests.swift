import Foundation
import Testing
@testable import AbydosKit

/// Which projects may run their own code, and how that is remembered.
@MainActor
struct ProjectTrustTests {
	private func store() -> (ProjectTrust, URL) {
		let file = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("trust-\(UUID().uuidString).json")
		return (ProjectTrust(storeURL: file, driven: false), file)
	}

	@Test func aProjectNobodyHasTrustedIsUntrusted() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let project = URL(fileURLWithPath: "/Users/me/dev/downloaded")

		#expect(!trust.isTrusted(project))
		#expect(trust.decision(for: project) == .untrusted(project: "downloaded"))
		#expect(trust.decision(for: project).said?.contains("not trusted") == true)
	}

	@Test func trustingAFolderTrustsThatFolder() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let project = URL(fileURLWithPath: "/Users/me/dev/abydos")

		trust.trust(project)
		#expect(trust.isTrusted(project))
		#expect(trust.decision(for: project) == .trusted)
		#expect(!trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev/other")))
	}

	@Test func aTrustedParentCoversWhatIsUnderIt() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }

		trust.trust(URL(fileURLWithPath: "/Users/me/dev"), coveringChildren: true)
		#expect(trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev/abydos")))
		#expect(trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev/deep/nested/thing")))
		#expect(trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev")))
	}

	/// **A name that looks like another name.** A prefix match alone trusts
	/// `~/development` because `~/dev` was trusted; the boundary is what makes
	/// "under" mean under.
	@Test func aFolderBesideATrustedOneIsNotUnderIt() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }

		trust.trust(URL(fileURLWithPath: "/Users/me/dev"), coveringChildren: true)
		#expect(!trust.isTrusted(URL(fileURLWithPath: "/Users/me/development/thing")))
		#expect(!trust.isTrusted(URL(fileURLWithPath: "/Users/me/devil")))
	}

	@Test func aFolderTrustedWithoutItsChildrenCoversOnlyItself() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }

		trust.trust(URL(fileURLWithPath: "/Users/me/dev"))
		#expect(trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev")))
		#expect(!trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev/abydos")))
	}

	/// `/tmp/x` and `/private/tmp/x` are the same folder, and only one spelling
	/// would otherwise be trusted — the standardising the git paths already do.
	@Test func aPathAndItsResolvedFormAreTheSameFolder() throws {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let name = "trust-resolve-\(UUID().uuidString)"
		let short = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
		try FileManager.default.createDirectory(at: short, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: short) }

		trust.trust(short)
		#expect(trust.isTrusted(URL(fileURLWithPath: "/private/tmp").appendingPathComponent(name)))
	}

	@Test func trustCanBeTakenBack() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let project = URL(fileURLWithPath: "/Users/me/dev/abydos")

		trust.trust(project)
		let entry = trust.entry(covering: project)
		#expect(entry?.path == "/Users/me/dev/abydos")
		trust.withdraw(path: entry!.path)
		#expect(!trust.isTrusted(project))
	}

	@Test func aProjectSaysWhichEntryTrustsIt() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }

		trust.trust(URL(fileURLWithPath: "/Users/me/dev"), coveringChildren: true)
		let entry = trust.entry(covering: URL(fileURLWithPath: "/Users/me/dev/abydos"))
		#expect(entry?.path == "/Users/me/dev")
		#expect(entry?.coversChildren == true)
	}

	@Test func theParentIsWhatTheSheetOffers() {
		#expect(ProjectTrust.parent(of: URL(fileURLWithPath: "/Users/me/dev/abydos"))?.path
			== "/Users/me/dev")
		#expect(ProjectTrust.parent(of: URL(fileURLWithPath: "/Users")) == nil)
	}

	@Test func whatIsTrustedSurvivesTheProcess() throws {
		let file = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("trust-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }

		let first = ProjectTrust(storeURL: file, driven: false)
		first.trust(URL(fileURLWithPath: "/Users/me/dev/abydos"), coveringChildren: true)

		let second = ProjectTrust(storeURL: file, driven: false)
		#expect(second.isTrusted(URL(fileURLWithPath: "/Users/me/dev/abydos/deep")))
	}

	/// A capture run trusting a temporary directory must not leave that in
	/// somebody's real list — `RecentProjects`' rule, for its reason.
	// MARK: - Where a clone came from

	/// An enterprise server: a hundred repositories from one place, where a
	/// folder entry per clone is the dialog people learn to dismiss.
	@Test func aTrustedHostCoversEveryCloneFromIt() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let project = URL(fileURLWithPath: "/Users/me/dev/thing")

		trust.noteRemote(host: "git.company.com", owner: "platform", for: project)
		#expect(!trust.isTrusted(project))
		trust.trust(remoteHost: "git.company.com")
		#expect(trust.isTrusted(project))
	}

	/// **`github.com` is the world and an organisation on it is a place**, so
	/// the owner is its own entry and the host's does not follow from it.
	@Test func aTrustedOwnerIsNotTheWholeHost() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let mine = URL(fileURLWithPath: "/Users/me/dev/mine")
		let theirs = URL(fileURLWithPath: "/Users/me/dev/theirs")

		trust.noteRemote(host: "github.com", owner: "my-org", for: mine)
		trust.noteRemote(host: "github.com", owner: "somebody-else", for: theirs)
		trust.trust(remoteHost: "github.com", owner: "my-org")

		#expect(trust.isTrusted(mine))
		#expect(!trust.isTrusted(theirs))
	}

	@Test func aHostIsSpeltOneWay() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let project = URL(fileURLWithPath: "/Users/me/dev/thing")

		trust.noteRemote(host: "GitHub.com", owner: "My-Org", for: project)
		trust.trust(remoteHost: "github.com", owner: "my-org")
		#expect(trust.isTrusted(project))
	}

	@Test func aProjectWithNoRemoteIsNotCoveredByAnyOfThem() {
		let (trust, file) = store()
		defer { try? FileManager.default.removeItem(at: file) }
		let project = URL(fileURLWithPath: "/Users/me/dev/local-only")

		trust.trust(remoteHost: "github.com")
		trust.noteRemote(host: nil, owner: nil, for: project)
		#expect(!trust.isTrusted(project))
	}

	/// **The world is not a scope.** `github.com` is every repository anybody
	/// has ever pushed; `git.company.com` is a place whose every repository is
	/// a colleague's, which is the case the host scope exists for.
	@Test func aPublicForgeIsNotSomewhereToTrustWholesale() {
		#expect(TrustedRemote.isPublicForge("github.com"))
		#expect(TrustedRemote.isPublicForge("GitHub.com"))
		#expect(TrustedRemote.isPublicForge("gitlab.com"))
		#expect(TrustedRemote.isPublicForge("bitbucket.org"))
		#expect(!TrustedRemote.isPublicForge("github.company.com"))
		#expect(!TrustedRemote.isPublicForge("git.company.com"))
	}

	/// What is not a known forge is somebody's own server until shown
	/// otherwise: one entry too narrow is the safe way to be wrong.
	@Test func anUnknownHostIsTreatedAsSomebodysOwn() {
		#expect(!TrustedRemote.isPublicForge("scm.internal"))
	}

	@Test func aRemoteEntryReadsAsAPlace() {
		#expect(TrustedRemote(host: "github.com", owner: "my-org").said == "github.com/my-org")
		#expect(TrustedRemote(host: "git.company.com").said == "git.company.com")
	}

	@Test func aTrustedRemoteSurvivesTheProcessBesideTheFolders() {
		let file = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("trust-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }

		let first = ProjectTrust(storeURL: file, driven: false)
		first.trust(URL(fileURLWithPath: "/Users/me/dev/abydos"))
		first.trust(remoteHost: "git.company.com")

		let second = ProjectTrust(storeURL: file, driven: false)
		#expect(second.isTrusted(URL(fileURLWithPath: "/Users/me/dev/abydos")))
		#expect(second.remotes.map(\.said) == ["git.company.com"])
	}

	/// The file's first shape was a bare array of folders. Trusting everything
	/// again should not be the price of an update.
	@Test func theOlderFileIsStillRead() throws {
		let file = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("trust-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let old = [TrustedFolder(path: "/Users/me/dev/abydos", coversChildren: true)]
		try JSONEncoder().encode(old).write(to: file)

		let trust = ProjectTrust(storeURL: file, driven: false)
		#expect(trust.isTrusted(URL(fileURLWithPath: "/Users/me/dev/abydos/deep")))
	}

	@Test func aDrivenRunLeavesTheListOnDiskAlone() {
		let file = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("trust-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }

		let driven = ProjectTrust(storeURL: file, driven: true)
		driven.trust(URL(fileURLWithPath: "/tmp/whatever"))
		#expect(driven.isTrusted(URL(fileURLWithPath: "/tmp/whatever")))
		#expect(!FileManager.default.fileExists(atPath: file.path))
	}
}
