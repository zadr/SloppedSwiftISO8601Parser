/// Fields of a representation, not range-checked; the test-only input to `Resolver.resolve(_:zoneOffset:)`.
struct RawComponents: Hashable, Sendable {
    enum DatePart: Hashable, Sendable {
        /// `19` is 1900 through 1999.
        case century(Int)
        /// `198` is 1980 through 1989.
        case decade(Int)
        case year(Int)
        case month(year: Int, month: Int)
        case calendar(year: Int, month: Int, day: Int)
        case ordinal(year: Int, day: Int)
        /// `weekday == nil` is the reduced-precision `YYYY-Www` form.
        case week(year: Int, week: Int, weekday: Int?)
    }

    /// `digits / power` of the lowest-order time component present; `power` is 10 to the digit count.
    /// `Fraction(digits: 0, power: 1)` means no fraction.
    struct Fraction: Hashable, Sendable {
        var digits: Int
        var power: Int
    }

    struct TimePart: Hashable, Sendable {
        /// Lowest-order component present. Absent components are 0.
        enum Precision: Hashable, Sendable { case hour, minute, second }
        var hour: Int
        var minute = 0
        var second = 0
        var fraction = Fraction(digits: 0, power: 1)
        var precision = Precision.hour
    }

    enum Offset: Hashable, Sendable {
        case utc
        case fixed(negative: Bool, hours: Int, minutes: Int)
    }

    var date: DatePart
    var time: TimePart?
    var offset: Offset?
}
