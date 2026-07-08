import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var longUnclassifiedThresholdMinutes: Int
    var exportOnlyConfirmed: Bool
    var includeDraftInTodaySummary: Bool

    init(
        id: UUID = UUID(),
        longUnclassifiedThresholdMinutes: Int = 90,
        exportOnlyConfirmed: Bool = true,
        includeDraftInTodaySummary: Bool = true
    ) {
        self.id = id
        self.longUnclassifiedThresholdMinutes = longUnclassifiedThresholdMinutes
        self.exportOnlyConfirmed = exportOnlyConfirmed
        self.includeDraftInTodaySummary = includeDraftInTodaySummary
    }
}
