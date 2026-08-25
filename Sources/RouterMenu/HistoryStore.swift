import Foundation
import Observation

struct HistorySample: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let batteryPercent: Int?
    /// Legacy combined rx+tx counter (≤0.5.x files). Still written so a
    /// downgraded build keeps drawing its chart; new series read the split.
    let totalBytes: Int?
    let totalRx: Int?
    let totalTx: Int?
    let rsrp: Int?
    let sinr: Double?

    init(id: UUID = UUID(), timestamp: Date, batteryPercent: Int?,
         totalRx: Int?, totalTx: Int?, rsrp: Int?, sinr: Double?) {
        self.id = id
        self.timestamp = timestamp
        self.batteryPercent = batteryPercent
        if let totalRx, let totalTx {
            self.totalBytes = totalRx + totalTx
        } else {
            self.totalBytes = nil
        }
        self.totalRx = totalRx
        self.totalTx = totalTx
        self.rsrp = rsrp
        self.sinr = sinr
    }
}

@MainActor
@Observable
public final class HistoryStore {
    private(set) var samples: [HistorySample] = []
    private let fileURL: URL
    private let now: () -> Date
    private let window: TimeInterval = 24 * 3600
    /// A pair of counter samples further apart than this is not a speed
    /// reading — the app was off or asleep, and averaging across the gap
    /// would draw a misleading plateau.
    private let maxSpeedGap: TimeInterval = 15 * 60

    public init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("zte-menu", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("history.json")
        }
        load()
    }

    func add(battery: Int? = nil, totalRx: Int? = nil, totalTx: Int? = nil,
             rsrp: Int? = nil, sinr: Double? = nil) {
        let t = now()
        samples.append(HistorySample(timestamp: t, batteryPercent: battery,
                                     totalRx: totalRx, totalTx: totalTx,
                                     rsrp: rsrp, sinr: sinr))
        let cutoff = t.addingTimeInterval(-window)
        samples.removeAll { $0.timestamp < cutoff }
        save()
    }

    func batterySeries() -> [(Date, Int)] {
        samples.compactMap { s in s.batteryPercent.map { (s.timestamp, $0) } }
    }

    func rsrpSeries() -> [(Date, Int)] {
        samples.compactMap { s in s.rsrp.map { (s.timestamp, $0) } }
    }

    func sinrSeries() -> [(Date, Double)] {
        samples.compactMap { s in s.sinr.map { (s.timestamp, $0) } }
    }

    func downloadSpeedSeries() -> [(Date, Double)] {
        speedSeries(\.totalRx)
    }

    func uploadSpeedSeries() -> [(Date, Double)] {
        speedSeries(\.totalTx)
    }

    /// Bytes-per-second deltas of a cumulative counter. A pair is dropped
    /// when the counter went backwards (device reboot reset it) or when the
    /// samples are too far apart to be one reading — the chain restarts from
    /// the newer sample, so one bad boundary never fabricates a spike.
    private func speedSeries(_ counter: KeyPath<HistorySample, Int?>) -> [(Date, Double)] {
        var result: [(Date, Double)] = []
        var prev: HistorySample?
        for s in samples {
            if let p = prev, let a = p[keyPath: counter], let b = s[keyPath: counter] {
                let dt = s.timestamp.timeIntervalSince(p.timestamp)
                if dt > 0, dt <= maxSpeedGap, b >= a {
                    result.append((s.timestamp, Double(b - a) / dt))
                }
            }
            prev = s
        }
        return result
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([HistorySample].self, from: data) else {
            return
        }
        samples = loaded
    }

    func save() {
        if let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
