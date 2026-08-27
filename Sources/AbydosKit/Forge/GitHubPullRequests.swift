import Foundation

/// Asking GitHub about pull requests, one command at a time.
///
/// Every call is a `gh` invocation asking for JSON and a decoder of this
/// repository's own beside it. **One decoder per command**, and each of them
/// reads the payload field by field rather than through `Codable`: a `Decodable`
/// struct fails the whole array when one row is missing a field, and `gh`'s
/// JSON is a contract this program does not own. A pull request whose author has
/// been deleted should be a row that says less, not a list that says nothing.
///
/// Which repository to ask about comes from `GitForge.repository(in:)`, which
/// already turns a remote into a host, an owner and a name. Nothing here parses
/// a remote.
public enum GitHubPullRequests {
	/// How many to ask for. A review list is read from the top; a repository
	/// with more than this open has a bigger problem than a truncated list.
	public static let listLimit = 60

	// MARK: - The list

	/// The open pull requests, with the ones waiting on this account marked.
	///
	/// Two calls and not one: `gh pr list` says what is open, and GitHub's
	/// search says which of them have been asked of this account. The second is
	/// a search qualifier rather than a scan of `reviewRequests`, because "a
	/// team I am in" is a question only the host can answer.
	public static func list(
		in root: URL,
		scope: ReviewRequestScope = .meOrMyTeams
	) async -> ForgeReply<[PullRequest]> {
		if let absence = await GitHubCLI.availability(in: root) {
			return .unavailable(absence)
		}

		let fields = [
			"number", "title", "author", "headRefName", "baseRefName",
			"isDraft", "statusCheckRollup", "updatedAt", "url",
		].joined(separator: ",")

		let listed = await GitHubCLI.run(
			["pr", "list", "--state", "open", "--limit", "\(listLimit)", "--json", fields],
			in: root
		)
		guard listed.exitCode == 0 else { return .failed(complaint(listed)) }

		let requests = pullRequests(fromJSON: listed.stdout)

		// A failure here is not a failure of the list: the rows are still worth
		// showing without the mark, which is the whole reason it is a second
		// call.
		let waiting = await waitingOnMe(in: root, scope: scope)
		return .answered(marking(requests, waiting: waiting))
	}

	/// The numbers of the open pull requests asking for this account's review.
	static func waitingOnMe(in root: URL, scope: ReviewRequestScope) async -> Set<Int> {
		let result = await GitHubCLI.run(
			[
				"pr", "list", "--state", "open", "--limit", "\(listLimit)",
				"--search", scope.searchQualifier, "--json", "number",
			],
			in: root
		)
		guard result.exitCode == 0 else { return [] }
		return Set(numbers(fromJSON: result.stdout))
	}

	/// Marks the rows the search named, and leaves the rest alone.
	///
	/// Its own function because it is the whole of what the second call is for,
	/// and because a live proof of it needs somebody to have asked this account
	/// for a review — which is not something a test can arrange for on anybody
	/// else's repository.
	public static func marking(_ requests: [PullRequest], waiting: Set<Int>) -> [PullRequest] {
		guard !waiting.isEmpty else { return requests }
		return requests.map {
			var request = $0
			request.isWaitingOnMe = waiting.contains($0.number)
			return request
		}
	}

	/// `gh pr list --json` — an array of objects, one per pull request.
	///
	/// Every field is optional to this reader. A row with no number is the one
	/// thing it cannot do without, because that is what everything else is asked
	/// by; anything else missing costs that row a word.
	public static func pullRequests(fromJSON text: String) -> [PullRequest] {
		guard let rows = array(from: text) else { return [] }
		return rows.compactMap { row in
			guard let number = row["number"] as? Int else { return nil }
			return PullRequest(
				number: number,
				title: (row["title"] as? String) ?? "(untitled)",
				author: login(from: row["author"]) ?? "(unknown)",
				headRefName: (row["headRefName"] as? String) ?? "",
				baseRefName: (row["baseRefName"] as? String) ?? "",
				isDraft: (row["isDraft"] as? Bool) ?? false,
				checks: checksState(from: row["statusCheckRollup"]),
				updatedAt: date(from: row["updatedAt"]),
				url: (row["url"] as? String).flatMap(URL.init(string:))
			)
		}
	}

	/// `--json number` — the shape the "waiting on me" search answers with.
	static func numbers(fromJSON text: String) -> [Int] {
		guard let rows = array(from: text) else { return [] }
		return rows.compactMap { $0["number"] as? Int }
	}

