import Foundation

// MARK: - Standard (3-4 Player) Board

extension GameMap {
    /// The 3-4 player board: 19 hex tiles (radius-2), 18 number tokens, 9 ports, 25-card dev deck.
    /// Tile terrain is placed in a fixed order so the board graph and port assignments are
    /// reproducible across runs. Number tokens and dev cards are placed/shuffled by `Round.init`.
    public static func standard() -> GameMap {
        let layout: [(CubeCoord, TileType)] = Self.standardTileLayout
        let portAssignments: [(portVerts: (Int, Int), kind: Port.Kind)] = Self.standardPortAssignments
        let built = Self.buildBoard(layout: layout, portAssignments: portAssignments)
        return GameMap(
            tiles: built.tiles,
            vertices: built.vertices,
            edges: built.edges,
            ports: built.ports,
            numberTokenBag: Self.standardNumberTokens,
            devCardDeck: Self.standardDevCardDeck
        )
    }

    // MARK: - Tile layout

    static var standardTileLayout: [(CubeCoord, TileType)] {
        // 19 tiles: 3 hills, 4 forest, 4 pasture, 4 fields, 3 mountains, 1 desert.
        // Fixed (deterministic) terrain order; number tokens shuffled at Round.init time.
        let coords: [CubeCoord] = radius2Coords()
        let order: [TileType] = [
            .forest, .forest, .forest,
            .pasture, .pasture, .pasture, .pasture,
            .fields, .fields, .fields, .fields,
            .desert,
            .hills, .hills, .hills,
            .mountains, .mountains, .mountains,
            .forest,
        ]
        precondition(order.count == coords.count, "Standard tile count mismatch")
        var result: [(CubeCoord, TileType)] = []
        for (i, c) in coords.enumerated() {
            result.append((c, order[i]))
        }
        return result
    }

    private static func radius2Coords() -> [CubeCoord] {
        var out: [CubeCoord] = []
        for x in -2...2 {
            for y in -2...2 {
                let z: Int = -x - y
                if abs(z) <= 2 {
                    out.append(CubeCoord(x: x, y: y, z: z))
                }
            }
        }
        return out
    }

    // MARK: - Number tokens

    /// 18 number tokens for 18 non-desert tiles.
    public static var standardNumberTokens: [Int] {
        [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]
    }

    // MARK: - Dev card deck

    /// 25 dev cards: 14 Ranger, 5 Landmark, 2 Pathfinder, 2 Roundup, 2 Bountiful Harvest.
    public static var standardDevCardDeck: [DevCard] {
        var out: [DevCard] = []
        var nextID: DevCardID = 1
        for _ in 0..<14 { out.append(DevCard(id: nextID, kind: .ranger)); nextID += 1 }
        for _ in 0..<5 { out.append(DevCard(id: nextID, kind: .landmark)); nextID += 1 }
        for _ in 0..<2 { out.append(DevCard(id: nextID, kind: .pathfinder)); nextID += 1 }
        for _ in 0..<2 { out.append(DevCard(id: nextID, kind: .roundup)); nextID += 1 }
        for _ in 0..<2 { out.append(DevCard(id: nextID, kind: .bountifulHarvest)); nextID += 1 }
        return out
    }

    // MARK: - Port assignments

    /// The 9 ports for the standard board: 4 generic (3:1) + 5 specific (2:1 for each resource).
    /// Vertex IDs are picked from the perimeter after the graph is built, so we derive them
    /// here by running a lightweight build pass first and selecting perimeter edges.
    static var standardPortAssignments: [(portVerts: (Int, Int), kind: Port.Kind)] {
        let portKinds: [Port.Kind] = [
            .generic,
            .specific(.wheat),
            .generic,
            .specific(.ore),
            .generic,
            .specific(.sheep),
            .generic,
            .specific(.brick),
            .specific(.wood),
        ]
        return perimeterPortVertexPairs(layout: standardTileLayout, portKinds: portKinds)
    }
}

// MARK: - Port vertex selection (shared by standard + expansion)

extension GameMap {
    /// Given a tile layout, runs a preliminary build (no ports), finds the perimeter edges
    /// (edges with only 1 adjacent tile), picks `portKinds.count` of them spaced around the
    /// perimeter, and returns the port vertex pairs in the order they appear. This gives a
    /// reproducible, structurally valid port placement without hand-coding vertex IDs.
    static func perimeterPortVertexPairs(
        layout: [(CubeCoord, TileType)],
        portKinds: [Port.Kind]
    ) -> [(portVerts: (Int, Int), kind: Port.Kind)] {
        let bare = buildBoard(layout: layout, portAssignments: [])
        let perimeterEdges: [Edge] = bare.edges.filter { $0.adjacentTileIDs.count == 1 }
        guard perimeterEdges.isEmpty == false else { return [] }

        let tileCenterByID: [TileID: CubeCoord] = Dictionary(uniqueKeysWithValues: bare.tiles.map { ($0.id, $0.coord) })
        let vertexApproximateAngle: [VertexID: Double] = Dictionary(uniqueKeysWithValues: bare.vertices.map { v in
            // Approximate angle from origin for stable sort around the perimeter.
            let nearbyTiles: [CubeCoord] = v.adjacentTileIDs.compactMap { tileCenterByID[$0] }
            let avg: CubeCoord = nearbyTiles.reduce(CubeCoord(x: 0, y: 0, z: 0)) { partial, c in
                CubeCoord(x: partial.x + c.x, y: partial.y + c.y, z: partial.z + c.z)
            }
            let count: Double = Double(max(nearbyTiles.count, 1))
            // Project axial to 2D for angle: q=x, r=z (pointy-top).
            let q: Double = Double(avg.x) / count
            let r: Double = Double(avg.z) / count
            let x2d: Double = sqrt(3.0) * (q + r / 2.0)
            let y2d: Double = 1.5 * r
            return (v.id, atan2(y2d, x2d))
        })

        let sortedPerimeter: [Edge] = perimeterEdges.sorted { a, b in
            let aAngle: Double = edgeAngle(a, angles: vertexApproximateAngle)
            let bAngle: Double = edgeAngle(b, angles: vertexApproximateAngle)
            return aAngle < bAngle
        }

        // Pick every-other perimeter edge so ports aren't all adjacent.
        var picked: [Edge] = []
        let step: Int = max(1, sortedPerimeter.count / portKinds.count)
        var idx: Int = 0
        while picked.count < portKinds.count && idx < sortedPerimeter.count {
            picked.append(sortedPerimeter[idx])
            idx += step
        }
        if picked.count < portKinds.count {
            // Fallback: fill remaining slots from the unused perimeter edges
            for edge in sortedPerimeter where picked.contains(where: { $0.id == edge.id }) == false {
                picked.append(edge)
                if picked.count == portKinds.count { break }
            }
        }

        var result: [(portVerts: (Int, Int), kind: Port.Kind)] = []
        for (i, edge) in picked.enumerated() {
            let endpoints: [VertexID] = edge.endpointVertexIDs
            let v1: VertexID = endpoints.first ?? 0
            let v2: VertexID = endpoints.dropFirst().first ?? v1
            result.append((portVerts: (v1, v2), kind: portKinds[i]))
        }
        return result
    }

    private static func edgeAngle(_ edge: Edge, angles: [VertexID: Double]) -> Double {
        let a1: Double = edge.endpointVertexIDs.first.flatMap { angles[$0] } ?? 0
        let a2: Double = edge.endpointVertexIDs.dropFirst().first.flatMap { angles[$0] } ?? a1
        return (a1 + a2) / 2.0
    }
}
