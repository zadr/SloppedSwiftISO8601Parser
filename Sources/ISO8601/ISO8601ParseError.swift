public enum ISO8601ParseError: Error, Hashable, Sendable {
    public enum Component: String, Hashable, Sendable {
        case year, month, day, ordinalDay, week, weekday
        case hour, minute, second
        case offsetHour, offsetMinute
    }

    // Lexical. Positions are UTF-8 byte offsets into the input.
    case unexpectedEnd(at: Int)
    case unexpectedCharacter(at: Int)
    /// A digit run whose length no representation allows, e.g. `202401` (basic `YYYYMM` is not ISO 8601).
    case invalidDigitCount(Int, at: Int)
    /// Basic and extended format combined, e.g. `2024-01-02T1030`.
    case mixedFormats(at: Int)

    // Semantic.
    case outOfRange(Component, value: Int)
    /// Hour 24 with a nonzero minute, second, or fraction.
    case invalidEndOfDay
    /// Second `60` outside 23:59:60 UTC.
    case invalidLeapSecond
}

extension ISO8601ParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unexpectedEnd(let at): "Unexpected end of input at offset \(at)"
        case .unexpectedCharacter(let at): "Unexpected character at offset \(at)"
        case .invalidDigitCount(let count, let at): "Invalid run of \(count) digits at offset \(at)"
        case .mixedFormats(let at): "Basic and extended formats mixed at offset \(at)"
        case .outOfRange(let component, let value): "\(component.rawValue) \(value) out of range"
        case .invalidEndOfDay: "Hour 24 requires zero minutes, seconds, and fraction"
        case .invalidLeapSecond: "Second 60 is valid only at 23:59:60 UTC"
        }
    }
}
