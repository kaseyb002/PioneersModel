import Foundation

public enum BuildingKind: String, Equatable, Codable, CaseIterable, Sendable {
    case homestead
    case town

    public var displayableName: String {
        switch self {
        case .homestead: "Homestead"
        case .town: "Town"
        }
    }

    public var victoryPoints: Int {
        switch self {
        case .homestead: 1
        case .town: 2
        }
    }

    public var resourceYield: Int {
        switch self {
        case .homestead: 1
        case .town: 2
        }
    }
}

public struct Building: Equatable, Codable, Sendable {
    public let kind: BuildingKind
    public let ownerID: PlayerID
    public let vertexID: VertexID

    public enum CodingKeys: String, CodingKey {
        case kind
        case ownerID = "ownerId"
        case vertexID = "vertexId"
    }

    public init(
        kind: BuildingKind,
        ownerID: PlayerID,
        vertexID: VertexID
    ) {
        self.kind = kind
        self.ownerID = ownerID
        self.vertexID = vertexID
    }
}

extension Building {
    public static func fake(
        kind: BuildingKind = .homestead,
        ownerID: PlayerID = "p1",
        vertexID: VertexID = 0
    ) -> Building {
        Building(
            kind: kind,
            ownerID: ownerID,
            vertexID: vertexID
        )
    }
}
