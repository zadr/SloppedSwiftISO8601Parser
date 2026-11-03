import Foundation
import ISO8601
import Testing

private let newYork = TimeZone(identifier: "America/New_York")!

private func parseEachWay(_ input: String, in timeZone: TimeZone = .gmt) throws(ISO8601ParseError) -> [Date] {
    let parser = ISO8601Parser(timeZone: timeZone)
    return try [
        parser.parse(input),
        parser.parse(utf8: input.utf8.span),
        Date(iso8601: input, timeZone: timeZone),
    ]
}

private let wholeSeconds: [(String, TimeInterval)] = [
    ("2024", 1_704_067_200),
    ("2024-02", 1_706_745_600),
    ("2024-01-02", 1_704_153_600),
    ("20240102", 1_704_153_600),
    ("2024-060", 1_709_164_800),
    ("2024060", 1_709_164_800),
    ("2024-366", 1_735_603_200),
    // 2008-12-29.
    ("2009-W01-1", 1_230_508_800),
    ("2009W011", 1_230_508_800),
    // 2005-01-01.
    ("2004-W53-6", 1_104_537_600),
    ("2020-W53", 1_609_113_600),
    // 2021-01-03.
    ("2020W537", 1_609_632_000),
    // 2025-12-29.
    ("2026-W01", 1_766_966_400),
    ("2000-02-29", 951_782_400),
    ("0000-02-29", -62_162_121_600),
    // Proleptic Gregorian; Foundation's Julian reading of this date is 10 days later.
    ("1500-03-01", -14_826_672_000),
    ("19", -2_208_988_800),
    ("198", 315_532_800),
    ("+0019", -2_208_988_800),
    ("+00198", 315_532_800),
    ("+012345-06-07", 327_416_947_200),
    ("-0001-12-31", -62_167_305_600),
    ("\u{2212}0044-03-15", -63_549_360_000),
    ("+002024-01-02", 1_704_153_600),
    ("+0020240102", 1_704_153_600),
    ("-00010102", -62_198_668_800),
    ("-2024W013", -126_038_592_000),
    ("+999999-12-31", 31_494_784_694_400),
    ("-999999", -31_619_087_596_800),

    ("2024-01-02T10Z", 1_704_189_600),
    ("2024-01-02T10:30Z", 1_704_191_400),
    ("2024-01-02T10:30:45Z", 1_704_191_445),
    ("20240102T103045Z", 1_704_191_445),
    ("2024-01-02T10:30:45", 1_704_191_445),
    ("2024-01-02T10:30:45-00:00", 1_704_191_445),
    ("2024-01-02T10:30:45+01:00", 1_704_187_845),
    ("2024-01-02T10:30:45-05:30", 1_704_211_245),
    ("2024-01-02T10:30:45\u{2212}05:30", 1_704_211_245),
    ("20240102T103045+0130", 1_704_186_045),
    ("20240102T103045-08", 1_704_220_245),
    ("2024-366T23:59:59Z", 1_735_689_599),
    ("2024-W01-1T00:00:00Z", 1_704_067_200),
    ("2024W013T1030Z", 1_704_277_800),
    ("2024-01-02T24:00Z", 1_704_240_000),
    ("2024-12-31T24:00:00Z", 1_735_689_600),
    ("2024-01-02T24:00:00.000Z", 1_704_240_000),
    ("2016-12-31T23:59:60Z", 1_483_228_800),
    ("2017-01-01T00:59:60+01:00", 1_483_228_800),
    ("2016-12-31T18:59:60-05:00", 1_483_228_800),
]

private let fractional: [(String, TimeInterval)] = [
    ("2024-01-02T10.5Z", 1_704_191_400),
    ("2024-01-02T10,25", 1_704_190_500),
    ("2024-01-02T10:30.25Z", 1_704_191_415),
    ("2024-01-02T10:30:45,5Z", 1_704_191_445.5),
    ("2024-01-02T10:30:45.050Z", 1_704_191_445.05),
    ("20240102T103045,123456789Z", 1_704_191_445.123456789),
    ("2024-01-02T10:30:45.1234567890123456789Z", 1_704_191_445.123456789012345678),
    ("1969-12-31T23:59:59.5Z", -0.5),
]

