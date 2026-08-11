import Foundation
import Testing
@testable import TimeLedger

struct ArchitectureBoundaryTests {
    private enum ProductionV3Checker {
        static func violations(appSource: String, migrationSource: String) -> [String] {
            var violations: [String] = []
            if !appSource.contains("Schema(versionedSchema: TimeLedgerSchemaV3.self)") {
                violations.append("TimeLedgerApp.bootstrap")
            }
            if !appSource.contains("TimeLedgerSchemaV3.models") {
                violations.append("TimeLedgerModels.all")
            }
            if !migrationSource.contains("Schema(versionedSchema: TimeLedgerSchemaV3.self)") {
                violations.append("ContentMigrationCoordinator.open")
            }
            if appSource.contains("FrozenThoughtRecord")
                || appSource.contains("FrozenThoughtMediaRecord") {
                violations.append("TimeLedgerModels.all includes frozen models")
            }
            return violations
        }
    }

    private enum LegacyBusinessModelChecker {
        static let allowedPaths: Set<String> = [
            "TimeLedger/Models/LegacyMigrationModels.swift",
            "TimeLedger/Models/TimeLedgerSchemas.swift",
            "TimeLedger/Models/ThoughtNote.swift",
            "TimeLedger/Models/ThoughtMediaLink.swift",
            "TimeLedger/Services/ContentMigrationService.swift",
        ]

        static let pattern = #"\b(ThoughtNote|ThoughtMediaLink|FrozenThoughtRecord|FrozenThoughtMediaRecord|ThoughtLinkingService|ThoughtComposerCommitService|ThoughtMediaLinkService|TimeEntryAttachmentService)\b"#

        static func isViolation(path: String, content: String) -> Bool {
            if allowedPaths.contains(path) {
                return (path.hasSuffix("ThoughtNote.swift") || path.hasSuffix("ThoughtMediaLink.swift"))
                    && content.contains("typealias")
            }
            return content.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private enum WriteBoundaryChecker {
        static let pattern = #"modelContext\.(insert|delete|save)|(?<![A-Za-z])context\.(insert|delete|save)"#

        static func containsDirectWrite(in text: String) -> Bool {
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static let writeGatekeepers: Set<String> = [
        "TimeLedgerEngine.swift",
        "EngineContentCommands.swift",
        "EngineJournalCommands.swift",
        "EngineImportCommands.swift",
        "EngineProjectSettingsCommands.swift",
        "EngineFixtureCommands.swift",
        "EngineMediaMomentCommands.swift",
        "EngineActionCompletionCommands.swift",
        "ContentMigrationService.swift",
        "ContentRollback.swift",
    ]

    @Test func violationSampleTurnsWriteBoundaryCheckerRed() {
        let sample = """
        func bad() {
            modelContext.insert(entry)
            try modelContext.save()
        }
        """
        #expect(WriteBoundaryChecker.containsDirectWrite(in: sample))
    }

    @Test func violationSampleTurnsProductionV3CheckerRed() {
        let v2App = """
        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        let all = TimeLedgerSchemaV2.models
        """
        let v2Migration = "Schema(versionedSchema: TimeLedgerSchemaV2.self)"
        #expect(
            ProductionV3Checker.violations(appSource: v2App, migrationSource: v2Migration)
                == ["TimeLedgerApp.bootstrap", "TimeLedgerModels.all", "ContentMigrationCoordinator.open"]
        )
    }

    @Test func frozenModelsCannotBeAddedBackToDebugModelRegistry() {
        let disguisedApp = """
        let schema = Schema(versionedSchema: TimeLedgerSchemaV3.self)
        let all = TimeLedgerSchemaV3.models + [FrozenThoughtRecord.self]
        """
        let v3Migration = "Schema(versionedSchema: TimeLedgerSchemaV3.self)"
        #expect(
            ProductionV3Checker.violations(
                appSource: disguisedApp,
                migrationSource: v3Migration
            ).contains("TimeLedgerModels.all includes frozen models")
        )
    }

    @Test func productionLaunchMigrationAndModelsUseV3() throws {
        let appSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("TimeLedger/TimeLedgerApp.swift"),
            encoding: .utf8
        )
        let migrationSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("TimeLedger/Services/ContentMigrationService.swift"),
            encoding: .utf8
        )
        let violations = ProductionV3Checker.violations(
            appSource: appSource,
            migrationSource: migrationSource
        )
        #expect(violations.isEmpty, "生产启动、迁移协调器和 TimeLedgerModels 必须统一 V3：\(violations)")
    }

