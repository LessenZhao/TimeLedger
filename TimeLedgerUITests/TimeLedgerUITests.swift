//
//  TimeLedgerUITests.swift
//  TimeLedgerUITests
//
//  Created by Lessen Zhao on 2026/7/8.
//

import XCTest

final class TimeLedgerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testDailyActionCompletesAndAppearsOnDraft() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.tabBars.buttons["事项"].tap()
        app.buttons["action.add"].tap()
        let titleField = app.textFields["action.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("吃药")
        app.buttons["action.save"].tap()

        app.tabBars.buttons["今天"].tap()
        let actionButton = app.buttons["吃药"]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 3))
        XCTAssertEqual(actionButton.value as? String, "未完成")
        actionButton.tap()
        XCTAssertEqual(actionButton.value as? String, "已完成")
        XCTAssertFalse(actionButton.isEnabled)

        let addProject = app.buttons["添加项目"]
        XCTAssertTrue(addProject.waitForExistence(timeout: 3))
        addProject.tap()
        let projectName = app.textFields["项目名称"]
        XCTAssertTrue(projectName.waitForExistence(timeout: 3))
        projectName.tap()
        projectName.typeText("UI测试项目")
        app.buttons["保存"].tap()

        let quickRecord = app.buttons["快速记录 UI测试项目"]
        XCTAssertTrue(quickRecord.waitForExistence(timeout: 3))
        quickRecord.tap()

        app.segmentedControls.buttons["草稿"].tap()
        let draftProject = app.staticTexts["UI测试项目"]
        XCTAssertTrue(draftProject.waitForExistence(timeout: 3))
        draftProject.tap()
        XCTAssertTrue(app.staticTexts["完成事项"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["吃药"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
