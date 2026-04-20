import Foundation

public struct Trail: Equatable, Codable, Sendable {
    public let ownerID: PlayerID
    public let edgeID: EdgeID

    public enum CodingKeys: String, CodingKey {
        case ownerID = "ownerId"
        case edgeID = "edgeId"
    }

    public init(
        ownerID: PlayerID,
        edgeID: EdgeID
    ) {
        self.ownerID = ownerID
        self.edgeID = edgeID
    }
}

extension Trail {
    public static func fake(
        ownerID: PlayerID = "p1",
        edgeID: EdgeID = 0
    ) -> Trail {
        Trail(
            ownerID: ownerID,
            edgeID: edgeID
        )
    }
}
