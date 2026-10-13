import Foundation

extension Round {
    // MARK: - Play Dev Card

    /// Play a dev card from the active player's hand. Dev cards cannot be played on the same turn
    /// they were purchased (except Landmark, which is silent), and only one dev card may be played
    /// per turn. A dev card may also be played before rolling the dice.
    public mutating func playDevCard(id: DevCardID, resource: Resource? = nil, pickedResources: [Resource]? = nil) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard openTradeOffer == nil else { throw PioneersModelError.tradeOfferIsOpen }
        guard case .waitingForPlayer(let activeID, let phase) = state else {
            throw PioneersModelError.notWaitingForPlayerToAct
        }
        // Dev cards may be played in `.main` or `.beforeRoll`.
        switch phase {
        case .main, .beforeRoll: break
        default: throw PioneersModelError.notInMainPhase
        }
        guard let handIdx: Int = playerIndex(of: activeID) else {
            throw PioneersModelError.playerNotFound
        }
        guard let cardIdx: Int = playerHands[handIdx].heldDevCardIDs.firstIndex(of: id) else {
            throw PioneersModelError.devCardNotInHand
        }
        guard let card = devCardsMap[id] else { throw PioneersModelError.devCardNotInHand }

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

        // Validate card-specific input before consuming the card or changing turn state.
        switch card.kind {
        case .roundup:
            guard resource != nil else { throw PioneersModelError.invalidTradeOffer }
        case .bountifulHarvest:
            guard let pickedResources, pickedResources.count == min(2, bankResourceIDs.count) else { throw PioneersModelError.invalidTradeOffer }
            let requested = pickedResources.reduce(into: [Resource: Int]()) { $0[$1, default: 0] += 1 }
            guard Self.hand(bankResourceCounts, covers: requested) else { throw PioneersModelError.insufficientBankResources }
        case .ranger, .pathfinder, .landmark:
            break
        }

        // Remove the card and mark it played.
        playerHands[handIdx].heldDevCardIDs.remove(at: cardIdx)
        playerHands[handIdx].playedDevCardIDs.append(id)
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
                let ids = playerHands[pidIdx].resourceIDs.filter { resourcesMap[$0] == r }
                playerHands[pidIdx].resourceIDs.removeAll { resourcesMap[$0] == r }
                playerHands[handIdx].resourceIDs.append(contentsOf: ids)
                collected += ids.count
            }
            logAction(
                playerID: activeID,
                decision: .playedDevCard(.roundup(resource: r, collected: collected))
            )
            state = .waitingForPlayer(id: activeID, phase: phaseAfterDevCardResolution)

        case .bountifulHarvest:
            guard let picks: [Resource] = pickedResources else {
                throw PioneersModelError.invalidTradeOffer
            }
            for r in picks { grantResources([r: 1], toPlayerID: activeID) }
            logAction(
                playerID: activeID,
                decision: .playedDevCard(.bountifulHarvest(resources: picks))
            )
            state = .waitingForPlayer(id: activeID, phase: phaseAfterDevCardResolution)

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
        state = .waitingForPlayer(id: activeID, phase: phaseAfterDevCardResolution)
    }

    private var phaseAfterDevCardResolution: TurnPhase {
        hasRolledDiceThisTurn ? .main : .beforeRoll
    }
}
