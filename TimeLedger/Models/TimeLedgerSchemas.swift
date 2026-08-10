import SwiftData

/// V1：原始发布版模型集合，使用真实 @Model 类型。
enum TimeLedgerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Project.self,
        TimeCursor.self,
        TimeEntry.self,
        AppSettings.self,
        ThoughtNote.self,
        ActionItem.self,
        ActionCompletion.self,
        MediaMoment.self,
        ThoughtMediaLink.self,
    ]
}

/// V2：V1 + 内容模型（ContentDocument、JournalEntry、JournalTimeLink、ContentAttachment）。
enum TimeLedgerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any PersistentModel.Type] = TimeLedgerSchemaV1.models + [
        ContentDocument.self,
        JournalEntry.self,
        JournalTimeLink.self,
        ContentAttachment.self,
        ContentMigrationCheckpoint.self,
    ]
}

/// V3：正式事实模型 + 内容模型，不含 ThoughtNote / ThoughtMediaLink。
enum TimeLedgerSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Project.self,
        TimeCursor.self,
        TimeEntry.self,
        AppSettings.self,
        ActionItem.self,
        ActionCompletion.self,
        MediaMoment.self,
        ContentDocument.self,
        JournalEntry.self,
        JournalTimeLink.self,
        ContentAttachment.self,
        ContentMigrationCheckpoint.self,
    ]
}

enum TimeLedgerMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        TimeLedgerSchemaV1.self,
        TimeLedgerSchemaV2.self,
        TimeLedgerSchemaV3.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: TimeLedgerSchemaV1.self, toVersion: TimeLedgerSchemaV2.self),
        .lightweight(fromVersion: TimeLedgerSchemaV2.self, toVersion: TimeLedgerSchemaV3.self),
    ]
}

/// 引入版本化 Schema 前（`c22bc89` 等价模型）的真实历史库形状，仅引用冻结类型。
enum TimeLedgerHistoricalSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        LegacyMigration.Project.self,
        LegacyMigration.TimeCursor.self,
        LegacyMigration.TimeEntry.self,
        LegacyMigration.AppSettings.self,
        LegacyMigration.ThoughtNote.self,
        LegacyMigration.ActionItem.self,
        LegacyMigration.ActionCompletion.self,
        LegacyMigration.MediaMoment.self,
        LegacyMigration.ThoughtMediaLink.self,
    ]
}

/// 最早发布版 `9cdbf49` 的历史库形状，仅引用冻结类型。
enum TimeLedgerEarliestSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(0, 9, 0)
    static let models: [any PersistentModel.Type] = [
        LegacyMigration.Project.self,
        LegacyMigration.TimeCursor.self,
        LegacyMigration.TimeEntry.self,
        LegacyMigration.AppSettings.self,
    ]
}

enum TimeLedgerHistoricalMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        TimeLedgerHistoricalSchemaV1.self,
        TimeLedgerSchemaV2.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(
            fromVersion: TimeLedgerHistoricalSchemaV1.self,
            toVersion: TimeLedgerSchemaV2.self
        ),
    ]
}

enum TimeLedgerEarliestMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        TimeLedgerEarliestSchema.self,
        TimeLedgerSchemaV2.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(
            fromVersion: TimeLedgerEarliestSchema.self,
            toVersion: TimeLedgerSchemaV2.self
        ),
    ]
}
