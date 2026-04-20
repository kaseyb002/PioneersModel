import Foundation

/// A complete board configuration for a Round: terrain tiles, the vertex/edge graph computed from
/// them, port placements, the number-token bag (one per non-desert tile), and the dev-card deck
/// composition. The graph is precomputed at construction so `Round` can query adjacency cheaply.
public struct GameMap: Equatable, Codable, Sendable {
    public let tiles: [Tile]
    public let vertices: [Vertex]
    public let edges: [Edge]
    public let ports: [Port]
    /// Count of each number token to distribute (2-12, excluding 7). The total must equal the
    /// number of non-desert tiles.
    public let numberTokenBag: [Int]
    public let devCardDeck: [DevCard]

    public init(
        tiles: [Tile],
        vertices: [Vertex],
        edges: [Edge],
        ports: [Port],
        numberTokenBag: [Int],
        devCardDeck: [DevCard]
    ) {
        self.tiles = tiles
        self.vertices = vertices
        self.edges = edges
        self.ports = ports
        self.numberTokenBag = numberTokenBag
        self.devCardDeck = devCardDeck
    }

    public var desertTileIDs: [TileID] {
        tiles.filter { $0.type == .desert }.map(\.id)
    }
}

// MARK: - Board building

extension GameMap {
    /// Builds the vertex / edge graph from a list of tile cube coordinates and terrain types.
    /// Number tokens are left as `nil` — assigned by `Round.init` from `numberTokenBag`.
    /// Ports are assigned to the given list of perimeter (vertexID, vertexID, kind) triples.
    static func buildBoard(
        layout: [(CubeCoord, TileType)],
        portAssignments: [(portVerts: (Int, Int), kind: Port.Kind)]
    ) -> (tiles: [Tile], vertices: [Vertex], edges: [Edge], ports: [Port]) {
        var builder = BoardBuilder()
        for (i, entry) in layout.enumerated() {
            builder.addTile(id: i, coord: entry.0, type: entry.1)
        }
        var ports: [Port] = []
        for (i, entry) in portAssignments.enumerated() {
            let (v1, v2) = entry.portVerts
            ports.append(Port(id: i, kind: entry.kind, vertexIDs: [v1, v2]))
        }
        return builder.finalize(ports: ports)
    }
}

private struct BoardBuilder {
    var tiles: [Tile] = []
    var vertices: [Vertex] = []
    var edges: [Edge] = []

    private var vertexKeys: [VertexKey: VertexID] = [:]
    private var edgeKeys: [EdgeKey: EdgeID] = [:]

    private var vAdjTiles: [VertexID: [TileID]] = [:]
    private var vAdjEdges: [VertexID: [EdgeID]] = [:]
    private var vAdjVerts: [VertexID: [VertexID]] = [:]
    private var eAdjTiles: [EdgeID: [TileID]] = [:]
    private var eEndpoints: [EdgeID: [VertexID]] = [:]

    mutating func addTile(id: TileID, coord: CubeCoord, type: TileType) {
        let dirs: [CubeCoord] = CubeCoord.directions

        var cornerVIDs: [VertexID] = []
        for c in 0..<6 {
            let key = VertexKey(coords: [coord, coord + dirs[c], coord + dirs[(c + 1) % 6]])
            let vid: VertexID
            if let existing: VertexID = vertexKeys[key] {
                vid = existing
            } else {
                vid = vertices.count
                vertexKeys[key] = vid
                vertices.append(Vertex(id: vid, adjacentTileIDs: [], adjacentEdgeIDs: [], adjacentVertexIDs: []))
                vAdjTiles[vid] = []
                vAdjEdges[vid] = []
                vAdjVerts[vid] = []
            }
            cornerVIDs.append(vid)
            if vAdjTiles[vid]?.contains(id) == false {
                vAdjTiles[vid]?.append(id)
            }
        }

        var sideEIDs: [EdgeID] = []
        for s in 0..<6 {
            let key = EdgeKey(coords: [coord, coord + dirs[s]])
            let eid: EdgeID
            if let existing: EdgeID = edgeKeys[key] {
                eid = existing
            } else {
                eid = edges.count
                edgeKeys[key] = eid
                let v1: VertexID = cornerVIDs[(s + 5) % 6]
                let v2: VertexID = cornerVIDs[s]
                eEndpoints[eid] = [v1, v2]
                eAdjTiles[eid] = []
                edges.append(Edge(id: eid, endpointVertexIDs: [v1, v2], adjacentTileIDs: []))
                if vAdjEdges[v1]?.contains(eid) == false {
                    vAdjEdges[v1]?.append(eid)
                }
                if vAdjEdges[v2]?.contains(eid) == false {
                    vAdjEdges[v2]?.append(eid)
                }
                if vAdjVerts[v1]?.contains(v2) == false {
                    vAdjVerts[v1]?.append(v2)
                }
                if vAdjVerts[v2]?.contains(v1) == false {
                    vAdjVerts[v2]?.append(v1)
                }
            }
            sideEIDs.append(eid)
            if eAdjTiles[eid]?.contains(id) == false {
                eAdjTiles[eid]?.append(id)
            }
        }

        tiles.append(Tile(
            id: id,
            coord: coord,
            type: type,
            numberToken: nil,
            vertexIDs: cornerVIDs,
            edgeIDs: sideEIDs
        ))
    }

    mutating func finalize(ports: [Port]) -> (tiles: [Tile], vertices: [Vertex], edges: [Edge], ports: [Port]) {
        var finalV: [Vertex] = []
        for i in 0..<vertices.count {
            let portID: PortID? = ports.first(where: { $0.vertexIDs.contains(i) })?.id
            finalV.append(Vertex(
                id: i,
                adjacentTileIDs: (vAdjTiles[i] ?? []).sorted(),
                adjacentEdgeIDs: (vAdjEdges[i] ?? []).sorted(),
                adjacentVertexIDs: (vAdjVerts[i] ?? []).sorted(),
                portID: portID
            ))
        }
        var finalE: [Edge] = []
        for e in edges {
            finalE.append(Edge(
                id: e.id,
                endpointVertexIDs: eEndpoints[e.id] ?? e.endpointVertexIDs,
                adjacentTileIDs: (eAdjTiles[e.id] ?? []).sorted()
            ))
        }
        return (tiles: tiles, vertices: finalV, edges: finalE, ports: ports)
    }

    private struct VertexKey: Hashable {
        let sorted: [CubeCoord]
        init(coords: [CubeCoord]) { self.sorted = coords.sorted() }
    }

    private struct EdgeKey: Hashable {
        let sorted: [CubeCoord]
        init(coords: [CubeCoord]) { self.sorted = coords.sorted() }
    }
}
