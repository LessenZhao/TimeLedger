import XCTest

final class ReviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourPeriodEntrancesExist() throws {
        let app = launch(extraArguments: ["-ui-review-fixture"])
        openReview(in: app)

        let picker = app.segmentedControls["review.period.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        for title in ["日", "周", "月", "年"] {
            XCTAssertTrue(picker.buttons[title].exists)
        }
        XCTAssertTrue(app.buttons["review.previous"].exists)
        XCTAssertTrue(app.buttons["review.next"].exists)
        XCTAssertTrue(app.buttons["review.current"].exists)
        XCTAssertTrue(app.staticTexts["项目趋势"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["值得注意"].exists)
    }

    @MainActor
    func testProjectSortAndSingleExpand() throws {
        let app = launch(extraArguments: ["-ui-review-fixture"])
        openReview(in: app)

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1. 复盘Alpha"))
                .firstMatch
                .waitForExistence(timeout: 5),
            "Alpha should be first by total duration"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "复盘Beta"))
                .firstMatch
                .waitForExistence(timeout: 3)
        )

        // Default expanded: long-term entry visible once
        let longTerm = app.buttons.matching(NSPredicate(format: "label == %@", "长期趋势"))
        XCTAssertTrue(longTerm.firstMatch.waitForExistence(timeout: 5), "Top project should be expanded")
        XCTAssertEqual(longTerm.count, 1, "Only one project expanded")

        let betaHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "review.project.header.", "复盘Beta"))
            .firstMatch
        if betaHeader.waitForExistence(timeout: 2) {
            betaHeader.tap()
        } else {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "复盘Beta")).firstMatch.tap()
        }

        XCTAssertTrue(longTerm.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(longTerm.count, 1, "Still only one expanded project")
    }

    @MainActor
    func testPendingBannerAndSegmentedBucketValues() throws {
        let app = launch(extraArguments: ["-ui-review-fixture"])
        openReview(in: app)

        let banner = app.descendants(matching: .any)["review.pending.banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 5)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "草稿待确认")).firstMatch.waitForExistence(timeout: 3),
            "Draft pending banner should show"
        )

        // Ensure first project expanded content is on screen
        app.swipeUp()
        let longTerm = app.buttons.matching(NSPredicate(format: "label == %@", "长期趋势")).firstMatch
        if !longTerm.waitForExistence(timeout: 3) {
            let alphaHeader = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "review.project.header.", "复盘Alpha"))
                .firstMatch
            if alphaHeader.waitForExistence(timeout: 2) { alphaHeader.tap() }
            app.swipeUp()
        }
        XCTAssertTrue(longTerm.waitForExistence(timeout: 5), "Expanded project required")

        let selectedMarker = app.descendants(matching: .any)["review.project.selected"]
        let selectedByLabel = app.staticTexts["已选时段"]
        XCTAssertTrue(
            selectedMarker.waitForExistence(timeout: 5) || selectedByLabel.waitForExistence(timeout: 3),
            "Selected bucket marker should appear"
        )
        let detail = app.descendants(matching: .any)["review.project.selected.detail"]
        let detailByText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", "确认", "草稿", "次")
        ).firstMatch
        XCTAssertTrue(
            detail.waitForExistence(timeout: 3) || detailByText.waitForExistence(timeout: 3),
            "Selected bucket detail should appear"
        )
        let selectedText = detail.exists ? detail.label : detailByText.label
        XCTAssertTrue(
            selectedText.contains("确认") && selectedText.contains("草稿") && selectedText.contains("次"),
            "Selected detail should show confirmed/draft/count: \(selectedText)"
        )

        let buckets = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.project.bucket."))
        XCTAssertTrue(buckets.firstMatch.waitForExistence(timeout: 3))

        let chartBuckets = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "review.project.chart.bucket.")
        )
        XCTAssertTrue(chartBuckets.firstMatch.waitForExistence(timeout: 3), "Chart bars must be tappable")
        let detailBeforeChartTap = detail.exists ? detail.label : detailByText.label
        chartBuckets.firstMatch.tap()
        let detailAfterChartTap = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", "确认", "草稿", "次")
        ).firstMatch
        XCTAssertTrue(detailAfterChartTap.waitForExistence(timeout: 3), "Chart tap must keep exact detail visible")
        XCTAssertNotEqual(
            detailAfterChartTap.label,
            detailBeforeChartTap,
            "Tapping a different chart bucket must update the exact value"
        )

        if buckets.count > 1 {
            let target = buckets.element(boundBy: min(1, buckets.count - 1))
            if target.isHittable {
                target.tap()
            } else {
                target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            let detailAfter = app.descendants(matching: .any)["review.project.selected.detail"]
            let detailAfterText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "确认", "草稿")
            ).firstMatch
            XCTAssertTrue(
                detailAfter.waitForExistence(timeout: 3) || detailAfterText.waitForExistence(timeout: 3),
                "Detail should remain after selecting another bucket"
            )
            let text = detailAfter.exists ? detailAfter.label : detailAfterText.label
            XCTAssertTrue(text.contains("确认"), "After tap: \(text)")
        }
    }

    @MainActor
    func testMonthDrillsIntoDayAndYearIntoMonth() throws {
        let app = launch(extraArguments: ["-ui-review-fixture"])
        openReview(in: app)

        let picker = app.segmentedControls["review.period.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        picker.buttons["月"].tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "月")
        // Ensure expanded content is on screen
        app.swipeUp()

        let dayDrill = app.buttons["查看当天"]
        XCTAssertTrue(dayDrill.waitForExistence(timeout: 5))
        dayDrill.tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "日")

        picker.buttons["年"].tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "年")
        app.swipeUp()
        let monthDrill = app.buttons["查看该月"]
        XCTAssertTrue(monthDrill.waitForExistence(timeout: 5))
        monthDrill.tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "月")
    }

    @MainActor
    func testLongTermDetailOpens() throws {
        let app = launch(extraArguments: ["-ui-review-fixture"])
        openReview(in: app)

        let longTerm = app.buttons.matching(NSPredicate(format: "label == %@", "长期趋势")).firstMatch
        XCTAssertTrue(longTerm.waitForExistence(timeout: 5))
        // Ensure visible
        if !longTerm.isHittable {
            app.swipeUp()
        }
        longTerm.tap()

        XCTAssertTrue(app.staticTexts["累计时长"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["活跃天数"].exists)
        XCTAssertTrue(app.staticTexts["单次时长中位数"].exists)
        XCTAssertTrue(app.staticTexts["最长连续记录"].exists)

        let granularity = app.segmentedControls["review.longterm.granularity"]
        if granularity.waitForExistence(timeout: 2) {
            XCTAssertTrue(granularity.buttons["日"].exists)
            XCTAssertTrue(granularity.buttons["周"].exists)
            XCTAssertTrue(granularity.buttons["月"].exists)
            granularity.buttons["周"].tap()
        }

        let close = app.buttons["review.longterm.close"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            app.buttons["关闭"].tap()
        }
    }

    @MainActor
    func testEvidenceOnlyVisibleOnDayPeriod() throws {
        let app = launch(extraArguments: ["-ui-review-fixture"])
        openReview(in: app)

        XCTAssertTrue(app.staticTexts["证据明细"].waitForExistence(timeout: 5), "Day period should show evidence")

        let picker = app.segmentedControls["review.period.picker"]
        picker.buttons["周"].tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "周")
        XCTAssertFalse(app.staticTexts["证据明细"].exists, "Week should not render evidence list")

        picker.buttons["月"].tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "月")
        XCTAssertFalse(app.staticTexts["证据明细"].exists)

        picker.buttons["年"].tap()
        XCTAssertEqual(app.staticTexts["review.active.period"].label, "年")
        XCTAssertFalse(app.staticTexts["证据明细"].exists)

        picker.buttons["日"].tap()
        XCTAssertTrue(app.staticTexts["证据明细"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func openReview(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["复盘"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        XCTAssertTrue(app.staticTexts["项目趋势"].waitForExistence(timeout: 8))
    }
}
