import Foundation
import Testing
@testable import ISO8601

private func resolve(_ raw: RawComponents, in timeZone: TimeZone = .gmt) throws(ISO8601ParseError) -> TimeInterval {
    try Resolver(timeZone: timeZone).resolve(raw).timeIntervalSince1970
}

private let newYork = TimeZone(identifier: "America/New_York")!
private let jan2 = RawComponents.DatePart.calendar(year: 2024, month: 1, day: 2)
private let dec31of2016 = RawComponents.DatePart.calendar(year: 2016, month: 12, day: 31)
private let jan15 = RawComponents.DatePart.calendar(year: 2024, month: 1, day: 15)

private let dates: [(RawComponents.DatePart, TimeInterval)] = [
    (.century(19), -2_208_988_800),
    (.century(0), -62_167_219_200),
    (.decade(198), 315_532_800),
    (.decade(-198), -124_649_971_200),
    (.year(2024), 1_704_067_200),
    (.month(year: 2024, month: 2), 1_706_745_600),
    (.month(year: 2024, month: 12), 1_733_011_200),
    (jan2, 1_704_153_600),
    (.calendar(year: 1970, month: 1, day: 1), 0),
    (.calendar(year: 2000, month: 2, day: 29), 951_782_400),
    // Proleptic Gregorian; Foundation's Julian reading of this date is 10 days later.
    (.calendar(year: 1500, month: 3, day: 1), -14_826_672_000),
    // Inside the 1582 Julian-to-Gregorian gap.
    (.calendar(year: 1582, month: 10, day: 10), -12_219_724_800),
    (.calendar(year: 1, month: 1, day: 1), -62_135_596_800),
    (.year(0), -62_167_219_200),
    (.calendar(year: 0, month: 2, day: 29), -62_162_121_600),
    (.calendar(year: -400, month: 2, day: 29), -74_784_902_400),
    (.year(-1), -62_198_755_200),
    (.calendar(year: -44, month: 3, day: 15), -63_549_360_000),
    (.year(10000), 253_402_300_800),
    (.year(999_999_999), 31_556_889_801_244_800),
    (.calendar(year: 999_999_999, month: 12, day: 31), 31_556_889_832_694_400),
    (.year(-999_999_999), -31_557_014_135_596_800),
    (.ordinal(year: 2024, day: 1), 1_704_067_200),
    (.ordinal(year: 2024, day: 60), 1_709_164_800),
    (.ordinal(year: 2024, day: 366), 1_735_603_200),
    (.ordinal(year: 2023, day: 365), 1_703_980_800),
    // March 1.
    (.ordinal(year: 1900, day: 60), -2_203_891_200),
    (.week(year: 2024, week: 1, weekday: nil), 1_704_067_200),
    // 2025-12-29.
    (.week(year: 2026, week: 1, weekday: nil), 1_766_966_400),
    // 2008-12-29.
    (.week(year: 2009, week: 1, weekday: 1), 1_230_508_800),
    // 2005-01-01.
    (.week(year: 2004, week: 53, weekday: 6), 1_104_537_600),
    (.week(year: 2020, week: 53, weekday: nil), 1_609_113_600),
    // 2021-01-03.
    (.week(year: 2020, week: 53, weekday: 7), 1_609_632_000),
    (.week(year: 2015, week: 53, weekday: 4), 1_451_520_000),
    // 2027-01-03.
    (.week(year: 2026, week: 53, weekday: 7), 1_798_934_400),
    (.week(year: -2024, week: 1, weekday: 3), -126_038_592_000),
]

