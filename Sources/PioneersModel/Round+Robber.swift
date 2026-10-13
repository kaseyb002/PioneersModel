import Foundation

extension Round {
    // MARK: - Discard After Seven

    /// The current player discards `resources` (must total exactly half of their current hand, rounded
    /// down). Called repeatedly (one per player in the pending list) until all discards are done.
    public mutating func discardResources(playerID: PlayerID, resources: [Resource: Int]) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .discardingAfterSeven(var pending)) = state else {
            throw PioneersModelError.cannotDiscardNow
        }
        guard pending.contains(playerID) else {
            throw PioneersModelError.cannotDiscardNow
        }
        guard let handIdx: Int = playerIndex(of: playerID) else {
            throw PioneersModelError.playerNotFound
        }

        let total: Int = playerHands[handIdx].totalResourceCount
        let required: Int = total / 2
        guard resources.values.allSatisfy({ $0 >= 0 }) else {
            throw PioneersModelError.wrongDiscardAmount
        }
        let offered: Int = resources.values.reduce(0, +)
        guard offered == required else {
            throw PioneersModelError.wrongDiscardAmount
        }

        guard Self.hand(playerHands[handIdx].resources(using: resourcesMap), covers: resources) else {
            throw PioneersModelError.insufficientResources
        }
        try spendResources(resources, fromPlayerID: playerID)
        logAction(playerID: playerID, decision: .discardedResources(resources: resources))

        pending.removeAll { $0 == playerID }
        if pending.isEmpty {
            state = .waitingForPlayer(id: activeID, phase: .movingOutlaw(reason: .rolledSeven))
        } else {
            state = .waitingForPlayer(id: activeID, phase: .discardingAfterSeven(pendingPlayerIDs: pending))
        }
    }

    // MARK: - Move Outlaw

    /// The active player moves the outlaw to another tile. If any opponent has a building on a corner
    /// of the new tile (other than themselves), the player must then choose a victim to steal from.
    public mutating func moveOutlaw(toTileID tileID: TileID) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .movingOutlaw(let reason)) = state else {
            throw PioneersModelError.mustMoveOutlawFirst
        }
        guard let t: Tile = tile(id: tileID) else { throw PioneersModelError.invalidTileID }
        guard t.id != outlawTileID else { throw PioneersModelError.cannotMoveOutlawToSameTile }

        outlawTileID = tileID
        logAction(playerID: activeID, decision: .movedOutlaw(toTileID: tileID))

        // Identify candidates: opponents with at least one building on a vertex of this tile,
        // and who currently hold at least one resource card (you can't steal from the empty-handed).
        var candidates: [PlayerID] = []
        for vertexID in t.vertexIDs {
            if let b: Building = building(at: vertexID) {
                if b.ownerID != activeID,
                   playerHand(for: b.ownerID)?.totalResourceCount ?? 0 > 0,
                   candidates.contains(b.ownerID) == false {
                    candidates.append(b.ownerID)
                }
            }
        }

        if candidates.isEmpty {
            // Nobody to steal from — finish the outlaw sequence.
            finishOutlawResolution(reason: reason, activeID: activeID)
        } else if candidates.count == 1 {
            try stealFromPlayer(victimID: candidates[0])
        } else {
            state = .waitingForPlayer(id: activeID, phase: .stealingAfterOutlaw(candidates: candidates, reason: reason))
        }
    }

    // MARK: - Steal From Player

    @discardableResult
    public mutating func stealFromPlayer(victimID: PlayerID) throws -> Resource? {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }

        // Accept either direct call from .movingOutlaw (single-candidate auto-steal path) or from
        // the .stealingAfterOutlaw selection phase.
        let activeID: PlayerID
        let reason: OutlawReason
        switch state {
        case .waitingForPlayer(let id, .movingOutlaw(let r)):
            activeID = id
            reason = r
        case .waitingForPlayer(let id, .stealingAfterOutlaw(let candidates, let r)):
            guard candidates.contains(victimID) else {
                throw PioneersModelError.cannotStealFromPlayer
            }
            activeID = id
            reason = r
        default:
            throw PioneersModelError.cannotStealFromPlayer
        }

        guard victimID != activeID else { throw PioneersModelError.cannotStealFromPlayer }
        guard let victimIdx: Int = playerIndex(of: victimID) else { throw PioneersModelError.playerNotFound }
        guard let activeIdx: Int = playerIndex(of: activeID) else { throw PioneersModelError.playerNotFound }

        // Transfer the exact card selected by the shared ID order.
        let stolenID: ResourceID? = consumeStealResource(fromIndex: victimIdx)
        let stolen = stolenID.flatMap { resourcesMap[$0] }
        if let stolenID {
            playerHands[activeIdx].resourceIDs.append(stolenID)
        }
        logAction(playerID: activeID, decision: .stoleResource(from: victimID, resource: stolen))

        finishOutlawResolution(reason: reason, activeID: activeID)
        return stolen
    }

    private mutating func finishOutlawResolution(reason: OutlawReason, activeID: PlayerID) {
        let nextPhase: TurnPhase
        switch reason {
        case .rolledSeven:
            nextPhase = .main
        case .playedRanger:
            // Ranger may be played before rolling. Completing the card must not skip the
            // required roll, but a Ranger played after rolling returns to the main phase.
            nextPhase = hasRolledDiceThisTurn ? .main : .beforeRoll
        }
        state = .waitingForPlayer(id: activeID, phase: nextPhase)
    }

    /// IDs are assigned randomly once at round creation. Selecting the lowest ID
    /// makes theft reproducible without consuming a separate RNG or adding a counter.
    private mutating func consumeStealResource(fromIndex idx: Int) -> ResourceID? {
        let ids = playerHands[idx].resourceIDs
        guard !ids.isEmpty else { return nil }
        let picked: ResourceID
        if !cookedStealChoices.isEmpty {
            let resource = cookedStealChoices.removeFirst()
            picked = ids.filter { resourcesMap[$0] == resource }.min() ?? ids.min()!
        } else {
            picked = ids.min()!
        }
        playerHands[idx].resourceIDs.removeAll { $0 == picked }
        return picked
    }
}
