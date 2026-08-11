import Foundation

public enum UnitMode: String, CaseIterable, Codable {
    case fixedKB = "KB/s"
    case fixedMB = "MB/s"
    case fixedMbps = "Mbps"
}

public enum DisplayLayout: String, CaseIterable, Codable {
    case stacked = "Stacked (Upload & Download)"
    case downloadOnly = "Download Only"
    case uploadOnly = "Upload Only"
}

public class SpeedFormatter {
    public static func formatSpeed(_ bytesPerSec: Double, unitMode: UnitMode) -> String {
        switch unitMode {
        case .fixedKB:
            let kb = bytesPerSec / 1024.0
            return String(format: "%.1f KB/s", kb)
        case .fixedMB:
            let mb = bytesPerSec / (1024.0 * 1024.0)
            return String(format: "%.1f MB/s", mb)
        case .fixedMbps:
            let mbps = (bytesPerSec * 8.0) / 1_000_000.0
            return String(format: "%.1f Mbps", mbps)
        }
    }
    
    public static func formatDataSize(_ bytes: UInt64) -> String {
        let doubleBytes = Double(bytes)
        if doubleBytes < 1024 {
            return "\(bytes) B"
        } else if doubleBytes < 1024 * 1024 {
            return String(format: "%.0f KB", doubleBytes / 1024.0)
        } else if doubleBytes < 1024 * 1024 * 1024 {
            return String(format: "%.0f MB", doubleBytes / (1024.0 * 1024.0))
        } else {
            return String(format: "%.0f GB", doubleBytes / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
