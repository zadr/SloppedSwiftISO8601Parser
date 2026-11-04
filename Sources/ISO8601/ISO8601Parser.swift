public import Foundation

/// Parses ISO 8601-1:2019 date and date-time representations into `Date`.
///
/// Date (required):
///
///     Calendar   YYYY-MM-DD  YYYYMMDD  YYYY-MM
///     Ordinal    YYYY-DDD    YYYYDDD
///     Week       YYYY-Www-D  YYYYWwwD  YYYY-Www  YYYYWww
///     Year       YYYY
///     Decade     YYY
///     Century    YY
///
/// Expanded representations add a sign (`+`, `-`, U+2212) and exactly two digits: `±YYYYYY`,
/// `±YYYYY` (decade), `±YYYY` (century). A minus sign with four digits is a plain negative year,
/// so `-0001` is year -1 and `+0019` is century 19.
///
/// Time (optional, only after a complete date), introduced by `T`.
/// Must use the same format (basic or extended) as the date.
///
///     hh  hh:mm  hh:mm:ss  hhmm  hhmmss
///
/// The last time component may carry a fraction introduced by `.` or `,`.
/// `24:00` is the start of the next day. Second `60` is accepted only at 23:59:60 UTC.
///
/// Offset (optional, only after a time): `Z`, `±hh`, `±hh:mm`, `±hhmm`.
///
/// Values without an offset, including date-only values, are resolved in ``timeZone``.
/// Reduced-precision dates resolve to the first day of the period. Dates use the proleptic
/// Gregorian calendar, unlike `Calendar(identifier: .gregorian)`, which switches to Julian before 1582-10-15.
public struct ISO8601Parser: Hashable, Sendable {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .gmt) {
        self.timeZone = timeZone
    }

    public func parse(_ string: borrowing String) throws(ISO8601ParseError) -> Date {
        try parse(utf8: string.utf8.span)
    }

    @inline(__always)
    public func parse(utf8 bytes: Span<UInt8>) throws(ISO8601ParseError) -> Date {
        try Lexer(bytes).lex { Resolver.zoneOffset(atLocal: $0, in: timeZone) }
    }
}

extension Date {
    public init(iso8601 string: borrowing String, timeZone: TimeZone = .gmt) throws(ISO8601ParseError) {
        self = try Lexer(string.utf8.span).lex { Resolver.zoneOffset(atLocal: $0, in: timeZone) }
    }
}
