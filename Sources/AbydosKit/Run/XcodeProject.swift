import Foundation

/// An Xcode project or workspace, and the schemes it can run.
///
/// Schemes are read from disk rather than from `xcodebuild -list`, because
/// `xcodebuild` takes seconds to answer and this is asked every time a project
/// is scanned. What is on disk is also the better list: a project that depends
/// on Swift packages has a scheme for every one of them in `xcodebuild -list`,
/// none of which anybody wants to run, while `xcshareddata/xcschemes` holds the
/// ones somebody made and shared.
public struct XcodeProject: Equatable, Sendable {
	public enum Container: String, Sendable {
		case project
		case workspace
	}

	public let path: String
	public let container: Container

	public init(path: String, container: Container) {
		self.path = path
		self.container = container
	}

	/// The name without the extension — `docscanner` for `docscanner.xcodeproj`.
	public var name: String {
		URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
	}

	/// What `xcodebuild` is pointed at this with.
	public var xcodebuildArguments: [String] {
		[container == .workspace ? "-workspace" : "-project", path]
	}

	/// The workspace if there is one, otherwise the project.
	///
	/// A workspace wins because a project that has one is usually a project that
	/// cannot be built alone — it is where the other projects and the packages
	/// are listed. `.xcodeproj` inside a `.xcworkspace` bundle is skipped for the
	/// same reason a nested one anywhere else is: it is a part, not the thing.
	public static func find(in directory: URL) -> XcodeProject? {
		let contents = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []

		let workspaces = contents.filter { $0.pathExtension == "xcworkspace" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
		if let workspace = workspaces.first {
			return XcodeProject(path: workspace.path, container: .workspace)
		}

		let projects = contents.filter { $0.pathExtension == "xcodeproj" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
		if let project = projects.first {
			return XcodeProject(path: project.path, container: .project)
		}
		return nil
	}

	/// The schemes on disk: the shared ones, then this user's own.
	///
	/// A user scheme with the same name as a shared one is the same scheme —
	/// Xcode writes the shared copy and leaves the name in the user's
	/// management plist — so the shared one wins and the name appears once.
	public func schemes() -> [XcodeScheme] {
		var found: [XcodeScheme] = []
		var names: Set<String> = []

		for directory in schemeDirectories() {
			let files = (try? FileManager.default.contentsOfDirectory(
				at: directory, includingPropertiesForKeys: nil
			)) ?? []
			for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
			where file.pathExtension == "xcscheme" {
				guard let scheme = XcodeScheme(file: file), names.insert(scheme.name).inserted
				else { continue }
				found.append(scheme)
			}
		}
		return found
	}

	/// Shared first, then every user's — this machine has one user, but a
	/// checkout carries whoever else has opened it.
	func schemeDirectories() -> [URL] {
		let container = URL(fileURLWithPath: path)
		var directories = [
			container.appendingPathComponent("xcshareddata/xcschemes"),
		]

		let userData = container.appendingPathComponent("xcuserdata")
		let users = (try? FileManager.default.contentsOfDirectory(
			at: userData, includingPropertiesForKeys: nil
		)) ?? []
		for user in users.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
		where user.pathExtension == "xcuserdatad" {
			directories.append(user.appendingPathComponent("xcschemes"))
		}
		return directories
	}
}

/// A scheme and the project it belongs to, which is what running one needs.
public struct XcodeTarget: Equatable, Sendable {
	public let project: XcodeProject
	public let scheme: XcodeScheme

	public init(project: XcodeProject, scheme: XcodeScheme) {
		self.project = project
		self.scheme = scheme
	}
}

/// One scheme, as far as running it goes.
public struct XcodeScheme: Equatable, Sendable, Identifiable {
	public let name: String
	/// The bundle the scheme launches — `docscanner.app`. Nil when the scheme
	/// builds something that cannot be launched, which is most of what a
	/// package contributes: a library scheme has no runnable.
	public let product: String?
	/// The configuration its launch action uses, `Debug` unless it says
	/// otherwise. Running a scheme should build what pressing play in Xcode
	/// builds, and a scheme that launches Release means it.
	public let configuration: String

	public var id: String { name }
	public var isRunnable: Bool { product != nil }

	public init(name: String, product: String?, configuration: String = "Debug") {
		self.name = name
		self.product = product
		self.configuration = configuration
	}

	/// Reads a `.xcscheme`, whose name is the file's rather than anything
	/// inside it — that is where Xcode keeps it.
	public init?(file: URL) {
		guard let document = try? XMLDocument(contentsOf: file, options: []) else { return nil }
		let name = file.deletingPathExtension().lastPathComponent

		let launch = (try? document.nodes(forXPath: "//LaunchAction"))?.first as? XMLElement
		let runnable = (try? document.nodes(forXPath:
			"//LaunchAction/BuildableProductRunnable/BuildableReference"))?.first as? XMLElement

		self.init(
			name: name,
			product: runnable?.attribute(forName: "BuildableName")?.stringValue,
			configuration: launch?.attribute(forName: "buildConfiguration")?.stringValue ?? "Debug"
		)
	}
}

/// Somewhere a scheme can run: this Mac, a simulator, or a device.
public struct XcodeDestination: Equatable, Sendable, Identifiable {
	public enum Kind: String, Sendable {
		case mac
		case simulator
		case device
	}

	public let id: String
	public let name: String
	/// As `xcodebuild` spells it: `macOS`, `iOS`, `iOS Simulator`.
	public let platform: String
	/// The OS a simulator runs, which is the only thing telling two simulators
	/// of the same model apart.
	public let os: String?
	/// `xcodebuild`'s own word for a flavour of a platform — "Mac Catalyst",
	/// "Designed for [iPad,iPhone]". Nil for everything that has only one.
	public let variant: String?

	public init(
		id: String, name: String, platform: String, os: String? = nil, variant: String? = nil
	) {
		self.id = id
		self.name = name
		self.platform = platform
		self.os = os
		self.variant = variant
	}

	/// An iOS app built to run on this Mac as a Mac app.
	///
	/// Its own case throughout, because it is macOS everywhere it is asked and
	/// not macOS anywhere it matters: a different product directory, and a
	/// `-destination` that has to say which of the two macOS destinations it
	/// means.
	public var isMacCatalyst: Bool { variant == "Mac Catalyst" }

	public var kind: Kind {
		if platform == "macOS" { return .mac }
		return platform.hasSuffix("Simulator") ? .simulator : .device
	}

	/// What the menu shows. The OS distinguishes the six iPhone 17 Pros that
	/// come with six installed runtimes; a device has one and does not need it.
	public var title: String {
		if isMacCatalyst { return "\(name) (Mac Catalyst)" }
		guard kind == .simulator, let os else { return name }
		return "\(name) (\(os))"
	}

	/// What `-destination` has to say to mean this one.
	///
	/// An id alone is enough for anything with one flavour. It is not enough
	/// for a Mac: this Mac has the same id as a macOS destination and as a Mac
	/// Catalyst one, and `xcodebuild` given only the id picks for itself.
	public var destinationArgument: String {
		guard let variant else { return "id=\(id)" }
		return "platform=\(platform),variant=\(variant),id=\(id)"
	}

	/// The directory `xcodebuild` puts the product in, under
	/// `Build/Products/<configuration><suffix>`.
	public var productDirectorySuffix: String {
		// Before the platform, since Catalyst answers "macOS" and lands
		// somewhere else entirely.
		if isMacCatalyst { return "-maccatalyst" }
		switch platform {
		case "macOS": return ""
		case "iOS": return "-iphoneos"
		case "iOS Simulator": return "-iphonesimulator"
		case "tvOS": return "-appletvos"
		case "tvOS Simulator": return "-appletvsimulator"
		case "watchOS": return "-watchos"
		case "watchOS Simulator": return "-watchsimulator"
		case "visionOS": return "-xros"
		case "visionOS Simulator": return "-xrsimulator"
		default: return ""
		}
	}

	/// Reads `xcodebuild -showdestinations`.
	///
	/// Two things in that output are not destinations anybody can run on. The
	/// placeholders — "Any iOS Device" — name a family rather than a machine,
	/// and installing on one is not a thing. And everything after "Ineligible
	/// destinations" is listed with the reason it cannot be used, usually a
	/// simulator whose runtime is older than the deployment target; those are
	/// the majority of the lines on a machine with several runtimes installed,
	/// and offering them is offering a build that is going to fail.
	public static func parse(_ output: String) -> [XcodeDestination] {
		var found: [XcodeDestination] = []

		for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
			let text = line.trimmingCharacters(in: .whitespaces)
			// Two spellings in the wild: "Ineligible destinations for the …
			// scheme" and "Destinations incompatible with the … scheme". Both
			// introduce the same list, and matching one of them was matching
			// whichever project happened to be open when this was written.
			if text.hasPrefix("Ineligible destinations")
				|| text.hasPrefix("Destinations incompatible") { break }
			guard text.hasPrefix("{"), text.hasSuffix("}") else { continue }

			// The placeholders go, and they were asked about again and the
			// answer was the same: they stay out. "Any iOS Device" is not a
			// machine — nothing installs on it — so offering it in a menu whose
			// every other line is somewhere a build lands would be offering one
			// line that means "let xcodebuild choose", minutes before finding
			// out what it chose. They are recognisable two ways and both are
			// needed: `id:dvtdevice-…`, which is the generic placeholder id, and
			// "Any Mac", which comes with no id at all.
			let fields = self.fields(in: text)
			guard fields["error"] == nil,
			      let id = fields["id"], !id.hasPrefix("dvtdevice-"),
			      let name = fields["name"],
			      let platform = fields["platform"]
			else { continue }

			// "Designed for [iPad,iPhone]" is an iOS build running on this Mac,
			// and it is left out: it is a real destination, but it shares this
			// Mac's name and id with the macOS one and the two are a different
			// product directory, so offering both would be offering a coin
			// toss.
			//
			// Mac Catalyst is not that. It says what it is, it is the only
			// macOS destination an iOS app with Catalyst enabled has — which
			// is why this guard, written for the line above, was answering
			// "there is no Mac" for every such project — and it is carried
			// through to both the product directory and `-destination` below.
			let variant = fields["variant"]
			if let variant, variant != "Mac Catalyst" { continue }

			found.append(XcodeDestination(
				id: id, name: name, platform: platform, os: fields["OS"], variant: variant
			))
		}
		return found
	}

	/// `{ platform:iOS, arch:arm64, id:0000, name:p.iphone }` as a dictionary.
	///
	/// Split on the separator rather than on every comma: a name can hold one
	/// ("iPhone 16 Pro, Ultra") and so can the error text, and a value that
	/// swallowed the next field would be a destination pointed at nothing.
	static func fields(in text: String) -> [String: String] {
		let body = text.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
		var result: [String: String] = [:]

		for part in body.components(separatedBy: ", ") {
			guard let colon = part.firstIndex(of: ":") else { continue }
			let key = String(part[..<colon]).trimmingCharacters(in: .whitespaces)
			// Only where the key looks like one: this is how a value holding
			// ", something:" fails to become a field of its own.
			guard !key.isEmpty, !key.contains(" ") else { continue }
			let value = String(part[part.index(after: colon)...])
				.trimmingCharacters(in: .whitespaces)
			if result[key] == nil { result[key] = value }
		}
		return result
	}
}
