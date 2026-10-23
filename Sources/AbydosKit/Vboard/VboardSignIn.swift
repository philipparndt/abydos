import Foundation
import Security

/// Signing in to a vboard server through the system's sign-in sheet, and the
/// token that comes back.
///
/// Not in the tab's web view: a server behind Entra ID with Conditional
/// Access wants a compliant device, and the proof of one comes from Apple's
/// Enterprise SSO extension, which answers for Safari and for the system's
/// sign-in sheet but not for a web view inside an app. Seen on 2026-10-23 as
/// "Set up your device to get access" in place of the board. vboard's iPad app
/// meets the same wall the same way: `/auth/app-login` signs the person in,
/// makes a personal access token named after the device, and hands it back by
/// redirecting to `vboard://signin?token=…&id=…&name=…` — a redirect only the
/// sheet that opened the page receives.
public enum VboardSignIn {
	/// The scheme of the redirect the token comes back on. vboard's, not this
	/// app's: the sheet catches it without it being registered anywhere.
	public static let callbackScheme = "vboard"

	/// Where the sheet opens.
	public static func url(server: URL, device: String) -> URL {
		var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
		let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
		components.path = base + "/auth/app-login"
		components.queryItems = [URLQueryItem(name: "device", value: device)]
		components.fragment = nil
		return components.url!
	}

	/// The token in the redirect that ends the sign-in, if it is one.
	public static func credential(from callback: URL) -> VboardCredential? {
		guard callback.scheme == callbackScheme, callback.host == "signin",
		      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
		      let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty
		else { return nil }
		return VboardCredential(
			token: token,
			id: items.first(where: { $0.name == "id" })?.value ?? "",
			name: items.first(where: { $0.name == "name" })?.value ?? ""
		)
	}
}

/// A personal access token for one server, with what is needed to revoke it.
public struct VboardCredential: Codable, Equatable, CustomStringConvertible {
	public let token: String
	/// The token's id, for `DELETE /api/v1/me/tokens/{id}` on sign-out.
	public let id: String
	/// Who signed in, to say so in the settings.
	public let name: String

	public init(token: String, id: String, name: String) {
		self.token = token
		self.id = id
		self.name = name
	}

	/// Never the token: a credential interpolated into a log line would be the
	/// person's write access to every board they can open.
	public var description: String { "VboardCredential(\(name), id \(id))" }
}

/// Where the tokens are kept: one per server origin.
public protocol VboardCredentials: AnyObject {
	func credential(for server: URL) -> VboardCredential?
	func keep(_ credential: VboardCredential, for server: URL)
	func forget(for server: URL)
}

public extension VboardCredentials {
	/// A server's origin, which is what a token belongs to: the same server
	/// under another path is the same server.
	static func origin(of server: URL) -> String {
		var components = URLComponents()
		components.scheme = server.scheme?.lowercased()
		components.host = server.host?.lowercased()
		components.port = server.port
		return components.string ?? server.absoluteString
	}
}

/// The Keychain: the person signs in once per server, not once per file.
///
/// A generic password per origin, in this app's own service name, readable
/// only by this app. On a driven run nothing is read or written — a driven
/// run never reaches a server, and must never find somebody's token either.
public final class KeychainVboardCredentials: VboardCredentials {
	public static let shared: VboardCredentials = DrivenRun.isActive
		? MemoryVboardCredentials()
		: KeychainVboardCredentials()

	private let service = "de.rnd7.abydos.vboard"

	private func query(_ server: URL) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: Self.origin(of: server),
		]
	}

	public func credential(for server: URL) -> VboardCredential? {
		var query = query(server)
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		var found: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data
		else { return nil }
		return try? JSONDecoder().decode(VboardCredential.self, from: data)
	}

	public func keep(_ credential: VboardCredential, for server: URL) {
		guard let data = try? JSONEncoder().encode(credential) else { return }
		forget(for: server)
		var item = query(server)
		item[kSecValueData as String] = data
		item[kSecAttrLabel as String] = "Abydos · vboard · \(server.host ?? "")"
		item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		SecItemAdd(item as CFDictionary, nil)
	}

	public func forget(for server: URL) {
		SecItemDelete(query(server) as CFDictionary)
	}
}

/// Tokens that live as long as the process: a driven run's, and a test's.
public final class MemoryVboardCredentials: VboardCredentials {
	private var kept: [String: VboardCredential] = [:]
	public init() {}
	public func credential(for server: URL) -> VboardCredential? { kept[Self.origin(of: server)] }
	public func keep(_ credential: VboardCredential, for server: URL) { kept[Self.origin(of: server)] = credential }
	public func forget(for server: URL) { kept[Self.origin(of: server)] = nil }
}
