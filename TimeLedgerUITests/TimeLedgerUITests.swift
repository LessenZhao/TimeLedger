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
        XCTAssertEqual(actionButton.images.count, 0)
        XCTAssertEqual(actionButton.value as? String, "未完成，今天0次")
        actionButton.tap()
        XCTAssertEqual(actionButton.value as? String, "未完成，今天0次")
        actionButton.press(forDuration: 0.1)
        XCTAssertEqual(actionButton.value as? String, "未完成，今天0次")
        actionButton.press(forDuration: 0.25)
        XCTAssertEqual(actionButton.value as? String, "已完成，今天1次")
        XCTAssertTrue(actionButton.isEnabled)

        actionButton.press(forDuration: 0.25)
        XCTAssertTrue(app.alerts["开始新一轮？"].waitForExistence(timeout: 3))
        app.alerts["开始新一轮？"].buttons["开始新一轮"].tap()
        XCTAssertEqual(actionButton.value as? String, "第2轮未完成，今天已完成1次")
        actionButton.press(forDuration: 0.1)
        XCTAssertEqual(actionButton.value as? String, "第2轮未完成，今天已完成1次")
        actionButton.press(forDuration: 0.25)
        XCTAssertEqual(actionButton.value as? String, "已完成，今天2次")

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
        app.buttons["展开 UI测试项目"].tap()
        let editEntry = app.buttons["编辑 UI测试项目"]
        XCTAssertTrue(editEntry.waitForExistence(timeout: 3))
        editEntry.tap()
        XCTAssertTrue(app.staticTexts["完成事项"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "吃药")).count,
            2
        )

        app.navigationBars["编辑草稿"].buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["事项"].tap()
        let deleteCompletionButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "删除 吃药 记录")
        )
        XCTAssertEqual(deleteCompletionButtons.count, 2)
        deleteCompletionButtons.firstMatch.tap()
        XCTAssertTrue(app.alerts["删除这次完成记录？"].waitForExistence(timeout: 3))
        app.alerts["删除这次完成记录？"].buttons["删除"].tap()
        XCTAssertEqual(deleteCompletionButtons.count, 1)

        app.tabBars.buttons["今天"].tap()
        app.segmentedControls.buttons["项目"].tap()
        XCTAssertTrue(app.buttons["吃药"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["吃药"].value as? String, "已完成，今天1次")
    }

    @MainActor
    func testQuickThoughtTapAndCameraLongPressAreMutuallyExclusive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-camera-fixture"]
        app.launch()

        let control = app.buttons["today.quickThoughtCamera"]
        XCTAssertTrue(control.waitForExistence(timeout: 3))

        control.tap()
        XCTAssertTrue(app.navigationBars["记录思考"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["thought.composer.photoLibrary"].exists)
        XCTAssertTrue(app.buttons["thought.composer.camera"].exists)
        XCTAssertFalse(app.staticTexts["系统相机边界已调用"].exists)
        app.buttons["取消"].tap()

        XCTAssertTrue(control.waitForExistence(timeout: 3))
        control.press(forDuration: 0.25)
        XCTAssertTrue(app.staticTexts["系统相机边界已调用"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录思考"].exists)
        XCTAssertFalse(app.buttons["系统相册"].exists)
        XCTAssertFalse(app.buttons["两边"].exists)
        app.buttons["camera.fixture.usePhoto"].tap()

        XCTAssertTrue(app.navigationBars["记录思考"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 张附件"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["thought.composer.camera"].exists)
    }

    @MainActor
    func testDraftAndConfirmedCardsUseTwoLevelExpansion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        let draftProject = app.staticTexts["Fixture 草稿项目"]
        XCTAssertTrue(draftProject.waitForExistence(timeout: 3))
        XCTAssertTrue(app.scrollViews["draft.scroll"].exists)
        let draftTopBeforeExpansion = draftProject.frame.minY
        XCTAssertFalse(app.staticTexts["Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。"].exists)
        app.buttons["展开 Fixture 草稿项目"].tap()
        XCTAssertTrue(
            app.staticTexts["Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(draftProject.frame.minY, draftTopBeforeExpansion, accuracy: 1)
        let draftCard = app.otherElements["timeEntry.card.draft"].firstMatch
        draftCard.swipeLeft()
        let deleteDraft = app.buttons["删除"]
        XCTAssertTrue(deleteDraft.waitForExistence(timeout: 3))
        deleteDraft.tap()
        XCTAssertTrue(app.alerts["删除这条草稿？"].waitForExistence(timeout: 3))
        app.alerts["删除这条草稿？"].buttons["取消"].tap()

        let editDraft = app.buttons["编辑 Fixture 草稿项目"]
        XCTAssertTrue(editDraft.exists)
        XCTAssertLessThanOrEqual(editDraft.frame.width, 40)
        XCTAssertLessThanOrEqual(draftCard.frame.maxX - editDraft.frame.maxX, 16)
        editDraft.tap()
        XCTAssertTrue(app.navigationBars["编辑草稿"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.segmentedControls.buttons["已确认"].tap()
        let confirmedProject = app.staticTexts["Fixture 已确认项目"]
        XCTAssertTrue(confirmedProject.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Fixture 已确认思考全文"].exists)
        app.buttons["展开 Fixture 已确认项目"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 已确认思考全文"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["编辑 Fixture 已确认项目"].exists)
    }

    @MainActor
    func testDraftListScrollsVerticallyAcrossManyRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-draft-scroll-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        let scrollView = app.scrollViews["draft.scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        let firstDraft = app.staticTexts["Fixture 滚动 00"]
        XCTAssertTrue(firstDraft.isHittable)
        let firstDraftTop = firstDraft.frame.minY

        scrollView.swipeUp()

        XCTAssertLessThan(firstDraft.frame.minY, firstDraftTop - 50)
        XCTAssertTrue(app.staticTexts["Fixture 滚动 10"].isHittable)
    }

    @MainActor
    func testTimelineFourFiltersShowCorrectKinds() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()
        app.tabBars.buttons["时间线"].tap()

        let filter = app.segmentedControls["timeline.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。"].exists)
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertTrue(app.staticTexts["视频"].exists)

        filter.buttons["思考"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 已确认思考全文"].exists)
        XCTAssertFalse(app.staticTexts["照片"].exists)
        XCTAssertFalse(app.staticTexts["视频"].exists)

        filter.buttons["照片"].tap()
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertFalse(app.staticTexts["Fixture 已确认思考全文"].exists)
        XCTAssertFalse(app.staticTexts["视频"].exists)

        filter.buttons["视频"].tap()
        XCTAssertTrue(app.staticTexts["视频"].exists)
        XCTAssertFalse(app.staticTexts["照片"].exists)
        XCTAssertFalse(app.staticTexts["Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。"].exists)

        filter.buttons["全部"].tap()
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertTrue(app.staticTexts["视频"].exists)
        XCTAssertTrue(app.staticTexts["Fixture 已确认思考全文"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
