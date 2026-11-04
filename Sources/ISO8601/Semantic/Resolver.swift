import Foundation

/// Semantic phase: range checks and conversion to an instant. The lexer applies the pieces to each field as
/// it scans; `resolve(_:zoneOffset:)` applies them to `RawComponents`.
enum Resolver {
    /// A date-time read in its zone: whole seconds since the reference date, the fraction of a second as
    /// `remainder / power` in `0..<1`, and the second lexed, which the leap-second check needs.
    struct LocalTime {
        var seconds: Int
        var remainder = 0
        var power = 1
        var second = 0
    }

    static let secondsPerDay = 86_400
    private static let yearRange = -999_999_999...999_999_999
    /// `Date.timeIntervalBetween1970AndReferenceDate` is 11_323 whole days, so `CivilCalendar`'s counts
    /// shift to the reference date by one subtraction, placed where it folds into the calendar's epoch constant.
    private static let daysBeforeReferenceDate = 11_323

    /// `zoneOffset` gives the zone's offset from UTC at a local time in seconds since 2001-01-01, `Date`'s
    /// reference date. It is called only when `raw` has a time without a UTC offset, or no time.
    @inline(always)
    static func resolve(
        _ raw: borrowing RawComponents,
        zoneOffset: (_ local: Int) -> Int
    ) throws(ISO8601ParseError) -> Date {
        let midnight = try midnight(raw.date)
        guard let rawTime = raw.time else { return date(midnight: midnight, zoneOffset: zoneOffset) }
        let time = try localTime(midnight: midnight, rawTime)
        let local = time.seconds
        let utc: Int
        switch raw.offset {
        case .utc?:
            utc = local
        case .fixed(let negative, let hours, let minutes)?:
            utc = try Self.utc(local, negative: negative, hours: hours, minutes: minutes)
        case nil:
            utc = local - zoneOffset(local)
        }
        return try date(utc: utc, time)
    }

    /// `midnight` is the start of the day in the zone, in seconds since the reference date.
    @inline(always)
    static func date(midnight: Int, zoneOffset: (_ local: Int) -> Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(midnight - zoneOffset(midnight)))
    }

    @inline(always)
    static func utc(_ local: Int, negative: Bool, hours: Int, minutes: Int) throws(ISO8601ParseError) -> Int {
        try validate(.offsetHour, hours, in: 0...23)
        try validate(.offsetMinute, minutes, in: 0...59)
        let magnitude = hours * 3600 + minutes * 60
        return local - (negative ? -magnitude : magnitude)
    }

    /// The instant; the leap-second check needs the UTC reading.
    @inline(always)
    static func date(utc: Int, _ time: LocalTime) throws(ISO8601ParseError) -> Date {
        if time.second == 60, CivilCalendar.floorMod(utc, secondsPerDay) != 0 {
            throw .invalidLeapSecond
        }
        let seconds = Double(utc)
        if time.remainder != 0 {
            return Date(timeIntervalSinceReferenceDate: seconds + Double(time.remainder) / Double(time.power))
        }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Second pass corrects for a zone whose offset differs between the local and UTC readings of `local`.
    /// Not inlined: its `Date` temporaries have no fixed layout, and inlined they would force a dynamic frame
    /// (metadata lookup, value-witness size, stack probe) on every caller.
    @inline(never)
    static func zoneOffset(atLocal local: Int, in timeZone: borrowing TimeZone) -> Int {
        let estimate = timeZone.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: Double(local)))
        return timeZone.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: Double(local - estimate)))
    }
}

// MARK: Local midnight

extension Resolver {
    typealias Year = CivilCalendar.Year

    /// The start of the day in the zone, in seconds since the reference date. A `RawComponents` year may be
    /// any `Int`; a lexed year has at most six digits and needs no check.
    @inline(always)
    static func midnight(_ date: RawComponents.DatePart) throws(ISO8601ParseError) -> Int {
        switch date {
        case .century(let century):
            return startOfYear(try year(century * 100))
        case .decade(let decade):
            return startOfYear(try year(decade * 10))
        case .year(let value):
            return startOfYear(try year(value))
        case .month(let value, let month):
            return try startOfMonth(year: try year(value), month: month)
        case .calendar(let value, let month, let day):
            return try calendarDay(year: try year(value), month: month, day: day)
        case .ordinal(let value, let day):
            return try ordinalDay(year: try year(value), day: day)
        case .week(let value, let week, let weekday):
            return try weekDay(year: try year(value), week: week, weekday: weekday ?? 1)
        }
    }

    @inline(always)
    private static func year(_ year: Int) throws(ISO8601ParseError) -> Year {
        try validate(.year, year, in: yearRange)
        return Year(year)
    }

