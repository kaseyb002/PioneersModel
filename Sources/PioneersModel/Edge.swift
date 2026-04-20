import Foundation

public typealias EdgeID = Int

public struct Edge: Equatable, Codable, Identifiable, Sendable {
    public let id: EdgeID
    /// The two vertex IDs this edge connects.
    public let endpointVertexIDs: [VertexID]
    /// The 1 or 2 tile IDs this edge lies on the border of.
    public let adjacentTileIDs: [TileID]

    public init(
        id: EdgeID,
        endpointVertexIDs: [VertexID],
        adjacentTileIDs: [TileID]
    ) {
        self.id = id
        self.endpointVertexIDs = endpointVertexIDs
        self.adjacentTileIDs = adjacentTileIDs
    }
}

extension Edge {
    public static func fake(
        id: EdgeID = 0,
        endpointVertexIDs: [VertexID] = [0, 1],
        adjacentTileIDs: [TileID] = [0]
    ) -> Edge {
        Edge(
            id: id,
            endpointVertexIDs: endpointVertexIDs,
            adjacentTileIDs: adjacentTileIDs
        )
    }
}
