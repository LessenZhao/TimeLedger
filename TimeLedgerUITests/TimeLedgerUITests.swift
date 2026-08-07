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
        XCTAssertFalse(app.staticTexts["完成事项"].exists)
        XCTAssertFalse(app.buttons["查看详情 UI测试项目"].exists)
        app.buttons["展开详情 UI测试项目"].tap()
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(app.staticTexts["完成事项"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "吃药")).count,
            2
        )
        app.buttons["编辑 UI测试项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        app.buttons["timeEntry.edit.cancel"].tap()

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
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
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
        XCTAssertTrue(app.staticTexts["1 个附件"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
    }

    @MainActor
    func testNewRecordEditorCancelsNoteAndCameraPhotoDraft() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-camera-fixture"]
        app.launch()

        app.buttons["添加项目"].tap()
        let projectName = app.textFields["项目名称"]
        XCTAssertTrue(projectName.waitForExistence(timeout: 3))
        projectName.tap()
        projectName.typeText("记录详情测试")
        app.buttons["保存"].tap()

        let projectButton = app.buttons["快速记录 记录详情测试"]
        XCTAssertTrue(projectButton.waitForExistence(timeout: 3))
        projectButton.press(forDuration: 0.5)

        XCTAssertTrue(app.navigationBars["记录时间"].waitForExistence(timeout: 3))
        // 今天页长按项目打开的是 TimeAdjustmentSheet，备注仍是页内 TextEditor
        let note = app.textViews["richContent.text"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("现场备注")

        app.buttons["richContent.addMedia"].tap()
        app.buttons["拍照或录像"].tap()
        XCTAssertTrue(app.staticTexts["系统相机边界已调用"].waitForExistence(timeout: 3))
        app.buttons["camera.fixture.usePhoto"].tap()

        XCTAssertTrue(app.navigationBars["记录时间"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["移除媒体"].waitForExistence(timeout: 3))
        app.buttons["timeEntry.create.cancel"].tap()

        XCTAssertTrue(projectButton.waitForExistence(timeout: 3))
        projectButton.press(forDuration: 0.5)
        XCTAssertTrue(app.navigationBars["记录时间"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textViews["richContent.text"].value as? String, "")
        XCTAssertFalse(app.buttons["移除媒体"].exists)
    }

    @MainActor
    func testDraftNoteHasDistinctSemanticLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 草稿项目"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["timeEntry.note.label"].waitForExistence(timeout: 3),
            "草稿备注需要稳定的语义标签，不能只靠与思考相同的正文字体"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["timeEntry.note.text"].waitForExistence(timeout: 3)
        )
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
        let longThought = Self.fixtureLongThought(in: app)
        XCTAssertFalse(longThought.exists)
        app.buttons["展开详情 Fixture 草稿项目"].tap()
        XCTAssertTrue(longThought.waitForExistence(timeout: 3))
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
        Self.assertTouchTarget(editDraft, name: "草稿编辑")
        editDraft.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(app.textViews["timeEntry.edit.note"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
        XCTAssertEqual(
            app.navigationBars["编辑记录"].buttons.matching(NSPredicate(format: "label == %@", "取消")).count,
            1
        )
        XCTAssertEqual(
            app.navigationBars["编辑记录"].buttons.matching(NSPredicate(format: "label == %@", "保存")).count,
            1
        )
        app.buttons["timeEntry.edit.cancel"].tap()

        app.segmentedControls.buttons["已确认"].tap()
        let confirmedProject = app.staticTexts["Fixture 已确认项目"]
        XCTAssertTrue(confirmedProject.waitForExistence(timeout: 3))
        XCTAssertFalse(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").exists)
        app.buttons["展开详情 Fixture 已确认项目"].tap()
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").waitForExistence(timeout: 3))
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
        // 先滚回顶部，避免大触控按钮导致首行不在视口
        scrollView.swipeDown()
        scrollView.swipeDown()
        let firstDraft = Self.element(in: app, labelContaining: "Fixture 滚动 00")
        XCTAssertTrue(firstDraft.waitForExistence(timeout: 5), "应看到首条滚动草稿")
        let firstDraftTop = firstDraft.frame.minY

        scrollView.swipeUp()
        scrollView.swipeUp()

        XCTAssertTrue(
            Self.element(in: app, labelContaining: "Fixture 滚动 10").waitForExistence(timeout: 5),
            "上滑后应看到更后面的草稿"
        )
        if firstDraft.exists {
            XCTAssertLessThan(firstDraft.frame.minY, firstDraftTop - 20)
        }
    }

    @MainActor
    func testTimelineFilterSheetShowsCorrectKinds() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()
        app.tabBars.buttons["时间线"].tap()

        let typeMode = app.segmentedControls["timeline.typeMode.picker"]
        XCTAssertTrue(typeMode.waitForExistence(timeout: 3))
        XCTAssertTrue(typeMode.buttons["合并"].isSelected)

        let filter = app.buttons["timeline.filter.button"]
        XCTAssertTrue(filter.waitForExistence(timeout: 3))
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertTrue(app.staticTexts["视频"].exists)
        XCTAssertFalse(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "DurationFormatter"))
                .firstMatch
                .exists,
            "视频时长不得显示实现源码"
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "<1分钟"))
                .firstMatch
                .exists,
            "fixture 视频应显示格式化后的时长"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "timeline.media.menu")
                .firstMatch
                .waitForExistence(timeout: 3),
            "纯媒体卡也必须使用统一的省略号菜单"
        )
        XCTAssertTrue(app.staticTexts["备注"].exists)
        XCTAssertTrue(app.staticTexts["思考"].exists)
        XCTAssertTrue(app.staticTexts["关联思考 1 条"].exists)
        XCTAssertTrue(app.staticTexts["关联备注"].exists)
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 首页独立思考").exists)

        let julyDay = String(format: "%04d-07-20", Calendar.current.component(.year, from: Date()))
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 七月备注").exists, "七月备注应出现在语义日 \(julyDay)")
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 七月条目思考").exists)
        XCTAssertTrue(app.staticTexts[julyDay].exists)

        typeMode.buttons["备注"].tap()
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 草稿备注").waitForExistence(timeout: 3))
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 七月备注").exists)
        XCTAssertFalse(Self.fixtureLongThought(in: app).exists)
        XCTAssertFalse(Self.element(in: app, labelContaining: "Fixture 首页独立思考").exists)

        typeMode.buttons["思考"].tap()
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 首页独立思考").exists)
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 七月条目思考").exists)
        XCTAssertFalse(Self.element(in: app, labelContaining: "Fixture 草稿备注").exists)
        XCTAssertFalse(Self.element(in: app, labelContaining: "Fixture 七月备注").exists)

        typeMode.buttons["合并"].tap()
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 草稿备注").waitForExistence(timeout: 3))
        XCTAssertTrue(Self.fixtureLongThought(in: app).exists)

        filter.tap()
        app.buttons["timeline.filter.option.text"].tap()
        app.buttons["timeline.filter.done"].tap()
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").exists)
        XCTAssertTrue(Self.fixtureLongThought(in: app).exists)
        XCTAssertFalse(app.staticTexts["照片"].exists)
        XCTAssertFalse(app.staticTexts["视频"].exists)

        filter.tap()
        app.buttons["timeline.filter.reset"].tap()
        app.buttons["timeline.filter.option.photos"].tap()
        app.buttons["timeline.filter.done"].tap()
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertTrue(Self.fixtureLongThought(in: app).exists)
        XCTAssertFalse(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").exists)
        XCTAssertFalse(app.staticTexts["视频"].exists)

        filter.tap()
        app.buttons["timeline.filter.reset"].tap()
        app.buttons["timeline.filter.option.videos"].tap()
        app.buttons["timeline.filter.done"].tap()
        XCTAssertTrue(app.staticTexts["视频"].exists)
        XCTAssertFalse(Self.fixtureLongThought(in: app).exists)
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").exists)
        XCTAssertFalse(app.staticTexts["照片"].exists)

        filter.tap()
        app.buttons["timeline.filter.reset"].tap()
        app.buttons["timeline.filter.option.text"].tap()
        app.buttons["timeline.filter.option.photos"].tap()
        app.buttons["timeline.filter.done"].tap()
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").exists)
        XCTAssertTrue(Self.fixtureLongThought(in: app).exists)
        XCTAssertFalse(app.staticTexts["视频"].exists)

        filter.tap()
        app.buttons["timeline.filter.reset"].tap()
        app.buttons["timeline.filter.done"].tap()
        XCTAssertTrue(app.staticTexts["照片"].exists)
        XCTAssertTrue(app.staticTexts["视频"].exists)
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 已确认思考全文").exists)

        // 选择记忆：切到备注后杀进程再启动，应保持备注
        typeMode.buttons["备注"].tap()
        XCTAssertTrue(typeMode.buttons["备注"].isSelected)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture", "-ui-keep-timeline-type-mode"]
        app.launch()
        app.tabBars.buttons["时间线"].tap()
        let restoredMode = app.segmentedControls["timeline.typeMode.picker"]
        XCTAssertTrue(restoredMode.waitForExistence(timeout: 3))
        XCTAssertTrue(restoredMode.buttons["备注"].isSelected)
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 七月备注").waitForExistence(timeout: 3))
        XCTAssertFalse(Self.element(in: app, labelContaining: "Fixture 首页独立思考").exists)

        // 取消关联：保留则关系仍在，确认才解除
        restoredMode.buttons["思考"].tap()
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 3))
        let relatedBefore = app.staticTexts.matching(NSPredicate(format: "label == %@", "关联备注")).count
        XCTAssertGreaterThanOrEqual(relatedBefore, 1)

        // 思考卡操作收入省略号菜单
        let thoughtMenus = app.descendants(matching: .any)
            .matching(identifier: "timeline.thought.menu.linked")
        XCTAssertTrue(thoughtMenus.firstMatch.waitForExistence(timeout: 3))
        thoughtMenus.firstMatch.tap()
        let thoughtUnlink = app.buttons
            .matching(NSPredicate(format: "label == %@ OR identifier == %@", "取消关联", "timeline.thought.unlink"))
            .firstMatch
        XCTAssertTrue(thoughtUnlink.waitForExistence(timeout: 3))
        thoughtUnlink.tap()
        let unlinkAlert = app.alerts["取消关联？"]
        XCTAssertTrue(unlinkAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(unlinkAlert.staticTexts.element(boundBy: 0).exists)
        unlinkAlert.buttons["保留关联"].firstMatch.tap()
        XCTAssertFalse(app.alerts["取消关联？"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "关联备注")).count,
            relatedBefore
        )

        thoughtMenus.firstMatch.tap()
        XCTAssertTrue(thoughtUnlink.waitForExistence(timeout: 3))
        thoughtUnlink.tap()
        XCTAssertTrue(app.alerts["取消关联？"].waitForExistence(timeout: 3))
        app.alerts["取消关联？"].buttons["确认取消关联"].firstMatch.tap()
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "关联备注")).count,
            relatedBefore - 1
        )
    }


    @MainActor
    func testDraftBodyExpandsInPlaceAndDoesNotOpenDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 草稿项目"].waitForExistence(timeout: 3))
        let thoughtBody = Self.fixtureLongThought(in: app)
        XCTAssertFalse(thoughtBody.exists)
        app.staticTexts["Fixture 草稿项目"].tap()
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(thoughtBody.waitForExistence(timeout: 3))

        let editDraft = app.buttons["编辑 Fixture 草稿项目"]
        XCTAssertTrue(editDraft.waitForExistence(timeout: 3))
        editDraft.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
    }

    @MainActor
    func testLongNoteEditPersistsThroughSingleSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 草稿项目"].waitForExistence(timeout: 3))
        app.buttons["展开详情 Fixture 草稿项目"].tap()
        app.buttons["编辑 Fixture 草稿项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))

        let editor = app.textViews["timeEntry.edit.note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()

        let longTail = "LONG_NOTE_TAIL_MARKER_98765"
        // 追加长文标记，避免全选菜单在部分系统上卡住
        let chunk = "长备注段落用于验证全高编辑与换行显示。"
        editor.typeText(chunk + chunk + chunk + longTail)
        app.buttons["timeEntry.edit.save"].tap()
        XCTAssertTrue(
            Self.element(in: app, labelContaining: longTail).waitForExistence(timeout: 5),
            "保存后列表应看到长备注标记"
        )

        let editAgain = app.buttons["编辑 Fixture 草稿项目"]
        XCTAssertTrue(editAgain.waitForExistence(timeout: 3))
        editAgain.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        let reopened = app.textViews["timeEntry.edit.note"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        let reopenedValue = reopened.value as? String ?? ""
        XCTAssertTrue(reopenedValue.contains(longTail), "重新打开备注编辑页后内容不完整: \(reopenedValue)")
    }

    @MainActor
    func testTimelineLinkedStandaloneMediaHasVisibleEditEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-unified-content-fixture"]
        app.launch()

        app.tabBars.buttons["时间线"].tap()
        let typeMode = app.segmentedControls["timeline.typeMode.picker"]
        XCTAssertTrue(typeMode.waitForExistence(timeout: 3))
        typeMode.buttons["思考"].tap()

        let mediaEdit = app.buttons["timeline.media.edit"].firstMatch
        if !mediaEdit.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(
            mediaEdit.waitForExistence(timeout: 3),
            "关联到记录的纯图片卡需要显式编辑入口"
        )
        mediaEdit.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["timeEntry.edit.note"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.buttons["移除媒体"].firstMatch.waitForExistence(timeout: 3),
            "从纯图片卡进入记录编辑后必须看到当前照片"
        )
    }

    @MainActor
    func testTimelineEditsNoteAndThoughtCardsImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()

        app.tabBars.buttons["时间线"].tap()
        let typeMode = app.segmentedControls["timeline.typeMode.picker"]
        XCTAssertTrue(typeMode.waitForExistence(timeout: 3))

        // 编辑备注卡
        typeMode.buttons["备注"].tap()
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 草稿备注").waitForExistence(timeout: 3))
        let noteCard = app.descendants(matching: .any)["timeline.card.note"].firstMatch
        XCTAssertTrue(noteCard.waitForExistence(timeout: 3), "备注卡片应出现在时间线备注模式")
        let editNote = app.buttons["timeline.note.edit"].firstMatch
        XCTAssertTrue(editNote.waitForExistence(timeout: 3))
        editNote.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        let noteEditor = app.textViews["timeEntry.edit.note"]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 3))
        noteEditor.tap()
        noteEditor.typeText("-XYZ更新")
        app.buttons["timeEntry.edit.save"].tap()
        XCTAssertTrue(
            Self.element(in: app, labelContaining: "XYZ更新").waitForExistence(timeout: 3)
        )
        // 项目与关联状态仍在
        XCTAssertTrue(Self.element(in: app, labelContaining: "Fixture 草稿项目").exists)
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["时间线"].waitForExistence(timeout: 3))
        XCTAssertTrue(typeMode.waitForExistence(timeout: 3))

        // 编辑思考卡
        typeMode.buttons["思考"].tap()
        let editThought = app.buttons["timeline.thought.edit"].firstMatch
        XCTAssertTrue(editThought.waitForExistence(timeout: 3))
        editThought.tap()
        XCTAssertTrue(app.navigationBars["编辑思考"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["思考详情"].exists)
        let thoughtEditor = app.textViews["thought.edit.body"]
        XCTAssertTrue(thoughtEditor.waitForExistence(timeout: 3))
        thoughtEditor.tap()
        thoughtEditor.typeText("【时间线已改】")
        app.buttons["thought.edit.save"].tap()
        XCTAssertTrue(
            Self.element(in: app, labelContaining: "【时间线已改】").waitForExistence(timeout: 5),
            "时间线思考保存后应看到更新"
        )
        // 关联信息仍可见
        XCTAssertTrue(
            Self.element(in: app, labelContaining: "Fixture 草稿项目").exists,
            "思考关联项目仍可见"
        )
    }

    @MainActor
    func testUnifiedContentEntryEntrancesUseDirectEditors() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-unified-content-fixture"]
        app.launch()

        // 1. 草稿主体只展开，不导航；可见编辑直达编辑 Sheet
        app.segmentedControls.buttons["草稿"].tap()
        let draftProject = app.staticTexts["Fixture 草稿项目"]
        XCTAssertTrue(draftProject.waitForExistence(timeout: 3))
        draftProject.tap()
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 3))
        app.buttons["编辑 Fixture 草稿项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(app.textViews["timeEntry.edit.note"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
        app.buttons["timeEntry.edit.cancel"].tap()

        // 2. 已确认可见编辑直达编辑 Sheet，时间保持只读由编辑页语义保证
        app.segmentedControls.buttons["已确认"].tap()
        let confirmedProject = app.staticTexts["Fixture 已确认项目"]
        XCTAssertTrue(confirmedProject.waitForExistence(timeout: 3))
        app.buttons["编辑 Fixture 已确认项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(app.textViews["timeEntry.edit.note"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
        app.buttons["timeEntry.edit.cancel"].tap()

        // 3. 时间线备注可见编辑直达记录编辑
        app.tabBars.buttons["时间线"].tap()
        app.segmentedControls["timeline.typeMode.picker"].buttons["备注"].tap()
        let note = Self.element(in: app, labelContaining: "Fixture 草稿备注")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        app.buttons["timeline.note.edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["记录详情"].exists)
        XCTAssertTrue(app.textViews["timeEntry.edit.note"].waitForExistence(timeout: 3))
        app.buttons["timeEntry.edit.cancel"].tap()

        // 4. 时间线思考可见编辑直达思考编辑
        app.segmentedControls["timeline.typeMode.picker"].buttons["思考"].tap()
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 3))
        app.buttons["timeline.thought.edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["编辑思考"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["思考详情"].exists)
        XCTAssertTrue(app.textViews["thought.edit.body"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
        XCTAssertEqual(
            app.navigationBars["编辑思考"].buttons.matching(NSPredicate(format: "label == %@", "取消")).count,
            1
        )
        XCTAssertEqual(
            app.navigationBars["编辑思考"].buttons.matching(NSPredicate(format: "label == %@", "保存")).count,
            1
        )
    }

    @MainActor
    func testUnifiedContentNewInputsUseSameRichEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-unified-content-fixture"]
        app.launch()

        // 6. 新建 TimeEntry 输入
        let projectButton = app.buttons["快速记录 Fixture 草稿项目"]
        XCTAssertTrue(projectButton.waitForExistence(timeout: 3))
        projectButton.press(forDuration: 0.5)
        XCTAssertTrue(app.navigationBars["记录时间"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["richContent.text"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
        app.buttons["timeEntry.create.cancel"].tap()

        // 7. 新建 Thought 输入
        let quickThought = app.buttons["today.quickThoughtCamera"]
        XCTAssertTrue(quickThought.waitForExistence(timeout: 3))
        quickThought.tap()
        XCTAssertTrue(app.navigationBars["记录思考"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["thought.composer.text"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["richContent.addMedia"].exists)
    }

    @MainActor
    func testRecordEditorUsesCompactRichContentLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-unified-content-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 草稿项目"].waitForExistence(timeout: 3))
        app.buttons["编辑 Fixture 草稿项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))

        let editor = app.textViews["timeEntry.edit.note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(
            editor.frame.height,
            132,
            "备注编辑区不应以固定大高度挤出上下空白: \(editor.frame)"
        )
        XCTAssertTrue(app.buttons["移除媒体"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(
            app.staticTexts["richContent.media.existing"].exists,
            "缩略图已经表达已有媒体，不应重复显示说明文字"
        )
    }

    @MainActor
    func testUnifiedContentCancelAndRemoveKeepMediaMomentRecoverable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-unified-content-fixture", "-ui-camera-fixture"]
        app.launch()

        app.segmentedControls.buttons["草稿"].tap()
        let draftProject = app.staticTexts["Fixture 草稿项目"]
        XCTAssertTrue(draftProject.waitForExistence(timeout: 3))
        app.buttons["编辑 Fixture 草稿项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["timeEntry.edit.note"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["移除媒体"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["移除媒体"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["richContent.media.pendingRemoval"].waitForExistence(timeout: 3))
        app.buttons["timeEntry.edit.cancel"].tap()

        draftProject.tap()
        XCTAssertTrue(app.buttons["查看照片"].waitForExistence(timeout: 3))
        let photoCountBeforeRemoval = app.buttons.matching(
            NSPredicate(format: "label == %@", "查看照片")
        ).count
        app.buttons["编辑 Fixture 草稿项目"].tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 3))
        app.buttons["移除媒体"].firstMatch.tap()
        app.buttons["timeEntry.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 草稿项目"].waitForExistence(timeout: 5))

        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label == %@", "查看照片")).count,
            photoCountBeforeRemoval - 1
        )
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 3))
    }

    @MainActor
    func testPhotoOnlyThoughtKeepsThoughtIdentityAndCanGainText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-camera-fixture"]
        app.launch()

        let quickThought = app.buttons["today.quickThoughtCamera"]
        XCTAssertTrue(quickThought.waitForExistence(timeout: 3))
        quickThought.tap()
        XCTAssertTrue(app.navigationBars["记录思考"].waitForExistence(timeout: 3))
        app.buttons["richContent.addMedia"].tap()
        app.buttons["拍照或录像"].tap()
        XCTAssertTrue(app.staticTexts["系统相机边界已调用"].waitForExistence(timeout: 3))
        app.buttons["camera.fixture.usePhoto"].tap()
        XCTAssertTrue(app.staticTexts["1 个附件"].waitForExistence(timeout: 3))
        app.buttons["thought.composer.save"].tap()

        app.tabBars.buttons["时间线"].tap()
        app.segmentedControls["timeline.typeMode.picker"].buttons["思考"].tap()
        let photoThoughtEdit = app.buttons["timeline.thought.edit"]
        XCTAssertTrue(
            photoThoughtEdit.waitForExistence(timeout: 3),
            "纯照片 Thought 必须保留 Thought 身份并提供直达编辑入口"
        )
        photoThoughtEdit.tap()
        XCTAssertTrue(app.navigationBars["编辑思考"].waitForExistence(timeout: 3))
        let editor = app.textViews["thought.edit.body"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("照片补充文字")
        app.buttons["thought.edit.save"].tap()
        XCTAssertTrue(
            Self.element(in: app, labelContaining: "照片补充文字").waitForExistence(timeout: 5),
            "纯照片思考补充文字后应可见"
        )
    }

    @MainActor
    func testReadingSurfaceEditIsOneTapAndTouchTargetsAreSafe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-media-fixture"]
        app.launch()

        // 今天页：无查看详情；正文/箭头只折叠；编辑一次直达
        XCTAssertTrue(app.segmentedControls.buttons["草稿"].waitForExistence(timeout: 5), "T1 草稿段")
        app.segmentedControls.buttons["草稿"].tap()
        XCTAssertTrue(app.staticTexts["Fixture 草稿项目"].waitForExistence(timeout: 5), "T2 草稿项目")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "查看详情")).count, 0, "T3 无查看详情")

        let expand = app.buttons["展开详情 Fixture 草稿项目"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "T4 展开按钮")
        expand.tap()
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 5), "T5 展开后长文")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Fixture 草稿备注")
            ).firstMatch.waitForExistence(timeout: 5),
            "T6 备注"
        )
        XCTAssertFalse(app.navigationBars["记录详情"].exists, "T7 无详情导航")

        let todayEdit = app.buttons["编辑 Fixture 草稿项目"]
        XCTAssertTrue(todayEdit.waitForExistence(timeout: 5), "T8 今天编辑")
        Self.assertTouchTarget(todayEdit, name: "今天编辑")
        todayEdit.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 5), "T9 进编辑记录")
        XCTAssertFalse(app.navigationBars["记录详情"].exists, "T10 编辑非详情")

        // 编辑记录：关联思考卡直接显示正文与编辑
        let editForm = app.collectionViews.firstMatch
        if editForm.waitForExistence(timeout: 2) {
            editForm.swipeUp()
            editForm.swipeUp()
        } else {
            app.swipeUp()
            app.swipeUp()
        }
        let linkedEdit = app.buttons["timeEntry.edit.thought.edit"].firstMatch
        XCTAssertTrue(linkedEdit.waitForExistence(timeout: 5), "T11 关联思考编辑")
        Self.assertTouchTarget(linkedEdit, name: "关联思考编辑")
        XCTAssertTrue(
            Self.fixtureLongThought(in: app).exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture 草稿思考")).firstMatch.exists,
            "T12 关联思考正文"
        )
        linkedEdit.tap()
        XCTAssertTrue(app.navigationBars["编辑思考"].waitForExistence(timeout: 5), "T13 进编辑思考")
        app.buttons.matching(NSPredicate(format: "label == %@", "取消")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 5), "T14 回编辑记录")
        app.buttons["timeEntry.edit.cancel"].tap()

        // 时间线：无详情；编辑/更多触控安全；长文往返；短文无假按钮
        app.tabBars.buttons["时间线"].tap()
        let typeMode = app.segmentedControls["timeline.typeMode.picker"]
        XCTAssertTrue(typeMode.waitForExistence(timeout: 5), "T15 时间线")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "查看详情")).count, 0, "T16 时间线无详情")
        XCTAssertFalse(app.buttons["timeline.note.detail"].exists, "T17 无 note.detail")
        XCTAssertFalse(app.buttons["timeline.thought.detail"].exists, "T18 无 thought.detail")
        XCTAssertFalse(app.descendants(matching: .any)["timeline.note.menu"].exists, "T19 备注无更多")

        typeMode.buttons["备注"].tap()
        let noteEdit = app.buttons["timeline.note.edit"].firstMatch
        XCTAssertTrue(noteEdit.waitForExistence(timeout: 5), "T20 备注编辑")
        Self.assertTouchTarget(noteEdit, name: "备注编辑")
        noteEdit.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 5), "T21 备注进编辑")
        app.buttons["timeEntry.edit.cancel"].tap()

        typeMode.buttons["思考"].tap()
        XCTAssertTrue(Self.fixtureLongThought(in: app).waitForExistence(timeout: 5), "T22 时间线长文")
        let thoughtEdit = app.buttons["timeline.thought.edit"].firstMatch
        XCTAssertTrue(thoughtEdit.waitForExistence(timeout: 5), "T23 思考编辑")
        Self.assertTouchTarget(thoughtEdit, name: "思考编辑")
        let thoughtMenu = app.descendants(matching: .any)["timeline.thought.menu.linked"].firstMatch
        XCTAssertTrue(thoughtMenu.waitForExistence(timeout: 5), "T24 思考更多")
        Self.assertTouchTarget(thoughtMenu, name: "思考更多")
        Self.assertNoOverlap(thoughtEdit, thoughtMenu, minGap: 8)

        // 等截断检测完成
        let expandBody = app.buttons["timeline.body.expand"].firstMatch
        var sawExpand = expandBody.waitForExistence(timeout: 8)
        if !sawExpand {
            app.swipeUp()
            sawExpand = expandBody.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(sawExpand, "长文应出现真实展开按钮")
        expandBody.tap()
        let collapseBody = app.buttons["timeline.body.collapse"].firstMatch
        XCTAssertTrue(collapseBody.waitForExistence(timeout: 5), "点展开后应出现收起")
        collapseBody.tap()
        XCTAssertTrue(
            app.buttons["timeline.body.expand"].firstMatch.waitForExistence(timeout: 5),
            "按钮收起后应回到展开"
        )
        // 正文控件存在（与展开按钮共用 toggle）
        let longBody = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "timeline.body.text",
                Self.fixtureLongThoughtSnippet
            )
        ).firstMatch
        XCTAssertTrue(longBody.waitForExistence(timeout: 5), "应有长文正文控件")

        XCTAssertTrue(
            Self.element(in: app, labelContaining: "短文无展开").waitForExistence(timeout: 5),
            "短文 fixture 应可见"
        )

        // 更多菜单仅低频动作；编辑一次直达
        let menus = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.thought.menu."))
        XCTAssertTrue(menus.firstMatch.waitForExistence(timeout: 5), "应有思考更多菜单")
        menus.firstMatch.tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@ OR label == %@", "删除", "取消关联", "手动关联")
            ).firstMatch.waitForExistence(timeout: 5),
            "更多菜单应只有低频动作"
        )
        // 点菜单外关闭
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        XCTAssertFalse(app.navigationBars["思考详情"].exists, "菜单不应进详情")

        let thoughtEditAgain = app.buttons["timeline.thought.edit"].firstMatch
        XCTAssertTrue(thoughtEditAgain.waitForExistence(timeout: 5), "编辑仍在")
        thoughtEditAgain.tap()
        XCTAssertTrue(app.navigationBars["编辑思考"].waitForExistence(timeout: 5), "编辑直达思考")
        XCTAssertFalse(app.navigationBars["思考详情"].exists, "不是详情页")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private static let fixtureLongThoughtSnippet =
        "Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。"

    private static func fixtureLongThought(in app: XCUIApplication) -> XCUIElement {
        element(in: app, labelContaining: fixtureLongThoughtSnippet)
    }

    private static func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", text)
        ).firstMatch
    }



    private static func assertTouchTarget(_ element: XCUIElement, name: String, file: StaticString = #filePath, line: UInt = #line) {
        // Simulator 坐标可能出现 43.999… 浮点误差，按 0.5pt 容差视为达到 44pt
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.5, "\(name) 宽应≥44，实际 \(element.frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.5, "\(name) 高应≥44，实际 \(element.frame)", file: file, line: line)
    }

    private static func assertNoOverlap(
        _ a: XCUIElement,
        _ b: XCUIElement,
        minGap: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let af = a.frame
        let bf = b.frame
        if af.maxX <= bf.minX || bf.maxX <= af.minX {
            let gap = af.maxX <= bf.minX ? (bf.minX - af.maxX) : (af.minX - bf.maxX)
            XCTAssertGreaterThanOrEqual(gap, minGap, "水平间距应≥\(minGap)，实际 \(gap)", file: file, line: line)
            return
        }
        if af.maxY <= bf.minY || bf.maxY <= af.minY {
            let gap = af.maxY <= bf.minY ? (bf.minY - af.maxY) : (af.minY - bf.maxY)
            XCTAssertGreaterThanOrEqual(gap, minGap, "垂直间距应≥\(minGap)，实际 \(gap)", file: file, line: line)
            return
        }
        XCTFail("触控区域相交: \(af) vs \(bf)", file: file, line: line)
    }
}
