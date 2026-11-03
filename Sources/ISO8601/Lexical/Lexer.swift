/// Single-pass scanner over UTF-8 bytes. Recognizes structure only; `Resolver` range-checks values.
struct Lexer: ~Copyable, ~Escapable {
    private enum Format { case basic, extended }

    private struct DigitRun {
        var value = 0
        var count = 0
        var start: Int
    }

    /// Longest run that cannot overflow `Int`.
    private static let maxDigits = 18

    private let bytes: Span<UInt8>
    private var position = 0

    @_lifetime(copy bytes)
    init(_ bytes: Span<UInt8>) {
        self.bytes = bytes
    }

    consuming func lex() throws(ISO8601ParseError) -> RawComponents {
        let (date, format) = try lexDate()
        var components = RawComponents(date: date)
        guard !isAtEnd else { return components }
        guard let format, consume(.uppercaseT) || consume(.lowercaseT) || consume(.space) else {
            throw .unexpectedCharacter(at: position)
        }
        components.time = try lexTime(format)
        components.offset = try lexOffset(format)
        guard isAtEnd else { throw .unexpectedCharacter(at: position) }
        return components
    }
}

// MARK: Date

extension Lexer {
    /// `format` is nil for reduced-precision dates, which cannot be followed by a time.
    private typealias LexedDate = (date: RawComponents.DatePart, format: Format?)

    private mutating func lexDate() throws(ISO8601ParseError) -> LexedDate {
        let negative = consumeSign()
        let run = try digits()
        let year: Int
        switch (negative, run.count) {
        case (nil, 4):
            year = run.value
        case (nil, 7):
            return (.ordinal(year: run.value / 1000, day: run.value % 1000), .basic)
        case (nil, 8):
            return (.calendar(year: run.value / 10000, month: run.value / 100 % 100, day: run.value % 100), .basic)
        case (let negative?, 4...):
            year = negative ? -run.value : run.value
        default:
            throw .invalidDigitCount(run.count, at: run.start)
        }

        if isAtEnd { return (.year(year), nil) }
        if consume(.hyphen) { return try lexExtendedDate(year: year) }
        if consume(.uppercaseW) { return try lexBasicWeekDate(year: year) }
        throw .unexpectedCharacter(at: position)
    }

    private mutating func lexExtendedDate(year: Int) throws(ISO8601ParseError) -> LexedDate {
        if consume(.uppercaseW) {
            let week = try digits()
            switch week.count {
            case 2: break
            case 3: throw .mixedFormats(at: week.start)
            default: throw .invalidDigitCount(week.count, at: week.start)
            }
            guard consume(.hyphen) else { return (.week(year: year, week: week.value, weekday: nil), nil) }
            return (.week(year: year, week: week.value, weekday: try digits(count: 1)), .extended)
        }

        let run = try digits()
        switch run.count {
        case 2:
            guard consume(.hyphen) else { return (.month(year: year, month: run.value), nil) }
            return (.calendar(year: year, month: run.value, day: try digits(count: 2)), .extended)
        case 3:
            return (.ordinal(year: year, day: run.value), .extended)
        default:
            throw .invalidDigitCount(run.count, at: run.start)
        }
    }

    private mutating func lexBasicWeekDate(year: Int) throws(ISO8601ParseError) -> LexedDate {
        let run = try digits()
        switch run.count {
        case 2:
            if peek == .hyphen { throw .mixedFormats(at: position) }
            return (.week(year: year, week: run.value, weekday: nil), nil)
        case 3:
            return (.week(year: year, week: run.value / 10, weekday: run.value % 10), .basic)
        default:
            throw .invalidDigitCount(run.count, at: run.start)
        }
    }
}

// MARK: Time and offset

extension Lexer {
    private mutating func lexTime(_ format: Format) throws(ISO8601ParseError) -> RawComponents.TimePart {
        let run = try digits()
        var time: RawComponents.TimePart
        switch (format, run.count) {
        case (_, 2):
            time = .init(hour: run.value)
        case (.basic, 4):
            time = .init(hour: run.value / 100, minute: run.value % 100)
        case (.basic, 6):
            time = .init(hour: run.value / 10000, minute: run.value / 100 % 100, second: run.value % 100)
        case (.extended, 4), (.extended, 6):
            throw .mixedFormats(at: run.start)
        default:
            throw .invalidDigitCount(run.count, at: run.start)
        }

        switch format {
        case .extended:
            if consume(.colon) {
                time.minute = try digits(count: 2)
                if consume(.colon) { time.second = try digits(count: 2) }
            }
        case .basic:
            if peek == .colon { throw .mixedFormats(at: position) }
        }

        if consume(.period) || consume(.comma) { time.fraction = try fraction() }
        return time
    }

