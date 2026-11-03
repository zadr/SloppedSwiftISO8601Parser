import Testing
@testable import ISO8601

func lex(_ s: String) throws(ISO8601ParseError) -> RawComponents {
    try Lexer(s.utf8.span).lex()
}

extension RawComponents {
    init(_ date: DatePart, _ time: TimePart? = nil, _ offset: Offset? = nil) {
        self.init(date: date, time: time, offset: offset)
    }
}

extension RawComponents.TimePart {
    static func at(_ hour: Int, _ minute: Int? = nil, _ second: Int? = nil, fraction: RawComponents.Fraction? = nil) -> Self {
        Self(hour: hour, minute: minute, second: second, fraction: fraction)
    }
}

private let jan2 = RawComponents.DatePart.calendar(year: 2024, month: 1, day: 2)

private let dates: [(String, RawComponents.DatePart)] = [
    ("2024", .year(2024)),
    ("0000", .year(0)),
    ("2024-01", .month(year: 2024, month: 1)),
    ("2024-01-02", jan2),
    ("20240102", jan2),
    ("2024-032", .ordinal(year: 2024, day: 32)),
    ("2024032", .ordinal(year: 2024, day: 32)),
    ("2024-W01", .week(year: 2024, week: 1, weekday: nil)),
    ("2024W01", .week(year: 2024, week: 1, weekday: nil)),
    ("2024-W01-3", .week(year: 2024, week: 1, weekday: 3)),
    ("2024W013", .week(year: 2024, week: 1, weekday: 3)),
    // Ranges are checked by the Resolver.
    ("2024-13-45", .calendar(year: 2024, month: 13, day: 45)),
    ("2024-000", .ordinal(year: 2024, day: 0)),
    ("2024W990", .week(year: 2024, week: 99, weekday: 0)),
    ("+12345", .year(12345)),
    ("+12345-06", .month(year: 12345, month: 6)),
    ("-0001", .year(-1)),
    ("-0000", .year(0)),
    ("\u{2212}0044-03-15", .calendar(year: -44, month: 3, day: 15)),
    ("+002024-01-02", jan2),
    // A signed run is always the whole year, never YYYYMMDD.
    ("+0020240102", .year(20_240_102)),
    ("+10000-366", .ordinal(year: 10000, day: 366)),
    ("-2024W013", .week(year: -2024, week: 1, weekday: 3)),
    ("\u{2212}2024-W01", .week(year: -2024, week: 1, weekday: nil)),
    ("-999999999-12-31", .calendar(year: -999_999_999, month: 12, day: 31)),
    ("+123456789012345678", .year(123_456_789_012_345_678)),
]

