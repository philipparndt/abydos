import Foundation

/// What a Go program's heap has been doing since it started.
///
/// A profile is a snapshot: it says where the memory went, at one moment. The
/// question this answers is the other one — whether it is growing — and that
/// needs a line rather than a picture. `expvar` publishes `runtime.MemStats`
/// on the same server pprof is already mounted on, so this costs the program
/// nothing it was not already paying.
public enum GoMemoryWatch {
	/// One reading.
	public struct Sample: Equatable, Sendable {
		/// When it was taken, by this machine's clock.
		public let at: Date
		/// How long the program had been running, if it says.
		public let uptime: TimeInterval?
		/// Bytes of heap in use by live objects.
		public let heapAlloc: Int
		/// Bytes of heap the runtime is holding, live or not.
		public let heapInuse: Int
		/// Bytes taken from the system for everything.
		public let sys: Int
		/// Every byte the program has ever allocated, which only goes up: the
		/// one figure here that really is "since it started".
		public let totalAlloc: Int
		/// Collections so far, which is what a growing heap is racing.
		public let collections: Int

		public init(
			at: Date,
			uptime: TimeInterval? = nil,
			heapAlloc: Int,
			heapInuse: Int,
			sys: Int,
			totalAlloc: Int = 0,
			collections: Int
		) {
			self.at = at
			self.uptime = uptime
			self.heapAlloc = heapAlloc
			self.heapInuse = heapInuse
			self.sys = sys
			self.totalAlloc = totalAlloc
			self.collections = collections
		}
	}

	/// Where `expvar` sits for a program whose pprof handlers are at `base`.
	///
	/// Both are mounted by importing a package and nothing else, and a program
	/// with one almost always has the other: `/debug/pprof` and `/debug/vars`
	/// are siblings.
	public static func varsURL(for base: URL) -> URL? {
		var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
		components?.path = base.path
			.replacingOccurrences(of: "/debug/pprof", with: "/debug/vars")
		if components?.path.contains("/debug/vars") != true {
			components?.path = "/debug/vars"
		}
		return components?.url
	}

	/// Takes one reading.
	///
	/// `expvar` first, and the heap profile after it: `/debug/vars` exists only
	/// for a program that imported `expvar`, which many have not, while every
	/// program with pprof can print its own `MemStats` at the foot of a text
	/// heap profile. The second is dearer — the profile is built to answer —
	/// so it is the fallback rather than the first try.
	public static func sample(from base: URL, at now: Date = Date()) async -> Sample? {
		if let url = varsURL(for: base), let data = await fetch(url) {
			if let sample = parse(data, at: now) { return sample }
		}
		var heap = base.appendingPathComponent("heap")
		heap = URL(string: heap.absoluteString + "?debug=1") ?? heap
		guard let data = await fetch(heap) else { return nil }
		return parseMemStatsText(String(decoding: data, as: UTF8.self), at: now)
	}

	private static func fetch(_ url: URL) async -> Data? {
		var request = URLRequest(url: url)
		request.timeoutInterval = 4
		guard let (data, response) = try? await URLSession.shared.data(for: request),
		      (response as? HTTPURLResponse)?.statusCode == 200
		else { return nil }
		return data
	}

	/// Reads the `MemStats` a text heap profile ends with.
	///
	/// `/debug/pprof/heap?debug=1` prints the sampled allocations and then the
	/// whole of `runtime.MemStats`, a line each, commented out:
	/// `# HeapInuse = 232300544`. Nothing else here needs the profile itself.
	static func parseMemStatsText(_ text: String, at now: Date) -> Sample? {
		var values: [String: Int] = [:]
		for line in text.split(separator: "\n") where line.hasPrefix("# ") {
			let parts = line.dropFirst(2).split(separator: "=", maxSplits: 1)
			guard parts.count == 2 else { continue }
			let key = parts[0].trimmingCharacters(in: .whitespaces)
			// `# PauseNs = [12 0 0 …]` and friends: only the plain numbers.
			guard let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
			values[key] = value
		}
		guard let heapAlloc = values["HeapAlloc"] else { return nil }
		return Sample(
			at: now,
			heapAlloc: heapAlloc,
			heapInuse: values["HeapInuse"] ?? heapAlloc,
			sys: values["Sys"] ?? 0,
			totalAlloc: values["TotalAlloc"] ?? 0,
			collections: values["NumGC"] ?? 0
		)
	}

