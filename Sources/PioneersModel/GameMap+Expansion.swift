import Foundation

// MARK: - Expansion (5-6 Player) Board

extension GameMap {
    /// The 5-6 player expansion board: 30 tiles arranged in rows of 3/4/5/6/5/4/3, 28 number
    /// tokens, 11 ports, 34-card dev deck. Used automatically by Round.init when player count >= 5.
    public static func expansion() -> GameMap {
        let layout: [(CubeCoord, TileType)] = Self.expansionTileLayout
        let portAssignments: [(portVerts: (Int, Int), kind: Port.Kind)] = Self.expansionPortAssignments
        let built = Self.buildBoard(layout: layout, portAssignments: portAssignments)
        return GameMap(
            tiles: built.tiles,
            vertices: built.vertices,
            edges: built.edges,
            ports: built.ports,
            numberTokenBag: Self.expansionNumberTokens,
            devCardDeck: Self.expansionDevCardDeck
        )
    }

    // MARK: - Tile layout

    static var expansionTileLayout: [(CubeCoord, TileType)] {
        let coords: [CubeCoord] = Self.expansionCoords()
        // 30 tiles: 5 hills, 6 forest, 6 pasture, 6 fields, 5 mountains, 2 desert
        let order: [TileType] = [
            .forest, .forest, .forest, .forest, .forest, .forest,
            .pasture, .pasture, .pasture, .pasture, .pasture, .pasture,
            .fields, .fields, .fields, .fields, .fields, .fields,
            .hills, .hills, .hills, .hills, .hills,
            .mountains, .mountains, .mountains, .mountains, .mountains,
            .desert, .desert,
        ]
        precondition(order.count == coords.count, "Expansion tile count mismatch")
        var result: [(CubeCoord, TileType)] = []
        for (i, c) in coords.enumerated() {
            result.append((c, order[i]))
        }
        return result
    }

    /// Rows by z-coord: z=-3..+3 with x-range that produces 3/4/5/6/5/4/3.
    private static func expansionCoords() -> [CubeCoord] {
        var out: [CubeCoord] = []
        let rows: [(z: Int, xRange: ClosedRange<Int>)] = [
            (-3, 0...2),
            (-2, -1...2),
            (-1, -2...2),
            (0, -3...2),
            (1, -3...1),
            (2, -3...0),
            (3, -3...(-1)),
        ]
        for row in rows {
            for x in row.xRange {
                let z: Int = row.z
                let y: Int = -x - z
                out.append(CubeCoord(x: x, y: y, z: z))
            }
        }
        return out
    }

    // MARK: - Number tokens

    /// 28 tokens for 28 non-desert tiles (2 deserts have no token).
    public static var expansionNumberTokens: [Int] {
        [2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12]
    }

    // MARK: - Dev card deck

    /// 34 dev cards: 20 Ranger, 5 Landmark, 3 Pathfinder, 3 Roundup, 3 Bountiful Harvest.
    public static var expansionDevCardDeck: [DevCard] {
        var out: [DevCard] = []
        var nextID: DevCardID = 1
        for _ in 0..<20 { out.append(DevCard(id: nextID, kind: .ranger)); nextID += 1 }
        for _ in 0..<5 { out.append(DevCard(id: nextID, kind: .landmark)); nextID += 1 }
        for _ in 0..<3 { out.append(DevCard(id: nextID, kind: .pathfinder)); nextID += 1 }
        for _ in 0..<3 { out.append(DevCard(id: nextID, kind: .roundup)); nextID += 1 }
        for _ in 0..<3 { out.append(DevCard(id: nextID, kind: .bountifulHarvest)); nextID += 1 }
        return out
    }

    // MARK: - Port assignments

    static var expansionPortAssignments: [(portVerts: (Int, Int), kind: Port.Kind)] {
        let portKinds: [Port.Kind] = [
            .generic,
            .specific(.wheat),
            .generic,
            .specific(.ore),
            .generic,
            .specific(.sheep),
            .generic,
            .specific(.brick),
            .generic,
            .specific(.wood),
            .specific(.wood),
        ]
        return perimeterPortVertexPairs(layout: expansionTileLayout, portKinds: portKinds)
    }
}
