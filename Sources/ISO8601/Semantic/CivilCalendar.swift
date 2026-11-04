/// Proleptic Gregorian arithmetic on days since 1970-01-01, on years read as decimal pairs.
enum CivilCalendar {
    /// `100 * century + yearOfCentury` with `yearOfCentury` in 0...99 for negative years too. The leap rule
    /// reads the pairs directly: a year is leap when `yearOfCentury` is divisible by 4, except that year 0 of
    /// a century is leap only when `century` is.
    struct Year {
        var century: Int
        var yearOfCentury: Int

        @inline(always)
        init(century: Int, yearOfCentury: Int) {
            self.century = century
            self.yearOfCentury = yearOfCentury
        }

        /// Floor split of an integer year.
        init(_ year: Int) {
            let century = year / 100
            let yearOfCentury = year - century * 100
            self.init(
                century: yearOfCentury < 0 ? century - 1 : century,
                yearOfCentury: yearOfCentury < 0 ? yearOfCentury + 100 : yearOfCentury
            )
        }

        /// `century & 3` is the century modulo 4 for negative centuries too.
        @inline(always)
        var isLeap: Bool {
            yearOfCentury & 3 == 0 && (yearOfCentury != 0 || century & 3 == 0)
        }

        @inline(always)
        var leapDay: Int { isLeap ? 1 : 0 }

        /// The year after, carrying into the century.
        @inline(always)
        var next: Year {
            yearOfCentury == 99
                ? Year(century: century + 1, yearOfCentury: 0)
                : Year(century: century, yearOfCentury: yearOfCentury + 1)
        }

        /// The year of the opposite sign, `yearOfCentury` kept in 0...99.
        @inline(always)
        var negated: Year {
            yearOfCentury == 0
                ? Year(century: -century, yearOfCentury: 0)
                : Year(century: -century - 1, yearOfCentury: 100 - yearOfCentury)
        }
    }

    /// Years are counted from March, so a leap day is the last day of its year. The days before March 1 of
    /// year `(c, yy)` are 36524.25 per century and 365.25 per year within it, each floored on its own:
    /// `36524 * c + c >> 2 + 365 * yy + yy >> 2`, exact for any `c` with the arithmetic shift and `yy` in
    /// 0...99. January and February belong to the March-based year before, which ends with this February
    /// and so is 365 days plus this year's leap day long. 1970-01-01 is March-based year (19, 69), month
    /// 10 from March, day 1: 719_162 + 306.
    @inline(always)
    static func epochDayInMonth(year: Year, month: Int, day: Int) -> (epochDay: Int, daysInMonth: Int) {
        let daysBeforeMarch = daysBeforeMarch(year)
        let daysBeforeMonth: Int
        let daysInMonth: Int
        if month <= 2 {
            let leapDay = year.leapDay
            daysBeforeMonth = daysBeforeMarch - 365 - leapDay + startOfMonth(fromMarch: month + 9)
            daysInMonth = month == 2 ? 28 + leapDay : 31
        } else {
            daysBeforeMonth = daysBeforeMarch + startOfMonth(fromMarch: month - 3)
            daysInMonth = 30 + ((month ^ (month >> 3)) & 1)
        }
        return (daysBeforeMonth + day - 1 - 719_468, daysInMonth)
    }

    @inline(always)
    static func epochDay(year: Year, month: Int, day: Int) -> Int {
        epochDayInMonth(year: year, month: month, day: day).epochDay
    }

    @inline(always)
    private static func daysBeforeMarch(_ year: Year) -> Int {
        36524 * year.century + (year.century >> 2) + 365 * year.yearOfCentury + (year.yearOfCentury >> 2)
    }

    /// Day of the March-based year on which month `monthFromMarch` starts, for 0...11: 0, 31, 61, 92, 122,
    /// 153, 184, 214, 245, 275, 306, 337. Month lengths from March alternate 31, 30 apart from July and
    /// August, so the starts are the floor of a line whose slope may be anything in a narrow band; on this
    /// twelve-value domain 1959/64 is in the band, and its power-of-two denominator makes the division a shift.
    @inline(always)
    private static func startOfMonth(fromMarch monthFromMarch: Int) -> Int {
        (1959 * monthFromMarch + 28) >> 6
    }

    /// Month lengths alternate 31, 30 from January, with the parity flipped from August on, so bit 0 of
    /// `month ^ month >> 3` is the 31st day; February is 28 plus the leap day.
    @inline(always)
    static func daysInMonth(_ month: Int, year: Year) -> Int {
        month == 2 ? 28 + year.leapDay : 30 + ((month ^ (month >> 3)) & 1)
    }

    @inline(always)
    static func daysInYear(_ year: Year) -> Int {
        365 + year.leapDay
    }

    /// Monday = 1. Day 0 was a Thursday.
    @inline(always)
    static func weekday(ofEpochDay day: Int) -> Int {
        floorMod(day + 3, 7) + 1
    }

    /// Monday of ISO week 1, the week containing January 4.
    @inline(always)
    static func startOfWeekYear(_ year: Year) -> Int {
        let january4 = epochDay(year: year, month: 1, day: 4)
        return january4 - weekday(ofEpochDay: january4) + 1
    }

    @inline(always)
    static func weeksInYear(_ year: Year) -> Int {
        (startOfWeekYear(year.next) - startOfWeekYear(year)) / 7
    }

    @inline(always)
    static func floorMod(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }
}

// MARK: Integer years

extension CivilCalendar {
    @inline(always)
    static func epochDay(year: Int, month: Int, day: Int) -> Int {
        epochDay(year: Year(year), month: month, day: day)
    }

    @inline(always)
    static func daysInMonth(_ month: Int, year: Int) -> Int {
        daysInMonth(month, year: Year(year))
    }

    @inline(always)
    static func isLeapYear(_ year: Int) -> Bool {
        Year(year).isLeap
    }

    @inline(always)
    static func startOfWeekYear(_ year: Int) -> Int {
        startOfWeekYear(Year(year))
    }

    @inline(always)
    static func weeksInYear(_ year: Int) -> Int {
        weeksInYear(Year(year))
    }
}
