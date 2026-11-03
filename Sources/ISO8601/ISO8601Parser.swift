public import Foundation

/// Parses ISO 8601-1:2019 date and date-time representations into `Date`.
///
/// Date (required). `YYYY` may be an expanded year: sign (`+`, `-`, U+2212) and 4+ digits,
/// usable in extended forms, basic week forms, or alone.
///
///     Calendar   YYYY-MM-DD  YYYYMMDD  YYYY-MM
///     Ordinal    YYYY-DDD    YYYYDDD
///     Week       YYYY-Www-D  YYYYWwwD  YYYY-Www  YYYYWww
///     Year       YYYY
///
/// Time (optional, only after a complete date). Separator `T`, `t`, or space.
/// Must use the same format (basic or extended) as the date.
///
///     hh  hh:mm  hh:mm:ss  hhmm  hhmmss
///
/// The last time component may carry a fraction introduced by `.` or `,`.
/// `24:00` is the start of the next day. Second `60` is accepted only at 23:59:60 UTC.
///
/// Offset (optional, only after a time): `Z`, `z`, `±hh`, `±hh:mm`, `±hhmm`.
///
/// Values without an offset, including date-only values, are resolved in ``timeZone``.
/// Reduced-precision dates resolve to the first day of the period. Dates use the proleptic
/// Gregorian calendar, unlike `Calendar(identifier: .gregorian)`, which switches to Julian before 1582-10-15.
public struct ISO8601Parser: Hashable, Sendable {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .gmt) {
        self.timeZone = timeZone
    }

    public func parse(_ string: consuming String) throws(ISO8601ParseError) -> Date {
        string.makeContiguousUTF8()
        return try parse(utf8: string.utf8.span)
    }

    public func parse(utf8 bytes: Span<UInt8>) throws(ISO8601ParseError) -> Date {
        let components = try Lexer(bytes).lex()
        return try Resolver(timeZone: timeZone).resolve(components)
    }
}

extension Date {
    public init(iso8601 string: consuming String, timeZone: TimeZone = .gmt) throws(ISO8601ParseError) {
        self = try ISO8601Parser(timeZone: timeZone).parse(string)
    }
}
