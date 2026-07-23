import Foundation

/// Kind of long-running work shown in the global activity strip.
enum AppActivityKind: String, Equatable {
    case scanning
    case fingerprinting
    case importingMetadata
    case exportingMetadata
    case reencoding
    case moving
    case deleting
    case message
    case error
}

/// Action when the user clicks an activity chip / primary row.
enum AppActivityAction: Equatable {
    case openConversionQueue
    case openMoveQueue
}

/// One unit of work for the bottom activity strip.
struct AppActivity: Identifiable, Equatable {
    let id: String
    let kind: AppActivityKind
    let title: String
    /// 0...1 when determinate; `nil` for indeterminate.
    let fraction: Double?
    let isError: Bool
    let action: AppActivityAction?

    init(
        id: String,
        kind: AppActivityKind,
        title: String,
        fraction: Double? = nil,
        isError: Bool = false,
        action: AppActivityAction? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.fraction = fraction
        self.isError = isError
        self.action = action
    }
}

/// Snapshot for the bottom activity strip (Option B).
struct ActivityStripState: Equatable {
    /// Headline activity (left): fullest treatment.
    var primary: AppActivity?
    /// Concurrent jobs as compact pills (right).
    var secondaries: [AppActivity]

    var isVisible: Bool { primary != nil || !secondaries.isEmpty }

    static let empty = ActivityStripState(primary: nil, secondaries: [])
}