	// MARK: - One of them

	/// One pull request, for a page that was handed a number rather than a row.
	public static func view(number: Int, in root: URL) async -> ForgeReply<PullRequest> {
		if let absence = await GitHubCLI.availability(in: root) {
			return .unavailable(absence)
		}
		let fields = [
			"number", "title", "author", "headRefName", "baseRefName",
			"isDraft", "statusCheckRollup", "updatedAt", "url",
		].joined(separator: ",")
		let result = await GitHubCLI.run(
			["pr", "view", "\(number)", "--json", fields], in: root
		)
		guard result.exitCode == 0 else { return .failed(complaint(result)) }
		guard let request = pullRequest(fromJSON: result.stdout) else {
			return .failed("The GitHub CLI answered nothing about #\(number).")
		}
		return .answered(request)
	}

	/// `gh pr view --json` — one object rather than an array of them.
	public static func pullRequest(fromJSON text: String) -> PullRequest? {
		guard let data = text.data(using: .utf8),
		      let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
		      let number = row["number"] as? Int
		else { return nil }
		return PullRequest(
			number: number,
			title: (row["title"] as? String) ?? "(untitled)",
			author: login(from: row["author"]) ?? "(unknown)",
			headRefName: (row["headRefName"] as? String) ?? "",
			baseRefName: (row["baseRefName"] as? String) ?? "",
			isDraft: (row["isDraft"] as? Bool) ?? false,
			checks: checksState(from: row["statusCheckRollup"]),
			updatedAt: date(from: row["updatedAt"]),
			url: (row["url"] as? String).flatMap(URL.init(string:))
		)
	}

	/// The head commit the pull request is at, which every tick is recorded
	/// against and every comment is written against.
	public static func head(of number: Int, in root: URL) async -> String? {
		let result = await GitHubCLI.run(
			["pr", "view", "\(number)", "--json", "headRefOid", "--jq", ".headRefOid"], in: root
		)
		guard result.exitCode == 0 else { return nil }
		let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return hash.isEmpty ? nil : hash
	}

	// MARK: - What it changes

	/// The files a pull request changes, against the point it branched from.
	///
	/// **The API's file list and not `git diff head..base`.** GitHub answers
	/// this endpoint with the three-dot diff — the change the pull request
	/// itself makes — so a file the base branch moved underneath it is not in
	/// the list. Comparing two tips would list somebody else's work and send a
	/// reviewer to read it.
	///
	/// It is also the only source that says what *happened* to each file:
	/// `gh pr view --json files` gives a path and two numbers and no status at
	/// all, so every row would have to be drawn as a modification.
	public static func files(of number: Int, in root: URL) async -> ForgeReply<[PullRequestFile]> {
		guard let repository = await GitForge.repository(in: root) else {
			return .unavailable(.noGitHubRemote)
		}
		if let absence = await GitHubCLI.availability(in: root) {
			return .unavailable(absence)
		}
		let result = await GitHubCLI.run(
			[
				"api", "--hostname", repository.host, "--paginate",
				"repos/\(repository.owner)/\(repository.name)/pulls/\(number)/files",
			],
			in: root
		)
		guard result.exitCode == 0 else { return .failed(complaint(result)) }
		return .answered(files(fromJSON: result.stdout))
	}

	/// `GET /repos/{owner}/{repo}/pulls/{n}/files`.
	///
	/// `--paginate` concatenates the pages as separate JSON arrays, so this
	/// reads a stream of them rather than one.
	public static func files(fromJSON text: String) -> [PullRequestFile] {
		arrays(from: text).flatMap { rows in
			rows.compactMap { row -> PullRequestFile? in
				guard let path = row["filename"] as? String, !path.isEmpty else { return nil }
				return PullRequestFile(
					path: path,
					additions: (row["additions"] as? Int) ?? 0,
					deletions: (row["deletions"] as? Int) ?? 0,
					kind: kind(from: row["status"] as? String)
				)
			}
		}
	}

	/// GitHub's word for what happened to a file, in this repository's own.
	static func kind(from status: String?) -> GitChange.Kind {
		switch status {
		case "added":    return .added
		case "removed":  return .deleted
		case "renamed":  return .renamed
		case "copied":   return .copied
		// `changed` and `unchanged` are both a modification as far as a row is
		// concerned, and so is a status this does not know about: a file in the
		// list changed somehow, and "modified" is the honest thing to draw.
		default:         return .modified
		}
	}

