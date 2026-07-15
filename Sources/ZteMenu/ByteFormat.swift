import Foundation

enum ByteFormat {
    static func gb(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.2f GB", gb)
    }

    static func speed(_ bytesPerSec: Int) -> String {
        let b = Double(bytesPerSec)
        if b >= 1_048_576 { // 1024 * 1024
            return String(format: "%.1f MB/s", b / (1024.0 * 1024.0))
        } else if b >= 1_024 {
            return String(format: "%.1f KB/s", b / 1024.0)
        } else {
            return "\(bytesPerSec) B/s"
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
