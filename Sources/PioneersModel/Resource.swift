import Foundation

public enum Resource: String, Equatable, Codable, CaseIterable, Hashable, Sendable {
    case wood
    case brick
    case wheat
    case sheep
    case ore

    public var displayableName: String {
        switch self {
        case .wood: "Wood"
        case .brick: "Brick"
        case .wheat: "Wheat"
        case .sheep: "Sheep"
        case .ore: "Ore"
        }
    }
}

extension Resource {
    public var displaySortOrder: Int {
        switch self {
        case .wood: 0
        case .brick: 1
        case .wheat: 2
        case .sheep: 3
        case .ore: 4
        }
    }
}

extension [Resource] {
    public var sortedForDisplay: [Resource] {
        sorted { $0.displaySortOrder < $1.displaySortOrder }
    }
}
