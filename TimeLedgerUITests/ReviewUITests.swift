import XCTest

final class ReviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourPeriodEntrancesExist() throws {
        let app = launch()
        app.tabBars.buttons["复盘"].tap()

        let picker = app.segmentedControls["review.period.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        for title in ["日", "周", "月", "年"] {
            XCTAssertTrue(picker.buttons[title].exists)
        }
        XCTAssertTrue(app.buttons["review.previous"].exists)
        XCTAssertTrue(app.buttons["review.next"].exists)
        XCTAssertTrue(app.buttons["review.current"].exists)
    }

    @MainActor
    func testTodayCompletedActionAppearsInReview() throws {
        let app = launch()
        createAction(named: "复盘测试事项", in: app)

        app.tabBars.buttons["今天"].tap()
        let action = app.buttons["复盘测试事项"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.press(forDuration: 0.25)

        app.tabBars.buttons["复盘"].tap()
        XCTAssertTrue(app.staticTexts["复盘测试事项"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '具体日期'")).firstMatch.exists)
    }

    @MainActor
    func testDraftDoesNotEnterFormalTotal() throws {
        let app = launch()
        createProject(named: "复盘草稿项目", in: app)

        let quickRecord = app.buttons["快速记录 复盘草稿项目"]
        XCTAssertTrue(quickRecord.waitForExistence(timeout: 3))
        quickRecord.tap()

        app.tabBars.buttons["复盘"].tap()
        let formalTotal = app.staticTexts["review.total.confirmed"]
        XCTAssertTrue(formalTotal.waitForExistence(timeout: 3))
        XCTAssertEqual(formalTotal.label, "<1分钟")
        XCTAssertTrue(app.staticTexts["review.pending"].label.hasPrefix("1 条"))
    }

    @MainActor
    func testWeeklyBarDrillsIntoDay() throws {
        let app = launch(extraArguments: ["-ui-media-fixture"])
        app.tabBars.buttons["复盘"].tap()
        app.segmentedControls["review.period.picker"].buttons["周"].tap()

        let bucket = app.buttons["review.time.bucket.0"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 3))
        bucket.tap()

        let activePeriod = app.staticTexts["review.active.period"]
        XCTAssertTrue(activePeriod.waitForExistence(timeout: 3))
        XCTAssertEqual(activePeriod.label, "日")
    }

    @MainActor
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func createAction(named name: String, in app: XCUIApplication) {
        app.tabBars.buttons["事项"].tap()
        app.buttons["action.add"].tap()
        let field = app.textFields["action.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(name)
        app.buttons["action.save"].tap()
    }

    @MainActor
    private func createProject(named name: String, in app: XCUIApplication) {
        app.tabBars.buttons["今天"].tap()
        let addProject = app.buttons["添加项目"]
        XCTAssertTrue(addProject.waitForExistence(timeout: 3))
        addProject.tap()
        let nameField = app.textFields["项目名称"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["保存"].tap()
    }
}
