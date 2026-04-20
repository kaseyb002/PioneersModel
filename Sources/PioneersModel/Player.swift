import Foundation

public typealias PlayerID = String

public struct Player: Equatable, Codable, Identifiable, Sendable {
    public let id: PlayerID
    public var name: String
    public var imageURL: URL?
    public let color: PlayerColor

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case imageURL = "imageUrl"
        case color
    }

    public init(
        id: PlayerID,
        name: String,
        imageURL: URL? = nil,
        color: PlayerColor
    ) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.color = color
    }
}
