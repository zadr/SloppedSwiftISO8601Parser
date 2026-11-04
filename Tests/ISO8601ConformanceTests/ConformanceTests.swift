import Foundation
@testable import ISO8601
import Testing

@Suite("CalConnect ISO 8601 conformance")
struct ConformanceTests {
    @Test(arguments: try ConformanceSuite.inScopeCases())
    func conformance(_ testCase: ConformanceCase) throws {
        guard let reason = ConformanceSuite.knownDefects[testCase.id] else {
            return try check(testCase)
        }
        withKnownIssue(Comment(rawValue: reason)) { try check(testCase) }
    }

    @Test func unsupportedTestsExist() throws {
        let cases = try ConformanceSuite.allCases()
        let ids = Set(cases.map(\.id))
        let listed = Set(ConformanceSuite.unsupportedTests.keys).union(ConformanceSuite.knownDefects.keys)
        #expect(listed.subtracting(ids).isEmpty, "Stale IDs: \(listed.subtracting(ids).sorted())")
    }

    @Test func everyTestTypeIsHandled() throws {
        let handled: Set = ["parsing", "validity", "equivalence"]
        let unknown = try ConformanceSuite.inScopeCases().filter { !handled.contains($0.testType) }
        #expect(unknown.isEmpty, "Unhandled: \(unknown.map(\.id))")
    }

    private func check(_ testCase: ConformanceCase) throws {
        switch testCase.testType {
        case "parsing":
            let expression = try #require(testCase.expression)
            let expected = try #require(Self.components(testCase.expectComponents))
            #expect(try ISO8601Parser().parse(expression) == Resolver.resolve(expected) { _ in 0 })

        case "validity":
            let expression = try #require(testCase.expression)
            let expected = try #require(testCase.expectValid as Bool?)
            var failure: ISO8601ParseError?
            do { _ = try ISO8601Parser().parse(expression) } catch { failure = error }
            #expect((failure == nil) == expected, "\(failure.map(String.init(describing:)) ?? "accepted")")

        case "equivalence":
            let a = try ISO8601Parser().parse(try #require(testCase.expressionA))
            let b = try ISO8601Parser().parse(try #require(testCase.expressionB))
            #expect((a == b) == (try #require(testCase.expectEquivalent as Bool?)))

        default:
            Issue.record("Unhandled test type \(testCase.testType)")
        }
    }

    /// `RawComponents` from the suite's component vocabulary, or nil for a key path outside it.
    private static func components(_ paths: [String: String]?) -> RawComponents? {
        guard var paths else { return nil }
        func take(_ key: String) -> Int? { paths.removeValue(forKey: key).flatMap { Int($0) } }

        let date: RawComponents.DatePart
        if let century = take("calendar.century") {
            date = .century(century)
        } else if let decade = take("calendar.decade") {
            date = .decade(decade)
        } else if let year = take("week.week_year") {
            guard let week = take("week.week") else { return nil }
            date = .week(year: year, week: week, weekday: take("week.day_of_week"))
        } else if let year = take("ordinal.year") {
            guard let day = take("ordinal.day_of_year") else { return nil }
            date = .ordinal(year: year, day: day)
        } else if let year = take("calendar.year") {
            if let month = take("calendar.month") {
                date = take("calendar.day").map { .calendar(year: year, month: month, day: $0) }
                    ?? .month(year: year, month: month)
            } else {
                date = .year(year)
            }
        } else {
            return nil
        }

        var time: RawComponents.TimePart?
        if let hour = take("time.hour") {
            let minute = take("time.minute")
            let second = take("time.second")
            let (precision, unit): (RawComponents.TimePart.Precision, String) =
                second != nil ? (.second, "second") : minute != nil ? (.minute, "minute") : (.hour, "hour")
            var fraction = RawComponents.Fraction(digits: 0, power: 1)
            if let digits = take("time.fractional_\(unit).value"), let scale = take("time.fractional_\(unit).precision") {
                fraction.digits = digits
                for _ in 0..<scale { fraction.power *= 10 }
            }
            time = .init(hour: hour, minute: minute ?? 0, second: second ?? 0, fraction: fraction, precision: precision)
        }

        var offset: RawComponents.Offset?
        if let hours = take("time.utc_offset.hours") {
            let sign = paths.removeValue(forKey: "time.utc_offset.sign")
            offset = .fixed(negative: sign == "-", hours: hours, minutes: take("time.utc_offset.minutes") ?? 0)
        }

        guard paths.isEmpty else { return nil }
        return RawComponents(date: date, time: time, offset: offset)
    }
}
