import Foundation

/// Single-pass scanner over UTF-8 bytes. Each arm reduces its fields to numbers through `Resolver` as it goes,
/// so only the running result crosses a join.
///
/// Bytes are read through `Window`, sixteen at a time from the arm's start, so each arm addresses its fields
/// at constant offsets; an arm whose fields the window still covers moves it on by shifting rather than
/// loading again. Bytes past the end of input read as 0, which no grammar byte is; `unexpected(at:)` tells
/// the two apart by position.
struct Lexer: ~Copyable, ~Escapable {
    private enum Format { case basic, extended }

    private typealias LocalTime = Resolver.LocalTime
    private typealias Fraction = RawComponents.Fraction

    /// Longest run that cannot overflow `Int`.
    private static let maxDigits = 18

    private let bytes: Span<UInt8>
    /// Index of the byte at `window` offset 0.
    private var position = 0
    private var window: Window
    /// The byte after the date, set by each date arm as it returns.
    private var current = 0

    @inline(always)
    @_lifetime(copy bytes)
    init(_ bytes: Span<UInt8>) {
        self.bytes = bytes
        window = Window(bytes, at: 0)
    }

    /// `zoneOffset` as in `Resolver.resolve(_:zoneOffset:)`.
    @inline(always)
    consuming func lex(zoneOffset: (_ local: Int) -> Int) throws(ISO8601ParseError) -> Date {
        let (midnight, format) = try lexDate()
        // Anything but a time after a full-precision date is the end of input or an invalid continuation;
        // `end()` rejects the latter.
        guard let format, current == .timeDesignator else {
            try end()
            return Resolver.date(midnight: midnight, zoneOffset: zoneOffset)
        }
        position += 1
        reload()
        switch format {
        case .extended:
            return try lexExtendedOffset(lexExtendedTime(midnight: midnight), zoneOffset: zoneOffset)
        case .basic:
            return try lexBasicOffset(lexBasicTime(midnight: midnight), zoneOffset: zoneOffset)
        }
    }
}

// MARK: Window

extension Lexer {
    /// Sixteen bytes of input in two words, byte `i` at bits `8i ..< 8i + 8` of `lo` below 8 and of `hi` from
    /// 8 on, zero past the end of input. The digit words are derived from a word where an arm tests it:
    /// `digits` holds each byte's value as a decimal digit, meaningful where bit 7 of that byte of
    /// `nonDigits` is clear; bit 7 is set in every byte that is not an ASCII digit, and the other bits carry
    /// nothing.
    ///
    /// Every test is for zero bits in a word whose set bits mean the condition fails: the compiler lays the
    /// code for the zero case out first, so the arm that goes on falls through and the one that throws jumps.
    private struct Window {
        var lo: UInt64
        var hi: UInt64
        /// Bytes from offset 0 that come from the input; past them the window reads as past the end of
        /// input, so a digit run reaching them may go on in the input.
        var valid: Int

        /// The window at `position`, which is at most `span.count`. A full window is one range check and
        /// one load; a window reaching past the end takes its upper word, or both, from the last eight
        /// bytes shifted into place, so no byte is read on its own unless the whole input is shorter than
        /// a word.
        @inline(always)
        init(_ span: Span<UInt8>, at position: Int) {
            let count = span.count
            let remaining = count - position
            if remaining >= 16 {
                let w = span.extracting(position ..< position + 16)
                lo = Self.load(w, at: 0)
                hi = Self.load(w, at: 8)
            } else if remaining >= 8 {
                lo = Self.load(span.extracting(position ..< position + 8), at: 0)
                hi = Self.tail(span, keep: remaining - 8)
            } else if count >= 8 {
                lo = Self.tail(span, keep: remaining)
                hi = 0
            } else {
                lo = Self.gather(span, from: position)
                hi = 0
            }
            valid = 16
        }

        @inline(always)
        private init(lo: UInt64, hi: UInt64, valid: Int) {
            self.lo = lo
            self.hi = hi
            self.valid = valid
        }

        @inline(always)
        private static func load(_ w: Span<UInt8>, at i: Int) -> UInt64 {
            UInt64(w[i]) | UInt64(w[i + 1]) << 8 | UInt64(w[i + 2]) << 16 | UInt64(w[i + 3]) << 24
                | UInt64(w[i + 4]) << 32 | UInt64(w[i + 5]) << 40 | UInt64(w[i + 6]) << 48 | UInt64(w[i + 7]) << 56
        }

