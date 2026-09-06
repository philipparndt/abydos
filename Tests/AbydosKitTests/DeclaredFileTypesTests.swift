import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AbydosKit

/// What the bundle tells the Finder this editor opens, against what it reads.
///
/// **Two lists that drift the moment nothing compares them.** The plist says
/// which files offer Abydos under *Open With*; `LanguageRegistry` says which
/// files the editor can actually colour. A language added to one and not the
/// other is either a promise the editor cannot keep or a file the Finder never
/// offers to open here — and neither shows up until somebody tries it.
struct DeclaredFileTypesTests {
	/// The `Info.plist` the bundle is built from — `Scripts/bundle.sh` copies
	/// this file verbatim, so this is the one that reaches Launch Services.
	private static let plist: [String: Any] = {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let url = root.appendingPathComponent("Resources/Info.plist")
		let data = try! Data(contentsOf: url)
		return try! PropertyListSerialization.propertyList(
			from: data, format: nil
		) as! [String: Any]
	}()

	/// The content types the document entries claim.
	private static let declaredTypes: Set<String> = {
		let documents = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
		return Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
	}()

	/// The extensions the imported declarations name, and the identifier each
	/// belongs to.
	private static let importedExtensions: [String: String] = {
		let imported = plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
		var found: [String: String] = [:]
		for declaration in imported {
			guard let identifier = declaration["UTTypeIdentifier"] as? String,
			      let tags = declaration["UTTypeTagSpecification"] as? [String: Any],
			      let extensions = tags["public.filename-extension"] as? [String]
			else { continue }
			for name in extensions { found[name] = identifier }
		}
		return found
	}()

	/// Extensions the system names as something this editor is not.
	///
	/// **`.ts` is an MPEG-2 transport stream to macOS**, and `.mts` an AVCHD
	/// one — the system's own type wins over anything imported here, so the
	/// only way to be offered for a TypeScript file called `.ts` would be to
	/// claim video, which would put this editor in the *Open With* menu of a
	/// recording. Left alone deliberately, and named here so that the gap is a
	/// decision somebody can read rather than a hole somebody has to rediscover.
	static let systemCallsThemSomethingElse: Set<String> = ["ts", "mts"]

	/// Whether the Finder would offer this app for a file with this extension.
	///
	/// **The system's own type wins**, which is the order this asks in: an
	/// imported declaration only ever applies where macOS has no type of its
	/// own for the extension. Asking the other way round said `.toml` was
	/// covered while the Finder offered nothing, because `public.toml` exists
	/// and this bundle was not declaring it.
	private func isOffered(_ extensionName: String) -> Bool {
		if let type = UTType(filenameExtension: extensionName),
		   !type.identifier.hasPrefix("de.rnd7.abydos") {
			return Self.declaredTypes.contains { declared in
				guard let parent = UTType(declared) else { return false }
				return type.conforms(to: parent)
			}
		}
		guard let identifier = Self.importedExtensions[extensionName] else { return false }
		return Self.declaredTypes.contains(identifier)
	}

	@Test func everyLanguageTheEditorReadsIsOfferedByTheFinder() {
		let missing = LanguageRegistry.extensionMap.keys
			.filter { !Self.systemCallsThemSomethingElse.contains($0) }
			.filter { !isOffered($0) }
			.sorted()
		#expect(missing.isEmpty, "not offered under Open With: \(missing.joined(separator: ", "))")
	}

	/// The two the system calls video are still what it calls them: a test that
	/// stopped checking would let somebody "fix" the gap by claiming video.
	@Test func theOnesTheSystemCallsSomethingElseAreLeftAlone() {
		for name in Self.systemCallsThemSomethingElse {
			let type = UTType(filenameExtension: name)
			#expect(type?.conforms(to: .audiovisualContent) == true,
			        "\(name) is no longer video to the system — it may be claimable now")
		}
	}

	/// **Nothing is claimed that cannot be read.** A `.psd` in *Open With* is a
	/// promise this editor cannot keep, and the rank being *Alternate* does not
	/// make an unreadable file readable.
	@Test func nothingIsDeclaredThatTheEditorCannotRead() {
		let known = Set(LanguageRegistry.extensionMap.keys)
		let claimed = Set(Self.importedExtensions.keys)
		#expect(claimed.subtracting(known).isEmpty,
		        "declared and unknown to the registry: \(claimed.subtracting(known).sorted())")
	}

	/// The offer is an offer: *Owner* claims a type at installation, which is
	/// somebody's decision rather than an installer's.
	@Test func theBundleOffersRatherThanClaims() {
		let documents = Self.plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
		#expect(!documents.isEmpty)
		for entry in documents {
			#expect(entry["LSHandlerRank"] as? String == "Alternate")
		}
	}

	/// A folder is what a project is opened from, and this app has taken it
	/// since before it could open a file.
	@Test func aFolderIsStillDeclared() {
		#expect(Self.declaredTypes.contains("public.folder"))
	}
}
