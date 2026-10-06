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

    /// Returns a copy with the same coordinates, graph, and ports, but terrain types permuted.
    /// The multiset of tile types is unchanged (including desert count). Number tokens stay `nil`
    /// so `Round` can assign them after the shuffle.
    public func shufflingTileTypes() -> GameMap {
        let shuffledTypes: [TileType] = tiles.map(\.type).shuffled()
        let shuffledTiles: [Tile] = zip(tiles, shuffledTypes).map { tile, type in
            Tile(
                id: tile.id,
                coord: tile.coord,
                type: type,
                numberToken: nil,
                vertexIDs: tile.vertexIDs,
                edgeIDs: tile.edgeIDs
            )
        }
        return GameMap(
            tiles: shuffledTiles,
            vertices: vertices,
            edges: edges,
            ports: ports,
            numberTokenBag: numberTokenBag,
            devCardDeck: devCardDeck
        )
    }
}

// MARK: - Board building

extension GameMap {
    /// Tile IDs ordered counterclockwise around each successive outer ring, moving inward.
    /// The first tile is an arbitrary corner, matching the rule that setup may start at any corner.
    func spiralTileIDs() -> [TileID] {
        var remaining: [Tile] = tiles
        var result: [TileID] = []

        while !remaining.isEmpty {
            let remainingCoords: Set<CubeCoord> = Set(remaining.map(\.coord))
            let ring: [Tile] = remaining.filter { tile in
                CubeCoord.directions.contains { !remainingCoords.contains(tile.coord + $0) }
            }
            let centerX: Double = ring.map { Double($0.coord.x) }.reduce(0, +) / Double(ring.count)
            let centerZ: Double = ring.map { Double($0.coord.z) }.reduce(0, +) / Double(ring.count)
            let orderedRing: [Tile] = ring.sorted { lhs, rhs in
                let lhsAngle: Double = atan2(Double(lhs.coord.z) - centerZ, Double(lhs.coord.x) - centerX)
                let rhsAngle: Double = atan2(Double(rhs.coord.z) - centerZ, Double(rhs.coord.x) - centerX)
                if lhsAngle != rhsAngle { return lhsAngle > rhsAngle }
                return lhs.id < rhs.id
            }

            result.append(contentsOf: orderedRing.map(\.id))
            let ringIDs: Set<TileID> = Set(ring.map(\.id))
            remaining.removeAll { ringIDs.contains($0.id) }
        }

        return result
    }

    func areAdjacent(_ lhs: Tile, _ rhs: Tile) -> Bool {
        CubeCoord.directions.contains { lhs.coord + $0 == rhs.coord }
    }

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