private let times: [(RawComponents, TimeInterval)] = [
    (RawComponents(jan2, .at(10)), 1_704_189_600),
    (RawComponents(jan2, .at(10, 30)), 1_704_191_400),
    (RawComponents(jan2, .at(10, 30, 45)), 1_704_191_445),
    (RawComponents(jan2, .at(0, 0, 0)), 1_704_153_600),
    (RawComponents(jan2, .at(23, 59, 59)), 1_704_239_999),
    (RawComponents(jan2, .at(24)), 1_704_240_000),
    (RawComponents(jan2, .at(24, 0)), 1_704_240_000),
    (RawComponents(jan2, .at(24, 0, 0)), 1_704_240_000),
    (RawComponents(jan2, .at(24, 0, 0, fraction: .init(digits: 0, scale: 3))), 1_704_240_000),
    (RawComponents(.calendar(year: 2024, month: 12, day: 31), .at(24)), 1_735_689_600),
    (RawComponents(.calendar(year: -44, month: 3, day: 15), .at(12)), -63_549_316_800),
    (RawComponents(.ordinal(year: 2024, day: 366), .at(23, 59, 59), .utc), 1_735_689_599),
    (RawComponents(.week(year: 2024, week: 1, weekday: 3), .at(10, 30)), 1_704_277_800),

    (RawComponents(jan2, .at(10, 30), .utc), 1_704_191_400),
    (RawComponents(jan2, .at(10, 30), .fixed(negative: false, hours: 0, minutes: 0)), 1_704_191_400),
    (RawComponents(jan2, .at(10, 30), .fixed(negative: true, hours: 0, minutes: 0)), 1_704_191_400),
    (RawComponents(jan2, .at(10, 30), .fixed(negative: false, hours: 1, minutes: 0)), 1_704_187_800),
    (RawComponents(jan2, .at(10, 30), .fixed(negative: true, hours: 5, minutes: 30)), 1_704_211_200),
    (RawComponents(jan2, .at(10, 30, 45), .fixed(negative: false, hours: 23, minutes: 59)), 1_704_105_105),
    (RawComponents(jan2, .at(10, 30, 45), .fixed(negative: true, hours: 23, minutes: 59)), 1_704_277_785),
    // 2023-12-31T23:30Z.
    (RawComponents(.calendar(year: 2024, month: 1, day: 1), .at(0, 30), .fixed(negative: false, hours: 1, minutes: 0)), 1_704_065_400),
    // 2024-01-02T23:00Z.
    (RawComponents(jan2, .at(24, 0), .fixed(negative: false, hours: 1, minutes: 0)), 1_704_236_400),

    // Every accepted leap second equals the following 00:00:00Z.
    (RawComponents(dec31of2016, .at(23, 59, 60), .utc), 1_483_228_800),
    (RawComponents(dec31of2016, .at(23, 59, 60)), 1_483_228_800),
    (RawComponents(dec31of2016, .at(18, 59, 60), .fixed(negative: true, hours: 5, minutes: 0)), 1_483_228_800),
    (RawComponents(.calendar(year: 2017, month: 1, day: 1), .at(0, 59, 60), .fixed(negative: false, hours: 1, minutes: 0)), 1_483_228_800),
    // No leap second was inserted here; none is looked up.
    (RawComponents(.calendar(year: 2024, month: 6, day: 30), .at(23, 59, 60), .utc), 1_719_792_000),
]

private let fractions: [(RawComponents, TimeInterval)] = [
    // 10:30:00.
    (RawComponents(jan2, .at(10, fraction: .init(digits: 5, scale: 1))), 1_704_191_400),
    // 10:30:15.
    (RawComponents(jan2, .at(10, 30, fraction: .init(digits: 25, scale: 2))), 1_704_191_415),
    (RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 5, scale: 1))), 1_704_191_445.5),
    (RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 50, scale: 3))), 1_704_191_445.05),
    (
        RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 123_456_789_012_345_678, scale: 18))),
        1_704_191_445.123456789012345678
    ),
    // 0.999999 h = 3599.9964 s.
    (RawComponents(jan2, .at(0, fraction: .init(digits: 999_999, scale: 6))), 1_704_157_199.9964),
    // 10:06-05:30 = 15:36Z.
    (RawComponents(jan2, .at(10, fraction: .init(digits: 1, scale: 1)), .fixed(negative: true, hours: 5, minutes: 30)), 1_704_209_760),
    (RawComponents(.calendar(year: 1969, month: 12, day: 31), .at(23, 59, 59, fraction: .init(digits: 5, scale: 1)), .utc), -0.5),
]

private let newYorkTimes: [(RawComponents, TimeInterval)] = [
    // EST, UTC-5.
    (RawComponents(jan15, .at(12, 0)), 1_705_338_000),
    // EDT, UTC-4.
    (RawComponents(.calendar(year: 2024, month: 7, day: 15), .at(12)), 1_721_059_200),
    (RawComponents(jan15), 1_705_294_800),
    (RawComponents(.year(2024)), 1_704_085_200),
    // 2024-01-16 local midnight.
    (RawComponents(jan15, .at(24)), 1_705_381_200),
    (RawComponents(jan15, .at(12), .utc), 1_705_320_000),
    // 23:59:60Z.
    (RawComponents(dec31of2016, .at(18, 59, 60)), 1_483_228_800),
]