private let dateTimes: [(String, RawComponents)] = [
    ("2024-01-02T10", RawComponents(jan2, .at(10))),
    ("2024-01-02T10:30", RawComponents(jan2, .at(10, 30))),
    ("2024-01-02T10:30:45", RawComponents(jan2, .at(10, 30, 45))),
    ("20240102T10", RawComponents(jan2, .at(10))),
    ("20240102T1030", RawComponents(jan2, .at(10, 30))),
    ("20240102T103045", RawComponents(jan2, .at(10, 30, 45))),
    ("2024-01-02t10:30", RawComponents(jan2, .at(10, 30))),
    ("2024-01-02 10:30", RawComponents(jan2, .at(10, 30))),
    ("2024-01-02T24:00", RawComponents(jan2, .at(24, 0))),
    ("2024-01-02T23:59:60", RawComponents(jan2, .at(23, 59, 60))),
    ("2024-032T10:30", RawComponents(.ordinal(year: 2024, day: 32), .at(10, 30))),
    ("2024032T1030", RawComponents(.ordinal(year: 2024, day: 32), .at(10, 30))),
    ("2024-W01-3T10:30:45", RawComponents(.week(year: 2024, week: 1, weekday: 3), .at(10, 30, 45))),
    ("2024W013T103045", RawComponents(.week(year: 2024, week: 1, weekday: 3), .at(10, 30, 45))),
    ("-2024W013T1030", RawComponents(.week(year: -2024, week: 1, weekday: 3), .at(10, 30))),
    ("+12345-06-07T08:09:10Z", RawComponents(.calendar(year: 12345, month: 6, day: 7), .at(8, 9, 10), .utc)),

    ("2024-01-02T10.5", RawComponents(jan2, .at(10, fraction: .init(digits: 5, scale: 1)))),
    ("20240102T10,5", RawComponents(jan2, .at(10, fraction: .init(digits: 5, scale: 1)))),
    ("2024-01-02T10:30,25", RawComponents(jan2, .at(10, 30, fraction: .init(digits: 25, scale: 2)))),
    ("2024-01-02T10:30:45.050", RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 50, scale: 3)))),
    ("2024-01-02T10:30:45.000", RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 0, scale: 3)))),
    ("20240102T103045,123456789", RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 123_456_789, scale: 9)))),
    // Digits past the 18th are consumed and dropped.
    (
        "2024-01-02T10:30:45.1234567890123456789999",
        RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 123_456_789_012_345_678, scale: 18)))
    ),

    ("2024-01-02T10Z", RawComponents(jan2, .at(10), .utc)),
    ("2024-01-02T10:30:45Z", RawComponents(jan2, .at(10, 30, 45), .utc)),
    ("2024-01-02T10:30:45z", RawComponents(jan2, .at(10, 30, 45), .utc)),
    ("2024-01-02T10:30:45.5Z", RawComponents(jan2, .at(10, 30, 45, fraction: .init(digits: 5, scale: 1)), .utc)),
    ("2024-01-02T10:30:45+01:00", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: false, hours: 1, minutes: 0))),
    ("2024-01-02T10:30:45+01", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: false, hours: 1, minutes: 0))),
    ("2024-01-02T10:30:45-05:30", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: true, hours: 5, minutes: 30))),
    ("2024-01-02T10:30:45\u{2212}05:30", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: true, hours: 5, minutes: 30))),
    ("2024-01-02T10:30:45-00:00", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: true, hours: 0, minutes: 0))),
    ("2024-01-02T10:30:45+99:99", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: false, hours: 99, minutes: 99))),
    (
        "2024-01-02T10:30.5+01:00",
        RawComponents(jan2, .at(10, 30, fraction: .init(digits: 5, scale: 1)), .fixed(negative: false, hours: 1, minutes: 0))
    ),
    ("20240102T10+01", RawComponents(jan2, .at(10), .fixed(negative: false, hours: 1, minutes: 0))),
    ("20240102T103045+0130", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: false, hours: 1, minutes: 30))),
    ("20240102T103045-08", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: true, hours: 8, minutes: 0))),
    ("20240102T103045\u{2212}0800", RawComponents(jan2, .at(10, 30, 45), .fixed(negative: true, hours: 8, minutes: 0))),
]

