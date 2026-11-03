/// Lexical output: fields in a syntactically valid arrangement, values not yet range-checked.
struct RawComponents: Hashable, Sendable {
    enum DatePart: Hashable, Sendable {
        case year(Int)
        case month(year: Int, month: Int)
        case calendar(year: Int, month: Int, day: Int)
        case ordinal(year: Int, day: Int)
        /// `weekday == nil` is the reduced-precision `YYYY-Www` form.
        case week(year: Int, week: Int, weekday: Int?)
    }

    /// `digits / 10^scale` of the lowest-order time component present.
    struct Fraction: Hashable, Sendable {
        var digits: Int
        var scale: Int
    }

    struct TimePart: Hashable, Sendable {
        var hour: Int
        var minute: Int?
        var second: Int?
        var fraction: Fraction?
    }

    enum Offset: Hashable, Sendable {
        case utc
        case fixed(negative: Bool, hours: Int, minutes: Int)
    }

    var date: DatePart
    var time: TimePart?
    var offset: Offset?
}
