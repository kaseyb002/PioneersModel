import Foundation

extension Round {
    // MARK: - Victory Points

    /// Public VP (everyone can see): buildings + longest-road + largest-army bonuses.
    public func publicVictoryPoints(for playerID: PlayerID) -> Int {
        var total: Int = 0
        for b in buildings where b.ownerID == playerID {
            total += b.kind.victoryPoints
        }
        if longestRoadHolder == playerID { total += Self.longestRoadVictoryPoints }
        if largestArmyHolder == playerID { total += Self.largestArmyVictoryPoints }
        return total
    }

    /// Total VP including landmark cards (which are kept secret until declared).
    public func victoryPoints(for playerID: PlayerID) -> Int {
        var total: Int = publicVictoryPoints(for: playerID)
        if let hand: PlayerHand = playerHand(for: playerID) {
            total += hand.landmarksHeld
        }
        return total
    }

    // MARK: - Longest Road (trails)

    /// Returns (playerID, length) for the player with the longest contiguous trail (>= 5 edges),
    /// or nil if no player qualifies.
    public func longestRoadCandidate() -> (playerID: PlayerID, length: Int)? {
        var best: (PlayerID, Int)?
        for hand in playerHands {
            let length: Int = longestTrailLength(for: hand.player.id)
            if length >= Self.longestRoadMin {
                if let cur: (PlayerID, Int) = best {
                    if length > cur.1 { best = (hand.player.id, length) }
                } else {
                    best = (hand.player.id, length)
                }
            }
        }
        return best
    }

    /// Update `longestRoadHolder` after a trail-related change. Ties keep the current holder.
    mutating func checkLongestRoad() {
        let previousHolder: PlayerID? = longestRoadHolder
        guard let candidate: (PlayerID, Int) = longestRoadCandidate() else {
            // If no one qualifies, previous holder may still hold their own road if they themselves
            // still have 5+; in all other cases the bonus is removed.
            if let holder: PlayerID = previousHolder {
                if longestTrailLength(for: holder) >= Self.longestRoadMin {
                    return
                }
                longestRoadHolder = nil
            }
            return
        }

        if let holder: PlayerID = previousHolder {
            let holderLength: Int = longestTrailLength(for: holder)
            // Tie with current holder → holder keeps it.
            if holderLength >= candidate.1 { return }
        }

        if longestRoadHolder != candidate.0 {
            longestRoadHolder = candidate.0
            let activeID: PlayerID = activeTurnPlayerID ?? candidate.0
            logAction(playerID: activeID, decision: .longestRoadAwarded)
        }
    }

    /// Length of the longest trail walk for `playerID`, where each trail edge is used at most once.
    /// Opponent buildings on a shared vertex block the connection through that vertex.
    public func longestTrailLength(for playerID: PlayerID) -> Int {
        let ownTrails: [Trail] = trails.filter { $0.ownerID == playerID }
        if ownTrails.isEmpty { return 0 }
        let ownEdgeIDs: Set<EdgeID> = Set(ownTrails.map(\.edgeID))
        var best: Int = 0

        // Try a DFS starting from each endpoint of each owned trail.
        for trail in ownTrails {
            guard let e: Edge = edge(id: trail.edgeID) else { continue }
            for startVertex in e.endpointVertexIDs {
                var used: Set<EdgeID> = []
                dfsTrail(
                    fromVertex: startVertex,
                    playerID: playerID,
                    ownEdges: ownEdgeIDs,
                    used: &used,
                    length: 0,
                    best: &best
                )
            }
        }
        return best
    }

    private func dfsTrail(
        fromVertex vertexID: VertexID,
        playerID: PlayerID,
        ownEdges: Set<EdgeID>,
        used: inout Set<EdgeID>,
        length: Int,
        best: inout Int
    ) {
        if length > best { best = length }
        guard let v: Vertex = vertex(id: vertexID) else { return }
        // Opponent building on this vertex blocks continuation through it.
        if let b: Building = building(at: vertexID), b.ownerID != playerID {
            return
        }
        for eid in v.adjacentEdgeIDs where ownEdges.contains(eid) && used.contains(eid) == false {
            guard let e: Edge = edge(id: eid) else { continue }
            let other: VertexID = e.endpointVertexIDs.first(where: { $0 != vertexID }) ?? vertexID
            used.insert(eid)
            dfsTrail(
                fromVertex: other,
                playerID: playerID,
                ownEdges: ownEdges,
                used: &used,
                length: length + 1,
                best: &best
            )
            used.remove(eid)
        }
    }

    // MARK: - Largest Army (rangers)

    mutating func checkLargestArmy() {
        let previousHolder: PlayerID? = largestArmyHolder
        let counts: [(PlayerID, Int)] = playerHands.map { ($0.player.id, $0.rangersPlayed) }
        guard let best: (PlayerID, Int) = counts.max(by: { $0.1 < $1.1 }) else { return }
        guard best.1 >= Self.largestArmyMin else {
            // Someone was holding the bonus but they're no longer eligible? Standard Catan doesn't
            // revoke largest-army once granted, but we still track accurately.
            return
        }

        if let holder: PlayerID = previousHolder {
            let holderCount: Int = counts.first(where: { $0.0 == holder })?.1 ?? 0
            if holderCount >= best.1 { return } // tie → keep current holder
        }

        if largestArmyHolder != best.0 {
            largestArmyHolder = best.0
            let activeID: PlayerID = activeTurnPlayerID ?? best.0
            logAction(playerID: activeID, decision: .largestArmyAwarded)
        }
    }

    // MARK: - Win Check

    /// A player wins if they have >= `victoryPointsToWin` total VP — but only on their own turn.
    mutating func checkWin() {
        guard isComplete == false else { return }
        // Only score the active player on their own turn. This prevents the game from ending due to
        // an opponent crossing the threshold via a trade response or similar.
        guard let activeID: PlayerID = activeTurnPlayerID else { return }
        let totalVP: Int = victoryPoints(for: activeID)
        guard totalVP >= Self.victoryPointsToWin else { return }
        guard let winner: Player = player(byID: activeID) else { return }
        ended = .now
        logAction(playerID: activeID, decision: .winnerDeclared(playerID: activeID))
        state = .gameComplete(winner: winner)
    }
}
