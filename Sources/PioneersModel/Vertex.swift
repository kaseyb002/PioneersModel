import Foundation

public typealias VertexID = Int

public struct Vertex: Equatable, Codable, Identifiable, Sendable {
    public let id: VertexID
    public let adjacentTileIDs: [TileID]
    public let adjacentEdgeIDs: [EdgeID]
    public let adjacentVertexIDs: [VertexID]
    public let portID: PortID?

    public init(
        id: VertexID,
        adjacentTileIDs: [TileID],
        adjacentEdgeIDs: [EdgeID],
        adjacentVertexIDs: [VertexID],
        portID: PortID? = nil
    ) {
        self.id = id
        self.adjacentTileIDs = adjacentTileIDs
        self.adjacentEdgeIDs = adjacentEdgeIDs
        self.adjacentVertexIDs = adjacentVertexIDs
        self.portID = portID
    }
}

extension Vertex {
    public static func fake(
        id: VertexID = 0,
        adjacentTileIDs: [TileID] = [],
        adjacentEdgeIDs: [EdgeID] = [],
        adjacentVertexIDs: [VertexID] = [],
        portID: PortID? = nil
    ) -> Vertex {
        Vertex(
            id: id,
            adjacentTileIDs: adjacentTileIDs,
            adjacentEdgeIDs: adjacentEdgeIDs,
            adjacentVertexIDs: adjacentVertexIDs,
            portID: portID
        )
    }
}
