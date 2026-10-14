import Foundation

public enum PlayerColor: String, Equatable, Codable, CaseIterable, Sendable {
    case red
    case blue
    case purple
    case orange
    case green
    case brown

    public var displayableName: String {
        switch self {
        case .red: "Red"
        case .blue: "Blue"
        case .purple: "Purple"
        case .orange: "Orange"
        case .green: "Green"
        case .brown: "Brown"
        }
    }
}