        /// The last `keep` bytes of `span`, fewer than eight, at offset 0 with the rest zero: the last eight
        /// bytes shifted down. Two shifts of `4 * (8 - keep)` each: the amount is 1...8 bytes and a single
        /// shift by 64 bits would be out of range. The bytes are indexed in `span` itself: at least eight
        /// remain, so the range checks fold and no sub-span is taken.
        @inline(always)
        private static func tail(_ span: Span<UInt8>, keep: Int) -> UInt64 {
            let full = Self.load(span, at: span.count - 8)
            let half = (8 - keep) << 2
            return (full >> half) >> half
        }

        /// An input shorter than a word, from `position` on.
        @inline(never)
        private static func gather(_ span: Span<UInt8>, from position: Int) -> UInt64 {
            var bytes: UInt64 = 0
            var index = span.count
            while index > position {
                index -= 1
                bytes = bytes << 8 | UInt64(span[index])
            }
            return bytes
        }

        /// The window `k` bytes on, with `k` fewer valid bytes.
        @inline(always)
        func dropping(_ k: Int) -> Window {
            let bits = 8 * k
            return Window(lo: lo >> bits | hi << (64 - bits), hi: hi >> bits, valid: valid - k)
        }

        /// The word holding offset `i` and the offset's bit position in it.
        @inline(always)
        private func word(_ i: Int) -> (UInt64, Int) { i < 8 ? (lo, 8 * i) : (hi, 8 * (i - 8)) }

        @inline(always)
        private static func digits(_ w: UInt64) -> UInt64 { w ^ 0x3030_3030_3030_3030 }

        /// `'0'` is 0x30, so a digit is a byte that becomes 0...9. With bit 7 cleared, adding 0x76 sets
        /// bit 7 exactly for values of 10 and above without a carry out of the byte; bit 7 of the byte
        /// itself covers the rest. Bit 0 is cleared too: 0x76 is even, so it never carries, and the mask
        /// stays one the compiler can encode in the instruction once it drops that bit itself.
        @inline(always)
        private static func nonDigits(_ w: UInt64) -> UInt64 {
            let digits = digits(w)
            return ((digits & 0x7E7E_7E7E_7E7E_7E7E) + 0x7676_7676_7676_7676) | digits
        }

        /// Byte `i` is `10 * digit(i) + digit(i + 1)`, meaningful where both are digits; no byte carries into
        /// the next since each term is at most 15 times 10 or 15.
        @inline(always)
        private static func pairs(_ w: UInt64) -> UInt64 {
            let nibbles = w & 0x0F0F_0F0F_0F0F_0F0F
            return (nibbles << 3) + (nibbles << 1) + (nibbles >> 8)
        }

        /// The lower word's decimal values.
        @inline(always)
        var digits: UInt64 { Self.digits(lo) }

        @inline(always)
        func byte(_ i: Int) -> Int {
            let (w, shift) = word(i)
            return Int((w >> shift) & 0xFF)
        }

        @inline(always)
        func digit(_ i: Int) -> Int {
            let (w, shift) = word(i)
            return Int((Self.digits(w) >> shift) & 0xFF)
        }

        /// Bytes `i` and `i + 1` lie in one word: `i` is never 7.
        @inline(always)
        func pair(_ i: Int) -> Int {
            let (w, shift) = word(i)
            return Int((Self.pairs(w) >> shift) & 0xFF)
        }

        @inline(always)
        func isDigit(_ i: Int) -> Bool {
            let (w, shift) = word(i)
            return Self.nonDigits(w) & (0x80 << shift) == 0
        }

        /// `!isDigit(i)` for a word no arm derives `nonDigits` from: one byte tested on its own. The arm
        /// that goes on is the one that jumps.
        @inline(always)
        func nonDigit(_ i: Int) -> Bool { digit(i) > 9 }

        /// `nonDigits` of the lower word from offset `i`, bytes past 7 from the upper.
        @inline(always)
        private func nonDigits(from i: Int) -> UInt64 {
            Self.nonDigits(lo) >> (8 * i) | Self.nonDigits(hi) << (64 - 8 * i)
        }

        /// Bit 7 of byte `i` is set when byte `i` or `i + 1` is not a digit.
        @inline(always)
        private var nonPairs: UInt64 { Self.nonDigits(lo) | nonDigits(from: 1) }

