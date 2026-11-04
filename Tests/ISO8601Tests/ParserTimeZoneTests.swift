import Foundation
import Testing
@testable import ISO8601

private let newYork = TimeZone(identifier: "America/New_York")!
private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
private let plusOne = TimeZone(secondsFromGMT: 3600)!

private let noon = "2024-01-15T12:00:00"
/// `noon` read in UTC.
private let noonUTC: TimeInterval = 1_705_320_000

struct ParserTimeZoneTests {
    @Test func fixedOffsetZone() throws {
        let parser = ISO8601Parser(timeZone: plusOne)
        #expect(try parser.parse(noon).timeIntervalSince1970 == noonUTC - 3600)
        #expect(try parser.parse("2024-01-15").timeIntervalSince1970 == noonUTC - 12 * 3600 - 3600)
        #expect(try parser.parse(noon + "Z").timeIntervalSince1970 == noonUTC)
    }

    @Test func gmt() throws {
        let parser = ISO8601Parser()
        #expect(try parser.parse(noon).timeIntervalSince1970 == noonUTC)
        #expect(try parser.parse("2024-01-15").timeIntervalSince1970 == noonUTC - 12 * 3600)
    }

    /// Asia/Kolkata has no DST today but had wartime offset changes, so each instant is still looked up.
    @Test func historicalOffsetFollowsFoundation() throws {
        let wall = try ISO8601Parser().parse("1943-06-15T12:00:00")
        let actual = try ISO8601Parser(timeZone: kolkata).parse("1943-06-15T12:00:00")
        let offset = kolkata.secondsFromGMT(for: actual)
        #expect(offset != kolkata.secondsFromGMT())
        #expect(actual == wall - TimeInterval(offset))
    }

    @Test func changingTimeZoneTakesEffect() throws {
        var parser = ISO8601Parser()
        #expect(try parser.parse(noon).timeIntervalSince1970 == noonUTC)
        parser.timeZone = plusOne
        #expect(try parser.parse(noon).timeIntervalSince1970 == noonUTC - 3600)
        parser.timeZone = newYork
        #expect(try parser.parse(noon).timeIntervalSince1970 == noonUTC + 5 * 3600)
        parser.timeZone = .gmt
        #expect(try parser.parse(noon).timeIntervalSince1970 == noonUTC)
    }

    @Test func parsersWithTheSameZoneAreEqual() {
        var parser = ISO8601Parser()
        parser.timeZone = plusOne
        #expect(parser == ISO8601Parser(timeZone: plusOne))
        #expect(parser.hashValue == ISO8601Parser(timeZone: plusOne).hashValue)
        #expect(parser != ISO8601Parser())
    }
}
