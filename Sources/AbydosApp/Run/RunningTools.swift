import AppKit
import AbydosKit

/// What this app has started and has not ended, with what each costs.
///
/// 0427 is the reason this exists, and its last section is the condition on the
/// decision above it: a language server is kept until the app quits, which means
/// a session that opens project after project collects them — nine of them, with
/// fifteen gigabytes of `swift-frontend` underneath, on the machine that opened
/// the entry. That was found by running `ps`. This is the list that makes
/// running `ps` unnecessary, and the reason it has a Stop beside every row.
///
/// **Gathered in two halves, and the split is the point.** What is running is
/// known here, on the main actor, from the app's own registers; what it costs
/// has to be asked of the operating system and of a container runtime, which
/// blocks. So `descriptors()` is cheap and synchronous and `measure(_:)` is
/// neither, and nothing calls the second on the main thread.
@MainActor
enum RunningTools {
	/// What stopping a row means.
	enum Handle: Equatable, Sendable {
		/// A language server, by the key `LanguageService` files it under.
		case languageServer(String)
		/// A container, by the name the runtime knows it as.
		///
		/// The runtime is not in here although the row knows it: everything that
		/// removes a container looks the runtime up from the register itself,
		/// and a second copy of it in the handle would be a value that has to
		/// agree with the register and cannot be checked against it.
		case container(String)
	}

	/// One thing that is running, before anything has been measured.
	struct Descriptor: Sendable {
		let handle: Handle
		/// What it is: `sourcekit-lsp`, `PlantUML server`, `Dev container`.
		let title: String
		/// What it is for, in a few words: the project that asked for a server,
		/// and for a container its own name — which is the handle somebody needs
		/// if they do go and look with `docker` after all.
		let startedFor: String
		/// Its process on this machine, when it has one here.
		let pid: pid_t?
		/// Its container, when it is one or owns one — the one whose numbers are
		/// this thing's numbers, and which goes when this goes.
		let container: String?
		let runtime: ContainerRuntime?
		/// The container it merely lives in, shared with whatever else is in
		/// there. Set only when that is somebody else's container: it is why this
		/// row has no memory to show rather than a wrong one.
		let livesIn: String?
	}

	/// A row of the list.
	struct Row: Identifiable, Sendable {
		let handle: Handle
		let title: String
		let startedFor: String
		/// The executable `ps` resolved, or the image the container came from.
		///
		/// Worth a line of its own because of 0427's second fault: the servers
		/// were running out of swiftly's toolchain while the build used Xcode's,
		/// so the errors on screen were not the errors from the compiler. The one
		/// place that can be seen is the path of the process that is actually
		/// running.
		let from: String
		/// How long it has been up.
		let uptime: TimeInterval?
		/// Resident memory of it and everything under it, or nil when nothing
		/// would say — which is shown as a dash rather than as a zero.
		let residentBytes: Int64?
		/// How many processes are under it. The 15 GB lived here, not in the
		/// server, so the count is beside the number rather than hidden.
		let descendants: Int
		/// Its process on this machine, kept so that a measurement of this view
		/// can ask the operating system whether a stopped server really went.
		/// The list itself cannot answer that: it is drawn from the app's own
		/// register, which is the thing under test.
		let pid: pid_t?

		var id: String {
			switch handle {
			case let .languageServer(key): return "server:\(key)"
			case let .container(name): return "container:\(name)"
			}
		}
	}

	// MARK: - What is running

