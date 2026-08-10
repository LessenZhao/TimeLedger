import Foundation
import SwiftData

enum SystemProject {
    static let unknownName = "未知项目"
    static let unknownCategory = "系统"

    static func isUnknown(_ project: Project) -> Bool {
        project.name == unknownName
    }

    static func isUnknown(projectId: UUID, nameSnapshot: String) -> Bool {
        nameSnapshot == unknownName
    }

    static func isUnknownEntry(_ entry: TimeEntry) -> Bool {
        entry.projectNameSnapshot == unknownName
    }

    @discardableResult
    static func getOrCreateUnknown(modelContext: ModelContext) throws -> Project {
        let engine = TimeLedgerEngine(modelContext: modelContext)
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        if let existing = projects.first(where: { $0.name == unknownName }) {
            if existing.isArchived {
                existing.isArchived = false
                existing.updatedAt = Date()
                try engine.save()
            }
            return existing
        }

        let project = Project(
            name: unknownName,
            categoryName: unknownCategory,
            sortOrder: 9_999
        )
        engine.insert(project)
        try engine.save()
        return project
    }
}
