import Foundation

/// What somebody said about working a project inside the devcontainer it names.
///
/// **Why there is a question at all.** A project with a `devcontainer.json` gets
/// its language servers inside it, and the first time that happens it is a pull
/// or a `docker build` — minutes, and a gigabyte of disk — begun because a `.py`
/// file was opened, and announced to nobody. The behaviour is right and the
/// manners are not, which is what 0433 is: the machine it runs on may be on a
/// train, and nothing was said before it began.
///
/// **Why "no" is two answers rather than one.** Declining has to leave the
/// project in a state, and there are two states somebody could mean. The
/// devcontainer path deliberately refuses to fall back to a server on this
/// machine — the same code getting different answers depending on whose laptop
/// it is on is the fault the whole path exists to prevent — so "not now" cannot
/// quietly become "use this machine's toolchain". They are different sentences
/// and both are worth being able to say, so both are offered by name, and
/// whichever is in force says so above the file.
public enum DevContainerConsent: String, Sendable, CaseIterable {
	/// Yes. The container comes up and this project's language servers go inside
	/// it, which is what every project with a devcontainer used to do unasked.
	case container
	/// No, and deliberately: work this project with the servers on this machine,
	/// knowing they are not the toolchain the project names.
	case thisMachine
	/// Not this time. Nothing is started, nothing runs on this machine either,
	/// and nothing is written down.
	case notNow

	/// Whether this answer is one to keep.
	///
	/// **"Not now" is the one that is not.** It is an answer about this
	/// afternoon — the train, the battery, the download — rather than about the
	/// project, and a preference file that remembered it would turn a delay into
	/// a decision nobody made. The other two are about the project and are kept.
	public var isRemembered: Bool { self != .notNow }
}

public extension DevContainerConsent {
	/// Where the container's image comes from the first time it is started,
	/// which is the cost the question exists to disclose.
	enum FirstStart: Equatable, Sendable {
		/// Pulled from a registry, under this name.
		case image(String)
		/// Built here, from this Dockerfile as the project names it.
		case build(String)

		/// What the file asks for, or nil when it could not be read — in which
		/// case the question says what it knows and not what it does not.
		public static func of(_ configuration: DevContainerConfiguration) -> FirstStart {
			if let image = configuration.image { return .image(image) }
			guard let build = configuration.build else { return .image(configuration.imageReference) }
			let root = FilePath.canonical(configuration.project) + "/"
			let dockerfile = build.dockerfile.hasPrefix(root)
				? String(build.dockerfile.dropFirst(root.count))
				: build.dockerfile
			return .build(dockerfile)
		}
	}

	/// The title on the question, naming both halves of it.
	///
	/// The project and the container, because neither on its own is the
	/// question: a repository of subprojects with a devcontainer each — which is
	/// what `abydos-examples` is — can be asked about twice in a session, and
	/// "Use this devcontainer?" would be the same nine words both times.
	static func question(project: String, container: String) -> String {
		"Work on \(project) inside \(container)?"
	}

	/// The paragraph under it: what the container is for, and what saying yes
	/// costs the first time.
	///
	/// The cost is stated in the units somebody on a train cares about — minutes
	/// and disk — rather than as "this may take a while", and it says plainly
	/// that it is the first time only. The whole complaint 0433 comes from is
	/// that this was begun without being said.
	static func explanation(container: String, firstStart: FirstStart?) -> String {
		let why = "Its language servers — completion, problems, go to declaration — would run "
			+ "inside \(container), so that what the editor says about this code comes from the "
			+ "toolchain the project is built with rather than from whatever is installed here."
		guard let firstStart else { return why }
		let cost: String
		switch firstStart {
		case let .image(name):
			cost = "The first time, \(name) is downloaded, which can be several minutes and a "
				+ "gigabyte of disk. After that, starting it is seconds."
		case let .build(dockerfile):
			cost = "The first time, \(dockerfile) is built, which can be several minutes and a "
				+ "gigabyte of disk. After that, starting it is seconds."
		}
		return why + "\n\n" + cost
	}

	/// What the button for each answer says.
	///
	/// The container is named in the one that starts it, because a row of
	/// Yes/No/Later buttons is a question somebody has to read the paragraph
	/// again to answer.
	static func buttonTitle(_ answer: DevContainerConsent, container: String) -> String {
		switch answer {
		case .container: return "Use \(container)"
		case .thisMachine: return "Work on This Machine"
		case .notNow: return "Not Now"
		}
	}

	/// The order the buttons are offered in: the project's own answer first.
	static let answersInOrder: [DevContainerConsent] = [.container, .thisMachine, .notNow]

	/// What the strip above the file says while this answer is in force, or nil
	/// when there is nothing for it to say.
	///
	/// **Nil for `.container`**, because a container that is being used has the
	/// sentences it already had: coming up, up, or missing the server. This is
	/// only for the two states that are otherwise invisible — and they have to
	/// be told apart, since a Python file with no squiggles at all and one being
	/// checked by a server that is not the project's are the same picture.
	static func notice(language: String, container: String, consent: DevContainerConsent) -> String? {
		switch consent {
		case .container:
			return nil
		case .thisMachine:
			return "\(language) is checked by this machine's language server, not by \(container)'s."
		case .notNow:
			return "\(language)'s language server is in \(container), which has not been started."
		}
	}

	/// What the way back out of a decline says, above the file and in the menu.
	static func offerTitle(container: String) -> String { "Use \(container)" }
}