    @Test func violationSampleTurnsLegacyBusinessModelCheckerRed() {
        #expect(LegacyBusinessModelChecker.isViolation(
            path: "TimeLedger/Services/BadService.swift",
            content: "func save(_ note: ThoughtNote) {}"
        ))
        #expect(!LegacyBusinessModelChecker.isViolation(
            path: "TimeLedger/Services/ContentMigrationService.swift",
            content: "func migrate(_ note: ThoughtNote) {}"
        ))
        #expect(LegacyBusinessModelChecker.isViolation(
            path: "TimeLedger/Services/ThoughtLinkingService.swift",
            content: "struct ThoughtLinkingService { let note: FrozenThoughtRecord }"
        ))
        #expect(LegacyBusinessModelChecker.isViolation(
            path: "TimeLedger/Models/ThoughtNote.swift",
            content: "typealias FrozenThoughtRecord = ThoughtNote"
        ))
    }

    @Test func productionBusinessSourceDoesNotReferenceFrozenModels() throws {
        let offenders = try Self.swiftSources(in: "TimeLedger")
            .filter { LegacyBusinessModelChecker.isViolation(path: $0.path, content: $0.content) }
            .map(\.path)
            .sorted()
        #expect(
            offenders.isEmpty,
            "ThoughtNote/ThoughtMediaLink 只允许出现在冻结模型和迁移实现：\(offenders)"
        )
    }

    @Test func productionViewsHaveNoDirectDatabaseWrites() throws {
        let offenders = try Self.sourceFiles(in: "TimeLedger/Views")
            .filter { WriteBoundaryChecker.containsDirectWrite(in: $0.content) }
        #expect(offenders.isEmpty, "Views 不得直接写数据库：\(offenders.map(\.name))")
    }

    @Test func productionServicesWriteOnlyThroughEngineOrMigration() throws {
        let offenders = try Self.sourceFiles(in: "TimeLedger/Services")
            .filter { WriteBoundaryChecker.containsDirectWrite(in: $0.content) }
            .filter { !Self.writeGatekeepers.contains($0.name) }
        #expect(offenders.isEmpty, "Services 只能经 Engine/迁移写入：\(offenders.map { $0.name })")
    }

    @Test func productionUtilitiesHaveNoDirectDatabaseWrites() throws {
        let offenders = try Self.sourceFiles(in: "TimeLedger/Utilities")
            .filter { WriteBoundaryChecker.containsDirectWrite(in: $0.content) }
        #expect(offenders.isEmpty, "Utilities 不得直接写数据库：\(offenders.map(\.name))")
    }

    @Test func timeEntryRemainsSinglePhysicalModel() throws {
        let modelFiles = try Self.sourceFiles(in: "TimeLedger/Models")
        let splitTypes = modelFiles.filter {
            $0.content.contains("TimeFact") || $0.content.contains("EntryClassification")
        }
        #expect(splitTypes.isEmpty, "禁止拆分 TimeEntry 物理模型")
        let legacyModels = try #require(
            modelFiles.first { $0.name == "LegacyMigrationModels.swift" }
        )
        #expect(legacyModels.content.contains("final class TimeEntry {"))
    }

    @Test func releaseLaunchPathHasNoUITestFixtureCall() throws {
        let contentView = try #require(
            try Self.sourceFiles(in: "TimeLedger").first { $0.name == "ContentView.swift" }
        )
        #expect(contentView.content.contains("#if DEBUG"))
        #expect(contentView.content.contains("UITestFixtureService"))
        let debugRange = contentView.content.range(of: "#if DEBUG")!
        let callRange = contentView.content.range(of: "UITestFixtureService")!
        #expect(debugRange.upperBound < callRange.lowerBound)
    }

    @Test func syncJSONUsesEvolutionCoreTypedDTOs() throws {
        let files = try Self.sourceFiles(in: "TimeLedger/Services")
        for name in ["SyncEnvelopeExportService.swift", "EngineImportCommands.swift", "MirrorNetworkPhoneClient.swift"] {
            let file = try #require(files.first { $0.name == name })
            #expect(file.content.contains("import EvolutionCore"))
            #expect(!file.content.contains("JSONSerialization"))
        }
    }

    @Test func xcodeProjectLinksEvolutionCore() throws {
        let projectURL = Self.repoRoot
            .appendingPathComponent("TimeLedger.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        let content = try String(contentsOf: projectURL, encoding: .utf8)
        #expect(content.contains("XCLocalSwiftPackageReference"))
        #expect(content.contains("relativePath = Packages/EvolutionCore"))
        #expect(content.contains("productName = EvolutionCore"))
    }

    @Test func engineDoesNotExposeGenericWriteWrappers() throws {
        let engineSource = try String(
            contentsOf: Self.repoRoot
                .appendingPathComponent("TimeLedger/Services/TimeLedgerEngine.swift"),
            encoding: .utf8
        )
        #expect(
            !engineSource.contains("func insert<T: PersistentModel>"),
            "Engine 不得暴露泛型 insert<T>"
        )
        #expect(
            !engineSource.contains("func delete<T: PersistentModel>"),
            "Engine 不得暴露泛型 delete<T>"
        )
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func sourceFiles(in relativeDirectory: String) throws -> [(name: String, content: String)] {
        let directory = repoRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var files: [(name: String, content: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    private static func swiftSources(in relativeDirectory: String) throws -> [(path: String, content: String)] {
        let directory = repoRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var files: [(path: String, content: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relativePath = url.path.replacingOccurrences(
                of: repoRoot.path + "/",
                with: ""
            )
            files.append((relativePath, try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }
}
