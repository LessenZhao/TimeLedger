import Foundation

enum DurationFormatter {
    static func compact(_ duration: TimeInterval, approximate: Bool = false) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        let prefix = approximate && totalMinutes > 0 ? "约" : ""

        if totalMinutes < 1 {
            return "<1分钟"
        }

        if totalMinutes < 60 {
            return "\(prefix)\(totalMinutes)分钟"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 {
            return "\(prefix)\(hours)小时"
        }

        return "\(prefix)\(hours)小时\(minutes)分钟"
    }
}
