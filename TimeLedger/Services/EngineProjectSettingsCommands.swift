import Foundation
import SwiftData

@MainActor
struct ProjectCommandHandler {
    let modelContext: ModelContext

    func saveProject(
        project: Project?,
        name: String,
        categoryName: String,
        emoji: String?,
        colorHex: String?,
        sortOrder: Int,
        isArchived: Bool
    ) throws {
        if let project {
            project.name = name
            project.categoryName = categoryName
            project.emoji = emoji
            project.colorHex = colorHex
            project.sortOrder = sortOrder
            project.isArchived = isArchived
            project.updatedAt = Date()
        } else {
            modelContext.insert(Project(
                name: name,
                categoryName: categoryName,
                emoji: emoji,
                colorHex: colorHex,
                sortOrder: sortOrder,
                isArchived: isArchived
            ))
        }
        try modelContext.save()
    }

    func deleteProject(_ project: Project) throws {
        modelContext.delete(project)
        try modelContext.save()
    }
}

@MainActor
struct SettingsCommandHandler {
    let modelContext: ModelContext

    func getOrCreateAppSettings() throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    func saveAppSettings(_ settings: AppSettings) throws {
        try modelContext.save()
    }
}
