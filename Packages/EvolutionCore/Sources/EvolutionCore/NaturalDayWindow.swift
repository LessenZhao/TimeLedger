import Foundation

/// Local natural day windows for sync and filtering.
public struct NaturalDayWindow: Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var range: Range<Date> {
        start..<end
    }

    public static func forDate(_ date: Date, calendar: Calendar = .current) -> NaturalDayWindow {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return NaturalDayWindow(start: start, end: end)
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// A thread is "active on day" if created, updated, or any message falls in the window.
    /// Do not rely only on file mtime or createdAt alone.
    public func isThreadActiveOnDay(
        createdAt: Date,
        updatedAt: Date,
        messageTimes: [Date]
    ) -> Bool {
        if contains(createdAt) { return true }
        if contains(updatedAt) { return true }
        return messageTimes.contains { contains($0) }
    }
}
