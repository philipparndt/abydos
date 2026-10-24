import AbydosKit
import AppKit
import AuthenticationServices

/// A vboard server's login, in the system's sign-in sheet rather than a web
/// view: what a board tab runs, and what the board picker runs before it can
/// list anything.
///
/// Entra ID with Conditional Access wants a compliant device, and the proof of
/// one comes from Apple's Enterprise SSO extension, which answers for the
/// system's sheet and not for a web view inside an app. Seen on 2026-10-23 as
/// "Set up your device to get access" in place of the board.
@MainActor
final class VboardSignInSheet: NSObject {
	enum Ending {
		/// Signed in; the token is kept for the next board on this server.
		case signedIn(VboardCredential)
		case cancelled
		case failed(String)
	}

	private var session: ASWebAuthenticationSession?
	private weak var anchor: NSWindow?
	var isRunning: Bool { session != nil }

	/// Opens the sheet over `window`. False when it would not open, in which
	/// case `done` is never called.
	func start(server: URL, over window: NSWindow?, done: @escaping (Ending) -> Void) -> Bool {
		guard session == nil else { return true }
		anchor = window
		let device = "Abydos on \(Host.current().localizedName ?? "this Mac")"
		let session = ASWebAuthenticationSession(
			url: VboardSignIn.url(server: server, device: device),
			callbackURLScheme: VboardSignIn.callbackScheme
		) { [weak self] callback, error in
			DispatchQueue.main.async {
				self?.session = nil
				if let callback, let credential = VboardSignIn.credential(from: callback) {
					KeychainVboardCredentials.shared.keep(credential, for: server)
					done(.signedIn(credential))
				} else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
					done(.cancelled)
				} else {
					done(.failed(error?.localizedDescription ?? "No token came back."))
				}
			}
		}
		session.presentationContextProvider = self
		// Not ephemeral: the sheet shares Safari's sign-in, so somebody already
		// signed in there is not asked again.
		session.prefersEphemeralWebBrowserSession = false
		self.session = session
		guard session.start() else {
			self.session = nil
			return false
		}
		return true
	}

	func cancel() {
		session?.cancel()
		session = nil
	}
}

extension VboardSignInSheet: ASWebAuthenticationPresentationContextProviding {
	func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		anchor ?? NSApp.keyWindow ?? NSWindow()
	}
}