        /// For `i` below 8.
        @inline(always)
        func hasPair(_ i: Int) -> Bool { nonPairs & (0x80 << (8 * i)) == 0 }

        /// Bytes `i` and `i + 1` are digits and byte `i + 2` is not, for `i` below 8.
        @inline(always)
        func exactPair(_ i: Int) -> Bool { (nonPairs | ~nonDigits(from: 2)) & (0x80 << (8 * i)) == 0 }

        /// Byte `i` is a digit and byte `i + 1` is not, for `i` below 8.
        @inline(always)
        func exactDigit(_ i: Int) -> Bool { (Self.nonDigits(lo) | ~nonDigits(from: 1)) & (0x80 << (8 * i)) == 0 }

        /// Digits from offset `i` on within its word; `8 - i` when they reach the word's end, where the run
        /// may continue. The word is shifted before the digit test so what the compiler knows of the bytes
        /// below `i` cannot leak into the test's constants.
        @inline(always)
        func run(_ i: Int) -> Int {
            let (w, shift) = word(i)
            return (Self.nonDigits(w >> shift) & 0x8080_8080_8080_8080).trailingZeroBitCount >> 3
        }

        /// Digits from offset `i`, below 8, on; `16 - i` when they reach the end of the window.
        @inline(always)
        func digitRun(from i: Int) -> Int {
            let low = run(i)
            return low < 8 - i ? low : 8 - i + run(8)
        }
    }

    @inline(always)
    private mutating func reload() {
        window = Window(bytes, at: position)
    }

    /// Ends a date arm `k` bytes into its window.
    @inline(always)
    private mutating func advance(_ k: Int) {
        position += k
        current = window.byte(k)
    }
}

// MARK: Date

extension Lexer {
    /// `midnight` is the start of the day in seconds since the reference date. `format` is nil for
    /// reduced-precision dates, which cannot be followed by a time.
    private typealias LexedDate = (midnight: Int, format: Format?)
    private typealias Year = CivilCalendar.Year

    /// The grammar is pairs of digits, `YY` through `YYYYMMDD`, a decade or an ordinal day ending in one
    /// digit; expanded representations carry exactly two extra year digits, so `+` always means expanded
    /// (`+0019` is century 19) and `-` with four digits is a plain negative year (`-0001`). The run's length
    /// with the sign selects the form; a run filling the word continues in the next one. Each value is
    /// bounded by its pair, so nothing is checked or divided to split it.
    @inline(always)
    private mutating func lexDate() throws(ISO8601ParseError) -> LexedDate {
        var count = window.run(0)
        var negative: Bool? = nil
        // A sign is read only where the run is empty, so the signed arm's work stays off the other.
        if count == 0 {
            negative = consumeSign(reach: 8)
            count = window.run(0)
        }
        let start = position
        guard count >= 2 else { throw count == 0 ? unexpected(at: 0) : .invalidDigitCount(1, at: start) }
        let p1 = window.pair(0)
        guard count >= 4 else {
            // `YY`, `YYY`
            guard negative == nil else { throw .invalidDigitCount(count, at: start) }
            position += count
            let yearOfCentury = count == 3 ? window.digit(2) * 10 : 0
            return (Resolver.startOfYear(Year(century: p1, yearOfCentury: yearOfCentury)), nil)
        }
        let p2 = window.pair(2)
        var year = Year(century: p1, yearOfCentury: p2)
        if count < 6 {
            guard count == 4 else {
                // `±YYYYY` decade
                guard let negative else { throw .invalidDigitCount(5, at: start) }
                position += 5
                let expanded = Year(century: p1 * 100 + p2, yearOfCentury: window.digit(4) * 10)
                return (Resolver.startOfYear(negative ? expanded.negated : expanded), nil)
            }
            if let negative {
                // `+YYYY` century
                guard negative else {
                    position += 4
                    return (Resolver.startOfYear(Year(century: p1 * 100 + p2, yearOfCentury: 0)), nil)
                }
                // `-YYYY`
                year = year.negated
            }
        } else {
            let p3 = window.pair(4)
            if count == 6 {
                // `±YYYYYY`: the window moves up two so the separator sits at offset 4 as after `YYYY`.
                guard let negative else { throw .invalidDigitCount(6, at: start) }
                let expanded = Year(century: p1 * 100 + p2, yearOfCentury: p3)
                year = negative ? expanded.negated : expanded
                skip(2, reach: 5)
            } else if count == 7 {
                // `YYYYDDD`, `-YYYYDDD`
                guard negative != false else { throw .invalidDigitCount(7, at: start) }
                let day = p3 * 10 + window.digit(6)
                advance(7)
                return (try Resolver.ordinalDay(year: negative == true ? year.negated : year, day: day), .basic)
            } else {
                let p4 = window.pair(6)
                skip(8, reach: 3)
                switch (negative, window.run(0)) {
                case (nil, 0), (true, 0):
                    // `YYYYMMDD`, `-YYYYMMDD`
                    let midnight = try Resolver.calendarDay(
                        year: negative == true ? year.negated : year, month: p3, day: p4
                    )
                    advance(0)
                    return (midnight, .basic)
                case (let negative?, 1):
                    // `±YYYYYYDDD`
                    let expanded = Year(century: p1 * 100 + p2, yearOfCentury: p3)
                    let day = p4 * 10 + window.digit(0)
                    advance(1)
                    return (try Resolver.ordinalDay(year: negative ? expanded.negated : expanded, day: day), .basic)
                case (let negative?, 2):
                    // `±YYYYYYMMDD`
                    let expanded = Year(century: p1 * 100 + p2, yearOfCentury: p3)
                    let midnight = try Resolver.calendarDay(
                        year: negative ? expanded.negated : expanded, month: p4, day: window.pair(0)
                    )
                    advance(2)
                    return (midnight, .basic)
                default:
                    throw .invalidDigitCount(8 + digitCount(at: 0), at: start)
                }
            }
        }

        let separator = window.byte(4)
        if separator == .hyphen {
            skip(5, reach: 6)
            return try lexExtendedDate(year: year)
        }
        if separator == .weekDesignator {
            skip(5, reach: 4)
            return try lexBasicWeekDate(year: year)
        }
        position += 4
        guard position == bytes.count else { throw .unexpectedCharacter(at: position) }
        return (Resolver.startOfYear(year), nil)
    }