private let errors: [(RawComponents, ISO8601ParseError)] = [
    (RawComponents(.year(1_000_000_000)), .outOfRange(.year, value: 1_000_000_000)),
    (RawComponents(.year(-1_000_000_000)), .outOfRange(.year, value: -1_000_000_000)),
    (RawComponents(.month(year: 2024, month: 0)), .outOfRange(.month, value: 0)),
    (RawComponents(.month(year: 2024, month: 13)), .outOfRange(.month, value: 13)),
    (RawComponents(.calendar(year: 2024, month: 1, day: 0)), .outOfRange(.day, value: 0)),
    (RawComponents(.calendar(year: 2024, month: 1, day: 32)), .outOfRange(.day, value: 32)),
    (RawComponents(.calendar(year: 2024, month: 4, day: 31)), .outOfRange(.day, value: 31)),
    (RawComponents(.calendar(year: 2023, month: 2, day: 29)), .outOfRange(.day, value: 29)),
    (RawComponents(.calendar(year: 1900, month: 2, day: 29)), .outOfRange(.day, value: 29)),
    (RawComponents(.calendar(year: -100, month: 2, day: 29)), .outOfRange(.day, value: 29)),
    (RawComponents(.ordinal(year: 2024, day: 0)), .outOfRange(.ordinalDay, value: 0)),
    (RawComponents(.ordinal(year: 2024, day: 367)), .outOfRange(.ordinalDay, value: 367)),
    (RawComponents(.ordinal(year: 2023, day: 366)), .outOfRange(.ordinalDay, value: 366)),
    (RawComponents(.week(year: 2024, week: 0, weekday: nil)), .outOfRange(.week, value: 0)),
    (RawComponents(.week(year: 2021, week: 53, weekday: nil)), .outOfRange(.week, value: 53)),
    (RawComponents(.week(year: 2021, week: 53, weekday: 1)), .outOfRange(.week, value: 53)),
    (RawComponents(.week(year: 2020, week: 54, weekday: 1)), .outOfRange(.week, value: 54)),
    (RawComponents(.week(year: 2020, week: 1, weekday: 0)), .outOfRange(.weekday, value: 0)),
    (RawComponents(.week(year: 2020, week: 1, weekday: 8)), .outOfRange(.weekday, value: 8)),

    (RawComponents(jan2, .at(25)), .outOfRange(.hour, value: 25)),
    (RawComponents(jan2, .at(10, 60)), .outOfRange(.minute, value: 60)),
    (RawComponents(jan2, .at(10, 30, 61)), .outOfRange(.second, value: 61)),
    (RawComponents(jan2, .at(24, 1)), .invalidEndOfDay),
    (RawComponents(jan2, .at(24, 0, 1)), .invalidEndOfDay),
    (RawComponents(jan2, .at(24, fraction: .init(digits: 5, scale: 1))), .invalidEndOfDay),
    (RawComponents(jan2, .at(24, 0, 0, fraction: .init(digits: 1, scale: 3))), .invalidEndOfDay),
    (RawComponents(dec31of2016, .at(23, 59, 60), .fixed(negative: false, hours: 1, minutes: 0)), .invalidLeapSecond),
    (RawComponents(jan2, .at(12, 30, 60), .utc), .invalidLeapSecond),
    (RawComponents(jan2, .at(10), .fixed(negative: false, hours: 24, minutes: 0)), .outOfRange(.offsetHour, value: 24)),
    (RawComponents(jan2, .at(10), .fixed(negative: true, hours: 1, minutes: 60)), .outOfRange(.offsetMinute, value: 60)),

    // Validation order: date, then time, then offset.
    (RawComponents(.calendar(year: 1_000_000_000, month: 13, day: 32)), .outOfRange(.year, value: 1_000_000_000)),
    (RawComponents(.calendar(year: 2024, month: 13, day: 32)), .outOfRange(.month, value: 13)),
    (
        RawComponents(.calendar(year: 2024, month: 13, day: 1), .at(25), .fixed(negative: false, hours: 24, minutes: 0)),
        .outOfRange(.month, value: 13)
    ),
    (RawComponents(jan2, .at(25, 60, 61), .fixed(negative: false, hours: 24, minutes: 0)), .outOfRange(.hour, value: 25)),
    (RawComponents(jan2, .at(10, 60, 61)), .outOfRange(.minute, value: 60)),
    (RawComponents(jan2, .at(10), .fixed(negative: false, hours: 24, minutes: 60)), .outOfRange(.offsetHour, value: 24)),
]

struct ResolverTests {
    @Test(arguments: dates)
    func resolvesDate(_ date: RawComponents.DatePart, _ expected: TimeInterval) throws {
        #expect(try resolve(RawComponents(date)) == expected)
    }

    @Test(arguments: times)
    func resolvesTime(_ raw: RawComponents, _ expected: TimeInterval) throws {
        #expect(try resolve(raw) == expected)
    }

    @Test(arguments: fractions)
    func resolvesFraction(_ raw: RawComponents, _ expected: TimeInterval) throws {
        let actual = try resolve(raw)
        #expect(abs(actual - expected) < 1e-6)
    }

    @Test(arguments: newYorkTimes)
    func resolvesInTimeZone(_ raw: RawComponents, _ expected: TimeInterval) throws {
        #expect(try resolve(raw, in: newYork) == expected)
    }

    @Test(arguments: errors)
    func rejects(_ raw: RawComponents, _ error: ISO8601ParseError) {
        #expect(throws: error) { try resolve(raw) }
    }

    @Test func leapSecondUsesTimeZoneOffset() {
        // 23:59:60 EST is 04:59:60Z.
        #expect(throws: ISO8601ParseError.invalidLeapSecond) {
            try resolve(RawComponents(dec31of2016, .at(23, 59, 60)), in: newYork)
        }
    }
}
