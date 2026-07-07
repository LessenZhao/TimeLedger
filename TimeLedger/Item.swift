//
//  Item.swift
//  TimeLedger
//
//  Created by Lessen Zhao on 2026/7/8.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