    /// The window starts after the hyphen.
    @inline(always)
    private mutating func lexExtendedDate(year: Year) throws(ISO8601ParseError) -> LexedDate {
        if window.byte(0) == .weekDesignator {
            guard window.exactPair(1) else {
                let count = digitCount(at: 1)
                throw count == 3 ? .mixedFormats(at: position + 1) : invalidRun(count, at: 1)
            }
            let week = window.pair(1)
            guard window.byte(3) == .hyphen else {
                advance(3)
                return (try Resolver.weekDay(year: year, week: week, weekday: 1), nil)
            }
            guard window.exactDigit(4) else {
                throw window.isDigit(4) ? .invalidDigitCount(digitCount(at: 4), at: position + 4) : unexpected(at: 4)
            }
            let weekday = window.digit(4)
            advance(5)
            return (try Resolver.weekDay(year: year, week: week, weekday: weekday), .extended)
        }

        guard window.hasPair(0) else { throw invalidRun(at: 0) }
        if window.isDigit(2) {
            guard window.exactDigit(2) else { throw .invalidDigitCount(digitCount(at: 0), at: position) }
            let day = window.pair(0) * 10 + window.digit(2)
            advance(3)
            return (try Resolver.ordinalDay(year: year, day: day), .extended)
        }
        let month = window.pair(0)
        guard window.byte(2) == .hyphen else {
            advance(2)
            return (try Resolver.startOfMonth(year: year, month: month), nil)
        }
        guard window.exactPair(3) else { throw invalidRun(at: 3) }
        let day = window.pair(3)
        advance(5)
        return (try Resolver.calendarDay(year: year, month: month, day: day), .extended)
    }

    /// The window starts after the `W`.
    @inline(always)
    private mutating func lexBasicWeekDate(year: Year) throws(ISO8601ParseError) -> LexedDate {
        guard window.hasPair(0) else { throw invalidRun(at: 0) }
        let week = window.pair(0)
        guard window.isDigit(2) else {
            if window.byte(2) == .hyphen { throw .mixedFormats(at: position + 2) }
            advance(2)
            return (try Resolver.weekDay(year: year, week: week, weekday: 1), nil)
        }
        guard window.exactDigit(2) else { throw .invalidDigitCount(digitCount(at: 0), at: position) }
        let weekday = window.digit(2)
        advance(3)
        return (try Resolver.weekDay(year: year, week: week, weekday: weekday), .basic)
    }
}

