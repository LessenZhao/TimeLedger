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
            if !arguments.contains("-ui-keep-timeline-type-mode") {
                UserDefaults.standard.removeObject(forKey: "timeline.typeMode")
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
        guard arguments.contains("-ui-media-fixture")
            || arguments.contains("-ui-unified-content-fixture") else { return }
        guard try modelContext.fetch(FetchDescriptor<MediaMoment>()).isEmpty else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let elapsedToday = max(60, now.timeIntervalSince(dayStart))
        let fixtureUnit = min(30 * 60, elapsedToday / 8)
        let confirmedStart = dayStart.addingTimeInterval(fixtureUnit)
        let confirmedEnd = dayStart.addingTimeInterval(fixtureUnit * 2)
        let draftStart = dayStart.addingTimeInterval(fixtureUnit * 3)
        let draftEnd = dayStart.addingTimeInterval(fixtureUnit * 4)
        let confirmedContentAt = confirmedStart.addingTimeInterval(fixtureUnit / 2)
        let draftContentAt = draftStart.addingTimeInterval(fixtureUnit / 2)

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
        let longBody = Array(
            repeating: "Fixture 草稿思考全文，用于证明第一层只显示三行并可继续展开。加长段落确保超过六行收起限制。",
            count: 12
        ).joined(separator: "\n\n")
        let draftJournal = JournalEntry(capturedAt: draftContentAt, anchorAt: draftContentAt)
        let confirmedJournal = JournalEntry(capturedAt: confirmedContentAt, anchorAt: confirmedContentAt)
        let photoOnlyJournal = JournalEntry(
            capturedAt: draftContentAt.addingTimeInterval(fixtureUnit / 6),
            anchorAt: draftContentAt.addingTimeInterval(fixtureUnit / 6)
        )
        let shortStandaloneJournal = JournalEntry(capturedAt: now.addingTimeInterval(90), anchorAt: now.addingTimeInterval(90))
        let photo = MediaMoment(
            kind: .photo,
            capturedAt: draftContentAt,
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let video = MediaMoment(
            kind: .video,
            capturedAt: confirmedContentAt,
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
            capturedAt: draftContentAt.addingTimeInterval(fixtureUnit / 8),
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let standaloneVideo = MediaMoment(
            kind: .video,
            capturedAt: confirmedContentAt.addingTimeInterval(fixtureUnit / 8),
            requestedStorage: .photosLibrary,
            storedLocation: .photosLibrary,
            photosAssetIdentifier: "ui-fixture-standalone-video",
            thumbnailData: Data(),
            durationSeconds: 12,
            status: .saved,
            originalAvailability: .unavailable
        )
        let automaticStandalonePhoto = MediaMoment(
            kind: .photo,
            capturedAt: draftContentAt.addingTimeInterval(fixtureUnit / 10),
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let photoOnlyMedia = MediaMoment(
            kind: .photo,
            capturedAt: photoOnlyJournal.capturedAt,
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )

        // 7 月 20 日条目：备注照片与条目内思考的真实录入在“今天”，语义时间落在 7 月 20 日
        var julyComponents = calendar.dateComponents([.year], from: now)
        julyComponents.month = 7
        julyComponents.day = 20
        julyComponents.hour = 10
        julyComponents.minute = 0
        let july20Start = calendar.date(from: julyComponents) ?? dayStart.addingTimeInterval(-17 * 24 * 3600)
        let july20End = july20Start.addingTimeInterval(2 * 3600)
        let julyProject = Project(name: "Fixture 七月项目", categoryName: "测试")
        let julyEntry = TimeEntry(
            projectId: julyProject.id,
            projectNameSnapshot: julyProject.name,
            categoryNameSnapshot: julyProject.categoryName,
            startAt: july20Start,
            endAt: july20End,
            status: .confirmed
        )
        let julyNotePhoto = MediaMoment(
            kind: .photo,
            capturedAt: now,
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let julyJournal = JournalEntry(capturedAt: now, anchorAt: now)
        let homeJournal = JournalEntry(capturedAt: now.addingTimeInterval(60), anchorAt: now.addingTimeInterval(60))
        let homePhoto = MediaMoment(
            kind: .photo,
            capturedAt: now.addingTimeInterval(120),
            requestedStorage: .app,
            storedLocation: .app,
            thumbnailData: Data(),
            status: .saved,
            originalAvailability: .unavailable
        )
        let homeVideo = MediaMoment(
            kind: .video,
            capturedAt: now.addingTimeInterval(180),
            requestedStorage: .photosLibrary,
            storedLocation: .photosLibrary,
            photosAssetIdentifier: "ui-fixture-home-video",
            thumbnailData: Data(),
            durationSeconds: 8,
            status: .saved,
            originalAvailability: .unavailable
        )

        modelContext.insert(draftProject)
        modelContext.insert(confirmedProject)
        modelContext.insert(julyProject)
        insertEntry(draft, body: "Fixture 草稿备注")
        insertEntry(confirmed, body: "Fixture 已确认备注")
        insertEntry(julyEntry, body: "Fixture 七月备注")
        insertJournal(draftJournal, body: longBody, linkedEntryID: draft.id)
        insertJournal(confirmedJournal, body: "Fixture 已确认思考全文", linkedEntryID: confirmed.id)
        insertJournal(photoOnlyJournal, body: "")
        insertJournal(shortStandaloneJournal, body: "短文无展开")
        insertJournal(julyJournal, body: "Fixture 七月条目思考", linkedEntryID: julyEntry.id)
        insertJournal(homeJournal, body: "Fixture 首页独立思考")
        modelContext.insert(photo)
        modelContext.insert(video)
        modelContext.insert(standalonePhoto)
        modelContext.insert(standaloneVideo)
        modelContext.insert(automaticStandalonePhoto)
        modelContext.insert(photoOnlyMedia)
        modelContext.insert(julyNotePhoto)
        modelContext.insert(homePhoto)
        modelContext.insert(homeVideo)
        attach(photo, to: draftJournal.id)
        attach(video, to: confirmedJournal.id)
        attach(photoOnlyMedia, to: photoOnlyJournal.id)
        attach(standalonePhoto, toOwner: draft.id, kind: .timeEntry)
        attach(standaloneVideo, toOwner: confirmed.id, kind: .timeEntry)
        let automaticMediaJournal = JournalEntry(capturedAt: automaticStandalonePhoto.capturedAt, anchorAt: automaticStandalonePhoto.capturedAt)
        insertJournal(automaticMediaJournal, body: "")
        attach(automaticStandalonePhoto, to: automaticMediaJournal.id)
        attach(julyNotePhoto, toOwner: julyEntry.id, kind: .timeEntry)
        let homePhotoJournal = JournalEntry(capturedAt: homePhoto.capturedAt, anchorAt: homePhoto.capturedAt)
        let homeVideoJournal = JournalEntry(capturedAt: homeVideo.capturedAt, anchorAt: homeVideo.capturedAt)
        insertJournal(homePhotoJournal, body: "")
        insertJournal(homeVideoJournal, body: "")
        attach(homePhoto, to: homePhotoJournal.id)
        attach(homeVideo, to: homeVideoJournal.id)
        try ensureEntryDocuments()
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

        try ensureEntryDocuments()
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
            try ensureEntryDocuments()
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

        try ensureEntryDocuments()
        try modelContext.save()
    }

    private func insertEntry(_ entry: TimeEntry, body: String) {
        modelContext.insert(entry)
        modelContext.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: body))
    }

    private func insertJournal(_ journal: JournalEntry, body: String, linkedEntryID: UUID? = nil) {
        modelContext.insert(journal)
        modelContext.insert(ContentDocument(ownerID: journal.id, ownerKind: .journalEntry, body: body))
        if let linkedEntryID {
            modelContext.insert(
                JournalTimeLink(
                    journalEntryID: journal.id,
                    timeEntryID: linkedEntryID,
                    linkSource: .manual
                )
            )
        }
    }

    private func attach(_ media: MediaMoment, to journalID: UUID) {
        attach(media, toOwner: journalID, kind: .journalEntry)
    }

    private func attach(_ media: MediaMoment, toOwner ownerID: UUID, kind: ContentOwnerKind) {
        let documents = (try? modelContext.fetch(FetchDescriptor<ContentDocument>())) ?? []
        guard let document = documents.first(where: { $0.ownerID == ownerID && $0.ownerKind == kind.rawValue }) else {
            return
        }
        modelContext.insert(ContentAttachment(contentDocumentID: document.id, mediaMomentID: media.id, state: .ready))
    }

    private func ensureEntryDocuments() throws {
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let existingOwnerIDs = Set(documents.filter { $0.ownerKind == ContentOwnerKind.timeEntry.rawValue }.map(\.ownerID))
        for entry in entries where !existingOwnerIDs.contains(entry.id) {
            modelContext.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry))
        }
    }
}
