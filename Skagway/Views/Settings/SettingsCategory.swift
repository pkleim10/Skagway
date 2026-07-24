import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case library
    case video
    case dataSources
    case fileExt
    case tools
    case customMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .video: return "Video"
        case .dataSources: return "Data Sources"
        case .fileExt: return "Extensions"
        case .tools: return "Tools"
        case .customMetadata: return "Custom Metadata"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical"
        case .video: return "film"
        case .dataSources: return "folder"
        case .fileExt: return "doc.badge.gearshape"
        case .tools: return "wrench.and.screwdriver"
        case .customMetadata: return "square.grid.3x3.square.badge.ellipsis"
        }
    }
}
