import Foundation
import SwiftData

@MainActor
struct ActionCompletionCommandHandler {
    let modelContext: ModelContext

    /// 插入新 ActionItem 并提交。
    func saveItem(_ item: ActionItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }

    /// 插入新 ActionCompletion 并提交。
    func saveCompletion(_ completion: ActionCompletion) throws {
        modelContext.insert(completion)
        try modelContext.save()
    }

    /// 删除 ActionCompletion 并提交。
    func deleteCompletion(_ completion: ActionCompletion) throws {
        modelContext.delete(completion)
        try modelContext.save()
    }
}
