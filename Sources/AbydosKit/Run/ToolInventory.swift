import Foundation

/// What a process this app started is actually costing, and for how long.
///
/// The number that matters is never the process's own. 0427 was opened because
/// a machine sat at a hundred per cent and `ps` said 15 GB of `swift-frontend`;
/// the `sourcekit-lsp` above them was 32 MB. A view that showed the 32 would
/// have been worse than no view at all, because it would have said the servers
/// were cheap. So resident memory here is the process *and everything under
/// it*, and the count of what is under it is shown beside the number so nobody
/// has to wonder where it came from.
///
/// One `/bin/ps` for the whole machine rather than one per process. Everything
/// this view wants — how much, how long, and who the children are — is in that
/// one answer, and asking four times for four servers would make a view of
/// resource use into a use of resources.
public struct ProcessTable: Sendable {
	/// One line of `ps`.
	public struct Entry: Equatable, Sendable {
		public let pid: pid_t
		public let parent: pid_t
		/// Resident set size, in bytes. `ps` reports kilobytes.
		public let residentBytes: Int64
		/// How long this process has been running.
		public let elapsed: TimeInterval
		/// The executable, as `ps` resolved it — which is the thing to read when
		/// the question is "which toolchain is this", the question 0427's second
		/// fault was about.
		public let command: String
	}

	/// What a process and its descendants come to together.
	public struct Cost: Equatable, Sendable {
		public let residentBytes: Int64
		public let elapsed: TimeInterval
		/// How many processes are under this one, not counting itself.
		public let descendants: Int
	}

	public let entries: [pid_t: Entry]
	private let children: [pid_t: [pid_t]]

	public init(entries: [Entry]) {
		var byPID: [pid_t: Entry] = [:]
		var byParent: [pid_t: [pid_t]] = [:]
		for entry in entries {
			byPID[entry.pid] = entry
			byParent[entry.parent, default: []].append(entry.pid)
		}
		self.entries = byPID
		self.children = byParent
	}

	/// Every process on this machine, once.
	///
	/// `comm` is last on the line because it is the only field that can contain
	/// a space; everything before it is a fixed number of words. `-axo` with
	/// `=` on each field asks for no header, so there is nothing to skip.
	public static func sample() -> ProcessTable {
		let listing = (executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,rss=,etime=,comm="])
		// Short: this is a local `ps`, and one that has not answered in three
		// seconds is a machine in trouble rather than a slow command. Nothing is
		// left behind either way — that is what `RuntimeCommand` is for.
		let result = RuntimeCommand.run(listing, deadline: 3)
		guard result.succeeded else { return ProcessTable(entries: []) }
		return parse(result.output)
	}

	public static func parse(_ text: String) -> ProcessTable {
		var entries: [Entry] = []
		for line in text.split(separator: "\n") {
			// Every column is padded, so the fields are separated by runs of
			// spaces rather than by one. The command is whatever is left after
			// the four numbers — put back together rather than taken as a fifth
			// field, since a path may have a space in it.
			let fields = line.split(separator: " ", omittingEmptySubsequences: true)
			guard fields.count >= 4,
			      let pid = pid_t(fields[0]),
			      let parent = pid_t(fields[1]),
			      let resident = Int64(fields[2]),
			      let elapsed = seconds(elapsed: String(fields[3]))
			else { continue }
			entries.append(Entry(
				pid: pid,
				parent: parent,
				residentBytes: resident * 1024,
				elapsed: elapsed,
				command: fields.dropFirst(4).joined(separator: " ")
			))
		}
		return ProcessTable(entries: entries)
	}

	/// `ps`'s own elapsed time: `[[dd-]hh:]mm:ss`.
	public static func seconds(elapsed: String) -> TimeInterval? {
		var text = elapsed
		var days = 0.0
		if let dash = text.firstIndex(of: "-") {
			guard let counted = Double(text[text.startIndex..<dash]) else { return nil }
			days = counted
			text = String(text[text.index(after: dash)...])
		}
		let parts = text.split(separator: ":").map { Double($0) }
		guard !parts.isEmpty, parts.count <= 3, !parts.contains(where: { $0 == nil }) else {
			return nil
		}
		let numbers = parts.map { $0! }
		// From the right: seconds, then minutes, then hours.
		var total = days * 86_400
		for (index, value) in numbers.reversed().enumerated() {
			total += value * pow(60, Double(index))
		}
		return total
	}

	/// What this process and everything it started come to.
	///
	/// Nil when the process is not there any more, which is a real answer: a
	/// server that has just been stopped is gone from `ps` before the app has
	/// noticed, and a row that says "0 MB" would be claiming it measured
	/// something.
	public func cost(of pid: pid_t) -> Cost? {
		guard let root = entries[pid] else { return nil }
		var total = root.residentBytes
		var counted = 0
		// Iterative, and each pid visited once: `ps` is a snapshot and a parent
		// that exited mid-read can leave a cycle through pid 0.
		var seen: Set<pid_t> = [pid]
		var pending = children[pid] ?? []
		while let next = pending.popLast() {
			guard seen.insert(next).inserted, let entry = entries[next] else { continue }
			total += entry.residentBytes
			counted += 1
			pending += children[next] ?? []
		}
		return Cost(residentBytes: total, elapsed: root.elapsed, descendants: counted)
	}
}

/// What the runtime says about the containers this app started.
///
/// Two commands, both with deadlines and neither of them a poll. `docker stats`
/// without `--no-stream` never returns at all, which is exactly the shape of
/// process this app has spent 0406 and 0427 learning not to leave behind — so
/// it is asked once, for the names that are wanted, and it ends.
public enum ContainerInventory {
	/// One container, as the runtime describes it.
	public struct Fact: Equatable, Sendable {
		public let name: String
		/// The image it came from, which is what says what it is.
		public let image: String
		/// The runtime's own word for what it is doing — "Up 4 minutes",
		/// "Exited (0) 3 seconds ago", "running", "stopped".
		public let status: String
		/// Whether that word means it is running.
		///
		/// Read here, where the runtime that said it is known, rather than left
		/// to whoever shows the row: the two runtimes do not spell it the same
		/// way, and a view that guessed would be guessing about the one fact
		/// that decides whether a memory figure means anything.
		public let isRunning: Bool
		/// When the runtime made it, which for everything this app starts is also
		/// when it started: nothing here is created and left for later.
		///
		/// Asked of the runtime rather than remembered here, because after a
		/// crash and a sweep this app's own memory of it is gone and the
		/// runtime's is not.
		public let startedAt: Date?
		/// Resident memory, or nil when the runtime would not say.
		public let residentBytes: Int64?
	}

