import Foundation

enum DateRangeService {
    static func startOfNaturalDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func endOfNaturalDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfNaturalDay(for: date, calendar: calendar))!
    }

    static func naturalDayRange(for date: Date, calendar: Calendar = .current) -> Range<Date> {
        startOfNaturalDay(for: date, calendar: calendar)..<endOfNaturalDay(for: date, calendar: calendar)
    }

    static func startOfNaturalWeek(for date: Date, calendar: Calendar = .current) -> Date {
        let day = startOfNaturalDay(for: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: day)
        // weekday: 1 = Sunday ... 7 = Saturday; weekStartsOn controls offset
        let weekStartsOn = calendar.firstWeekday // 1 = Sunday, 2 = Monday
        let offset = (weekday - weekStartsOn + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func endOfNaturalWeek(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: startOfNaturalWeek(for: date, calendar: calendar))!
    }

    static func weekRange(for date: Date, calendar: Calendar = .current) -> Range<Date> {
        startOfNaturalWeek(for: date, calendar: calendar)..<endOfNaturalWeek(for: date, calendar: calendar)
    }

    static func startOfNaturalMonth(for date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)!
    }

    static func endOfNaturalMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 1, to: startOfNaturalMonth(for: date, calendar: calendar))!
    }

    static func monthRange(for date: Date, calendar: Calendar = .current) -> Range<Date> {
        startOfNaturalMonth(for: date, calendar: calendar)..<endOfNaturalMonth(for: date, calendar: calendar)
    }

    static func overlapDuration(
        entryStart: Date,
        entryEnd: Date,
        rangeStart: Date,
        rangeEnd: Date
    ) -> TimeInterval {
        let start = max(entryStart, rangeStart)
        let end = min(entryEnd, rangeEnd)
        return max(0, end.timeIntervalSince(start))
    }

    static func hasOverlap(
        entryStart: Date,
        entryEnd: Date,
        otherStart: Date,
        otherEnd: Date
    ) -> Bool {
        entryStart < otherEnd && otherStart < entryEnd
    }
}