	/// The whole diff, in one call.
	///
	/// One call and not one per file: a pull request of forty files would
	/// otherwise be forty processes, and the row count is the size of somebody
	/// else's change rather than anything this code chooses. Split per file by
	/// `FileDiffs.split`.
	public static func diff(of number: Int, in root: URL) async -> ForgeReply<String> {
		if let absence = await GitHubCLI.availability(in: root) {
			return .unavailable(absence)
		}
		let result = await GitHubCLI.run(["pr", "diff", "\(number)"], in: root)
		guard result.exitCode == 0 else { return .failed(complaint(result)) }
		return .answered(result.stdout)
	}

	/// One file's text at a commit, for the whole-file view of its diff.
	///
	/// The raw media type rather than the JSON one: the JSON carries the file
	/// base64-encoded inside a field, and this wants the bytes.
	public static func contents(
		of path: String, at ref: String, in root: URL
	) async -> ForgeReply<String> {
		guard let repository = await GitForge.repository(in: root) else {
			return .unavailable(.noGitHubRemote)
		}
		// Each component escaped on its own: a path has slashes that must stay
		// slashes, and may have a space that must not.
		let escaped = path.split(separator: "/").map {
			$0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
		}.joined(separator: "/")
		let result = await GitHubCLI.run(
			[
				"api", "--hostname", repository.host,
				"-H", "Accept: application/vnd.github.raw",
				"repos/\(repository.owner)/\(repository.name)/contents/\(escaped)?ref=\(ref)",
			],
			in: root
		)
		guard result.exitCode == 0 else { return .failed(complaint(result)) }
		return .answered(result.stdout)
	}

	// MARK: - The conversation

	/// The review comments already on it, at the lines they are still about.
	public static func comments(
		of number: Int, in root: URL
	) async -> ForgeReply<[ReviewComment]> {
		guard let repository = await GitForge.repository(in: root) else {
			return .unavailable(.noGitHubRemote)
		}
		if let absence = await GitHubCLI.availability(in: root) {
			return .unavailable(absence)
		}
		let result = await GitHubCLI.run(
			[
				"api", "--hostname", repository.host, "--paginate",
				"repos/\(repository.owner)/\(repository.name)/pulls/\(number)/comments",
			],
			in: root
		)
		guard result.exitCode == 0 else { return .failed(complaint(result)) }
		return .answered(comments(fromJSON: result.stdout))
	}

	/// `GET /repos/{owner}/{repo}/pulls/{n}/comments`.
	///
	/// `line` is null for a comment whose code has gone, and that null is the
	/// whole of what "outdated" means here — it is kept rather than filtered,
	/// because a conversation that happened is worth knowing about even when the
	/// lines it was about are not there any more.
	public static func comments(fromJSON text: String) -> [ReviewComment] {
		arrays(from: text).flatMap { rows in
			rows.compactMap { row -> ReviewComment? in
				guard let id = row["id"] as? Int else { return nil }
				return ReviewComment(
					id: id,
					author: login(from: row["user"]) ?? "(unknown)",
					body: (row["body"] as? String) ?? "",
					path: (row["path"] as? String) ?? "",
					line: row["line"] as? Int,
					createdAt: date(from: row["created_at"]),
					commit: row["commit_id"] as? String
				)
			}
		}
	}

	// MARK: - Answering

	/// Sends a review: the remarks written on the page, and the verdict.
	///
	/// One submission and not one comment at a time, which is how GitHub models
	/// it and how a reviewer thinks: a review is a set of remarks and a verdict,
	/// not a series of interruptions to the author.
	///
	/// - Parameter head: the commit the page was read at. Sent with the review,
	///   so GitHub anchors the comments where they were written rather than
	///   wherever those lines have since moved to.
	public static func submit(
		review verdict: ReviewVerdict,
		on number: Int,
		body: String,
		comments pending: [PendingComment],
		at head: String?,
		in root: URL
	) async -> ForgeReply<Void> {
		guard let repository = await GitForge.repository(in: root) else {
			return .unavailable(.noGitHubRemote)
		}
		if let absence = await GitHubCLI.availability(in: root) {
			return .unavailable(absence)
		}

		var payload: [String: Any] = ["event": verdict.rawValue]
		if !body.isEmpty { payload["body"] = body }
		if let head { payload["commit_id"] = head }
		if !pending.isEmpty {
			payload["comments"] = pending.map(\.payload)
		}

		guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
			return .failed("The review could not be written out as JSON.")
		}

