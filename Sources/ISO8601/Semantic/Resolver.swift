import Foundation

/// Semantic phase: range-checks `RawComponents` and converts them to an instant.
struct Resolver {
    private struct TimeOfDay {
        static let midnight = TimeOfDay(seconds: 0, fraction: 0, isLeapSecond: false)

        /// Up to 86_400 inclusive, for 24:00 and 23:59:60.
        var seconds: Int
        /// In `0..<1`.
        var fraction: Double
        var isLeapSecond: Bool
    }

    private static let secondsPerDay = 86_400
    private static let yearRange = -999_999_999...999_999_999
    private static let referenceDateOffset = Int(Date.timeIntervalBetween1970AndReferenceDate)

    var timeZone: TimeZone

    func resolve(_ raw: borrowing RawComponents) throws(ISO8601ParseError) -> Date {
        let day = try Self.epochDay(raw.date)
        let time = try raw.time.map { time throws(ISO8601ParseError) in try Self.timeOfDay(time) } ?? .midnight
        let explicitOffset = try raw.offset.map { offset throws(ISO8601ParseError) in try Self.seconds(offset) }

        let local = day * Self.secondsPerDay + time.seconds
        let utc = local - (explicitOffset ?? zoneOffset(atLocal: local))
        if time.isLeapSecond, CivilCalendar.floorMod(utc, Self.secondsPerDay) != 0 {
            throw .invalidLeapSecond
        }
        return Date(timeIntervalSinceReferenceDate: Double(utc - Self.referenceDateOffset) + time.fraction)
    }

    /// Second pass corrects for a zone whose offset differs between the local and UTC readings of `local`.
    private func zoneOffset(atLocal local: Int) -> Int {
        let estimate = timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(local)))
        return timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(local - estimate)))
    }

    private static func epochDay(_ date: RawComponents.DatePart) throws(ISO8601ParseError) -> Int {
        switch date {
        case .year(let year):
            try validate(.year, year, in: yearRange)
            return CivilCalendar.epochDay(year: year, month: 1, day: 1)

        case .month(let year, let month):
            try validate(.year, year, in: yearRange)
            try validate(.month, month, in: 1...12)
            return CivilCalendar.epochDay(year: year, month: month, day: 1)

        case .calendar(let year, let month, let day):
            try validate(.year, year, in: yearRange)
            try validate(.month, month, in: 1...12)
            try validate(.day, day, in: 1...CivilCalendar.daysInMonth(month, year: year))
            return CivilCalendar.epochDay(year: year, month: month, day: day)

        case .ordinal(let year, let day):
            try validate(.year, year, in: yearRange)
            try validate(.ordinalDay, day, in: 1...CivilCalendar.daysInYear(year))
            return CivilCalendar.epochDay(year: year, month: 1, day: 1) + day - 1

        case .week(let year, let week, let weekday):
            try validate(.year, year, in: yearRange)
            try validate(.week, week, in: 1...CivilCalendar.weeksInYear(year))
            let weekday = weekday ?? 1
            try validate(.weekday, weekday, in: 1...7)
            return CivilCalendar.startOfWeekYear(year) + (week - 1) * 7 + weekday - 1
        }
    }

    private static func timeOfDay(_ time: RawComponents.TimePart) throws(ISO8601ParseError) -> TimeOfDay {
        try validate(.hour, time.hour, in: 0...24)
        if time.hour == 24 {
            guard time.minute ?? 0 == 0, time.second ?? 0 == 0, time.fraction?.digits ?? 0 == 0 else {
                throw .invalidEndOfDay
            }
            return TimeOfDay(seconds: secondsPerDay, fraction: 0, isLeapSecond: false)
        }

        var seconds = time.hour * 3600
        var fractionUnit = 3600.0
        if let minute = time.minute {
            try validate(.minute, minute, in: 0...59)
            seconds += minute * 60
            fractionUnit = 60
        }
        if let second = time.second {
            try validate(.second, second, in: 0...60)
            seconds += second
            fractionUnit = 1
        }

        var fraction = 0.0
        if let raw = time.fraction {
            let fractionalSeconds = Double(raw.digits) / pow(10, Double(raw.scale)) * fractionUnit
            let whole = fractionalSeconds.rounded(.down)
            seconds += Int(whole)
            fraction = fractionalSeconds - whole
        }
        return TimeOfDay(seconds: seconds, fraction: fraction, isLeapSecond: time.second == 60)
    }

    private static func seconds(_ offset: RawComponents.Offset) throws(ISO8601ParseError) -> Int {
        switch offset {
        case .utc:
            return 0
        case .fixed(let negative, let hours, let minutes):
            try validate(.offsetHour, hours, in: 0...23)
            try validate(.offsetMinute, minutes, in: 0...59)
            let magnitude = hours * 3600 + minutes * 60
            return negative ? -magnitude : magnitude
        }
    }

    private static func validate(
        _ component: ISO8601ParseError.Component,
        _ value: Int,
        in range: ClosedRange<Int>
    ) throws(ISO8601ParseError) {
        guard range.contains(value) else { throw .outOfRange(component, value: value) }
    }
}