// MARK: Time

extension Lexer {
    /// The window starts at the hour. One compare bounds the hour and splits off hour 24. The fraction and
    /// offset arms read at most eight bytes after the time, so the window moves on to them by shifting.
    @inline(always)
    private mutating func lexExtendedTime(midnight: Int) throws(ISO8601ParseError) -> LocalTime {
        guard window.exactPair(0) else {
            let count = digitCount(at: 0)
            throw count == 4 || count == 6 ? .mixedFormats(at: position) : invalidRun(count, at: 0)
        }
        let hour = window.pair(0)
        guard hour < 24 else {
            guard hour == 24 else { throw .outOfRange(.hour, value: hour) }
            return try lexExtendedEndOfDay(midnight: midnight)
        }
        guard window.byte(2) == .colon else {
            skip(2, reach: 8)
            return Resolver.localTime(midnight: midnight, seconds: hour * 3600, second: 0, fraction: try fraction(), unit: 3600)
        }
        guard window.exactPair(3) else { throw invalidRun(at: 3) }
        let minute = window.pair(3)
        try Resolver.validate(.minute, minute, in: 0...59)
        let minutes = (hour * 60 + minute) * 60
        guard window.byte(5) == .colon else {
            skip(5, reach: 8)
            return Resolver.localTime(midnight: midnight, seconds: minutes, second: 0, fraction: try fraction(), unit: 60)
        }
        guard window.hasPair(6) else { throw invalidRun(at: 6) }
        let second = window.pair(6)
        let seconds = minutes + second
        skip(8, reach: 8)
        guard window.nonDigit(0) else { throw .invalidDigitCount(2 + digitCount(at: 0), at: position - 8) }
        try Resolver.validate(.second, second, in: 0...60)
        return Resolver.localTime(midnight: midnight, seconds: seconds, second: second, fraction: try fraction(), unit: 1)
    }

    /// After hour 24, every component must be zero.
    @inline(always)
    private mutating func lexExtendedEndOfDay(midnight: Int) throws(ISO8601ParseError) -> LocalTime {
        if window.byte(2) == .colon {
            guard window.exactPair(3) else { throw invalidRun(at: 3) }
            guard window.pair(3) == 0 else { throw .invalidEndOfDay }
            if window.byte(5) == .colon {
                guard window.hasPair(6) else { throw invalidRun(at: 6) }
                let second = window.pair(6)
                skip(8, reach: 8)
                guard window.nonDigit(0) else { throw .invalidDigitCount(2 + digitCount(at: 0), at: position - 8) }
                guard second == 0 else { throw .invalidEndOfDay }
            } else {
                skip(5, reach: 8)
            }
        } else {
            skip(2, reach: 8)
        }
        return try endOfDay(midnight: midnight)
    }

    @inline(always)
    private mutating func lexBasicTime(midnight: Int) throws(ISO8601ParseError) -> LocalTime {
        switch window.run(0) {
        case 2:
            if window.byte(2) == .colon { throw .mixedFormats(at: position + 2) }
            let hour = window.pair(0)
            skip(2, reach: 8)
            guard hour < 24 else {
                guard hour == 24 else { throw .outOfRange(.hour, value: hour) }
                return try endOfDay(midnight: midnight)
            }
            return Resolver.localTime(midnight: midnight, seconds: hour * 3600, second: 0, fraction: try fraction(), unit: 3600)
        case 4:
            if window.byte(4) == .colon { throw .mixedFormats(at: position + 4) }
            let hour = window.pair(0)
            let minute = window.pair(2)
            skip(4, reach: 8)
            guard hour < 24 else {
                guard hour == 24 else { throw .outOfRange(.hour, value: hour) }
                guard minute == 0 else { throw .invalidEndOfDay }
                return try endOfDay(midnight: midnight)
            }
            try Resolver.validate(.minute, minute, in: 0...59)
            return Resolver.localTime(
                midnight: midnight, seconds: (hour * 60 + minute) * 60, second: 0, fraction: try fraction(), unit: 60
            )
        case 6:
            if window.byte(6) == .colon { throw .mixedFormats(at: position + 6) }
            let hour = window.pair(0)
            let minute = window.pair(2)
            let second = window.pair(4)
            skip(6, reach: 8)
            guard hour < 24 else {
                guard hour == 24 else { throw .outOfRange(.hour, value: hour) }
                guard minute == 0, second == 0 else { throw .invalidEndOfDay }
                return try endOfDay(midnight: midnight)
            }
            try Resolver.validate(.minute, minute, in: 0...59)
            try Resolver.validate(.second, second, in: 0...60)
            return Resolver.localTime(
                midnight: midnight, seconds: (hour * 60 + minute) * 60 + second, second: second, fraction: try fraction(), unit: 1
            )
        case 0:
            throw unexpected(at: 0)
        default:
            throw .invalidDigitCount(digitCount(at: 0), at: position)
        }
    }

