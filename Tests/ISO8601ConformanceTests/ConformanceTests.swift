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
            let raw = try lex(expression)
            #expect(Self.keyPaths(raw) == testCase.expectComponents)
            #expect(throws: Never.self) { try Resolver(timeZone: .gmt).resolve(raw) }

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

    private func lex(_ expression: String) throws(ISO8601ParseError) -> RawComponents {
        var expression = expression
        expression.makeContiguousUTF8()
        return try Lexer(expression.utf8.span).lex()
    }

    /// `RawComponents` in the suite's component vocabulary.
    private static func keyPaths(_ raw: RawComponents) -> [String: String] {
        var paths: [String: String] = [:]
        func set(_ key: String, _ value: Int) { paths[key] = String(value) }

        switch raw.date {
        case .century(let century):
            set("calendar.century", century)
        case .decade(let decade):
            set("calendar.decade", decade)
        case .year(let year):
            set("calendar.year", year)
        case .month(let year, let month):
            set("calendar.year", year)
            set("calendar.month", month)
        case .calendar(let year, let month, let day):
            set("calendar.year", year)
            set("calendar.month", month)
            set("calendar.day", day)
        case .ordinal(let year, let day):
            set("ordinal.year", year)
            set("ordinal.day_of_year", day)
        case .week(let year, let week, let weekday):
            set("week.week_year", year)
            set("week.week", week)
            if let weekday { set("week.day_of_week", weekday) }
        }

        if let time = raw.time {
            set("time.hour", time.hour)
            if let minute = time.minute { set("time.minute", minute) }
            if let second = time.second { set("time.second", second) }
            if let fraction = time.fraction {
                let unit = time.second != nil ? "second" : time.minute != nil ? "minute" : "hour"
                set("time.fractional_\(unit).value", fraction.digits)
                set("time.fractional_\(unit).precision", fraction.scale)
            }
        }

        switch raw.offset {
        case nil:
            break
        case .utc:
            paths["time.utc_offset.sign"] = "+"
            set("time.utc_offset.hours", 0)
            set("time.utc_offset.minutes", 0)
        case .fixed(let negative, let hours, let minutes):
            paths["time.utc_offset.sign"] = negative ? "-" : "+"
            set("time.utc_offset.hours", hours)
            set("time.utc_offset.minutes", minutes)
        }
        return paths
    }
}
