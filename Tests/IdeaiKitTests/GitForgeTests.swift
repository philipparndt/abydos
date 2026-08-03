import Foundation
import Testing
@testable import IdeaiKit

/// Turning a remote into an address a browser can open.
///
/// A remote is written for git, and git accepts several shapes — the scp-like
/// one is not even a URL. Every shape here is one this repository or a
/// colleague's has actually had.
struct GitForgeTests {
	@Test func theUsualSSHRemote() {
		let repository = GitForge.repository(fromRemote: "git@github.com:philipparndt/ideai.git")
		#expect(repository == .init(host: "github.com", owner: "philipparndt", name: "ideai"))
		#expect(repository?.webURL?.absoluteString == "https://github.com/philipparndt/ideai")
	}

	@Test func anHTTPSRemote() {
		let repository = GitForge.repository(fromRemote: "https://github.com/philipparndt/ideai.git")
		#expect(repository == .init(host: "github.com", owner: "philipparndt", name: "ideai"))
	}

	/// Without the suffix, which is how a browser hands the address over.
	@Test func anHTTPSRemoteWithoutDotGit() {
		#expect(GitForge.repository(fromRemote: "https://github.com/philipparndt/ideai")?.name == "ideai")
	}

	/// An Enterprise install is another host and nothing else, which is the
	/// point: one implementation covers both.
	@Test func anEnterpriseHost() {
		let repository = GitForge.repository(fromRemote: "git@ghe.example.com:platform/tools.git")
		#expect(repository == .init(host: "ghe.example.com", owner: "platform", name: "tools"))
		#expect(repository?.displayName == "ghe.example.com")
		#expect(GitForge.repository(fromRemote: "git@github.com:a/b.git")?.displayName == "GitHub")
	}

	@Test func anSSHURLWithAPort() {
		let repository = GitForge.repository(
			fromRemote: "ssh://git@ghe.example.com:22/platform/tools.git"
		)
		#expect(repository == .init(host: "ghe.example.com", owner: "platform", name: "tools"))
	}

	/// Groups nest: everything before the repository is its owner, however
	/// many parts that is.
	@Test func aNestedGroup() {
		let repository = GitForge.repository(fromRemote: "git@ghe.example.com:team/sub/project.git")
		#expect(repository?.owner == "team/sub")
		#expect(repository?.name == "project")
		#expect(repository?.webURL?.absoluteString == "https://ghe.example.com/team/sub/project")
	}

	@Test func aUserInTheAddressIsNotTheOwner() {
		let repository = GitForge.repository(fromRemote: "https://philipp@ghe.example.com/a/b.git")
		#expect(repository == .init(host: "ghe.example.com", owner: "a", name: "b"))
	}

	// MARK: - The branch's page

	@Test func aBranchHasItsOwnPage() {
		let repository = GitForge.Repository(host: "github.com", owner: "me", name: "thing")
		#expect(repository.url(forBranch: "main")?.absoluteString
			== "https://github.com/me/thing/tree/main")
	}

	/// Branch names contain slashes, and may contain worse.
	@Test func aBranchNameIsEscaped() {
		let repository = GitForge.Repository(host: "github.com", owner: "me", name: "thing")
		#expect(repository.url(forBranch: "feature/a b")?.absoluteString
			== "https://github.com/me/thing/tree/feature/a%20b")
	}

	// MARK: - Nothing to open

	/// A local clone is a real remote and has no web page at all; saying so is
	/// better than inventing an address.
	@Test func aPathIsNotAWebsite() {
		#expect(GitForge.repository(fromRemote: "/Users/me/dev/thing") == nil)
		#expect(GitForge.repository(fromRemote: "") == nil)
		#expect(GitForge.repository(fromRemote: "git@github.com:nothing") == nil)
	}
}
