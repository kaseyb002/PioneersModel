import Foundation

public typealias TileID = Int

public struct Tile: Equatable, Codable, Identifiable, Sendable {
    public let id: TileID
    public let coord: CubeCoord
    public let type: TileType
    public let numberToken: Int?
    /// Six vertex IDs that are the corners of this hex, in order (matching `CubeCoord.directions`).
    public let vertexIDs: [VertexID]
    /// Six edge IDs that are the sides of this hex, in order (edge `i` lies in `directions[i]`).
    public let edgeIDs: [EdgeID]

    public init(
        id: TileID,
        coord: CubeCoord,
        type: TileType,
        numberToken: Int?,
        vertexIDs: [VertexID],
        edgeIDs: [EdgeID]
    ) {
        self.id = id
        self.coord = coord
        self.type = type
        self.numberToken = numberToken
        self.vertexIDs = vertexIDs
        self.edgeIDs = edgeIDs
    }
}

extension Tile {
    public static func fake(
        id: TileID = 0,
        coord: CubeCoord = CubeCoord(x: 0, y: 0, z: 0),
        type: TileType = .fields,
        numberToken: Int? = 6,
        vertexIDs: [VertexID] = [0, 1, 2, 3, 4, 5],
        edgeIDs: [EdgeID] = [0, 1, 2, 3, 4, 5]
    ) -> Tile {
        Tile(
            id: id,
            coord: coord,
            type: type,
            numberToken: numberToken,
            vertexIDs: vertexIDs,
            edgeIDs: edgeIDs
        )
    }
}
