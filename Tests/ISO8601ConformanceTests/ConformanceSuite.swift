import Foundation
import Testing
import Yams

/// One test from the CalConnect ISO 8601 suite, flattened for comparison.
struct ConformanceCase: Sendable, CustomTestStringConvertible {
    enum Support: Sendable, Equatable {
        case inScope
        case notSupported(String)
    }

    /// Path below `tests/` without extension, e.g. `8601-1/calendar-date`.
    let conformanceClass: String
    let id: String
    let testType: String
    let expression: String?
    let expressionA: String?
    let expressionB: String?
    let expectValid: Bool?
    let expectEquivalent: Bool?
    /// `expect.components` as dotted key paths, e.g. `calendar.year: "1985"`.
    let expectComponents: [String: String]?

    var testDescription: String {
        "\(id) \(expression ?? "\(expressionA ?? "") ≡ \(expressionB ?? "")")"
    }

    var support: Support {
        if conformanceClass.hasPrefix("8601-2/") { return .notSupported("ISO 8601-2 extensions") }
        if let reason = ConformanceSuite.unsupportedClasses[conformanceClass] { return .notSupported(reason) }
        if let reason = ConformanceSuite.unsupportedTypes[testType] { return .notSupported(reason) }
        if let reason = ConformanceSuite.unsupportedTests[id] { return .notSupported(reason) }
        return .inScope
    }
}

enum ConformanceSuite {
    static let unsupportedClasses = [
        "8601-1/duration": "durations have no Date",
        "8601-1/time-interval": "time intervals have no Date",
        "8601-1/recurring-time-interval": "recurring time intervals have no Date",
        "8601-1/time-of-day": "time of day without a date has no Date",
    ]

    static let unsupportedTypes = [
        "generation": "formatting is out of scope",
        "arithmetic": "date arithmetic is out of scope",
    ]

    private static let standaloneOffset = "UTC offset without a date has no Date"
    private static let standaloneTime = "time of day without a date has no Date"
    private static let duration = "durations have no Date"
    private static let interval = "time intervals have no Date"

    /// Tests in otherwise supported classes whose expression is not a date or date-time.
    static let unsupportedTests = [
        "conf-test:fundamentals-valid-022": standaloneOffset,
        "conf-test:fundamentals-valid-023": standaloneOffset,
        "conf-test:fundamentals-valid-024": standaloneOffset,
        "conf-test:fundamentals-valid-025": standaloneOffset,
        "conf-test:fundamentals-valid-046": standaloneOffset,
        "conf-test:fundamentals-valid-047": standaloneOffset,
        "conf-test:fundamentals-valid-026": standaloneTime,
        "conf-test:fundamentals-valid-027": standaloneTime,
        "conf-test:fundamentals-valid-028": standaloneTime,
        "conf-test:fundamentals-valid-031": standaloneTime,
        "conf-test:fundamentals-valid-049": standaloneTime,
        "conf-test:fundamentals-valid-050": standaloneTime,
        "conf-test:symbols-valid-001": duration,
        "conf-test:symbols-valid-003": duration,
        "conf-test:symbols-valid-004": duration,
        "conf-test:symbols-valid-005": duration,
        "conf-test:symbols-valid-007": duration,
        "conf-test:symbols-valid-008": duration,
        "conf-test:symbols-valid-009": duration,
        "conf-test:symbols-valid-016": duration,
        "conf-test:symbols-valid-017": duration,
        "conf-test:symbols-valid-010": "recurring time intervals have no Date",
        "conf-test:symbols-valid-014": interval,
        "conf-test:symbols-valid-015": interval,
        "conf-test:symbols-valid-011": standaloneTime,
        "conf-test:symbols-valid-013": standaloneTime,
    ]

    /// Suite expectations contradicted by the suite's own descriptions or by ISO 8601-1.
    static let knownDefects = [
        "conf-test:week-date-valid-001":
            "Described as week 00, but 1985W015 is the valid date 1985-W01-5",
    ]

    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Vendor/iso-8601-test-suite/tests")

    static func allCases() throws -> [ConformanceCase] {
        let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".yaml") }
            .sorted()
        return try paths.flatMap { path in
            let yaml = try String(contentsOf: directory.appending(path: path), encoding: .utf8)
            let conformanceClass = String(path.dropLast(".yaml".count))
            let tests = try Yams.compose(yaml: yaml)?["tests"]?.array() ?? []
            return try tests.map { try ConformanceCase(conformanceClass: conformanceClass, node: $0) }
        }
    }

    static func inScopeCases() throws -> [ConformanceCase] {
        try allCases().filter { $0.support == .inScope }
    }
}

extension ConformanceCase {
    struct MalformedTest: Error, CustomStringConvertible {
        let description: String
    }

    init(conformanceClass: String, node: Node) throws {
        guard let id = node["id"]?.string, let testType = node["test_type"]?.string else {
            throw MalformedTest(description: "\(conformanceClass): test without id or test_type")
        }
        self.conformanceClass = conformanceClass
        self.id = id
        self.testType = testType
        expression = node["given"]?["expression"]?.string
        expressionA = node["given"]?["expression_a"]?.string
        expressionB = node["given"]?["expression_b"]?.string
        expectValid = node["expect"]?["valid"]?.bool
        expectEquivalent = node["expect"]?["equivalent"]?.bool
        expectComponents = node["expect"]?["components"].map(Self.normalizedComponents)
    }

    private static func normalizedComponents(_ node: Node) -> [String: String] {
        var paths: [String: String] = [:]
        flatten(node, prefix: nil, into: &paths)
        if paths["time.utc_offset.hours"] != nil, paths["time.utc_offset.minutes"] == nil {
            paths["time.utc_offset.minutes"] = "0"
        }
        return paths
    }

    private static func flatten(_ node: Node, prefix: String?, into paths: inout [String: String]) {
        guard let mapping = node.mapping else {
            let scalar = node.string ?? ""
            paths[prefix ?? ""] = node.int.map(String.init) ?? scalar
            return
        }
        for (key, value) in mapping {
            let key = key.string ?? ""
            flatten(value, prefix: prefix.map { "\($0).\(key)" } ?? key, into: &paths)
        }
    }
}