	/// Reads what `/debug/vars` publishes.
	///
	/// Internal so it can be tested against what Go actually prints, which is
	/// a large JSON object with `memstats` among a program's own variables —
	/// and which has no uptime in it unless the program publishes one, so the
	/// usual names for that are looked for and its absence is not a failure.
	static func parse(_ data: Data, at now: Date) -> Sample? {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let stats = object["memstats"] as? [String: Any]
		else { return nil }

		func number(_ key: String) -> Int {
			(stats[key] as? NSNumber)?.intValue ?? 0
		}

		// Some programs publish their own start time or uptime; most do not,
		// and the chart falls back to counting from the first reading.
		var uptime: TimeInterval?
		for key in ["uptime", "uptime_seconds", "uptimeSeconds"] {
			if let seconds = (object[key] as? NSNumber)?.doubleValue { uptime = seconds }
		}
		for key in ["start_time", "startTime", "started"] {
			guard let started = (object[key] as? NSNumber)?.doubleValue, started > 0 else { continue }
			// Seconds or milliseconds since the epoch, whichever it looks like.
			let seconds = started > 1_000_000_000_000 ? started / 1000 : started
			uptime = now.timeIntervalSince1970 - seconds
		}

		return Sample(
			at: now,
			uptime: uptime,
			heapAlloc: number("HeapAlloc"),
			heapInuse: number("HeapInuse"),
			sys: number("Sys"),
			totalAlloc: number("TotalAlloc"),
			collections: number("NumGC")
		)
	}

	/// A series of readings, with the arithmetic a chart needs.
	public struct Series: Equatable, Sendable {
		public private(set) var samples: [Sample] = []
		/// How many readings to keep. An hour at one a second.
		public let limit: Int

		public init(limit: Int = 3600) {
			self.limit = limit
		}

		public mutating func append(_ sample: Sample) {
			samples.append(sample)
			if samples.count > limit { samples.removeFirst(samples.count - limit) }
		}

		public mutating func clear() { samples = [] }

		public var isEmpty: Bool { samples.isEmpty }
		public var latest: Sample? { samples.last }

		/// The tallest reading, which the chart is drawn against.
		///
		/// Never zero, so a program that has allocated nothing yet does not
		/// divide the world by it.
		public var peak: Int {
			max(1, samples.map(\.heapInuse).max() ?? 1)
		}

		/// How long the series covers.
		public var span: TimeInterval {
			guard let first = samples.first, let last = samples.last else { return 0 }
			return last.at.timeIntervalSince(first.at)
		}

		/// How much the heap has put on since the first reading.
		///
		/// Negative when a collection has taken more back than has been added,
		/// which is what a program that is *not* leaking looks like.
		public var growth: Int {
			guard let first = samples.first, let last = samples.last else { return 0 }
			return last.heapInuse - first.heapInuse
		}

		/// Whether the heap is higher than it was, by enough to mean it.
		///
		/// A tenth: a heap wanders by a few per cent between collections, and
		/// calling that growth would cry wolf on every program.
		public var isGrowing: Bool {
			guard let first = samples.first, let last = samples.last, samples.count > 4 else {
				return false
			}
			return Double(last.heapAlloc) > Double(first.heapAlloc) * 1.1
		}
	}

	/// Bytes, in the units somebody reads them in.
	public static func format(bytes: Int) -> String {
		let units = ["B", "KB", "MB", "GB"]
		var value = Double(bytes)
		var unit = 0
		while value >= 1024, unit < units.count - 1 {
			value /= 1024
			unit += 1
		}
		return value < 10 && unit > 0
			? String(format: "%.1f %@", value, units[unit])
			: String(format: "%.0f %@", value, units[unit])
	}
}
