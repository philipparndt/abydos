import CryptoKit
import Foundation

/// What the board tab puts into vboard's page, and what it keeps apart for it.
public enum VboardPage {
	/// The name the page's messages arrive under.
	public static let handlerName = "abydosBoard"

	/// Watches the page's own connection to its board and says what arrives.
	///
	/// The page's own socket, because every socket on a board is a participant:
	/// a second one from this app would put an "Abydos" avatar beside the person
	/// using it, on their screen and on everybody else's. And only what arrives,
	/// because what the page sends includes the board's key, which this script
	/// has no business touching.
	///
	/// It leans on vboard's documented WebSocket protocol and nothing inside its
	/// web app: the socket's address, and the `type` of each JSON message. What
	/// is passed on is the type, the number of people for `snapshot` and
	/// `presence`, and a `deleted` message's reason. Never an item, never a
	/// name.
	///
	/// Tried against `vboard-local` 0.67.0: the client that makes a change gets
	/// its own `items` message back, so the socket alone sees every change; and
	/// `presence` has one entry per person, the page's own included.
	public static let socketWatcher = #"""
	(() => {
		const Native = window.WebSocket;
		if (!Native || Native.__abydosWatched) return;
		const post = (message) => {
			try { window.webkit.messageHandlers.abydosBoard.postMessage(message); } catch (_) {}
		};
		const pattern = /\/api\/v1\/boards\/(b_[0-9a-f]{16})\/ws(\?|$)/;
		const counted = new Set(["items", "entries", "board", "deleted", "replaced", "accessRevoked"]);
		function Watched(url, protocols) {
			const socket = protocols === undefined ? new Native(url) : new Native(url, protocols);
			const match = pattern.exec(String(url));
			if (!match) return socket;
			const board = match[1];
			socket.addEventListener("message", (event) => {
				if (typeof event.data !== "string") return;
				let message;
				try { message = JSON.parse(event.data); } catch (_) { return; }
				const type = message && message.type;
				if (type === "snapshot" || type === "presence") {
					post({ board, type, people: Array.isArray(message.presence) ? message.presence.length : 0 });
				} else if (counted.has(type)) {
					post({ board, type, reason: type === "deleted" ? String(message.reason || "") : "" });
				}
			});
			return socket;
		}
		Watched.prototype = Native.prototype;
		for (const name of ["CONNECTING", "OPEN", "CLOSING", "CLOSED"]) Watched[name] = Native[name];
		Watched.__abydosWatched = true;
		window.WebSocket = Watched;
	})();
	"""#

	/// Keeps vboard's page from keeping the board in the signed-in person's
	/// account.
	///
	/// With a login, opening a private link makes the page "keep" it: it
	/// wraps the board's key to the person's own key pair with
	/// `POST /api/v1/boards/{id}/my-slot`, and when they have none, it offers to
	/// set one up — with a passkey, which an embedded web view cannot use. Seen
	/// on 2026-10-23: "it was asking for a passkey which is not possible in our
	/// integration but should also not be necessary for ephemeral/local
	/// boards". A board that ends when its tab closes has nothing to keep, so
	/// that one call, for the one board this page shows, is answered here with
	/// a refusal. The page takes a refusal other than 409 as "not kept" and
	/// says nothing; no slot is left in the account for a board that is gone.
	///
	/// The board is read from the page's own address at document start, so a
	/// page that moves to a new board — the file opened again — is a new
	/// document with a new answer. Every other request goes through untouched.
	public static let slotRefusal = #"""
	(() => {
		const shown = /^\/b\/(b_[0-9a-f]{16})\/?$/.exec(location.pathname);
		const native = window.fetch;
		if (!shown || !native || native.__abydosSlot) return;
		const slot = "/api/v1/boards/" + shown[1] + "/my-slot";
		const refused = () => new Response(
			JSON.stringify({ error: "A board opened from a file is not kept in the account.", code: "abydos.sessionBoard" }),
			{ status: 403, headers: { "Content-Type": "application/json" } }
		);
		const wrapped = function (input, init) {
			let url = typeof input === "string" ? input : input instanceof URL ? input.href : (input && input.url) || "";
			let method = (init && init.method) || (input && typeof input === "object" && input.method) || "GET";
			let path = url;
			try { path = decodeURIComponent(new URL(url, location.href).pathname); } catch (_) {}
			if (String(method).toUpperCase() === "POST" && path === slot) return Promise.resolve(refused());
			return native.apply(this, arguments);
		};
		wrapped.__abydosSlot = true;
		window.fetch = wrapped;
	})();
	"""#

	/// One message from the page, decoded.
	public enum Message: Equatable {
		/// The board is loaded, with this many people on it, the page's own
		/// person included.
		case snapshot(people: Int)
		case presence(people: Int)
		/// Items, a widget's entries or the board itself changed, whoever did it.
		case changed
		/// The board was deleted: `"deleted"` by somebody, `"expired"` by the
		/// server's cleanup of temporary boards.
		case deleted(reason: String)
		/// A newer file was put in its place; the page reloads by itself.
		case replaced
		/// With a login: the person may no longer open the board.
		case accessRevoked

		/// The message, if it is about `board`. A page that has moved on to a
		/// board this tab replaced still has the old socket closing.
		public init?(_ body: Any, board: String) {
			guard let fields = body as? [String: Any], fields["board"] as? String == board,
			      let type = fields["type"] as? String
			else { return nil }
			let people = (fields["people"] as? NSNumber)?.intValue ?? 0
			switch type {
			case "snapshot": self = .snapshot(people: people)
			case "presence": self = .presence(people: people)
			case "items", "entries", "board": self = .changed
			case "deleted": self = .deleted(reason: fields["reason"] as? String ?? "")
			case "replaced": self = .replaced
			case "accessRevoked": self = .accessRevoked
			default: return nil
			}
		}
	}

	/// The web data store a server's board tabs share, by an id made from the
	/// server's origin.
	///
	/// Per origin so a sign-in to one server is kept for the next tab on it and
	/// never offered to another; persistent so somebody signs in once rather
	/// than every time a file is opened. The same origin always gives the same
	/// id, which is what makes it the same store.
	public static func dataStoreID(for server: URL) -> UUID {
		var components = URLComponents()
		components.scheme = server.scheme?.lowercased()
		components.host = server.host?.lowercased()
		components.port = server.port
		let origin = components.string ?? server.absoluteString
		var bytes = Array(SHA256.hash(data: Data("abydos.vboard:\(origin)".utf8)).prefix(16))
		// A name-based UUID's version and variant bits, so it reads as one.
		bytes[6] = (bytes[6] & 0x0F) | 0x50
		bytes[8] = (bytes[8] & 0x3F) | 0x80
		return UUID(uuid: (
			bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
			bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
		))
	}
}
