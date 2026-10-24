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

	/// Puts the server's address back into the links vboard's page shows and
	/// copies, in place of the proxy's.
	///
	/// The page builds every share link from its own address — the share
	/// dialog, a card's or an item's link, the private-board list — and through
	/// the proxy that address is `http://127.0.0.1:<port>`, which opens nothing
	/// on a colleague's machine. Seen on 2026-10-23: "the board now shows a
	/// local link only". So the proxy's origin is swapped for the server's in
	/// what a person reads and copies: text on the page, the value of a field,
	/// and the clipboard, by the copy event the page fills and by the
	/// clipboard API it falls back to. Links the page *follows* — an `href`, a
	/// request — are left alone, because those have to go through the proxy.
	///
	/// A QR code is a picture and keeps the proxy's address. That and the rest
	/// of this are better fixed in vboard, by building share links from the
	/// address the embedding app gives; this stays until every server does.
	public static func linkRewrite(proxy: URL, server: URL) -> String {
		let encode = { (url: URL) -> String in
			let origin = (url.scheme ?? "http") + "://" + (url.host ?? "") + (url.port.map { ":\($0)" } ?? "")
			let data = try? JSONSerialization.data(withJSONObject: [origin], options: [.withoutEscapingSlashes])
			return data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
		}
		return """
		(() => {
			const local = \(encode(proxy)), remote = \(encode(server));
			if (!local || local === remote || window.__abydosLinks) return;
			window.__abydosLinks = true;
			const swap = (text) => typeof text === "string" && text.includes(local) ? text.split(local).join(remote) : text;
			for (const proto of [HTMLInputElement.prototype, HTMLTextAreaElement.prototype]) {
				const own = Object.getOwnPropertyDescriptor(proto, "value");
				if (!own || !own.set) continue;
				Object.defineProperty(proto, "value", {
					configurable: true, enumerable: own.enumerable,
					get() { return own.get.call(this); },
					set(value) { own.set.call(this, swap(value)); },
				});
			}
			const setData = DataTransfer.prototype.setData;
			DataTransfer.prototype.setData = function (format, data) { return setData.call(this, format, swap(data)); };
			if (navigator.clipboard && navigator.clipboard.writeText) {
				const writeText = navigator.clipboard.writeText.bind(navigator.clipboard);
				navigator.clipboard.writeText = (text) => writeText(swap(text));
			}
			const fix = (node) => {
				if (node.nodeType === Node.TEXT_NODE) {
					const swapped = swap(node.nodeValue);
					if (swapped !== node.nodeValue) node.nodeValue = swapped;
				} else if (node.nodeType === Node.ELEMENT_NODE) {
					const walk = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
					for (let text = walk.nextNode(); text; text = walk.nextNode()) fix(text);
				}
			};
			new MutationObserver((records) => {
				for (const record of records) {
					if (record.type === "characterData") fix(record.target);
					else record.addedNodes.forEach(fix);
				}
			}).observe(document, { subtree: true, childList: true, characterData: true });
		})();
		"""
	}

	/// Tells vboard's page it is shown by an app, and which server it is on.
	///
	/// vboard's web app already knows `window.vboardApp`: its iPad app puts it
	/// there for the same reason this one does — the page is served from a
	/// proxy on this machine, so `location.origin` is not the server. In
	/// "server" mode it carries the server's address, which a vboard that builds
	/// share links from it uses instead of the page's own (with older ones the
	/// link rewrite above does the work). Its settings button opens this app's
	/// settings. No `signOut`: the page's own log out then goes to the server as
	/// in a browser, and signing this app out is in its settings.
	public static func appBridge(server: URL, version: String) -> String {
		let encode = { (value: String) -> String in
			let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])
			return data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
		}
		let origin = MemoryVboardCredentials.origin(of: server)
		return """
		(() => {
			if (window.vboardApp) return;
			window.vboardApp = {
				platform: "abydos", version: \(encode(version)), mode: "server", serverURL: \(encode(origin)),
				openSettings() {
					try { window.webkit.messageHandlers.\(handlerName).postMessage({ app: "openSettings" }); } catch (_) {}
				},
			};
		})();
		"""
	}

	/// vboard's colours, set to this app's.
	///
	/// vboard draws its dark theme in navy — a navy canvas, navy frames, a navy
	/// banner — and accents in Vector's brand blue, which sat badly in a
	/// neutral grey editor with an orange accent ("the blue colors do not match
	/// nicely", 2026-10-23). Its colours are CSS custom properties: the design
	/// system's (`--background`, `--ring`, …) and its own board's (`--vb-…`),
	/// or in its classic design a palette of its own (`--bg`, `--indigo`, …).
	/// These rules set them for both of its themes, ahead of its own, so a
	/// change of this app's theme is a change of one stylesheet's text.
	public static func themeStyle(_ tokens: [String: String]) -> String {
		let body = tokens.sorted { $0.key < $1.key }
			.filter { $0.key.hasPrefix("--") && !$0.value.contains(";") && !$0.value.contains("}") }
			.map { "  \($0.key): \($0.value) !important;" }
			.joined(separator: "\n")
		return ":root:root, :root:root[data-theme='light'], :root:root[data-theme='dark'] {\n\(body)\n}"
	}

	/// Puts `themeStyle` into the page, and replaces it when called again.
	public static func themeScript(_ style: String) -> String {
		let data = try? JSONSerialization.data(withJSONObject: [style], options: [.withoutEscapingSlashes])
		let literal = data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
		return """
		(() => {
			const id = "abydos-theme";
			let sheet = document.getElementById(id);
			if (!sheet) {
				sheet = document.createElement("style");
				sheet.id = id;
				(document.head || document.documentElement).appendChild(sheet);
			}
			sheet.textContent = \(literal);
		})();
		"""
	}

	/// Keeps vboard's page from installing its service worker.
	///
	/// The worker is vboard's offline mode: on its first visit it fetches the
	/// whole web app ahead of time. In a board tab nothing needs it — the board
	/// lives on the server for the session and the file is the copy that stays
	/// — and it cost the first board on 2026-10-23 five of its 7.7 seconds: the
	/// page asked for its own board as request 543 of 568, queued behind the
	/// worker's downloads on the six connections WebKit opens to one plain-http
	/// address. vboard registers it in one place and only warns when that fails;
	/// a worker an earlier tab installed is removed. The page's files are still
	/// kept by the store's ordinary cache, which is what makes a second board
	/// quick.
	public static let noServiceWorker = #"""
	(() => {
		const workers = navigator.serviceWorker;
		if (!workers) return;
		workers.getRegistrations().then((all) => all.forEach((one) => one.unregister())).catch(() => {});
		workers.register = () => Promise.reject(new Error("A board in Abydos keeps no offline copy."));
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
	/// Persistent, so the page's scripts and its service worker are kept from
	/// one board to the next: a fresh store fetched the whole web app for every
	/// board, part of the thirteen seconds a board took to open on 2026-10-23.
	/// Per origin so one server's page never sees another's storage. The same
	/// origin always gives the same id, which is what makes it the same store.
	public static func dataStoreID(for server: URL) -> UUID {
		let origin = MemoryVboardCredentials.origin(of: server)
		var bytes = Array(SHA256.hash(data: Data("abydos.vboard:\(origin)".utf8)).prefix(16))
		// A name-based UUID's version and variant bits, so it reads as one.
		bytes[6] = (bytes[6] & 0x0F) | 0x50
		bytes[8] = (bytes[8] & 0x3F) | 0x80
		return UUID(uuid: (
			bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
			bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
		))
	}

	/// The loopback port a server's proxy asks for first.
	///
	/// The same one every time, because the port is part of the page's origin:
	/// a new port is a new origin, with an empty cache and no service worker.
	/// Spread over a range by the server's origin so two servers rarely ask for
	/// the same one; a port that is taken falls back to any free one.
	public static func preferredPort(for server: URL) -> UInt16 {
		var hash: UInt32 = 2_166_136_261
		for byte in MemoryVboardCredentials.origin(of: server).utf8 {
			hash = (hash ^ UInt32(byte)) &* 16_777_619
		}
		return 47_300 + UInt16(hash % 400)
	}
}
