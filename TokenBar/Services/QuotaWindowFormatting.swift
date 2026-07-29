import Foundation

enum QuotaWindowFormatting {
    static func label(seconds: TimeInterval?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        if seconds >= 86_400 {
            let days = max(Int(round(seconds / 86_400)), 1)
            return days == 1 ? "1-day window" : "\(days)-day window"
        }
        if seconds >= 3_600 {
            let hours = max(Int(round(seconds / 3_600)), 1)
            return hours == 1 ? "1-hour window" : "\(hours)-hour window"
        }
        let minutes = max(Int(round(seconds / 60)), 1)
        return minutes == 1 ? "1-minute window" : "\(minutes)-minute window"
    }

    static func label(from start: Date, to end: Date) -> String {
        label(seconds: max(end.timeIntervalSince(start), 0), fallback: "1-minute window")
    }

    static func primaryWindow(from windows: [CCSwitchQuotaWindow]) -> CCSwitchQuotaWindow? {
        windows.first(where: {
            $0.modelName == "general" && ($0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit)
        })
            ?? windows.first(where: { $0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit })
            ?? windows.first
    }
}
