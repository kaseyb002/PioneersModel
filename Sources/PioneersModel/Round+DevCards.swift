import Foundation

extension Round {
    // MARK: - Play Dev Card

    /// Play a dev card from the active player's hand. Dev cards cannot be played on the same turn
    /// they were purchased (except Landmark, which is silent), and only one dev card may be played
    /// per turn. Ranger may also be played *before* rolling the dice (standard Catan optional rule).
    public mutating func playDevCard(id: DevCardID, resource: Resource? = nil, pickedResources: [Resource]? = nil) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, let phase) = state else {
            throw PioneersModelError.notWaitingForPlayerToAct
        }
        // Dev cards may be played in `.main` or, for rangers, in `.beforeRoll`.
        switch phase {
        case .main, .beforeRoll: break
        default: throw PioneersModelError.notInMainPhase
        }
        guard let handIdx: Int = playerIndex(of: activeID) else {
            throw PioneersModelError.playerNotFound
        }
        guard let cardIdx: Int = playerHands[handIdx].heldDevCards.firstIndex(where: { $0.id == id }) else {
            throw PioneersModelError.devCardNotInHand
        }
        let card: DevCard = playerHands[handIdx].heldDevCards[cardIdx]

        // Landmark VP cards aren't "played" as an action — they're revealed at game end.
        guard card.kind != .landmark else { throw PioneersModelError.cannotPlayLandmark }

        // Enforce "can't play the turn it was purchased".
        if playerHands[handIdx].devCardIDsPurchasedThisTurn.contains(id) {
            throw PioneersModelError.cannotPlayDevCardPurchasedThisTurn
        }
        // Enforce "one dev card per turn".
        guard hasPlayedDevCardThisTurn == false else {
            throw PioneersModelError.alreadyPlayedDevCardThisTurn
        }

        // Remove the card and mark it played.
        playerHands[handIdx].heldDevCards.remove(at: cardIdx)
        playerHands[handIdx].playedDevCards.append(card)
        hasPlayedDevCardThisTurn = true

        switch card.kind {
        case .ranger:
            logAction(playerID: activeID, decision: .playedDevCard(.ranger))
            // Transition to outlaw-move sub-phase; reason retains the played card ID.
            state = .waitingForPlayer(id: activeID, phase: .movingOutlaw(reason: .playedRanger(devCardID: id)))
            checkLargestArmy()
            checkWin()

        case .pathfinder:
            logAction(playerID: activeID, decision: .playedDevCard(.pathfinder))
            // Active player must place up to 2 free trails (may end early if out of pieces / legal spots,
            // but the model accepts two sequential `buildTrail` calls; we allow fewer via `resolvePathfinderEarly`).
            state = .waitingForPlayer(id: activeID, phase: .playingPathfinder(remainingTrails: 2))

        case .roundup:
            guard let r: Resource = resource else { throw PioneersModelError.invalidTradeOffer }
            var collected: Int = 0
            for pidIdx in playerHands.indices {
                guard playerHands[pidIdx].player.id != activeID else { continue }
                let count: Int = playerHands[pidIdx].resources[r] ?? 0
                if count > 0 {
                    playerHands[pidIdx].resources.removeValue(forKey: r)
                    collected += count
                }
            }
            playerHands[handIdx].resources[r, default: 0] += collected
            logAction(
                playerID: activeID,
                decision: .playedDevCard(.roundup(resource: r, collected: collected))
            )
            state = .waitingForPlayer(id: activeID, phase: .main)

        case .bountifulHarvest:
            guard let picks: [Resource] = pickedResources, picks.count == 2 else {
                throw PioneersModelError.invalidTradeOffer
            }
            for r in picks { playerHands[handIdx].resources[r, default: 0] += 1 }
            logAction(
                playerID: activeID,
                decision: .playedDevCard(.bountifulHarvest(resources: picks))
            )
            state = .waitingForPlayer(id: activeID, phase: .main)

        case .landmark:
            // Already guarded above.
            break
        }
    }

    /// End a Pathfinder play early (e.g. if the active player has no legal second trail spot).
    public mutating func resolvePathfinderEarly() throws {
        guard case .waitingForPlayer(let activeID, .playingPathfinder) = state else {
            throw PioneersModelError.pathfinderRequiresTwoTrails
        }
        state = .waitingForPlayer(id: activeID, phase: .main)
    }
}
