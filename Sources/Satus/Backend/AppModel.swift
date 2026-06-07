import Foundation
import AppKit

// MARK: - App Models

enum AppSize: String, Codable {
    case regular // 1x1
    case large   // 2x2 (Hero)
}

enum AppViewMode: String, Codable {
    case grid
    case list
}

enum TagSortMode: String, Codable, CaseIterable {
    case manual
    case alphabetical
    case frequency
}

struct AppTag: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String?
    // We persist the layout of apps within this tag (order, size)
    var items: [String] = [] // List of Bundle IDs in order
    var usageCount: Int = 0
}

struct AppItem: Identifiable, Hashable {
    let id: String // Bundle Identifier
    let name: String
    let icon: NSImage
    let url: URL
    let category: String? // e.g. public.app-category.utilities
    
    var size: AppSize = .regular // Default/Home size
    var tags: Set<UUID> = []
    
    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// DTO for persistence
struct AppItemDTO: Codable {
    let id: String
    var tagIDs: Set<UUID>
}

struct AppTagDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String?
    let items: [String]
    let usageCount: Int?
}

import SwiftUI

struct AppInternalDragItem: Codable, Transferable {
    let id: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Focus Model
enum AppFocusArea: Hashable {
    case sidebar
    case grid(String) // App ID
}

enum SidebarSelection: Hashable {
    case allApps
    case openApps
    case utilities
    case untagged
    case tag(UUID)
    case headless   // CLI tools, package-manager installs, LaunchAgents/Daemons.
}
