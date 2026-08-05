import Foundation
import SwiftData

struct UITestFixtureService {
    let modelContext: ModelContext

    func seedIfRequested(now: Date = Date()) throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            let draftRoot = ThoughtComposerDraftStore().rootURL
            if FileManager.default.fileExists(atPath: draftRoot.path) {
                try FileManager.default.removeItem(at: draftRoot)
            }
        }
        if arguments.contains("-ui-draft-scroll-fixture") {
            try seedDraftScrollFixture(now: now)
            return
        }
        if arguments.contains("-ui-review-fixture") {
            try seedReviewFixture(now: now)
            return
        }
        guard arguments.contains("-ui-media-fixture") else { return }
        guard try modelContext.fetch(FetchDescriptor<MediaMoment>()).isEmpty else { return }

        let dayStart = Calendar.current.startOfDay(for: now)
        let confirmedStart = dayStart.addingTimeInterval(60 * 60)
        let confirmedEnd = dayStart.addingTimeInterval(90 * 60)
        let draftStart = dayStart.addingTimeInterval(2 * 60 * 60)
        let draftEnd = dayStart.addingTimeInterval(150 * 60)

        let draftProject = Project(name: "Fixture 草稿项目", categoryName: "测试")
        let confirmedProject = Project(name: "Fixture 已确认项目", categoryName: "测试")
        let draft = TimeEntry(
            projectId: draftProject.id,
            projectNameSnapshot: draftProject.name,
            categoryNameSnapshot: draftProject.categoryName,
            startAt: draftStart,
            endAt: draftEnd,
            status: .draft
        )
        let confirmed = TimeEntry(
            projectId: confirmedProject.id,
            projectNameSnapshot: confirmedProject.name,
            categoryNameSnapshot: confirmedProject.categoryName,
            startAt: confirmedStart,
            endAt: confirmedEnd,
            status: .confirmed
        )
        let draftThought = ThoughtNote(
            body: "Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。",
            capturedAt: draftStart.addingTimeInterval(15 * 60),
            linkedEntryId: draft.id,
            linkSource: .manual
        )
        let confirmedThought = ThoughtNote(
            body: "Fixture 已确认思考全文",
            capturedAt: confirmedStart.addingTimeInterval(15 * 60),
            linkedEntryId: confirmed.id,
            linkSource: .manual
        )
        let photo = MediaMoment(
            kind: .photo,
            capturedAt: draftStart.addingTimeInterval(20 * 60),
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
            capturedAt: confirmedStart.addingTimeInterval(20 * 60),
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
        let standalonePhoto = MediaMoment(
            kind: .photo,
            capturedAt: draftStart.addingTimeInterval(25 * 60),
            linkedEntryId: draft.id,
            linkSource: .manual,
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let standaloneVideo = MediaMoment(
            kind: .video,
            capturedAt: confirmedStart.addingTimeInterval(25 * 60),
            linkedEntryId: confirmed.id,
            linkSource: .manual,
            requestedStorage: .photosLibrary,
            storedLocation: .photosLibrary,
            photosAssetIdentifier: "ui-fixture-standalone-video",
            thumbnailData: Data(),
            durationSeconds: 12,
            status: .saved,
            originalAvailability: .unavailable
        )
        let photoLink = ThoughtMediaLink(
            thoughtId: draftThought.id,
            mediaMomentId: photo.id,
            sortOrder: 0
        )
        let videoLink = ThoughtMediaLink(
            thoughtId: confirmedThought.id,
            mediaMomentId: video.id,
            sortOrder: 0
        )

        modelContext.insert(draftProject)
        modelContext.insert(confirmedProject)
        modelContext.insert(draft)
        modelContext.insert(confirmed)
        modelContext.insert(draftThought)
        modelContext.insert(confirmedThought)
        modelContext.insert(photo)
        modelContext.insert(video)
        modelContext.insert(standalonePhoto)
        modelContext.insert(standaloneVideo)
        modelContext.insert(photoLink)
        modelContext.insert(videoLink)
        try modelContext.save()
    }

    private func seedDraftScrollFixture(now: Date) throws {
        let project = Project(name: "Fixture 滚动项目", categoryName: "测试")
        modelContext.insert(project)

        for index in 0..<18 {
            let startAt = now.addingTimeInterval(TimeInterval(-18 + index) * 1_800)
            modelContext.insert(
                TimeEntry(
                    projectId: project.id,
                    projectNameSnapshot: String(format: "Fixture 滚动 %02d", index),
                    categoryNameSnapshot: project.categoryName,
                    startAt: startAt,
                    endAt: startAt.addingTimeInterval(1_500),
                    status: .draft
                )
            )
        }

        try modelContext.save()
    }

    /// Deterministic review data: cross-midnight, same-day multi sessions,
    /// confirmed+draft, multi-project sort order, ≥35 days history.
    private func seedReviewFixture(now: Date) throws {
        guard try modelContext.fetch(FetchDescriptor<TimeEntry>()).isEmpty else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)

        let alpha = Project(name: "复盘Alpha", categoryName: "测试")
        let beta = Project(name: "复盘Beta", categoryName: "测试")
        let gamma = Project(name: "复盘Gamma", categoryName: "测试")
        modelContext.insert(alpha)
        modelContext.insert(beta)
        modelContext.insert(gamma)

        // 35 days of modest Alpha history for long-term / anomaly baseline
        for offset in 1...35 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: dayStart) else { continue }
            let start = day.addingTimeInterval(9 * 3_600)
            modelContext.insert(
                TimeEntry(
                    projectId: alpha.id,
                    projectNameSnapshot: alpha.name,
                    categoryNameSnapshot: alpha.categoryName,
                    startAt: start,
                    endAt: start.addingTimeInterval(3_600),
                    status: .confirmed
                )
            )
        }

        // Place today's sessions relative to `now` so unfinished-day effectiveRange always covers them.
        let anchor = min(now, dayStart.addingTimeInterval(20 * 3_600))
        func todayAt(hoursBefore endOffset: TimeInterval, duration: TimeInterval) -> (Date, Date) {
            let end = max(dayStart.addingTimeInterval(duration), anchor.addingTimeInterval(-endOffset))
            let start = end.addingTimeInterval(-duration)
            return (max(start, dayStart), end)
        }

        let (c1Start, c1End) = todayAt(hoursBefore: 5 * 3_600, duration: 3_600)
        modelContext.insert(
            TimeEntry(
                projectId: alpha.id,
                projectNameSnapshot: alpha.name,
                categoryNameSnapshot: alpha.categoryName,
                startAt: c1Start,
                endAt: c1End,
                status: .confirmed
            )
        )
        let (c2Start, c2End) = todayAt(hoursBefore: 3 * 3_600, duration: 3_600)
        modelContext.insert(
            TimeEntry(
                projectId: alpha.id,
                projectNameSnapshot: alpha.name,
                categoryNameSnapshot: alpha.categoryName,
                startAt: c2Start,
                endAt: c2End,
                status: .confirmed
            )
        )
        let (dStart, dEnd) = todayAt(hoursBefore: 30 * 60, duration: 1_800)
        modelContext.insert(
            TimeEntry(
                projectId: alpha.id,
                projectNameSnapshot: alpha.name,
                categoryNameSnapshot: alpha.categoryName,
                startAt: dStart,
                endAt: dEnd,
                status: .draft
            )
        )

        let (bStart, bEnd) = todayAt(hoursBefore: 4 * 3_600, duration: 2_400)
        modelContext.insert(
            TimeEntry(
                projectId: beta.id,
                projectNameSnapshot: beta.name,
                categoryNameSnapshot: beta.categoryName,
                startAt: bStart,
                endAt: bEnd,
                status: .confirmed
            )
        )

        let (gStart, gEnd) = todayAt(hoursBefore: 2 * 3_600, duration: 1_200)
        modelContext.insert(
            TimeEntry(
                projectId: gamma.id,
                projectNameSnapshot: gamma.name,
                categoryNameSnapshot: gamma.categoryName,
                startAt: gStart,
                endAt: gEnd,
                status: .confirmed
            )
        )

        // Cross-midnight into today (counts toward today morning)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart) else {
            try modelContext.save()
            return
        }
        modelContext.insert(
            TimeEntry(
                projectId: alpha.id,
                projectNameSnapshot: alpha.name,
                categoryNameSnapshot: alpha.categoryName,
                startAt: yesterday.addingTimeInterval(23 * 3_600),
                endAt: dayStart.addingTimeInterval(1 * 3_600),
                status: .confirmed
            )
        )

        // Earlier this week / month extra Beta for week charts
        if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: dayStart) {
            modelContext.insert(
                TimeEntry(
                    projectId: beta.id,
                    projectNameSnapshot: beta.name,
                    categoryNameSnapshot: beta.categoryName,
                    startAt: twoDaysAgo.addingTimeInterval(14 * 3_600),
                    endAt: twoDaysAgo.addingTimeInterval(15 * 3_600),
                    status: .confirmed
                )
            )
        }

        try modelContext.save()
    }
}
