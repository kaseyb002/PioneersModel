import Foundation

extension Round {
    // MARK: - Special Build Phase (5-6 players)

    /// Triggered by `endTurn()` when player count >= 5. Non-active players rotate starting from
    /// the one after the player who just ended their turn. Each one may perform at most one build
    /// action (trail, homestead, town, or dev-card buy) or pass. They may not roll, trade, or play
    /// dev cards.
    mutating func startSpecialBuildPhase(afterPlayerID playerID: PlayerID) {
        guard let startIdx: Int = playerIndex(of: playerID) else {
            advanceToNextPlayer(afterPlayerID: playerID)
            return
        }
        let count: Int = playerHands.count
        var pending: [PlayerID] = []
        // Start at the next player and rotate clockwise, skipping the one who just ended.
        for offset in 1...count {
            let idx: Int = (startIdx + offset) % count
            let pid: PlayerID = playerHands[idx].player.id
            if pid != playerID { pending.append(pid) }
        }
        advanceSpecialBuildQueue(originatingPlayerID: playerID, pending: pending)
    }

    /// The current special-build player skips their action and advances the queue.
    public mutating func specialBuildPass() throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .specialBuildPhase(let origin, var pending) = state else {
            throw PioneersModelError.notInSpecialBuildPhase
        }
        guard pending.isEmpty == false else {
            throw PioneersModelError.notInSpecialBuildPhase
        }
        let pid: PlayerID = pending.removeFirst()
        logAction(playerID: pid, decision: .specialBuildPass)
        advanceSpecialBuildQueue(originatingPlayerID: origin, pending: pending)
    }

    /// Whether `playerID` can legally perform at least one of the paid actions available during
    /// special build. Trading and playing development cards are intentionally excluded.
    public func canPerformSpecialBuild(playerID: PlayerID) -> Bool {
        guard let hand: PlayerHand = playerHand(for: playerID) else { return false }

        let canBuildTrail: Bool = hand.remainingTrails > 0 &&
            Self.hand(hand.resources, covers: Self.trailCost) &&
            edges.contains { canPlaceTrail(at: $0.id, forPlayerID: playerID) }
        let canBuildHomestead: Bool = hand.remainingHomesteads > 0 &&
            Self.hand(hand.resources, covers: Self.homesteadCost) &&
            vertices.contains { vertex in
                canPlaceHomestead(at: vertex.id) &&
                    vertex.adjacentEdgeIDs.contains {
                        trail(at: $0)?.ownerID == playerID
                    }
            }
        let canUpgradeTown: Bool = hand.remainingTowns > 0 &&
            Self.hand(hand.resources, covers: Self.townCost) &&
            buildings.contains {
                $0.ownerID == playerID && $0.kind == .homestead
            }
        let canBuyDevCard: Bool = devCardDeck.isEmpty == false &&
            Self.hand(hand.resources, covers: Self.devCardCost)

        return canBuildTrail || canBuildHomestead || canUpgradeTown || canBuyDevCard
    }

    /// Consumes the acting player's one special-build opportunity after a successful purchase.
    mutating func completeSpecialBuildAction(playerID: PlayerID) {
        guard case .specialBuildPhase(let origin, var pending) = state,
              pending.first == playerID
        else { return }

        pending.removeFirst()
        advanceSpecialBuildQueue(originatingPlayerID: origin, pending: pending)
    }

    /// Advances past players who have no legal special-build action. A player who can build remains
    /// in the queue so they may choose between making one purchase and explicitly passing.
    private mutating func advanceSpecialBuildQueue(
        originatingPlayerID origin: PlayerID,
        pending: [PlayerID]
    ) {
        var pending = pending
        while let playerID = pending.first,
              canPerformSpecialBuild(playerID: playerID) == false {
            pending.removeFirst()
            logAction(playerID: playerID, decision: .specialBuildPass)
        }

        if pending.isEmpty {
            advanceToNextPlayer(afterPlayerID: origin)
        } else {
            state = .specialBuildPhase(originatingPlayerID: origin, pending: pending)
        }
    }
}