    private mutating func lexOffset(_ format: Format) throws(ISO8601ParseError) -> RawComponents.Offset? {
        if consume(.uppercaseZ) || consume(.lowercaseZ) { return .utc }
        guard let negative = consumeSign() else { return nil }
        let run = try digits()
        switch (format, run.count) {
        case (.extended, 2):
            let minutes = try consume(.colon) ? digits(count: 2) : 0
            return .fixed(negative: negative, hours: run.value, minutes: minutes)
        case (.basic, 2):
            if peek == .colon { throw .mixedFormats(at: position) }
            return .fixed(negative: negative, hours: run.value, minutes: 0)
        case (.basic, 4):
            return .fixed(negative: negative, hours: run.value / 100, minutes: run.value % 100)
        case (.extended, 4):
            throw .mixedFormats(at: run.start)
        default:
            throw .invalidDigitCount(run.count, at: run.start)
        }
    }

    /// Keeps the first `maxDigits` digits; later ones are below any representable precision.
    private mutating func fraction() throws(ISO8601ParseError) -> RawComponents.Fraction {
        var fraction = RawComponents.Fraction(digits: 0, scale: 0)
        let start = position
        while let digit = peekDigit {
            position += 1
            guard fraction.scale < Self.maxDigits else { continue }
            fraction.digits = fraction.digits * 10 + digit
            fraction.scale += 1
        }
        guard position > start else { throw unexpected() }
        return fraction
    }
}

// MARK: Scanning primitives

extension Lexer {
    private var isAtEnd: Bool { position == bytes.count }

    private var peek: UInt8? { isAtEnd ? nil : bytes[position] }

    private var peekDigit: Int? {
        guard let byte = peek, (UInt8.digit0...UInt8.digit9).contains(byte) else { return nil }
        return Int(byte - .digit0)
    }

    private func unexpected() -> ISO8601ParseError {
        isAtEnd ? .unexpectedEnd(at: position) : .unexpectedCharacter(at: position)
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        position += 1
        return true
    }

    /// `nil` when no sign is present, otherwise whether the sign is negative.
    private mutating func consumeSign() -> Bool? {
        if consume(.plus) { return false }
        if consume(.hyphen) { return true }
        // U+2212 MINUS SIGN
        guard bytes.count - position >= 3,
              bytes[position] == 0xE2, bytes[position + 1] == 0x88, bytes[position + 2] == 0x92
        else { return nil }
        position += 3
        return true
    }

    private mutating func digits() throws(ISO8601ParseError) -> DigitRun {
        var run = DigitRun(start: position)
        while let digit = peekDigit {
            position += 1
            run.count += 1
            if run.count <= Self.maxDigits { run.value = run.value * 10 + digit }
        }
        guard run.count > 0 else { throw unexpected() }
        guard run.count <= Self.maxDigits else { throw .invalidDigitCount(run.count, at: run.start) }
        return run
    }

    private mutating func digits(count: Int) throws(ISO8601ParseError) -> Int {
        let run = try digits()
        guard run.count == count else { throw .invalidDigitCount(run.count, at: run.start) }
        return run.value
    }
}

extension UInt8 {
    fileprivate static let digit0 = UInt8(ascii: "0")
    fileprivate static let digit9 = UInt8(ascii: "9")
    fileprivate static let plus = UInt8(ascii: "+")
    fileprivate static let hyphen = UInt8(ascii: "-")
    fileprivate static let colon = UInt8(ascii: ":")
    fileprivate static let period = UInt8(ascii: ".")
    fileprivate static let comma = UInt8(ascii: ",")
    fileprivate static let space = UInt8(ascii: " ")
    fileprivate static let uppercaseT = UInt8(ascii: "T")
    fileprivate static let lowercaseT = UInt8(ascii: "t")
    fileprivate static let uppercaseW = UInt8(ascii: "W")
    fileprivate static let uppercaseZ = UInt8(ascii: "Z")
    fileprivate static let lowercaseZ = UInt8(ascii: "z")
}
