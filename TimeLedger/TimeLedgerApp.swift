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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(TimeLedgerModels.all)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

enum TimeLedgerModels {
    static let all: [any PersistentModel.Type] = [
        Project.self,
        TimeCursor.self,
        TimeEntry.self,
        AppSettings.self,
    ]
}
