import AppKit
import AbydosKit

/// Running somewhere that is not this machine.
///
/// Part of `RunCoordinator`, in a file of its own because the whole of it is
/// some 2,900 lines and one file of that size is what this change exists to
/// stop. Still one type: the state is in the main file, private to that type,
/// rather than spread between three of them.
extension RunCoordinator {





	/// Writes a line into the launch log.
	///
	/// Everything a cluster launch does happens somewhere else and takes
	/// seconds: which context, which pod, what helm is doing, what the cluster
	/// says about it. A spinner and one line of status is not enough to tell a
	/// slow step from a stuck one.
	func clusterLog(_ line: String, reset: Bool = false) {
		panel.appendLaunchLog(line, reset: reset)
	}

	/// Builds for the cluster, pushes the binary into a pod, and starts it.
	///
	/// The same configuration as any other: the package, the arguments and the
	/// environment do not change because the machine does. What changes is
	/// where the binary lands and who runs it.
	func runInCluster(
		_ configuration: LaunchConfiguration,
		in root: URL,
		environment: [String: String],
		debug: Bool
	) {
		guard let settings = configuration.devPod else { return }
		stopDevPodForwards()
		onSetPanelVisible(true)
		runControl?.setStatus("Looking for a pod\u{2026}", busy: true)
		clusterLog("launching \(configuration.name)", reset: true)

		// Kept, so the stop button has something to stop. Everything here waits
		// on a cluster, and waiting on a cluster is exactly when somebody wants
		// to change their mind.
		clusterTask = Task { @MainActor in
			defer { clusterTask = nil }
			do {
				// Which cluster, and whether this configuration is allowed on
				// it: one that follows the current context follows it
				// everywhere, and everybody has a production cluster in their
				// kubeconfig.
				let current = settings.followsCurrentContext
					? await Kubernetes.currentContext(kubeconfig: settings.kubeconfig)
					: nil
				let context: String?
				switch settings.resolve(current: current) {
				case let .success(name):
					context = name
				case let .failure(refusal):
					throw refusal
				}
				let kubeconfig = settings.kubeconfig.isEmpty ? nil : settings.kubeconfig
				clusterLog("cluster \(context ?? "current")"
					+ (settings.namespace.isEmpty ? "" : ", namespace \(settings.namespace)"))

				// A project with a chart of its own gets that chart, with one
				// container of it put into development mode. Everything the
				// chart gives that container — its environment, its secrets,
				// what it sits beside — is what the program will find.
				if let chart = configuration.helm {
					try await prepareChart(
						chart,
						configuration: configuration,
						settings: settings,
						context: context,
						kubeconfig: kubeconfig,
						root: root
					)
				}

				let pods = await DevPods.list(
					context: context,
					namespace: settings.namespace.isEmpty ? nil : settings.namespace,
					kubeconfig: kubeconfig
				).filter { $0.isRunning }

				// This project's own pod. Two projects sharing a namespace each
				// get a release named after them, and taking whichever pod is
				// listed first means one project's binary lands in the other's
				// pod — which looks, from the logs, like a stale build.
				// A chart of the project's own names its own release, and the
				// pod is whichever one holds the patched container.
				let release = configuration.helm?.release ?? DevPodInstall.releaseName(for: root)
				var candidates = settings.pod.isEmpty
					? pods.filter { $0.name.hasPrefix(release) }
					: pods
				if candidates.isEmpty, configuration.helm != nil {
					throw DevPodClient.Failure.unreachable(
						"The chart's pod did not come up. The launch log has what helm and the "
							+ "cluster said about it."
					)
				}
				if candidates.isEmpty {
					// Nowhere to run this yet, so make somewhere: pressing run
					// should not stop to say a chart is missing.
					guard settings.allowInstall else {
						throw DevPodClient.Failure.unreachable(
							"No development pod is running in "
								+ "\(context ?? "the current context")"
								+ (settings.namespace.isEmpty ? "" : "/\(settings.namespace)")
								+ ", and this configuration does not sidebar.install one."
						)
					}
					try await installDevPod(
							configuration: configuration, settings: settings,
							context: context, root: root
						)
					candidates = await DevPods.list(
						context: context,
						namespace: settings.namespace.isEmpty ? nil : settings.namespace,
						kubeconfig: kubeconfig
					).filter { $0.isRunning && (settings.pod.isEmpty ? $0.name.hasPrefix(release) : true) }
				}

				// A pod that is running is not necessarily a pod that is
				// published. What the chart was installed with is compared
				// against what this configuration asks for, and the release is
				// upgraded when they have drifted apart.
				if !candidates.isEmpty, settings.allowInstall, configuration.helm == nil {
					let desired = DevPodFiles.helmValues(
							for: settings,
							image: DevPodImage.resolved(settings.image, for: configuration, root: root)
						)
					let release = DevPodInstall.releaseName(for: root)
					let deployed = await DevPodInstall.deployedValues(
						release: release,
						namespace: settings.namespace.isEmpty ? "abydos-dev" : settings.namespace,
						context: context,
						kubeconfig: kubeconfig
					)
					if DevPodInstall.upgradeNeeded(desired: desired, deployed: deployed) {
						clusterLog("the pod is not set up the way this configuration asks for")
						try await installDevPod(
							configuration: configuration, settings: settings,
							context: context, root: root
						)
						candidates = await DevPods.list(
							context: context,
							namespace: settings.namespace.isEmpty ? nil : settings.namespace,
							kubeconfig: kubeconfig
						).filter { $0.isRunning && (settings.pod.isEmpty ? $0.name.hasPrefix(release) : true) }
					}
				}

				guard let pod = candidates.first(where: { settings.pod.isEmpty || $0.name == settings.pod })
					?? candidates.first
				else {
					throw DevPodClient.Failure.unreachable(
						"No development pod is running there, and installing one produced none."
					)
				}

				// The node decides what the binary has to be: a laptop is arm64
				// and a shared cluster usually is not.
				try Task.checkCancellation()
				clusterLog("pod \(pod.namespace)/\(pod.name)")
				let architecture = await DevPods.architecture(context: context, kubeconfig: kubeconfig)
					?? "amd64"
				runControl?.setStatus("Building for linux/\(architecture)…", busy: true)
				clusterLog("building for linux/\(architecture)")

				let output = FileManager.default.temporaryDirectory
					.appendingPathComponent("abydos-devpod-\(configuration.name.replacingOccurrences(of: " ", with: "-"))")
				// The project, not the working directory: what a build needs to
				// know — where go.mod is, where build.zig is, where make runs —
				// hangs off the project, and `cwd` is where the program runs.
				let binary = try await DevPodBuild.build(
					configuration: configuration,
					root: root,
					architecture: architecture,
					output: output,
					progress: { line in Task { @MainActor in self.clusterLog(line) } }
				)

				let attributes = try? FileManager.default.attributesOfItem(atPath: binary.path)
				let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
				runControl?.setStatus(
					"Sending \(ProfileValue.format(size, unit: "bytes")) to \(pod.name)…",
					busy: true
				)
				let control = try await PortForward.start(
					to: PodTarget(
						namespace: pod.namespace, name: pod.name, phase: pod.phase,
						containers: [], port: pod.controlPort, portSource: .containerPort
					),
					context: context,
					remotePort: pod.controlPort,
					kubeconfig: kubeconfig
				)
				devPodForwards.append(control)

				let client = DevPodClient(localPort: control.localPort)

				// Whatever the program reads goes first, and before it starts:
				// a service told where its configuration is cannot find it in
				// a pod that has never seen the file, and "no such file" says
				// nothing about the pod being empty.
				let plan = DevPodFiles.plan(
					files: settings.files,
					arguments: configuration.expandedArguments(root: root),
					root: root
				)
				for transfer in plan.transfers {
					try Task.checkCancellation()
					clusterLog("sending \(transfer.local.lastPathComponent) to \(transfer.remote)")
					try await client.push(file: transfer.local, to: transfer.remote)
				}
				if !plan.transfers.isEmpty {
					runControl?.setStatus(
						"Sent \(plan.transfers.count) file\(plan.transfers.count == 1 ? "" : "s")…",
						busy: true
					)
				}

				// Delve debugs Go; a JVM debugs itself, given the flag; and
				// everything else is held by gdbserver and driven by the LLDB on
				// this machine.
				// Nothing recognised means the full image is in the pod, which has
				// both; gdbserver is the one that works on a binary from anywhere.
				let debugger = DevPodBuild.debugger(for: configuration, root: root)
				let isGo = debugger == .delve
				let isJava = debugger == .jdwp
				let mode: String
				switch (debug, debugger) {
				case (false, .jdwp): mode = "jvm"
				case (false, _): mode = "run"
				case (true, .delve): mode = "debug"
				case (true, .jdwp): mode = "jvm-debug"
				case (true, _): mode = "native-debug"
				}

				try Task.checkCancellation()
				clusterLog("sending the binary, mode \(mode)")
				let status = try await client.push(
					binary: binary,
					mode: mode,
					// In debug mode the editor says what to launch, so these
					// would be said twice; in run mode the pod is on its own.
					arguments: debug ? [] : plan.arguments,
					environment: debug ? [:] : environment
				)
				guard status.architecture.isEmpty || status.architecture == architecture else {
					throw DevPodClient.Failure.wrongArchitecture(
						binary: architecture, pod: status.architecture
					)
				}

				if debug {
					clusterLog("attaching the debugger")
					try await attachDebugger(
						to: pod, context: context, kubeconfig: kubeconfig,
						arguments: plan.arguments, environment: environment,
						nativeBinary: isGo || isJava ? nil : binary,
						java: isJava
							? JavaDebug.Request(
								kind: .attach,
								mainClass: configuration.javaMainClass ?? "",
								projectName: nil
							)
							: nil,
						root: root
					)
					// What the program prints goes to the pod's stdout, which
					// the debugger never sees. Followed into the console beside
					// the debugger's own output, so one pane has both.
					if let started = panel.activeDebugSession {
						followDevPodLogs(client, pod: pod, debugging: started)
					}
				} else {
					// Busy: the program is up in the cluster until somebody
					// stops it, and the strip is where that is said and done.
					// The size is what proves the push landed: a program that
					// looks unchanged is the first thing to doubt.
					runControl?.setStatus(
						"Running \(ProfileValue.format(Int64(status.binarySize), unit: "bytes")) "
							+ "in \(pod.namespace)/\(pod.name)",
						busy: true
					)
					clusterLog("running in \(pod.namespace)/\(pod.name)")
					devPodClient = client
					followDevPodLogs(client, pod: pod)
					await openServicePort(settings: settings, pod: pod, context: context, kubeconfig: kubeconfig)

					if profileAfterRun {
						profileAfterRun = false
						await openProfiler(on: pod, context: context, kubeconfig: kubeconfig)
					}
				}
			} catch is CancellationError {
				stopDevPodForwards()
				clusterLog("stopped")
				runControl?.setStatus("Stopped")
			} catch {
				let detail = Self.describe(devPod: error)
				stopDevPodForwards()
				clusterLog(detail)
				// The strip gets the headline; the whole story is in the toast
				// and in the launch log, where there is room for it.
				runControl?.setStatus(Self.headline(of: detail), failed: true)
				notify("Could not run in the cluster", detail: detail)
			}
		}
	}

