import Foundation

/// Running a scheme somewhere, as a command line.
///
/// A command rather than a sequence of processes run from here, because this
/// app runs everything else in a terminal where the output is: a build that
/// fails prints what Xcode prints, and the line that failed can be read, copied
/// and run again by hand. `&&` between the steps is what makes it stop at the
/// first failure without a shell script to hold `set -e`.
///
/// Where the product lands is worked out rather than asked for. `xcodebuild
/// -showBuildSettings` knows, and takes about as long as a build; giving
/// `-derivedDataPath` a directory of our own makes the answer a path this can
/// spell — `Build/Products/<configuration><sdk>/<product>` — which is the same
/// bargain Xcode's own "Products" group makes.
public enum XcodeRun {
	/// Where builds go: inside the project, beside everything else this app
	/// keeps there, and one directory per scheme so switching between two
	/// schemes does not rebuild the world each time.
	public static func derivedDataPath(for scheme: XcodeScheme, in root: URL) -> String {
		IdeaiFolder.url(in: root).appendingPathComponent("xcode/\(scheme.name)").path
	}

	/// The whole thing: build, install, launch, with the app's output in the
	/// terminal it was started from.
	///
	/// Nil when the scheme has nothing to launch — a library scheme builds and
	/// that is all there is to do with it.
	public static func command(
		project: XcodeProject,
		scheme: XcodeScheme,
		destination: XcodeDestination,
		derivedData: String
	) -> String? {
		guard let product = scheme.product else { return nil }

		let products = "\(derivedData)/Build/Products/"
			+ scheme.configuration + destination.productDirectorySuffix
		let app = "\(products)/\(product)"

		var steps = [build(project: project, scheme: scheme, destination: destination, derivedData: derivedData)]

		switch destination.kind {
		case .mac:
			// Through LaunchServices rather than by running the binary, which
			// is the obvious thing and wrong: a sandboxed app started from a
			// shell cannot be granted its container and dies at once with
			// "sandbox_extension_issue_file_to_process failed". Nearly every
			// Mac app worth running is sandboxed.
			//
			// `open` can only redirect to a file — a pipe or a tty is refused
			// with -10810 — so what it prints goes to a file that is followed
			// while it runs. `-W` is what makes the run end when the app is
			// quit, rather than the moment it appears.
			let log = "\(derivedData)/run.log"
			steps.append(
				"printf '' > \(quoted(log))"
					+ " && { tail -f \(quoted(log)) & TAILPID=$!; }"
					+ " && open -W -n --stdout \(quoted(log)) --stderr \(quoted(log)) \(quoted(app))"
					// However the app ended, including a build that was stopped:
					// a `tail -f` left behind holds the terminal open and the run
					// never looks finished.
					+ "; kill $TAILPID 2>/dev/null"
			)

		case .simulator:
			let bundleID = plistValue("CFBundleIdentifier", in: "\(app)/Info.plist")
			// `bootstatus -b` boots one that is not booted and waits for one
			// that is still starting; either way what follows can install.
			steps.append("xcrun simctl bootstatus \(quoted(destination.id)) -b")
			// The window, which is a separate thing from the simulator running:
			// installing and launching work headless, and an app nobody can see
			// is not what "run it on a simulator" means.
			steps.append("open -a Simulator")
			steps.append("xcrun simctl install \(quoted(destination.id)) \(quoted(app))")
			steps.append(
				"xcrun simctl launch --console-pty --terminate-running-process "
					+ "\(quoted(destination.id)) \(bundleID)"
			)

		case .device:
			let bundleID = plistValue("CFBundleIdentifier", in: "\(app)/Info.plist")
			steps.append(
				"xcrun devicectl device install app --device \(quoted(destination.id)) \(quoted(app))"
			)
			steps.append(
				"xcrun devicectl device process launch --device \(quoted(destination.id)) "
					+ "--console --terminate-existing \(bundleID)"
			)
		}

		return steps.joined(separator: " && ")
	}

	/// The build on its own, which is also what a scheme with nothing to launch
	/// can still do.
	public static func build(
		project: XcodeProject,
		scheme: XcodeScheme,
		destination: XcodeDestination,
		derivedData: String
	) -> String {
		var arguments = ["xcodebuild"]
		// The path quoted, the flag not: quoting `-project` works and reads
		// like something nobody would type.
		arguments += project.xcodebuildArguments.enumerated()
			.map { $0.offset == 0 ? $0.element : quoted($0.element) }
		arguments += ["-scheme", quoted(scheme.name)]
		arguments += ["-configuration", quoted(scheme.configuration)]
		arguments += ["-destination", quoted("id=\(destination.id)")]
		arguments += ["-derivedDataPath", quoted(derivedData)]
		// Signing a build for a device needs a provisioning profile, and the
		// one thing worse than Xcode registering a device for you is being told
		// to open Xcode to have it done.
		if destination.kind == .device { arguments.append("-allowProvisioningUpdates") }
		arguments.append("build")
		return arguments.joined(separator: " ")
	}

	/// Read at launch rather than written in: the identifier belongs to the
	/// build, and a scheme that changes it between configurations would
	/// otherwise install one app and launch another.
	static func plistValue(_ key: String, in path: String) -> String {
		"\"$(/usr/libexec/PlistBuddy -c \(quoted("Print :" + key)) \(quoted(path)))\""
	}

	/// Single quotes, because these strings hold `$(…)` nowhere except where
	/// this file puts it, and a path with a space in it is ordinary.
	static func quoted(_ word: String) -> String {
		"'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