	/// Everything this app has started and not ended, without measuring any of
	/// it.
	///
	/// A language server that has a container of its own appears once, as the
	/// server: that container *is* that server, and two rows for one thing would
	/// be two Stop buttons where one is meant.
	///
	/// A server inside the project's *devcontainer* is the other case and gets
	/// two rows, which is not an oversight. The container is shared — with the
	/// terminals, the build, and every other server in it — so it outlives this
	/// server and has to be stoppable on its own. Measured: opening a Python
	/// project with a devcontainer gave one row for `pyright-langserver` and one
	/// for the container it is in.
	static func descriptors() -> [Descriptor] {
		let servers = LanguageService.shared.running
		var found: [Descriptor] = servers.map { server in
			Descriptor(
				handle: .languageServer(server.key),
				title: server.command,
				startedFor: server.project.lastPathComponent,
				pid: server.pid,
				container: server.containerName,
				runtime: nil,
				livesIn: server.containerName == nil ? server.insideContainer : nil
			)
		}

		let claimed = Set(servers.compactMap(\.containerName))
		for (name, runtime) in ToolContainers.shared.registrations where !claimed.contains(name) {
			found.append(Descriptor(
				handle: .container(name),
				title: title(ofContainer: name),
				startedFor: name,
				pid: nil,
				container: name,
				runtime: runtime,
				livesIn: nil
			))
		}
		return found
	}

	/// What a container is called in words, from the role its name carries.
	static func title(ofContainer name: String) -> String {
		switch ToolContainers.role(of: name) {
		case "devcontainer": return "Dev container"
		case "plantuml-server": return "PlantUML server"
		case "plantuml", "plantuml-export": return "PlantUML render"
		case let role? where role.hasPrefix("lsp-"): return String(role.dropFirst(4))
		case let role?: return role
		case nil: return name
		}
	}

	// MARK: - What it costs

	/// Measures what these are using. Blocks — one `ps`, and at most one pair of
	/// commands per container runtime.
	///
	/// Deliberately not `@MainActor`: `docker stats` is about a second even on a
	/// healthy daemon, and a list of what is wasting the machine's time must not
	/// be one of the things wasting it.
	nonisolated static func measure(_ descriptors: [Descriptor]) -> [Row] {
		let processes = descriptors.contains { $0.pid != nil }
			? ProcessTable.sample()
			: ProcessTable(entries: [])

		// One pair of commands per runtime, however many containers it holds.
		var containerFacts: [String: ContainerInventory.Fact] = [:]
		var byRuntime: [String: (runtime: ContainerRuntime, names: [String])] = [:]
		for descriptor in descriptors {
			guard let name = descriptor.container,
			      let runtime = descriptor.runtime ?? runtimeOf(descriptor)
			else { continue }
			byRuntime[runtime.path, default: (runtime, [])].names.append(name)
		}
		for group in byRuntime.values {
			for fact in ContainerInventory.facts(named: group.names, using: group.runtime) {
				containerFacts[fact.name] = fact
			}
		}

		return descriptors.map { descriptor in
			let cost = descriptor.pid.flatMap { processes.cost(of: $0) }
			let fact = descriptor.container.flatMap { containerFacts[$0] }

			// The container's memory wins where there is one. A language server
			// in a container is a `docker run` on this machine — a few megabytes
			// of client — with the whole of the server on the other side of it,
			// so the process's own tree is the wrong number by three orders of
			// magnitude.
			// And nothing at all where the thing lives in a container this row
			// does not own. The process out here is the runtime's client and the
			// server is on the other side of it; the container's own figure is
			// the row below, shared with everything else in there, and claiming
			// it twice would be worse than claiming it once in the wrong place.
			let resident = descriptor.livesIn != nil
				? nil
				: (fact?.residentBytes ?? cost?.residentBytes)
			// The image wins over the path for the same reason the container's
			// memory does. What the second line of a row is for is 0427's second
			// fault — which toolchain this server is really running out of — and
			// for a server in a container the answer is the image or the
			// container, never `/usr/local/bin/container`, which is true and says
			// nothing.
			var from = descriptor.livesIn.map { "in \($0)" }
				?? fact.map { $0.image.isEmpty ? $0.name : $0.image }
				?? descriptor.pid.flatMap { processes.entries[$0]?.command }
				?? ""
			// A container this app has not released yet but that the runtime has
			// stopped is still a row here, and everything else in it would read
			// as healthy: `docker stats` answers `0B / 0B` about a stopped
			// container rather than refusing, so the memory column would say
			// nought. The runtime's own word for it goes on the row instead of
			// being collected and thrown away.
			if let fact, !fact.isRunning, !fact.status.isEmpty {
				from = from.isEmpty ? fact.status : "\(from) — \(fact.status)"
			}

			// The process's own age where there is a process, and the runtime's
			// answer where the thing is only a container.
			let uptime = cost?.elapsed
				?? fact?.startedAt.map { Date().timeIntervalSince($0) }

			return Row(
				handle: descriptor.handle,
				title: descriptor.title,
				startedFor: descriptor.startedFor,
				from: from,
				uptime: uptime,
				residentBytes: resident,
				// Only where the number they are part of came from this machine.
				// A container's memory is measured inside it, and the processes
				// counted out here — the runtime client and its helper — are not
				// in that figure; "+2" beside it would say they were.
				descendants: resident == cost?.residentBytes ? (cost?.descendants ?? 0) : 0,
				pid: descriptor.pid
			)
		}
	}

