import Foundation
import SwiftData

struct UITestFixtureService {
    let modelContext: ModelContext

    func seedIfRequested(now: Date = Date()) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-media-fixture") else { return }
        guard try modelContext.fetch(FetchDescriptor<MediaMoment>()).isEmpty else { return }

        let draftProject = Project(name: "Fixture 草稿项目", categoryName: "测试")
        let confirmedProject = Project(name: "Fixture 已确认项目", categoryName: "测试")
        let draft = TimeEntry(
            projectId: draftProject.id,
            projectNameSnapshot: draftProject.name,
            categoryNameSnapshot: draftProject.categoryName,
            startAt: now.addingTimeInterval(-7_200),
            endAt: now.addingTimeInterval(-5_400),
            status: .draft
        )
        let confirmed = TimeEntry(
            projectId: confirmedProject.id,
            projectNameSnapshot: confirmedProject.name,
            categoryNameSnapshot: confirmedProject.categoryName,
            startAt: now.addingTimeInterval(-14_400),
            endAt: now.addingTimeInterval(-12_600),
            status: .confirmed
        )
        let draftThought = ThoughtNote(
            body: "Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。",
            capturedAt: now.addingTimeInterval(-6_300),
            linkedEntryId: draft.id,
            linkSource: .manual
        )
        let confirmedThought = ThoughtNote(
            body: "Fixture 已确认思考全文",
            capturedAt: now.addingTimeInterval(-13_500),
            linkedEntryId: confirmed.id,
            linkSource: .manual
        )
        let photo = MediaMoment(
            kind: .photo,
            capturedAt: now.addingTimeInterval(-6_000),
            linkedEntryId: draft.id,
            linkSource: .manual,
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let video = MediaMoment(
            kind: .video,
            capturedAt: now.addingTimeInterval(-13_200),
            linkedEntryId: confirmed.id,
            linkSource: .manual,
            requestedStorage: .photosLibrary,
            storedLocation: .photosLibrary,
            photosAssetIdentifier: "ui-fixture-video",
            thumbnailData: Data(),
            durationSeconds: 12,
            status: .saved,
            originalAvailability: .unavailable
        )

        modelContext.insert(draftProject)
        modelContext.insert(confirmedProject)
        modelContext.insert(draft)
        modelContext.insert(confirmed)
        modelContext.insert(draftThought)
        modelContext.insert(confirmedThought)
        modelContext.insert(photo)
        modelContext.insert(video)
        try modelContext.save()
    }
}
