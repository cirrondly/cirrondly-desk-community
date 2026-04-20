import XCTest
@testable import Cirrondly_Desk_Community

final class ForecastTests: XCTestCase {
    func testOnTrackForecastWhenPaceIsSafelyBelowEightyPercent() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 30,
            limit: 100,
            windowStart: now.addingTimeInterval(-5 * 60 * 60),
            windowEnd: now.addingTimeInterval(5 * 60 * 60),
            now: now
        )

        XCTAssertEqual(forecast?.status, .onTrack)
        XCTAssertEqual(forecast?.projectedPercentageAtReset ?? 0, 60, accuracy: 0.01)
    }

    func testTightForecastWhenProjectionIsEightyFivePercent() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 42.5,
            limit: 100,
            windowStart: now.addingTimeInterval(-5 * 60 * 60),
            windowEnd: now.addingTimeInterval(5 * 60 * 60),
            now: now
        )

        XCTAssertEqual(forecast?.status, .tight)
        XCTAssertEqual(forecast?.projectedPercentageAtReset ?? 0, 85, accuracy: 0.01)
    }

    func testWillExceedForecastWhenProjectionIsOneHundredTwentyPercent() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 60,
            limit: 100,
            windowStart: now.addingTimeInterval(-5 * 60 * 60),
            windowEnd: now.addingTimeInterval(5 * 60 * 60),
            now: now
        )

        XCTAssertEqual(forecast?.status, .willExceed)
        XCTAssertEqual(forecast?.projectedPercentageAtReset ?? 0, 120, accuracy: 0.01)
    }

    func testTimeToDepletionWhenCurrentPaceExceedsLimit() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 80,
            limit: 100,
            windowStart: now.addingTimeInterval(-4 * 60 * 60),
            windowEnd: now.addingTimeInterval(2 * 60 * 60),
            now: now
        )

        XCTAssertEqual(forecast?.status, .willExceed)
        XCTAssertEqual(forecast?.timeToDepletion ?? 0, 60 * 60, accuracy: 0.5)
    }

    func testForecastReturnsNilWhenElapsedIsUnderOneMinute() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 10,
            limit: 100,
            windowStart: now.addingTimeInterval(-30),
            windowEnd: now.addingTimeInterval(5 * 60 * 60),
            now: now
        )

        XCTAssertNil(forecast)
    }

    func testForecastShowsZeroPercentWhenUsageIsStillZero() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 0,
            limit: 100,
            windowStart: now.addingTimeInterval(-5 * 60 * 60),
            windowEnd: now.addingTimeInterval(5 * 60 * 60),
            now: now
        )

        XCTAssertEqual(forecast?.status, .onTrack)
        XCTAssertEqual(forecast?.projectedPercentageAtReset ?? -1, 0, accuracy: 0.01)
        XCTAssertNil(forecast?.timeToDepletion)
    }

    func testForecastReturnsNilWhenLimitIsZero() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let forecast = ForecastCalculator.forecastUsage(
            used: 10,
            limit: 0,
            windowStart: now.addingTimeInterval(-5 * 60 * 60),
            windowEnd: now.addingTimeInterval(5 * 60 * 60),
            now: now
        )

        XCTAssertNil(forecast)
    }
}