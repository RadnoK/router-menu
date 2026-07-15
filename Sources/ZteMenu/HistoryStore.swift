import Foundation
import Observation

struct HistorySample: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let batteryPercent: Int?
    let totalBytes: Int?

    init(id: UUID = UUID(), timestamp: Date, batteryPercent: Int?, totalBytes: Int?) {
        self.id = id
        self.timestamp = timestamp
        self.batteryPercent = batteryPercent
        self.totalBytes = totalBytes
    }
}

@MainActor
@Observable
public final class HistoryStore {
    private(set) var samples: [HistorySample] = []
    private let fileURL: URL
    private let now: () -> Date
    private let window: TimeInterval = 24 * 3600

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

    func add(battery: Int?, totalBytes: Int?) {
        let t = now()
        samples.append(HistorySample(timestamp: t, batteryPercent: battery, totalBytes: totalBytes))
        let cutoff = t.addingTimeInterval(-window)
        samples.removeAll { $0.timestamp < cutoff }
        save()
    }

    func batterySeries() -> [(Date, Int)] {
        samples.compactMap { s in s.batteryPercent.map { (s.timestamp, $0) } }
    }

    func downloadSpeedSeries() -> [(Date, Double)] {
        var result: [(Date, Double)] = []
        var prev: HistorySample?
        for s in samples {
            if let p = prev, let a = p.totalBytes, let b = s.totalBytes {
                let dt = s.timestamp.timeIntervalSince(p.timestamp)
                if dt > 0 {
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
