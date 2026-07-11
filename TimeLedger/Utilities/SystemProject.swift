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
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        if let existing = projects.first(where: { $0.name == unknownName }) {
            if existing.isArchived {
                existing.isArchived = false
                existing.updatedAt = Date()
                try modelContext.save()
            }
            return existing
        }

        let project = Project(
            name: unknownName,
            categoryName: unknownCategory,
            sortOrder: 9_999
        )
        modelContext.insert(project)
        try modelContext.save()
        return project
    }
}
