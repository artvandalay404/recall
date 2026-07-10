import Foundation

/// Short human-readable interval labels (`"<1m"`, `"10m"`, `"3d"`, `"2mo"`)
/// used to preview what each grade button will do to a card's next due date.
public enum IntervalFormatting {
    public static func short(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if seconds < 60 { return "<1m" }
        if minutes < 60 { return "\(Int(minutes.rounded()))m" }
        if hours < 24 { return "\(Int(hours.rounded()))h" }
        if days < 30 { return "\(Int(days.rounded()))d" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }
}
