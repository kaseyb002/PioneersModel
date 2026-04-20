import Foundation

extension Round {
    // MARK: - State queries

    public var isComplete: Bool {
        if case .gameComplete = state { return true }
        return false
    }

    public var isSetup: Bool {
        if case .setup = state { return true }
        return false
    }

    public var isSpecialBuildPhase: Bool {
        if case .specialBuildPhase = state { return true }
        return false
    }

    /// The player whose input the round is currently awaiting. Nil during `.setup` and `.gameComplete`.
    public var currentPlayerID: PlayerID? {
        switch state {
        case .waitingForPlayer(let id, _):
            return id
        case .specialBuildPhase(_, let pending):
            return pending.first
        case .setup(let placements):
            return placements.first?.playerID
        case .gameComplete:
            return nil
        }
    }

    public var currentPlayerHand: PlayerHand? {
        guard let id: PlayerID = currentPlayerID else { return nil }
        return playerHand(for: id)
    }

    public var currentPlayer: Player? {
        currentPlayerHand?.player
    }

    public var currentPhase: TurnPhase? {
        if case .waitingForPlayer(_, let phase) = state { return phase }
        return nil
    }

    /// The active player whose *turn* it is, even during a special-build interruption.
    public var activeTurnPlayerID: PlayerID? {
        switch state {
        case .waitingForPlayer(let id, _):
            return id
        case .specialBuildPhase(let origin, _):
            return origin
        case .setup, .gameComplete:
            return nil
        }
    }

    // MARK: - Lookups

    public func playerHand(for playerID: PlayerID) -> PlayerHand? {
        playerHands.first(where: { $0.player.id == playerID })
    }

    public func player(byID id: PlayerID) -> Player? {
        playerHand(for: id)?.player
    }

    public func tile(id: TileID) -> Tile? {
        tiles.first(where: { $0.id == id })
    }

    public func vertex(id: VertexID) -> Vertex? {
        guard id >= 0, id < vertices.count else { return nil }
        return vertices[id]
    }

    public func edge(id: EdgeID) -> Edge? {
        guard id >= 0, id < edges.count else { return nil }
        return edges[id]
    }

    public func port(id: PortID) -> Port? {
        ports.first(where: { $0.id == id })
    }

    public func building(at vertexID: VertexID) -> Building? {
        buildings.first(where: { $0.vertexID == vertexID })
    }

    public func trail(at edgeID: EdgeID) -> Trail? {
        trails.first(where: { $0.edgeID == edgeID })
    }

    public func buildings(for playerID: PlayerID) -> [Building] {
        buildings.filter { $0.ownerID == playerID }
    }

    public func trails(for playerID: PlayerID) -> [Trail] {
        trails.filter { $0.ownerID == playerID }
    }

    // MARK: - Placement legality

    /// True if a homestead can legally be placed on `vertexID` (ignoring resource cost + trail-adjacency,
    /// which callers enforce separately). Standard distance-2 rule: no adjacent vertex may hold a building.
    public func canPlaceHomestead(at vertexID: VertexID) -> Bool {
        guard let v: Vertex = vertex(id: vertexID) else { return false }
        if building(at: vertexID) != nil { return false }
        for adj in v.adjacentVertexIDs {
            if building(at: adj) != nil { return false }
        }
        return true
    }

    /// True if `playerID` has a trail at `edgeID` ends or a building at either endpoint.
    public func isEdgeConnectedToPlayerNetwork(edgeID: EdgeID, playerID: PlayerID) -> Bool {
        guard let e: Edge = edge(id: edgeID) else { return false }
        for v in e.endpointVertexIDs {
            if let b: Building = building(at: v), b.ownerID == playerID {
                return true
            }
        }
        // Connected through another trail of the same player that shares an endpoint vertex.
        for v in e.endpointVertexIDs {
            // But: if an opponent has a building on the shared vertex, the trail connection is blocked.
            if let b: Building = building(at: v), b.ownerID != playerID {
                continue
            }
            guard let vertex: Vertex = vertex(id: v) else { continue }
            for adjEdgeID in vertex.adjacentEdgeIDs where adjEdgeID != edgeID {
                if let t: Trail = trail(at: adjEdgeID), t.ownerID == playerID {
                    return true
                }
            }
        }
        return false
    }

    public func canPlaceTrail(at edgeID: EdgeID, forPlayerID playerID: PlayerID) -> Bool {
        guard edge(id: edgeID) != nil else { return false }
        if trail(at: edgeID) != nil { return false }
        return isEdgeConnectedToPlayerNetwork(edgeID: edgeID, playerID: playerID)
    }

    // MARK: - Ports

    public func ports(ownedBy playerID: PlayerID) -> [Port] {
        var result: [Port] = []
        for port in ports {
            for vid in port.vertexIDs {
                if let b: Building = building(at: vid), b.ownerID == playerID {
                    result.append(port)
                    break
                }
            }
        }
        return result
    }

    // MARK: - Dice probabilities

    /// The number of pip dots on a number token (5/9 -> 4, 6/8 -> 5, etc.). Desert / nil = 0.
    public func pipCount(forToken token: Int?) -> Int {
        guard let token else { return 0 }
        switch token {
        case 2, 12: return 1
        case 3, 11: return 2
        case 4, 10: return 3
        case 5, 9: return 4
        case 6, 8: return 5
        default: return 0
        }
    }

    // MARK: - Log helper

    mutating func logAction(playerID: PlayerID, decision: Decision, at timestamp: Date = .now) {
        log.append(Action(playerID: playerID, decision: decision, timestamp: timestamp))
        if log.count > Self.maxLogActions {
            log.removeFirst(log.count - Self.maxLogActions)
        }
    }

    // MARK: - Resource helpers

    /// Returns true if `hand.resources` covers all of `cost` (each key has at least the required amount).
    public static func hand(_ resources: [Resource: Int], covers cost: [Resource: Int]) -> Bool {
        for (r, n) in cost {
            if (resources[r] ?? 0) < n { return false }
        }
        return true
    }

    mutating func spendResources(_ cost: [Resource: Int], fromPlayerID playerID: PlayerID) throws {
        guard let idx: Int = playerHands.firstIndex(where: { $0.player.id == playerID }) else {
            throw PioneersModelError.playerNotFound
        }
        guard Round.hand(playerHands[idx].resources, covers: cost) else {
            throw PioneersModelError.insufficientResources
        }
        for (r, n) in cost {
            playerHands[idx].resources[r, default: 0] -= n
            if playerHands[idx].resources[r] == 0 {
                playerHands[idx].resources.removeValue(forKey: r)
            }
        }
    }

    mutating func grantResources(_ bundle: [Resource: Int], toPlayerID playerID: PlayerID) {
        guard let idx: Int = playerHands.firstIndex(where: { $0.player.id == playerID }) else { return }
        for (r, n) in bundle where n > 0 {
            playerHands[idx].resources[r, default: 0] += n
        }
    }

    // MARK: - Players

    public func playerIndex(of playerID: PlayerID) -> Int? {
        playerHands.firstIndex(where: { $0.player.id == playerID })
    }

    public func nextPlayerID(after playerID: PlayerID) -> PlayerID? {
        guard let idx: Int = playerIndex(of: playerID) else { return nil }
        return playerHands[(idx + 1) % playerHands.count].player.id
    }
}

extension Round.State {
    public var isComplete: Bool {
        if case .gameComplete = self { return true }
        return false
    }
}
