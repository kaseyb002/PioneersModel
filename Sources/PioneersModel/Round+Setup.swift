import Foundation

extension Round {
    // MARK: - Setup Phase

    /// Places an initial homestead at `vertexID` for the given player (during `.setup`). No resources
    /// are spent. On the second lap, the player immediately collects resources from all adjacent
    /// tiles (standard Catan second-settlement rule).
    public mutating func placeInitialHomestead(playerID: PlayerID, vertexID: VertexID) throws {
        guard case .setup(var pending) = state else {
            throw PioneersModelError.notInSetupPhase
        }
        guard let next: SetupPlacement = pending.first else {
            throw PioneersModelError.notInSetupPhase
        }
        guard next.playerID == playerID, next.step == .homestead else {
            throw PioneersModelError.notActivePlayer
        }
        guard vertex(id: vertexID) != nil else {
            throw PioneersModelError.invalidVertexID
        }
        guard canPlaceHomestead(at: vertexID) else {
            throw PioneersModelError.vertexTooCloseToBuilding
        }
        guard let handIdx: Int = playerIndex(of: playerID) else {
            throw PioneersModelError.playerNotFound
        }
        guard playerHands[handIdx].remainingHomesteads > 0 else {
            throw PioneersModelError.insufficientPieces
        }

        buildings.append(Building(kind: .homestead, ownerID: playerID, vertexID: vertexID))
        playerHands[handIdx].remainingHomesteads -= 1
        logAction(playerID: playerID, decision: .placedInitialHomestead(vertexID: vertexID))

        // On the second lap, grant one resource for each adjacent non-desert (and non-outlaw-at-start)
        // tile. Per the rulebook the outlaw starts in the desert so this resolves cleanly.
        if next.lap == 2 {
            var collected: [Resource: Int] = [:]
            if let v: Vertex = vertex(id: vertexID) {
                for tileID in v.adjacentTileIDs {
                    guard let t: Tile = tile(id: tileID) else { continue }
                    guard let resource: Resource = t.type.resource else { continue }
                    collected[resource, default: 0] += 1
                }
            }
            if collected.isEmpty == false {
                grantResources(collected, toPlayerID: playerID)
                logAction(
                    playerID: playerID,
                    decision: .collectedResources(perPlayer: [playerID: collected])
                )
            }
        }

        pending.removeFirst()
        state = .setup(pendingPlacements: pending)
    }

    /// Places an initial trail at `edgeID` for the given player. The edge must touch the most
    /// recently placed homestead for this lap.
    public mutating func placeInitialTrail(playerID: PlayerID, edgeID: EdgeID) throws {
        guard case .setup(var pending) = state else {
            throw PioneersModelError.notInSetupPhase
        }
        guard let next: SetupPlacement = pending.first else {
            throw PioneersModelError.notInSetupPhase
        }
        guard next.playerID == playerID, next.step == .trail else {
            throw PioneersModelError.notActivePlayer
        }
        guard let e: Edge = edge(id: edgeID) else {
            throw PioneersModelError.invalidEdgeID
        }
        guard trail(at: edgeID) == nil else {
            throw PioneersModelError.edgeAlreadyOccupied
        }
        guard let handIdx: Int = playerIndex(of: playerID) else {
            throw PioneersModelError.playerNotFound
        }
        guard playerHands[handIdx].remainingTrails > 0 else {
            throw PioneersModelError.insufficientPieces
        }

        // The edge must connect to the homestead the player just placed on this lap.
        guard let anchorVertex: VertexID = mostRecentInitialHomesteadVertex(playerID: playerID, lap: next.lap) else {
            throw PioneersModelError.trailMustConnectToOwnNetwork
        }
        guard e.endpointVertexIDs.contains(anchorVertex) else {
            throw PioneersModelError.trailMustConnectToOwnNetwork
        }

        trails.append(Trail(ownerID: playerID, edgeID: edgeID))
        playerHands[handIdx].remainingTrails -= 1
        logAction(playerID: playerID, decision: .placedInitialTrail(edgeID: edgeID))

        pending.removeFirst()
        if pending.isEmpty {
            // All placements done — start the game with the first player.
            let firstPlayerID: PlayerID = playerHands[0].player.id
            state = .waitingForPlayer(id: firstPlayerID, phase: .beforeRoll)
        } else {
            state = .setup(pendingPlacements: pending)
        }
    }

    /// The vertex ID of the homestead the player most recently placed on a given setup lap.
    /// Used to validate trail adjacency.
    private func mostRecentInitialHomesteadVertex(playerID: PlayerID, lap: Int) -> VertexID? {
        // Walk the log in reverse looking for this player's most recent `placedInitialHomestead`.
        for action in log.reversed() {
            if action.playerID != playerID { continue }
            if case .placedInitialHomestead(let vid) = action.decision {
                return vid
            }
        }
        return nil
    }
}
