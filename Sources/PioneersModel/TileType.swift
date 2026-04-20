import Foundation

public enum TileType: String, Equatable, Codable, CaseIterable, Sendable {
    case hills
    case forest
    case pasture
    case fields
    case mountains
    case desert

    public var resource: Resource? {
        switch self {
        case .hills: .brick
        case .forest: .wood
        case .pasture: .sheep
        case .fields: .wheat
        case .mountains: .ore
        case .desert: nil
        }
    }

    public var displayableName: String {
        switch self {
        case .hills: "Hills"
        case .forest: "Forest"
        case .pasture: "Pasture"
        case .fields: "Fields"
        case .mountains: "Mountains"
        case .desert: "Desert"
        }
    }
}