    /// The end of day once its whole components are known to be zero.
    @inline(always)
    private mutating func endOfDay(midnight: Int) throws(ISO8601ParseError) -> LocalTime {
        guard try fraction().digits == 0 else { throw .invalidEndOfDay }
        return Resolver.endOfDay(midnight)
    }

    /// The fraction introduced by `.` or `,` at the window's start, or none. Keeps the first `maxDigits`
    /// digits and consumes the rest, leaving a fresh window at the byte after.
    @inline(always)
    private mutating func fraction() throws(ISO8601ParseError) -> Fraction {
        // `,` is `.` with one bit cleared, so one compare admits both and no chain forms with the caller's tests.
        if window.byte(0) | 2 != .period { return Fraction(digits: 0, power: 1) }
        let count = window.run(1)
        guard count != 0 else { throw unexpected(at: 1) }
        var digits = 0
        var power = 1
        // The digits sit at offsets 1...7; a step per offset keeps each value within the one before's bound.
        for offset in 1 ... 7 {
            guard offset <= count else { break }
            digits = digits * 10 + window.digit(offset)
            power *= 10
        }
        position += 1 + count
        if count == 7 {
            let rest = Self.continueFraction(bytes, from: position, digits, power, kept: count)
            position = rest.end
            reload()
            return Fraction(digits: rest.digits, power: rest.power)
        }
        reload()
        return Fraction(digits: digits, power: power)
    }

    /// The rest of a fraction that fills its first word.
    @inline(never)
    private static func continueFraction(
        _ bytes: Span<UInt8>, from start: Int, _ digits: Int, _ power: Int, kept: Int
    ) -> (digits: Int, power: Int, end: Int) {
        var digits = digits
        var power = power
        var kept = kept
        var position = start
        while true {
            let window = Window(bytes, at: position)
            let run = window.run(0)
            let taken = min(run, maxDigits - kept)
            var source = window.digits
            for _ in 0 ..< taken {
                digits = digits * 10 + Int(source & 0xFF)
                power *= 10
                source >>= 8
            }
            kept += taken
            position += run
            if run < 8 { return (digits, power, position) }
        }
    }
}

// MARK: Offset

extension Lexer {
    /// The window starts at the offset. Each arm produces the instant itself so nothing meets at a join. The
    /// end of input is checked before the offset's values, so lexical errors keep precedence within the offset.
    @inline(always)
    private mutating func lexExtendedOffset(
        _ time: LocalTime, zoneOffset: (_ local: Int) -> Int
    ) throws(ISO8601ParseError) -> Date {
        let local = time.seconds
        if window.byte(0) == .utcDesignator {
            position += 1
            try end()
            return try Resolver.date(utc: local, time)
        }
        guard let negative = consumeSign(reach: 6) else {
            try end()
            return try Resolver.date(utc: local - zoneOffset(local), time)
        }
        guard window.exactPair(0) else {
            let count = digitCount(at: 0)
            throw count == 4 ? .mixedFormats(at: position) : invalidRun(count, at: 0)
        }
        let hours = window.pair(0)
        guard window.byte(2) == .colon else {
            position += 2
            try end()
            return try Resolver.date(utc: Resolver.utc(local, negative: negative, hours: hours, minutes: 0), time)
        }
        guard window.exactPair(3) else { throw invalidRun(at: 3) }
        let minutes = window.pair(3)
        position += 5
        try end()
        return try Resolver.date(utc: Resolver.utc(local, negative: negative, hours: hours, minutes: minutes), time)
    }