    @inline(always)
    static func startOfYear(_ year: Year) -> Int {
        midnight(year: year, month: 1, day: 1)
    }

    @inline(always)
    static func startOfMonth(year: Year, month: Int) throws(ISO8601ParseError) -> Int {
        try validate(.month, month, in: 1...12)
        return midnight(year: year, month: month, day: 1)
    }

    @inline(always)
    static func calendarDay(year: Year, month: Int, day: Int) throws(ISO8601ParseError) -> Int {
        try validate(.month, month, in: 1...12)
        let (epochDay, daysInMonth) = CivilCalendar.epochDayInMonth(year: year, month: month, day: day)
        try validate(.day, day, upTo: daysInMonth)
        return midnight(epochDay: epochDay)
    }

    @inline(always)
    static func ordinalDay(year: Year, day: Int) throws(ISO8601ParseError) -> Int {
        try validate(.ordinalDay, day, upTo: CivilCalendar.daysInYear(year))
        return midnight(epochDay: CivilCalendar.epochDay(year: year, month: 1, day: 1) + day - 1)
    }

    @inline(always)
    static func weekDay(year: Year, week: Int, weekday: Int) throws(ISO8601ParseError) -> Int {
        try validate(.week, week, upTo: CivilCalendar.weeksInYear(year))
        try validate(.weekday, weekday, in: 1...7)
        return midnight(epochDay: CivilCalendar.startOfWeekYear(year) + (week - 1) * 7 + weekday - 1)
    }

    @inline(always)
    private static func midnight(year: Year, month: Int, day: Int) -> Int {
        midnight(epochDay: CivilCalendar.epochDay(year: year, month: month, day: day))
    }

    /// Each date arm forms its own seconds, where the day's bound is in view; only the result crosses the join.
    @inline(always)
    private static func midnight(epochDay: Int) -> Int {
        (epochDay - daysBeforeReferenceDate) * secondsPerDay
    }
}

// MARK: Local time

extension Resolver {
    @inline(always)
    static func localTime(midnight: Int, _ time: RawComponents.TimePart) throws(ISO8601ParseError) -> LocalTime {
        if time.hour == 24 {
            guard time.minute == 0, time.second == 0, time.fraction.digits == 0 else { throw .invalidEndOfDay }
            return endOfDay(midnight)
        }
        try validate(.hour, time.hour, in: 0...23)
        try validate(.minute, time.minute, in: 0...59)
        try validate(.second, time.second, in: 0...60)
        let seconds = (time.hour * 60 + time.minute) * 60 + time.second
        switch time.precision {
        case .hour: return localTime(midnight: midnight, seconds: seconds, second: 0, fraction: time.fraction, unit: 3600)
        case .minute: return localTime(midnight: midnight, seconds: seconds, second: 0, fraction: time.fraction, unit: 60)
        case .second: return localTime(midnight: midnight, seconds: seconds, second: time.second, fraction: time.fraction, unit: 1)
        }
    }

    @inline(always)
    static func endOfDay(_ midnight: Int) -> LocalTime {
        LocalTime(seconds: midnight + secondsPerDay)
    }

    /// `seconds` after `midnight`; `unit` is the length in seconds of the component the fraction qualifies,
    /// a constant at each call.
    @inline(always)
    static func localTime(midnight: Int, seconds: Int, second: Int, fraction: RawComponents.Fraction, unit: Int) -> LocalTime {
        let local = midnight + seconds
        // `digits < power`, so a fraction of a second holds no whole seconds.
        if unit == 1 {
            return LocalTime(seconds: local, remainder: fraction.digits, power: fraction.power, second: second)
        }
        guard fraction.digits != 0 else {
            return LocalTime(seconds: local, remainder: 0, power: fraction.power, second: second)
        }
        // `digits * unit` can exceed `Int`; the quotient, whole seconds, is below `unit` since `digits < power`.
        let scaled = fraction.digits.multipliedFullWidth(by: unit)
        let (whole, remainder) = fraction.power.dividingFullWidth(scaled)
        return LocalTime(seconds: local + whole, remainder: remainder, power: fraction.power, second: second)
    }
}

// MARK: Range checks

extension Resolver {
    @inline(always)
    static func validate(
        _ component: ISO8601ParseError.Component,
        _ value: Int,
        in range: ClosedRange<Int>
    ) throws(ISO8601ParseError) {
        guard range.contains(value) else { throw .outOfRange(component, value: value) }
    }

    /// `value` in `1...upperBound`.
    @inline(always)
    static func validate(
        _ component: ISO8601ParseError.Component,
        _ value: Int,
        upTo upperBound: Int
    ) throws(ISO8601ParseError) {
        guard (value - 1) | (upperBound - value) >= 0 else { throw .outOfRange(component, value: value) }
    }
}