	/// How long either runtime gets to answer. `docker stats` is a second on a
	/// healthy daemon and never on a wedged one.
	public static let deadline: TimeInterval = 10

	/// What the runtime says about these containers.
	///
	/// Empty in, empty out, without launching anything: the common case for
	/// this view is a session with language servers and no containers at all,
	/// and it should cost nothing at all then.
	public static func facts(
		named names: [String], using runtime: ContainerRuntime
	) -> [Fact] {
		guard !names.isEmpty else { return [] }
		let listed = RuntimeCommand.run(listing(using: runtime), deadline: deadline)
		let described = listed.succeeded ? parseListing(listed.output, using: runtime) : [:]
		let measured = RuntimeCommand.run(stats(of: names, using: runtime), deadline: deadline)
		let memory: [String: Int64] = measured.succeeded
			? parseStats(measured.output, using: runtime)
			: [:]

		return names.sorted().map { name in
			let status = described[name]?.status ?? ""
			return Fact(
				name: name,
				image: described[name]?.image ?? "",
				status: status,
				isRunning: isRunning(status: status, using: runtime),
				startedAt: described[name]?.startedAt,
				residentBytes: memory[name]
			)
		}
	}

	/// Whether a runtime's status word means the container is running.
	///
	/// Worth reading rather than ignoring, because a container that has exited
	/// is still registered here until something releases it, and `docker stats`
	/// answers about one instead of refusing: measured on docker 29.1.4, a
	/// stopped container comes back as `0B / 0B`. A row showing nought bytes and
	/// nothing else would read as "running, and free".
	public static func isRunning(status: String, using runtime: ContainerRuntime) -> Bool {
		switch runtime {
		// "Up 4 minutes", "Up 2 hours (healthy)".
		case .docker: return status.hasPrefix("Up")
		// Its `status.state`, which is one word.
		case .apple: return status == "running"
		}
	}

	/// What the runtime's listing says about a container, before it is measured.
	public struct Listed: Equatable, Sendable {
		public let image: String
		public let status: String
		public let startedAt: Date?
	}