    @inline(always)
    private mutating func lexBasicOffset(
        _ time: LocalTime, zoneOffset: (_ local: Int) -> Int
    ) throws(ISO8601ParseError) -> Date {
        let local = time.seconds
        if window.byte(0) == .utcDesignator {
            position += 1
            try end()
            return try Resolver.date(utc: local, time)
        }
        guard let negative = consumeSign(reach: 6) else {
            try end()
            return try Resolver.date(utc: local - zoneOffset(local), time)
        }
        switch window.run(0) {
        case 2:
            if window.byte(2) == .colon { throw .mixedFormats(at: position + 2) }
            let hours = window.pair(0)
            position += 2
            try end()
            return try Resolver.date(utc: Resolver.utc(local, negative: negative, hours: hours, minutes: 0), time)
        case 4:
            let hours = window.pair(0)
            let minutes = window.pair(2)
            position += 4
            try end()
            return try Resolver.date(utc: Resolver.utc(local, negative: negative, hours: hours, minutes: minutes), time)
        case 0:
            throw unexpected(at: 0)
        default:
            throw .invalidDigitCount(digitCount(at: 0), at: position)
        }
    }
}

// MARK: Scanning primitives

extension Lexer {
    @inline(always)
    private func end() throws(ISO8601ParseError) {
        guard position == bytes.count else { throw .unexpectedCharacter(at: position) }
    }

    /// `nil` when no sign is present, otherwise whether the sign is negative. The window then starts after
    /// it: moved on when the valid bytes left in it cover `reach`, the caller's furthest read, else reloaded.
    @inline(always)
    private mutating func consumeSign(reach: Int) -> Bool? {
        let byte = window.byte(0)
        // `+` is 0x2B and `-` 0x2D: one test admits both, and it is not a comparison of the byte itself,
        // so a caller's test of the same byte stays a separate compare rather than joining it in a search tree.
        let sign = byte - .plus
        if sign & ~2 == 0 {
            skip(1, reach: reach)
            return sign != 0
        }
        guard byte != 0xE2 else {
            // U+2212 MINUS SIGN
            guard window.lo & 0xFF_FFFF == 0x92_88E2 else { return nil }
            skip(3, reach: reach)
            return true
        }
        return nil
    }

    /// Moves `k` bytes on: by shifting the window when the valid bytes left in it cover `reach`, the next
    /// arm's furthest read, else by loading it again. Both operands are constants at every call.
    @inline(always)
    private mutating func skip(_ k: Int, reach: Int) {
        position += k
        if window.valid - k >= reach { window = window.dropping(k) } else { reload() }
    }

    /// The byte at window offset `i`, which is at most the end of input.
    @inline(always)
    private func unexpected(at i: Int) -> ISO8601ParseError {
        let at = position + i
        return at == bytes.count ? .unexpectedEnd(at: at) : .unexpectedCharacter(at: at)
    }

    /// A digit run at offset `i` of the wrong width: its full count, or `unexpected` for none. Inlined with
    /// `unexpected` so no arm that throws needs the lexer in memory.
    @inline(always)
    private func invalidRun(at i: Int) -> ISO8601ParseError {
        invalidRun(digitCount(at: i), at: i)
    }

    @inline(always)
    private func invalidRun(_ count: Int, at i: Int) -> ISO8601ParseError {
        count == 0 ? unexpected(at: i) : .invalidDigitCount(count, at: position + i)
    }

    /// The whole digit run at offset `i`, however far past the window it reaches: counted afresh from the
    /// input, so the arms that throw take nothing from the window.
    @inline(always)
    private func digitCount(at i: Int) -> Int {
        Self.countDigits(bytes, from: position + i)
    }

    @inline(never)
    private static func countDigits(_ bytes: Span<UInt8>, from start: Int) -> Int {
        var position = start
        while true {
            let run = Window(bytes, at: position).digitRun(from: 0)
            position += run
            if run < 16 { return position - start }
        }
    }
}

extension Int {
    fileprivate static let plus = Int(UInt8(ascii: "+"))
    fileprivate static let hyphen = Int(UInt8(ascii: "-"))
    fileprivate static let colon = Int(UInt8(ascii: ":"))
    fileprivate static let period = Int(UInt8(ascii: "."))
    fileprivate static let timeDesignator = Int(UInt8(ascii: "T"))
    fileprivate static let weekDesignator = Int(UInt8(ascii: "W"))
    fileprivate static let utcDesignator = Int(UInt8(ascii: "Z"))
}
