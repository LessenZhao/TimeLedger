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
                try engine.saveProject(
                    project: existing,
                    name: existing.name,
                    categoryName: existing.categoryName,
                    emoji: existing.emoji,
                    colorHex: existing.colorHex,
                    sortOrder: existing.sortOrder,
                    isArchived: false
                )
            }
            return existing
        }

        try engine.saveProject(
            project: nil,
            name: unknownName,
            categoryName: unknownCategory,
            emoji: nil,
            colorHex: nil,
            sortOrder: 9_999,
            isArchived: false
        )
        let allProjects = try modelContext.fetch(FetchDescriptor<Project>())
        return allProjects.first(where: { $0.name == unknownName })!
    }
}
