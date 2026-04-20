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
        let offered: Int = resources.values.reduce(0, +)
        guard offered == required else {
            throw PioneersModelError.wrongDiscardAmount
        }

        for (r, n) in resources where n > 0 {
            guard (playerHands[handIdx].resources[r] ?? 0) >= n else {
                throw PioneersModelError.insufficientResources
            }
        }

        for (r, n) in resources where n > 0 {
            playerHands[handIdx].resources[r, default: 0] -= n
            if playerHands[handIdx].resources[r] == 0 {
                playerHands[handIdx].resources.removeValue(forKey: r)
            }
        }
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

        // Choose a random resource weighted by count.
        let stolen: Resource? = consumeRandomResource(fromIndex: victimIdx)
        if let stolen {
            playerHands[activeIdx].resources[stolen, default: 0] += 1
        }
        logAction(playerID: activeID, decision: .stoleResource(from: victimID, resource: stolen))

        finishOutlawResolution(reason: reason, activeID: activeID)
        return stolen
    }

    private mutating func finishOutlawResolution(reason: OutlawReason, activeID: PlayerID) {
        state = .waitingForPlayer(id: activeID, phase: .main)
    }

    /// Remove one random resource card (uniformly weighted) from `playerHands[idx]`, returning the
    /// resource that was removed. Uses `cookedStealChoices` when available (for deterministic tests).
    private mutating func consumeRandomResource(fromIndex idx: Int) -> Resource? {
        let hand: PlayerHand = playerHands[idx]
        if hand.totalResourceCount == 0 { return nil }

        // Prefer cooked choice when it matches a resource the victim actually holds.
        if cookedStealChoices.isEmpty == false {
            let picked: Resource = cookedStealChoices.removeFirst()
            if (hand.resources[picked] ?? 0) > 0 {
                playerHands[idx].resources[picked, default: 0] -= 1
                if playerHands[idx].resources[picked] == 0 {
                    playerHands[idx].resources.removeValue(forKey: picked)
                }
                return picked
            }
            // Cooked choice didn't match; fall through to random.
        }

        // Build the weighted pool and pick uniformly.
        var pool: [Resource] = []
        for (r, n) in hand.resources {
            for _ in 0..<n { pool.append(r) }
        }
        guard pool.isEmpty == false else { return nil }
        let picked: Resource = pool[Int.random(in: 0..<pool.count)]
        playerHands[idx].resources[picked, default: 0] -= 1
        if playerHands[idx].resources[picked] == 0 {
            playerHands[idx].resources.removeValue(forKey: picked)
        }
        return picked
    }
}