	/// Puts a development pod in the cluster for this project.
	///
	/// One release per project, named after it: two projects sharing a pod
	/// would overwrite each other's binary, and the name is what somebody sees
	/// in `helm list` when they wonder what this is.
	func installDevPod(
		configuration: LaunchConfiguration,
		settings: LaunchConfiguration.DevPodSettings,
		context: String?,
		root: URL
	) async throws {
		guard let chart = Self.bundledChart else { throw DevPodInstall.Failure.noChart }

		let release = DevPodInstall.releaseName(for: root)
		let namespace = settings.namespace.isEmpty ? "abydos-dev" : settings.namespace
		let kubeconfig = settings.kubeconfig.isEmpty ? nil : settings.kubeconfig
		// The slim image for whatever this project is written in, unless the
		// configuration names one itself: a pod that only ever debugs Go has no
		// use for gdbserver, and one that never sees Go has none for Delve.
		let image = DevPodImage.resolved(settings.image, for: configuration, root: root)
		runControl?.setStatus("Installing \(release) in \(namespace)…", busy: true)
		clusterLog("installing \(release) in \(namespace), image \(image)")

		// The sidebar.install and a watch on what it produces, side by side. helm waits
		// in silence and then reports its own deadline — "context deadline
		// exceeded" — while the cluster has been saying since the fourth second
		// that it cannot pull the image. Whichever finishes first wins: a pod
		// that will never start ends this now rather than in two minutes.
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { @MainActor [weak self] in
				try await DevPodInstall.install(
					chart: chart,
					release: release,
					namespace: namespace,
					// The resolved context, not what the configuration says: it
					// may say `${currentContext}`, which is not a cluster.
					context: context,
					kubeconfig: kubeconfig,
					image: image,
					// What the chart has to publish, and on which port.
					values: DevPodFiles.helmValues(for: settings, image: image),
					progress: { line in
						Task { @MainActor in self?.clusterLog(line) }
					}
				)
			}
			group.addTask { @MainActor [weak self] in
				try await self?.watchInstall(
					release: release, namespace: namespace,
					context: context, kubeconfig: kubeconfig, image: image
				)
			}

			defer { group.cancelAll() }
			try await group.next()
		}
		notify(
			"Installed a development pod",
			detail: "\(release) in \(namespace). Remove it with: helm uninstall \(release) -n \(namespace)",
			kind: .information
		)
	}

	/// Runs what is selected and puts the profiler in front of it.
	///
	/// The program has to be serving pprof for this to find anything, which for
	/// a Go service usually means `net/http/pprof` on 6060 — the profiler says
	/// so plainly when there is nothing there, which is the only useful thing
	/// to say about a program that is not instrumented.
	func profileSelectedConfiguration() {
		guard let configuration = selectedConfiguration else {
			notify("Nothing to profile", detail: "Choose a configuration first.", kind: .information)
			return
		}

		// Asked for now, done when there is something to profile. A cluster run
		// opens the profiler on the pod it just started; a local one waits for
		// the program to be listening.
		profileAfterRun = true
		runSelectedConfiguration(debug: false)

		guard configuration.devPod == nil else { return }
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 1_500_000_000)
			guard profileAfterRun else { return }
			profileAfterRun = false
			onSetPanelVisible(true)
			panel.showProfiler(address: Self.lastProfilerAddress, connecting: true)
		}
	}


	/// The profiler, on the pod this run just started.
	func openProfiler(on pod: DevPodTarget, context: String?, kubeconfig: String?) async {
		do {
			let forward = try await PortForward.start(
				to: PodTarget(
					namespace: pod.namespace, name: pod.name, phase: pod.phase,
					containers: [], port: 6060, portSource: .containerPort
				),
				context: context,
				remotePort: 6060,
				kubeconfig: kubeconfig
			)
			devPodForwards.append(forward)
			onSetPanelVisible(true)
			panel.showProfiler(address: "localhost:\(forward.localPort)", connecting: true)
			clusterLog("profiling through localhost:\(forward.localPort)")
		} catch {
			clusterLog("no profiler on port 6060: \(error.localizedDescription)")
			notify(
				"Could not reach the pod's profiler",
				detail: "Nothing answered on port 6060 in \(pod.name). A Go service serves "
					+ "pprof there when it imports net/http/pprof.\n\n"
					+ error.localizedDescription
			)
		}
	}

	/// Makes what the program serves reachable from here.
	///
	/// A microservice is tested by talking to it, and a pod in a cluster is not
	/// somewhere a browser can reach. A forward to the port it listens on costs
	/// nothing and turns "it is running" into a link. The ingress, when the
	/// configuration asks for one, is the other way in — and the one that other
	/// people can use.
	func openServicePort(
		settings: LaunchConfiguration.DevPodSettings,
		pod: DevPodTarget,
		context: String?,
		kubeconfig: String?
	) async {
		if !settings.ingressHost.isEmpty {
			clusterLog("published at http://\(settings.ingressHost)")
		}

		let port = settings.port > 0 ? settings.port : 8080
		do {
			let forward = try await PortForward.start(
				to: PodTarget(
					namespace: pod.namespace, name: pod.name, phase: pod.phase,
					containers: [], port: port, portSource: .containerPort
				),
				context: context,
				remotePort: port,
				kubeconfig: kubeconfig
			)
			devPodForwards.append(forward)
			clusterLog("reachable at http://localhost:\(forward.localPort) (pod port \(port))")
		} catch {
			// Not a failure: plenty of programs serve nothing at all.
			clusterLog("no forward to port \(port): \(error.localizedDescription)")
		}
	}

	/// Installs the project's own chart, and puts one of its containers into
	/// development mode.
	///
	/// Two steps, both of which somebody could do by hand and neither of which
	/// anybody wants to: `helm upgrade` with this stage's values, and a patch
	/// that swaps the named container's image and command for the supervisor.
	/// The pod keeps everything else the chart gave it.
	func prepareChart(
		_ chart: LaunchConfiguration.HelmSettings,
		configuration: LaunchConfiguration,
		settings: LaunchConfiguration.DevPodSettings,
		context: String?,
		kubeconfig: String?,
		root: URL
	) async throws {
		let namespace = settings.namespace.isEmpty ? "default" : settings.namespace

		let present = await HelmRelease.exists(
			release: chart.release, namespace: namespace, context: context, kubeconfig: kubeconfig
		)
		if !present || chart.install {
			guard chart.install else {
				throw HelmRelease.Failure(
					"The release \(chart.release) is not installed in \(namespace), and this "
						+ "configuration does not sidebar.install it."
				)
			}
			runControl?.setStatus("Installing \(chart.release)…", busy: true)
			clusterLog("installing \(chart.release) from \(chart.chart)")
			try await HelmRelease.upgrade(
				chart,
				root: root,
				namespace: namespace,
				context: context,
				kubeconfig: kubeconfig,
				progress: { line in Task { @MainActor in self.clusterLog(line) } }
			)
		}
		try Task.checkCancellation()

		// Which deployment holds the container this configuration is for. A pod
		// with an application and a web front end in it is two configurations,
		// and each replaces its own container.
		let deployments = await HelmRelease.deployments(
			release: chart.release, namespace: namespace, context: context, kubeconfig: kubeconfig
		)
		guard let deployment = HelmRelease.deployment(holding: chart.container, in: deployments) else {
			throw HelmRelease.Failure(
				"No deployment in \(chart.release) has a container called "
					+ "\(chart.container.isEmpty ? "anything" : chart.container). "
					+ "It has: " + deployments.map(\.name).joined(separator: ", ") + "."
			)
		}

		let image = DevPodImage.resolved(settings.image, for: configuration, root: root)
		let container = chart.container.isEmpty
			? (deployments.first { $0.name == deployment }?.containers.first ?? "app")
			: chart.container

		runControl?.setStatus("Putting \(container) into development mode…", busy: true)
		clusterLog("patching \(deployment)/\(container) to run the supervisor")

		let patch = await Kubernetes.run(
			[
				"patch", "deployment", deployment, "--namespace", namespace,
				"--type", "strategic",
				// Under helm's name: the cluster records who owns each field,
				// and a patch under a name of its own makes the next `helm
				// upgrade` a conflict rather than an upgrade.
				"--field-manager", "helm",
				"-p", DevContainerPatch.json(container: container, image: image),
			],
			context: context,
			kubeconfig: kubeconfig
		)
		guard patch.exitCode == 0 else {
			throw HelmRelease.Failure(patch.stderr.isEmpty ? patch.stdout : patch.stderr)
		}
		clusterLog(patch.stdout.trimmingCharacters(in: .whitespacesAndNewlines))

		// And wait for it, because the next thing that happens is a binary
		// being pushed into a pod that has to exist first.
		runControl?.setStatus("Waiting for \(deployment)…", busy: true)
		let rollout = await Kubernetes.run(
			[
				"rollout", "status", "deployment/" + deployment,
				"--namespace", namespace, "--timeout", "120s",
			],
			context: context,
			kubeconfig: kubeconfig
		)
		clusterLog(rollout.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
		guard rollout.exitCode == 0 else {
			throw HelmRelease.Failure(
				(rollout.stderr.isEmpty ? rollout.stdout : rollout.stderr)
					+ "\n\nThe container was patched but the pod did not come up. "
					+ "`kubectl rollout undo deployment/\(deployment) -n \(namespace)` puts it back."
			)
		}
	}

	func attachDebugger(
		to pod: DevPodTarget,
		context: String?,
		kubeconfig: String?,
		arguments: [String],
		environment: [String: String],
		nativeBinary: URL? = nil,
		java: JavaDebug.Request? = nil,
		root: URL? = nil
	) async throws {
		let debugForward = try await PortForward.start(
			to: PodTarget(
				namespace: pod.namespace, name: pod.name, phase: pod.phase,
				containers: [], port: pod.debugPort, portSource: .containerPort
			),
			context: context,
			remotePort: pod.debugPort,
			kubeconfig: kubeconfig
		)
		devPodForwards.append(debugForward)

		runControl?.setStatus("Debugging in \(pod.name)…", busy: true)

		// A JVM in a pod holds itself at its first instruction — `suspend=y` —
		// and waits for a debugger on the port the supervisor opened. What
		// connects to it is the adapter inside the language server here, so the
		// sources it shows are the ones on this disk.
		if var request = java {
			guard let root else { return }
			// The port and the class files together, from one server: whichever
			// jdtls can give them, which since 0452 may be one started for the
			// debugger alone. The class files are here, so a frame from the pod
			// lands on the source it was compiled from rather than on a
			// decompiled stub.
			let target = try await LanguageService.shared.javaLaunchTarget(
				project: root,
				// Off this thread and through the shared cache: the synchronous
				// scan reads every source file in the project, and
				// `mainClasses`' own documentation says not to call it from a
				// context like this one.
				anchor: await JavaTooling.mainClassesOffMain(in: root).first
					.map { URL(fileURLWithPath: $0.file) },
				saying: { sentence in
						self.runControl?.setStatus(sentence, busy: true, preparing: true)
					}
			)
			request.host = "127.0.0.1"
			request.port = debugForward.localPort
			request.classPaths = target.classPaths
			request.projectName = target.projectName

			guard let session = panel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: target.port, request: request),
				breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:],
				location: label(for: pod)
			) else { return }
			onWire(session)
			return
		}

		// A native program is held by gdbserver in the pod and driven by the
		// LLDB here, against the binary that was pushed — which was built here,
		// so its debug information points at these sources.
		if let nativeBinary {
			guard let lldb = DebugAdapters.executable(for: DebugAdapters.lldb) else {
				throw DevPodClient.Failure.unreachable(
					"Debugging a native program in a cluster needs LLDB's adapter here: "
						+ DebugAdapters.lldb.installHint
				)
			}
			guard let session = panel.startDebugging(
				adapter: DebugAdapters.lldb,
				executable: lldb,
				start: .nativeRemote(
					host: "127.0.0.1", port: debugForward.localPort, binary: nativeBinary
				),
				breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:],
				location: label(for: pod)
			) else { return }
			onWire(session)
			return
		}

		guard let session = panel.startDebugging(
			adapter: DebugAdapters.delve,
			executable: "",
			start: .remote(
				host: "127.0.0.1",
				port: debugForward.localPort,
				// The path inside the pod, which is where the supervisor put it.
				program: "/app/current",
				arguments: arguments,
				workingDirectory: "/app",
				environment: environment
			),
			breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:],
			location: label(for: pod)
		) else { return }
		onWire(session)
	}

	/// Shows what the program in the pod is printing.
	///
	/// While debugging it goes to the debug console rather than to a tab of its
	/// own. The adapter's output events carry what the *debugger* says; a
	/// program in a pod writes to the pod's stdout, which the debugger never
	/// sees — so the console sat empty through a whole session while
	/// `kubectl logs` had the story.
	func followDevPodLogs(
		_ client: DevPodClient,
		pod: DevPodTarget,
		debugging debugSession: DebugSession? = nil
	) {
		Task { @MainActor in
			// A poll rather than a stream: the supervisor keeps a tail, the
			// interesting output arrives in the first seconds, and a websocket
			// for this would be a protocol to maintain.
			//
			// A run is watched for a while; a debug session for as long as it
			// lasts, since the line worth reading is often the one printed just
			// before a breakpoint somebody took ten minutes to reach.
			var remaining = debugSession == nil ? 20 : Int.max
			// The console is appended to rather than replaced, so the same two
			// hundred lines must not arrive every second — and cannot simply be
			// replaced either, since the debugger's own output is interleaved
			// with the program's.
			var tail = LogTail()
			while remaining > 0 {
				remaining -= 1
				try? await Task.sleep(nanoseconds: 1_000_000_000)
				if let debugSession, debugSession.state == .terminated { return }
				guard let text = try? await client.logs(tail: 200), !text.isEmpty else { continue }
				guard debugSession != nil else {
					panel.showDevPodOutput(text, from: "\(pod.namespace)/\(pod.name)")
					continue
				}
				let fresh = tail.newText(in: text)
				if !fresh.isEmpty { panel.activeDebugPane?.appendOutput(fresh) }
			}
		}
	}

	func stopDevPodForwards() {
		for forward in devPodForwards { forward.stop() }
		devPodForwards = []
	}

	/// Stops a program running in a cluster, and closes the tunnels to it.
	func stopDevPod() {
		guard let client = devPodClient else { return }
		devPodClient = nil
		runControl?.setStatus("Stopping…", busy: true)
		Task { @MainActor in
			try? await client.stop()
			stopDevPodForwards()
			runControl?.setStatus("Stopped")
		}
	}

	/// Reports what the cluster is doing with the pods an sidebar.install just asked
	/// for, and gives up when there is nothing left to wait for.
	///
	/// Only failure ends this: readiness is helm's to decide, and a pod that
	/// looks ready for a moment is not the same as a release that is.
	func watchInstall(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?,
		image: String
	) async throws {
		var reported: Set<String> = []
		while !Task.isCancelled {
			try await Task.sleep(nanoseconds: 1_500_000_000)
			let states = await DevPodWatch.states(
				release: release, namespace: namespace,
				context: context, kubeconfig: kubeconfig
			)
			for state in states where !reported.contains(state.line) {
				reported.insert(state.line)
				clusterLog("  " + state.line)
			}
			if let hopeless = states.first(where: \.isHopeless) {
				throw DevPodInstall.Failure.failed(DevPodWatch.explain(hopeless, image: image))
			}
		}
	}

	/// The first line of a message, for somewhere a line is all there is.
	static func headline(of message: String) -> String {
		let first = message
			.split(separator: "\n", omittingEmptySubsequences: false)
			.first
			.map(String.init)?
			.trimmingCharacters(in: .whitespaces) ?? message
		return first.count > 140 ? String(first.prefix(139)) + "\u{2026}" : first
	}
}
