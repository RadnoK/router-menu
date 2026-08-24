import Foundation

enum ByteFormat {
    static func gb(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.2f GB", gb)
    }

    static func speed(_ bytesPerSec: Int) -> String {
        speed(Double(bytesPerSec))
    }

    /// Chart series and axis labels carry Double values.
    static func speed(_ bytesPerSec: Double) -> String {
        let b = bytesPerSec
        if b >= 1_073_741_824 { // 1024^3
            return String(format: "%.1f GB/s", b / 1_073_741_824.0)
        } else if b >= 1_048_576 { // 1024 * 1024
            return String(format: "%.1f MB/s", b / (1024.0 * 1024.0))
        } else if b >= 1_024 {
            return String(format: "%.1f KB/s", b / 1024.0)
        } else {
            return "\(Int(b)) B/s"
        }
    }

    /// Data amounts that may be small (a session's megabytes) or large
    /// (a month's gigabytes) — picks the unit instead of forcing GB.
    static func bytes(_ bytes: Int) -> String {
        let b = Double(bytes)
        if b >= 1_073_741_824 {
            return gb(bytes)
        } else if b >= 1_048_576 {
            return String(format: "%.1f MB", b / (1024.0 * 1024.0))
        } else if b >= 1_024 {
            return String(format: "%.1f KB", b / 1024.0)
        } else {
            return "\(bytes) B"
        }
    }

    static func uptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}