	/// The command that says what each container is and how long it has been up.
	public static func listing(
		using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .docker:
			return (runtime.path, [
				"ps", "-a", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}",
				"--filter", "name=\(ToolContainers.prefix)",
			])
		case .apple:
			return (runtime.path, ["ls", "--all", "--format", "json"])
		}
	}

	/// The command that says what each container is using.
	///
	/// `--no-stream` on both, and it is the whole of what makes this safe to
	/// call: without it the command runs until something kills it, and a view of
	/// what this app has left running would be leaving one behind every time it
	/// refreshed.
	public static func stats(
		of names: [String], using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		switch runtime {
		case .docker:
			return (runtime.path, ["stats", "--no-stream", "--format", "{{.Name}}\t{{.MemUsage}}"] + names)
		case .apple:
			return (runtime.path, ["stats", "--no-stream", "--format", "json"] + names)
		}
	}

	// MARK: - Reading the answers

	public static func parseListing(
		_ output: String, using runtime: ContainerRuntime
	) -> [String: Listed] {
		var found: [String: Listed] = [:]
		switch runtime {
		case .docker:
			for line in output.split(separator: "\n") {
				let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
				guard fields.count >= 3, ToolContainers.isOurs(String(fields[0])) else { continue }
				found[String(fields[0])] = Listed(
					image: String(fields[1]),
					status: String(fields[2]),
					startedAt: fields.count > 3 ? date(fromDockerTimestamp: String(fields[3])) : nil
				)
			}
		case .apple:
			for record in records(in: output) {
				// Its `ls --format json` puts the name, the image and the time it
				// was made under `configuration`, and the state and the time it
				// started under `status` — the same shape `AppleInspection`
				// reads, one level wider. Read off a real answer from `container`
				// 1.2.2 rather than guessed at.
				let configuration = record["configuration"] as? [String: Any]
				let status = record["status"] as? [String: Any]
				guard let name = (configuration?["id"] as? String) ?? (record["id"] as? String),
				      ToolContainers.isOurs(name)
				else { continue }
				found[name] = Listed(
					image: ((configuration?["image"] as? [String: Any])?["reference"] as? String) ?? "",
					status: status?["state"] as? String ?? "",
					// When it started, and only when it was made if it has not.
					// Docker has the one field and this runtime has both, a
					// second apart on the containers this app starts — but a
					// container that was created, stopped and started again is
					// where the difference stops being a second.
					startedAt: (status?["startedDate"] as? String).flatMap(date(fromISOTimestamp:))
						?? (configuration?["creationDate"] as? String).flatMap(date(fromISOTimestamp:))
				)
			}
		}
		return found
	}

	/// `2026-08-09 21:58:12 +0200 CEST`, which is how docker writes a time.
	///
	/// The zone abbreviation on the end is dropped rather than parsed: it
	/// repeats the offset in front of it, and abbreviations are ambiguous across
	/// the world in a way an offset is not.
	public static func date(fromDockerTimestamp text: String) -> Date? {
		let fields = text.trimmingCharacters(in: .whitespaces).split(separator: " ")
		guard fields.count >= 3 else { return nil }
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
		return formatter.date(from: fields.prefix(3).joined(separator: " "))
	}

	public static func parseStats(
		_ output: String, using runtime: ContainerRuntime
	) -> [String: Int64] {
		switch runtime {
		case .docker:
			var found: [String: Int64] = [:]
			for line in output.split(separator: "\n") {
				let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
				// "123.4MiB / 15.66GiB" — the first half is the one about this
				// container; the second is the machine and is the same on every
				// line.
				guard fields.count >= 2,
				      let used = fields[1].split(separator: "/").first,
				      let bytes = bytes(fromRuntimeSize: String(used))
				else { continue }
				found[String(fields[0])] = bytes
			}
			return found
		case .apple:
			// Bytes, already, and no unit to parse: `container stats --format
			// json` answers `memoryUsageBytes` beside `memoryLimitBytes`, and it
			// is the first of those that is about this container.
			var found: [String: Int64] = [:]
			for record in records(in: output) {
				guard let name = record["id"] as? String,
				      let used = record["memoryUsageBytes"] as? NSNumber
				else { continue }
				found[name] = used.int64Value
			}
			return found
		}
	}

	/// `2026-08-09T18:29:57Z`, which is how Apple's runtime writes a time.
	public static func date(fromISOTimestamp text: String) -> Date? {
		ISO8601DateFormatter().date(from: text)
	}

	/// `123.4MiB`, `1.5GB`, `800kB` — whatever a runtime feels like printing.
	public static func bytes(fromRuntimeSize text: String) -> Int64? {
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		let digits = trimmed.prefix { $0.isNumber || $0 == "." }
		guard let value = Double(digits), !digits.isEmpty else { return nil }
		let unit = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).lowercased()
		let multiplier: Double
		switch unit {
		case "b", "": multiplier = 1
		case "kb", "kib", "k": multiplier = 1_024
		case "mb", "mib", "m": multiplier = 1_048_576
		case "gb", "gib", "g": multiplier = 1_073_741_824
		case "tb", "tib", "t": multiplier = 1_099_511_627_776
		default: return nil
		}
		return Int64(value * multiplier)
	}

	/// The JSON records in a runtime's answer, however much progress noise came
	/// with them. The same reasoning as `AppleInspection.first`, one array wider.
	private static func records(in output: String) -> [[String: Any]] {
		var searched = output.startIndex
		while let start = output[searched...].firstIndex(of: "[") {
			if let parsed = try? JSONSerialization.jsonObject(with: Data(output[start...].utf8)),
			   let array = parsed as? [[String: Any]] {
				return array
			}
			searched = output.index(after: start)
		}
		return []
	}
}
