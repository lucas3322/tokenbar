import Foundation
import SwiftUI

enum Fmt {
    static func tokens(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.2fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(value) / 1_000)
        default: return "\(value)"
        }
    }

    static func money(_ value: Double) -> String {
        if value == 0 { return "—" }
        if value < 0.01 { return "<$0.01" }
        if value >= 1_000 { return String(format: "$%.0f", value) }
        return String(format: "$%.2f", value)
    }

    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }

    /// Contagem regressiva enxuta: "2h14" ou "38min".
    static func countdown(to date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "agora" }
        let hours = Int(remaining) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes)min"
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Nome curto do modelo para caber na lista.
    static func modelLabel(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "|fast", with: " ⚡︎")
        name = name.replacingOccurrences(of: "claude-", with: "")
        return name
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .ok: return Color(red: 0.25, green: 0.78, blue: 0.50)
        case .warn: return Color(red: 0.97, green: 0.72, blue: 0.24)
        case .critical: return Color(red: 0.95, green: 0.36, blue: 0.34)
        }
    }
}
