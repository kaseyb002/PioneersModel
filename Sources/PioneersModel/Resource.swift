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
