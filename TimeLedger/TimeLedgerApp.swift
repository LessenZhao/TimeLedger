//
//  TimeLedgerApp.swift
//  TimeLedger
//
//  Created by Lessen Zhao on 2026/7/8.
//

import SwiftUI
import SwiftData

@main
struct TimeLedgerApp: App {
    @State private var bootstrapState: TimeLedgerBootstrapState

    init() {
        _bootstrapState = State(initialValue: Self.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .blocked(let reason):
                ContentMigrationGateView(reason: reason) {
                    bootstrapState = Self.bootstrap()
                }
            }
        }
    }

    @MainActor
    private static func bootstrap() -> TimeLedgerBootstrapState {
        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            do {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return .ready(try ModelContainer(for: schema, configurations: [configuration]))
            } catch {
                return .blocked(error.localizedDescription)
            }
        }

        let defaultConfiguration = ModelConfiguration(schema: schema)
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let result = ContentMigrationCoordinator.open(
            storeURL: defaultConfiguration.url,
            backupRootURL: applicationSupport
                .appending(path: "MigrationBackups", directoryHint: .isDirectory)
                .appending(path: "ContentSchemaV1", directoryHint: .isDirectory)
        )
        switch result {
        case .ready(let container):
            return .ready(container)
        case .blocked(let reason):
            return .blocked(reason)
        }
    }
}

private enum TimeLedgerBootstrapState {
    case ready(ModelContainer)
    case blocked(String)
}

private struct ContentMigrationGateView: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("内容迁移尚未完成")
                .font(.title2.bold())
            Text(reason)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("migration.retry")
        }
        .padding(28)
        .accessibilityIdentifier("migration.gate")
    }
}

enum TimeLedgerModels {
    static let all: [any PersistentModel.Type] = TimeLedgerSchemaV2.models
}
