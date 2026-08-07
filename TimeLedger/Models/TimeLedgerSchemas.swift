import SwiftData

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

enum TimeLedgerMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        TimeLedgerSchemaV1.self,
        TimeLedgerSchemaV2.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: TimeLedgerSchemaV1.self, toVersion: TimeLedgerSchemaV2.self),
    ]
}
