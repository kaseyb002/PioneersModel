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
        state = .specialBuildPhase(originatingPlayerID: playerID, pending: pending)
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
        if pending.isEmpty {
            // End of special-build; start the next player's normal turn.
            advanceToNextPlayer(afterPlayerID: origin)
        } else {
            state = .specialBuildPhase(originatingPlayerID: origin, pending: pending)
        }
    }

}
