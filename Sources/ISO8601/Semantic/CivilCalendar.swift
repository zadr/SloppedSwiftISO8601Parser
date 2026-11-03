/// Proleptic Gregorian arithmetic on days since 1970-01-01.
/// `epochDay` follows Howard Hinnant, "chrono-Compatible Low-Level Date Algorithms".
enum CivilCalendar {
    static func epochDay(year: Int, month: Int, day: Int) -> Int {
        let year = month <= 2 ? year - 1 : year
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let monthFromMarch = (month + 9) % 12
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    static func daysInYear(_ year: Int) -> Int {
        isLeapYear(year) ? 366 : 365
    }

    static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Monday = 1. Day 0 was a Thursday.
    static func weekday(ofEpochDay day: Int) -> Int {
        floorMod(day + 3, 7) + 1
    }

    /// Monday of ISO week 1, the week containing January 4.
    static func startOfWeekYear(_ year: Int) -> Int {
        let january4 = epochDay(year: year, month: 1, day: 4)
        return january4 - weekday(ofEpochDay: january4) + 1
    }

    static func weeksInYear(_ year: Int) -> Int {
        (startOfWeekYear(year + 1) - startOfWeekYear(year)) / 7
    }

    static func floorMod(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }
}