private let errors: [(String, ISO8601ParseError)] = [
    ("", .unexpectedEnd(at: 0)),
    ("+", .unexpectedEnd(at: 1)),
    ("\u{2212}", .unexpectedEnd(at: 3)),
    ("x2024", .unexpectedCharacter(at: 0)),
    // U+2213 shares its first two UTF-8 bytes with U+2212.
    ("\u{2213}2024", .unexpectedCharacter(at: 0)),
    (" 2024-01-02", .unexpectedCharacter(at: 0)),
    ("+x", .unexpectedCharacter(at: 1)),
    ("+202", .invalidDigitCount(3, at: 1)),
    ("\u{2212}20", .invalidDigitCount(2, at: 3)),
    ("+1234567890123456789", .invalidDigitCount(19, at: 1)),
    ("1234567890123456789", .invalidDigitCount(19, at: 0)),
    ("202", .invalidDigitCount(3, at: 0)),
    ("20240", .invalidDigitCount(5, at: 0)),
    ("202401", .invalidDigitCount(6, at: 0)),
    ("2024010203", .invalidDigitCount(10, at: 0)),
    ("2024T10", .unexpectedCharacter(at: 4)),
    ("2024/01", .unexpectedCharacter(at: 4)),
    ("+12345T10", .unexpectedCharacter(at: 6)),
    ("+12345:", .unexpectedCharacter(at: 6)),

    ("2024-", .unexpectedEnd(at: 5)),
    ("2024-x", .unexpectedCharacter(at: 5)),
    ("2024-1", .invalidDigitCount(1, at: 5)),
    ("2024-0102", .invalidDigitCount(4, at: 5)),
    ("2024-01-", .unexpectedEnd(at: 8)),
    ("2024-01-2", .invalidDigitCount(1, at: 8)),
    ("2024-01-002", .invalidDigitCount(3, at: 8)),
    ("2024-W", .unexpectedEnd(at: 6)),
    ("2024-W1", .invalidDigitCount(1, at: 6)),
    ("2024-W013", .mixedFormats(at: 6)),
    ("2024-W0134", .invalidDigitCount(4, at: 6)),
    ("2024-W01-", .unexpectedEnd(at: 9)),
    ("2024-W01-12", .invalidDigitCount(2, at: 9)),
    ("2024W", .unexpectedEnd(at: 5)),
    ("2024W1", .invalidDigitCount(1, at: 5)),
    ("2024W0123", .invalidDigitCount(4, at: 5)),
    ("2024W01-3", .mixedFormats(at: 7)),

    ("2024-01T10", .unexpectedCharacter(at: 7)),
    ("2024-W01T10", .unexpectedCharacter(at: 8)),
    ("2024W01T10", .unexpectedCharacter(at: 7)),
    ("2024-01-02X", .unexpectedCharacter(at: 10)),
    ("2024-01-02Z", .unexpectedCharacter(at: 10)),
    ("2024-032-", .unexpectedCharacter(at: 8)),

    ("2024-01-02T", .unexpectedEnd(at: 11)),
    // Space is a time separator.
    ("2024-01-02 ", .unexpectedEnd(at: 11)),
    ("2024-01-02Tx", .unexpectedCharacter(at: 11)),
    ("2024-01-02T1", .invalidDigitCount(1, at: 11)),
    ("2024-01-02T103", .invalidDigitCount(3, at: 11)),
    ("2024-01-02T1030", .mixedFormats(at: 11)),
    ("2024-01-02T103045", .mixedFormats(at: 11)),
    ("2024-W01-3T1030", .mixedFormats(at: 11)),
    ("2024-01-02T10:", .unexpectedEnd(at: 14)),
    ("2024-01-02T10:3", .invalidDigitCount(1, at: 14)),
    ("2024-01-02T10:304", .invalidDigitCount(3, at: 14)),
    ("2024-01-02T10:30:", .unexpectedEnd(at: 17)),
    ("2024-01-02T10:30:4", .invalidDigitCount(1, at: 17)),
    ("2024-01-02T10:30:45:00", .unexpectedCharacter(at: 19)),
    ("20240102T", .unexpectedEnd(at: 9)),
    ("20240102T1", .invalidDigitCount(1, at: 9)),
    ("20240102T103", .invalidDigitCount(3, at: 9)),
    ("20240102T1030456", .invalidDigitCount(7, at: 9)),
    ("20240102T10:30", .mixedFormats(at: 11)),
    ("20240102T1030:45", .mixedFormats(at: 13)),
    ("2024W013T10:30", .mixedFormats(at: 11)),

    ("2024-01-02T10:30:45.", .unexpectedEnd(at: 20)),
    ("2024-01-02T10,", .unexpectedEnd(at: 14)),
    ("2024-01-02T10:30:45.Z", .unexpectedCharacter(at: 20)),
    ("2024-01-02T10.5:30", .unexpectedCharacter(at: 15)),

    ("2024-01-02T10:30:45+", .unexpectedEnd(at: 20)),
    ("2024-01-02T10:30:45\u{2212}", .unexpectedEnd(at: 22)),
    ("2024-01-02T10:30:45+x", .unexpectedCharacter(at: 20)),
    ("2024-01-02T10:30:45+1", .invalidDigitCount(1, at: 20)),
    ("2024-01-02T10:30:45+013", .invalidDigitCount(3, at: 20)),
    ("2024-01-02T10:30:45+0100", .mixedFormats(at: 20)),
    ("2024-01-02T10:30:45+01:", .unexpectedEnd(at: 23)),
    ("2024-01-02T10:30:45+01:0", .invalidDigitCount(1, at: 23)),
    ("20240102T103045+", .unexpectedEnd(at: 16)),
    ("20240102T103045+1", .invalidDigitCount(1, at: 16)),
    ("20240102T103045+013", .invalidDigitCount(3, at: 16)),
    ("20240102T103045+01:00", .mixedFormats(at: 18)),

    ("2024-01-02T10:30:45Zx", .unexpectedCharacter(at: 20)),
    ("2024-01-02T10:30:45+01:00 ", .unexpectedCharacter(at: 25)),
    ("2024-01-02T10:30:45+01:00:00", .unexpectedCharacter(at: 25)),
    ("2024-01-02T10:30:45\n", .unexpectedCharacter(at: 19)),
    ("2024-01-02T10:30:45\u{2212}05:00x", .unexpectedCharacter(at: 27)),
]

struct LexerTests {
    @Test(arguments: dates)
    func lexesDate(_ input: String, _ expected: RawComponents.DatePart) throws {
        #expect(try lex(input) == RawComponents(expected))
    }

    @Test(arguments: dateTimes)
    func lexesDateTime(_ input: String, _ expected: RawComponents) throws {
        #expect(try lex(input) == expected)
    }

    @Test(arguments: errors)
    func rejects(_ input: String, _ error: ISO8601ParseError) {
        #expect(throws: error) { try lex(input) }
    }
}