	/// The runtime a language server's container belongs to, which the server
	/// row does not carry: it is whatever `ToolContainers` registered it under.
	private nonisolated static func runtimeOf(_ descriptor: Descriptor) -> ContainerRuntime? {
		guard let name = descriptor.container else { return nil }
		return ToolContainers.shared.registrations.first { $0.name == name }?.runtime
	}

	// MARK: - Stopping one

	/// Stops one, and says what happened in a sentence fit to show.
	///
	/// Every route here goes through whatever owns the thing, never straight to
	/// a `kill`: a language server through `LanguageService`, a devcontainer
	/// through `DevContainers`. Otherwise the app goes on believing it has a
	/// server or a session that is not there, which is a worse state than the
	/// one this list exists to fix.
	static func stop(_ handle: Handle) async -> String {
		switch handle {
		case let .languageServer(key):
			guard LanguageService.shared.shutdown(server: key) else {
				return "It had already stopped."
			}
			return "Stopped. It starts again the next time a file needs it."

		case let .container(name):
			switch ToolContainers.role(of: name) {
			case "devcontainer":
				// Through the actor that keeps it, so the next terminal or
				// language server asks for a new one rather than being handed a
				// name nothing answers to.
				await DevContainers.shared.stop(named: name)
			default:
				// A PlantUML server is kept by an actor that already survives
				// this: the next render finds it not answering, forgets it and
				// starts another — the same path a container removed by hand
				// behind its back has always taken. Everything else registered
				// here is a one-shot run that its owner releases anyway.
				//
				// Off this actor, and that is not a nicety: `release` waits up
				// to `removalDeadline` — ten seconds — for the runtime to answer,
				// and this function is on the main one. A window whose subject is
				// a machine that has stopped responding must not itself stop
				// responding when somebody presses the button on it.
				await Task.detached { ToolContainers.shared.release(name) }.value
			}
			return "Stopped."
		}
	}

	// MARK: - Saying the numbers

	/// Memory, in the units somebody reads a machine in.
	static func memory(_ bytes: Int64?) -> String {
		guard let bytes else { return "—" }
		return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
	}

	/// How long, short enough for a column: `41s`, `12m`, `3h 04m`, `2d 07h`.
	static func uptime(_ seconds: TimeInterval?) -> String {
		guard let seconds, seconds >= 0 else { return "—" }
		let whole = Int(seconds)
		if whole < 60 { return "\(whole)s" }
		if whole < 3_600 { return "\(whole / 60)m" }
		if whole < 86_400 {
			return String(format: "%dh %02dm", whole / 3_600, (whole % 3_600) / 60)
		}
		return String(format: "%dd %02dh", whole / 86_400, (whole % 86_400) / 3_600)
	}
}