private let newYorkCases: [(String, TimeInterval)] = [
    // EST, UTC-5.
    ("2024-01-15T12:00:00", 1_705_338_000),
    // EDT, UTC-4.
    ("2024-07-15T12:00:00", 1_721_059_200),
    ("2024-01-15", 1_705_294_800),
    ("2024", 1_704_085_200),
    ("2024-01-15T12:00:00Z", 1_705_320_000),
    ("2016-12-31T18:59:60", 1_483_228_800),
]

private let errors: [(String, ISO8601ParseError)] = [
    ("", .unexpectedEnd(at: 0)),
    (" 2024-01-02", .unexpectedCharacter(at: 0)),
    ("2024-01-02T10:30:45Z ", .unexpectedCharacter(at: 20)),
    ("202401", .invalidDigitCount(6, at: 0)),
    ("2024-01-02T1030", .mixedFormats(at: 11)),
    ("2024-01-02 10:30:45Z", .unexpectedCharacter(at: 10)),
    ("2024-01-02t10:30:45Z", .unexpectedCharacter(at: 10)),
    ("+2024-01-02", .unexpectedCharacter(at: 5)),
    ("2024-13", .outOfRange(.month, value: 13)),
    ("1900-02-29", .outOfRange(.day, value: 29)),
    ("2023-366", .outOfRange(.ordinalDay, value: 366)),
    ("2021-W53", .outOfRange(.week, value: 53)),
    ("2021W531", .outOfRange(.week, value: 53)),
    ("2020-W01-8", .outOfRange(.weekday, value: 8)),
    ("2024-01-02T25", .outOfRange(.hour, value: 25)),
    ("2024-01-02T10:60", .outOfRange(.minute, value: 60)),
    ("2024-01-02T10:30:61", .outOfRange(.second, value: 61)),
    ("2024-01-02T24:00:01", .invalidEndOfDay),
    ("2024-01-02T24:00:00.5", .invalidEndOfDay),
    ("2016-12-31T23:59:60+01:00", .invalidLeapSecond),
    ("2024-01-02T10:30:45+24:00", .outOfRange(.offsetHour, value: 24)),
    ("2024-01-02T10:30:45+01:60", .outOfRange(.offsetMinute, value: 60)),
]

struct ParserTests {
    @Test(arguments: wholeSeconds)
    func parses(_ input: String, _ expected: TimeInterval) throws {
        for date in try parseEachWay(input) {
            #expect(date.timeIntervalSince1970 == expected)
        }
    }

    @Test(arguments: fractional)
    func parsesFraction(_ input: String, _ expected: TimeInterval) throws {
        for date in try parseEachWay(input) {
            #expect(abs(date.timeIntervalSince1970 - expected) < 1e-6)
        }
    }

    @Test(arguments: newYorkCases)
    func parsesInTimeZone(_ input: String, _ expected: TimeInterval) throws {
        for date in try parseEachWay(input, in: newYork) {
            #expect(date.timeIntervalSince1970 == expected)
        }
    }

    @Test(arguments: errors)
    func rejects(_ input: String, _ error: ISO8601ParseError) {
        #expect(throws: error) { try ISO8601Parser().parse(input) }
        #expect(throws: error) { try ISO8601Parser().parse(utf8: input.utf8.span) }
        #expect(throws: error) { try Date(iso8601: input) }
    }

    @Test func defaultTimeZoneIsGMT() {
        #expect(ISO8601Parser().timeZone == .gmt)
    }

    @Test func parsesSpanSlice() throws {
        let bytes = Array("xx2024-01-02T10:30:45Zyy".utf8)
        let date = try ISO8601Parser().parse(utf8: bytes.span.extracting(2..<22))
        #expect(date.timeIntervalSince1970 == 1_704_191_445)
    }

    @Test func errorOffsetIsRelativeToSpan() {
        let bytes = Array("xx2024T10yy".utf8)
        #expect(throws: ISO8601ParseError.unexpectedCharacter(at: 4)) {
            try ISO8601Parser().parse(utf8: bytes.span.extracting(2..<9))
        }
    }

    @Test func parsesBridgedString() throws {
        // A non-ASCII Cocoa string bridges lazily as UTF-16; parse(_:) must make it contiguous UTF-8.
        let storage: NSString = NSMutableString(string: "\u{2212}0044-03-15")
        let bridged = storage as String
        #expect(try ISO8601Parser().parse(bridged).timeIntervalSince1970 == -63_549_360_000)
    }
}
