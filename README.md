# ISO8601

Parse ISO 8601-1 date and date-time strings into `Foundation.Date`.

## Usage

```swift
import ISO8601

let date = try ISO8601Parser().parse("1985-04-12T23:20:50Z")
let local = try Date(iso8601: "1985-W15-5", timeZone: .current)
```

The errors are typed (`ISO8601ParseError`).

## Supported representations

- Calendar, ordinal, and week dates, in basic and extended format.
- Reduced precision: month, year, decade, and century.
- Expanded years with two extra digits, for example `+001985-04-12`.
- Time of day after a complete date, with an optional decimal fraction and UTC offset.

A value without a UTC offset uses `timeZone` (default GMT). The calendar is proleptic Gregorian.

Not supported: durations, intervals, recurring intervals, time of day without a date, and ISO 8601-2.

## Design

1. Lexical phase: a `Span<UInt8>` scanner finds the raw components. It does not check ranges.
2. Semantic phase: the resolver checks the ranges and calculates the `Date`.

## Requirements

Swift 6.2 or later and macOS 26 or later (or the equivalent platforms). The package enables the experimental `Lifetimes` feature.

## Tests

```sh
git submodule update --init
swift test
```

`ISO8601ConformanceTests` runs the [CalConnect ISO 8601](https://github.com/CalConnect/iso-8601-test-suite/) test suite. Tests outside the supported scope are not run.

## Prompts


1. In idiomatic swift 6 (e.g. using borrowing/consuming, span types, etc) create a new Swift package to parse arbitrary Strings that are date strings in some iso8601 format to a Foundation.Date object. Internally, this should be represented as a lexical phase to get raw components, and a semantic phase to validate + convert to Date. Do not use a regex.

2. As a submodule, add a new test target that validates against every applicable test case and spec in https://github.com/CalConnect/iso-8601-test-suite/. Make sure all pass.