		let result = await GitHubCLI.run(
			[
				"api", "--hostname", repository.host, "--method", "POST",
				"repos/\(repository.owner)/\(repository.name)/pulls/\(number)/reviews",
				"--input", "-",
			],
			in: root,
			input: data
		)
		guard result.exitCode == 0 else { return .failed(complaint(result)) }
		return .answered(())
	}

	// MARK: - Reading the payloads

	/// What `gh` said when it refused, as a sentence rather than a status.
	///
	/// stderr first, because that is where `gh` puts its complaint; the exit
	/// code only when it said nothing at all, which is what a killed process
	/// looks like.
	static func complaint(_ result: GitRepository.ProcessResult) -> String {
		let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
		if !said.isEmpty { return said }
		let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		if !out.isEmpty { return out }
		return "The GitHub CLI exited with \(result.exitCode) and said nothing."
	}

	private static func array(from text: String) -> [[String: Any]]? {
		guard let data = text.data(using: .utf8),
		      let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
		else { return nil }
		return rows
	}

	/// Every JSON array in the text, for `gh api --paginate`.
	///
	/// **`--paginate` concatenates pages.** Three pages of an endpoint come back
	/// as `[…][…][…]` — three documents one after another, which is not a JSON
	/// document and which `JSONSerialization` refuses whole. A pull request with
	/// thirty-one changed files is two pages, so this is the ordinary case
	/// rather than an exotic one: the first version of this read the first page
	/// and silently lost the rest.
	static func arrays(from text: String) -> [[[String: Any]]] {
		guard let data = text.data(using: .utf8), !data.isEmpty else { return [] }

		// One document is the common case and is worth not scanning for.
		if let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
			return [rows]
		}

		var found: [[[String: Any]]] = []
		var depth = 0
		var start: String.Index?
		var inString = false
		var escaped = false
		for index in text.indices {
			let character = text[index]
			if inString {
				if escaped { escaped = false } else if character == "\\" { escaped = true }
				else if character == "\"" { inString = false }
				continue
			}
			switch character {
			case "\"": inString = true
			case "[":
				if depth == 0 { start = index }
				depth += 1
			case "]":
				guard depth > 0 else { break }
				depth -= 1
				if depth == 0, let from = start {
					let piece = String(text[from...index])
					if let data = piece.data(using: .utf8),
					   let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
						found.append(rows)
					}
					start = nil
				}
			default: break
			}
		}
		return found
	}

	/// A GitHub actor, which is `{"login": …}` in the API and in `gh`'s own JSON
	/// alike. A deleted account is `null`, which is why this is optional.
	static func login(from value: Any?) -> String? {
		guard let actor = value as? [String: Any],
		      let login = actor["login"] as? String,
		      !login.isEmpty
		else { return nil }
		return login
	}

	private static let timestamps: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()

	static func date(from value: Any?) -> Date? {
		guard let text = value as? String else { return nil }
		return timestamps.date(from: text)
	}

	/// What `statusCheckRollup` adds up to.
	///
	/// Two shapes in the one array, because GitHub has two kinds of check: a
	/// check run, which has a `status` and a `conclusion`, and a commit status,
	/// which has a `state`. Both are read, and an element that is neither is
	/// ignored rather than counted as a failure — an unknown shape is not bad
	/// news, it is no news.
	///
	/// The worst state wins: one red check makes the pull request red however
	/// many green ones are beside it, which is what somebody deciding whether to
	/// read it wants to know.
	static func checksState(from value: Any?) -> ChecksState {
		guard let entries = value as? [[String: Any]], !entries.isEmpty else { return .none }

		var sawPassing = false
		var sawPending = false
		for entry in entries {
			if let conclusion = entry["conclusion"] as? String, !conclusion.isEmpty {
				switch conclusion.uppercased() {
				case "SUCCESS", "NEUTRAL", "SKIPPED": sawPassing = true
				case "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE":
					return .failing
				default: sawPending = true
				}
				continue
			}
			if let status = entry["status"] as? String, !status.isEmpty,
			   status.uppercased() != "COMPLETED" {
				sawPending = true
				continue
			}
			if let state = entry["state"] as? String, !state.isEmpty {
				switch state.uppercased() {
				case "SUCCESS":           sawPassing = true
				case "FAILURE", "ERROR":  return .failing
				case "PENDING", "EXPECTED": sawPending = true
				default: break
				}
			}
		}
		if sawPending { return .pending }
		return sawPassing ? .passing : .none
	}
}
