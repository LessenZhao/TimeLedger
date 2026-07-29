import AppKit
import Combine
import EvolutionHubCore
import Foundation
import SwiftUI

/// Single active text selection for annotatable readers (008 L2).
@MainActor
final class MarkdownSelectionStore: ObservableObject {
    struct Selection: Equatable {
        var blockID: String
        var textUTF16Range: NSRange
        var sourceRange: NSRange
        var quote: String
        /// Selection rect in global (screen) coordinates for toolbar placement.
        var anchorRect: CGRect
    }

    @Published private(set) var active: Selection?

    func set(_ selection: Selection) {
        active = selection
    }

    func clear(ifBlockID blockID: String? = nil) {
        if let blockID {
            if active?.blockID == blockID { active = nil }
        } else {
            active = nil
        }
    }

    func clearAll() {
        active = nil
    }
}
