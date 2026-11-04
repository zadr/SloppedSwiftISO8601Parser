import Testing
@testable import ISO8601

private func referenceDaysInMonth(_ month: Int, year: Int) -> Int {
    switch month {
    case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}

struct CivilCalendarTests {
    @Test func epochDayOfKnownDates() {
        #expect(CivilCalendar.epochDay(year: 1970, month: 1, day: 1) == 0)
        #expect(CivilCalendar.epochDay(year: 1985, month: 4, day: 12) == 5580)
        #expect(CivilCalendar.epochDay(year: 2000, month: 2, day: 29) == 11016)
        #expect(CivilCalendar.epochDay(year: 2024, month: 1, day: 2) == 19724)
        // The instants ResolverTests expects for these dates, in days.
        #expect(CivilCalendar.epochDay(year: 999_999_999, month: 12, day: 31) == 31_556_889_832_694_400 / 86_400)
        #expect(CivilCalendar.epochDay(year: -999_999_999, month: 1, day: 1) == -31_557_014_135_596_800 / 86_400)
    }

    /// Walks every date from -2000 through 4000, counting days from the first one.
    @Test func epochDayCountsEveryDay() {
        var expected = CivilCalendar.epochDay(year: -2000, month: 1, day: 1)
        for year in -2000...4000 {
            for month in 1...12 {
                let length = referenceDaysInMonth(month, year: year)
                let actual = CivilCalendar.daysInMonth(month, year: year)
                guard actual == length else {
                    Issue.record("daysInMonth(\(month), year: \(year)) is \(actual), expected \(length)")
                    return
                }
                for day in 1...length {
                    let actual = CivilCalendar.epochDay(year: year, month: month, day: day)
                    guard actual == expected else {
                        Issue.record("epochDay(year: \(year), month: \(month), day: \(day)) is \(actual), expected \(expected)")
                        return
                    }
                    expected += 1
                }
            }
        }
        #expect(expected == CivilCalendar.epochDay(year: 4001, month: 1, day: 1))
    }
}
