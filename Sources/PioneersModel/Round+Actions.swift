import Foundation

extension Round {
    // MARK: - Roll Dice

    /// Rolls the dice for the active player. If the round has cooked dice rolls queued (used by tests)
    /// the next cooked value is consumed. Otherwise a random 2-12 sum from two d6 is produced.
    ///
    /// A roll of 7 jumps into the seven-resolution sub-phases (discard -> move outlaw -> steal).
    /// Any other roll distributes resources to all matching tiles (except the one under the outlaw)
    /// and transitions to `.main`.
    @discardableResult
    public mutating func rollDice() throws -> Int {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .beforeRoll) = state else {
            throw PioneersModelError.notInBeforeRollPhase
        }

        let total: Int
        if cookedDiceRolls.isEmpty == false {
            total = cookedDiceRolls.removeFirst()
        } else {
            let d1: Int = Int.random(in: 1...6)
            let d2: Int = Int.random(in: 1...6)
            total = d1 + d2
        }
        guard (2...12).contains(total) else {
            throw PioneersModelError.invalidDiceTotal
        }

        hasRolledDiceThisTurn = true
        lastDiceTotal = total
        logAction(playerID: activeID, decision: .rolledDice(total: total))

        if total == 7 {
            enterSevenResolution(activeID: activeID)
        } else {
            distributeResources(forRoll: total, activeID: activeID)
            state = .waitingForPlayer(id: activeID, phase: .main)
        }
        return total
    }

    private mutating func enterSevenResolution(activeID: PlayerID) {
        let pending: [PlayerID] = playerHands
            .filter { $0.totalResourceCount > Self.maxHandSizeBeforeDiscard }
            .map { $0.player.id }

        if pending.isEmpty {
            state = .waitingForPlayer(id: activeID, phase: .movingOutlaw(reason: .rolledSeven))
        } else {
            state = .waitingForPlayer(id: activeID, phase: .discardingAfterSeven(pendingPlayerIDs: pending))
        }
    }

    private mutating func distributeResources(forRoll total: Int, activeID: PlayerID) {
        var perPlayer: [PlayerID: [Resource: Int]] = [:]
        for t in tiles {
            guard t.numberToken == total else { continue }
            if t.id == outlawTileID { continue }
            guard let resource: Resource = t.type.resource else { continue }
            for vertexID in t.vertexIDs {
                guard let b: Building = building(at: vertexID) else { continue }
                perPlayer[b.ownerID, default: [:]][resource, default: 0] += b.kind.resourceYield
            }
        }
        for (pid, bundle) in perPlayer {
            grantResources(bundle, toPlayerID: pid)
        }
        if perPlayer.isEmpty == false {
            logAction(playerID: activeID, decision: .collectedResources(perPlayer: perPlayer))
        }
    }

    // MARK: - Build Trail

    /// Build a trail for the active player. Callable in `.main` (costs wood+brick),
    /// `.playingPathfinder` (free), or during the special-build phase.
    public mutating func buildTrail(edgeID: EdgeID) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }

        let builderID: PlayerID
        let isFree: Bool
        var isPathfinderStep: Bool = false

        switch state {
        case .waitingForPlayer(let id, let phase):
            switch phase {
            case .main:
                builderID = id
                isFree = false
            case .playingPathfinder:
                builderID = id
                isFree = true
                isPathfinderStep = true
            default:
                throw PioneersModelError.notInMainPhase
            }
        case .specialBuildPhase(_, let pending):
            guard let id: PlayerID = pending.first else {
                throw PioneersModelError.notInSpecialBuildPhase
            }
            builderID = id
            isFree = false
        default:
            throw PioneersModelError.notInMainPhase
        }

        guard let handIdx: Int = playerIndex(of: builderID) else {
            throw PioneersModelError.playerNotFound
        }
        guard playerHands[handIdx].remainingTrails > 0 else {
            throw PioneersModelError.insufficientPieces
        }
        guard edge(id: edgeID) != nil else {
            throw PioneersModelError.invalidEdgeID
        }
        guard trail(at: edgeID) == nil else {
            throw PioneersModelError.edgeAlreadyOccupied
        }
        guard isEdgeConnectedToPlayerNetwork(edgeID: edgeID, playerID: builderID) else {
            throw PioneersModelError.trailMustConnectToOwnNetwork
        }

        if isFree == false {
            try spendResources(Self.trailCost, fromPlayerID: builderID)
        }
        trails.append(Trail(ownerID: builderID, edgeID: edgeID))
        playerHands[handIdx].remainingTrails -= 1
        logAction(playerID: builderID, decision: .builtTrail(edgeID: edgeID))

        if isPathfinderStep {
            if case .waitingForPlayer(let id, .playingPathfinder(let remaining)) = state {
                let next: Int = remaining - 1
                if next <= 0 {
                    state = .waitingForPlayer(id: id, phase: .main)
                } else {
                    state = .waitingForPlayer(id: id, phase: .playingPathfinder(remainingTrails: next))
                }
            }
        }
        checkLongestRoad()
        checkWin()
    }

    // MARK: - Build Homestead

    public mutating func buildHomestead(vertexID: VertexID) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        let builderID: PlayerID = try currentBuildActorID()

        guard let handIdx: Int = playerIndex(of: builderID) else {
            throw PioneersModelError.playerNotFound
        }
        guard playerHands[handIdx].remainingHomesteads > 0 else {
            throw PioneersModelError.insufficientPieces
        }
        guard vertex(id: vertexID) != nil else {
            throw PioneersModelError.invalidVertexID
        }
        guard canPlaceHomestead(at: vertexID) else {
            throw PioneersModelError.vertexTooCloseToBuilding
        }
        // Must be connected to one of this player's own trails.
        guard let v: Vertex = vertex(id: vertexID) else { throw PioneersModelError.invalidVertexID }
        var connected: Bool = false
        for eid in v.adjacentEdgeIDs {
            if let t: Trail = trail(at: eid), t.ownerID == builderID {
                connected = true
                break
            }
        }
        guard connected else { throw PioneersModelError.trailMustConnectToOwnNetwork }

        try spendResources(Self.homesteadCost, fromPlayerID: builderID)
        buildings.append(Building(kind: .homestead, ownerID: builderID, vertexID: vertexID))
        playerHands[handIdx].remainingHomesteads -= 1
        logAction(playerID: builderID, decision: .builtHomestead(vertexID: vertexID))

        checkLongestRoad()
        checkWin()
    }

    // MARK: - Upgrade to Town

    public mutating func upgradeToTown(vertexID: VertexID) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        let builderID: PlayerID = try currentBuildActorID()

        guard let b: Building = building(at: vertexID) else {
            throw PioneersModelError.vertexAlreadyOccupied
        }
        guard b.ownerID == builderID else { throw PioneersModelError.notYourBuilding }
        guard b.kind == .homestead else { throw PioneersModelError.mustBeHomesteadToUpgrade }

        guard let handIdx: Int = playerIndex(of: builderID) else {
            throw PioneersModelError.playerNotFound
        }
        guard playerHands[handIdx].remainingTowns > 0 else {
            throw PioneersModelError.insufficientPieces
        }

        try spendResources(Self.townCost, fromPlayerID: builderID)
        // Replace the homestead with a town; homestead piece returns to the player's pool.
        guard let bIdx: Int = buildings.firstIndex(where: { $0.vertexID == vertexID }) else {
            throw PioneersModelError.vertexAlreadyOccupied
        }
        buildings[bIdx] = Building(kind: .town, ownerID: builderID, vertexID: vertexID)
        playerHands[handIdx].remainingHomesteads += 1
        playerHands[handIdx].remainingTowns -= 1
        logAction(playerID: builderID, decision: .upgradedToTown(vertexID: vertexID))

        checkWin()
    }

    // MARK: - Buy Dev Card

    public mutating func buyDevCard() throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        let buyerID: PlayerID = try currentBuildActorID()

        guard devCardDeck.isEmpty == false else {
            throw PioneersModelError.noDevCardsAvailable
        }
        guard let handIdx: Int = playerIndex(of: buyerID) else {
            throw PioneersModelError.playerNotFound
        }

        try spendResources(Self.devCardCost, fromPlayerID: buyerID)
        let card: DevCard = devCardDeck.removeFirst()
        playerHands[handIdx].heldDevCards.append(card)
        playerHands[handIdx].devCardIDsPurchasedThisTurn.append(card.id)
        logAction(playerID: buyerID, decision: .boughtDevCard)

        // Buying a landmark immediately bumps total VP; check for win.
        checkWin()
    }

    // MARK: - End Turn

    public mutating func endTurn() throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, let phase) = state else {
            throw PioneersModelError.notWaitingForPlayerToAct
        }
        guard case .main = phase else {
            throw PioneersModelError.notInMainPhase
        }
        guard hasRolledDiceThisTurn else {
            throw PioneersModelError.mustRollDiceFirst
        }

        // Clear turn-scoped flags.
        openTradeOffer = nil
        hasPlayedDevCardThisTurn = false
        hasRolledDiceThisTurn = false
        if let idx: Int = playerIndex(of: activeID) {
            playerHands[idx].devCardIDsPurchasedThisTurn = []
        }
        logAction(playerID: activeID, decision: .endedTurn)

        if playerHands.count >= Self.expansionThreshold {
            startSpecialBuildPhase(afterPlayerID: activeID)
        } else {
            advanceToNextPlayer(afterPlayerID: activeID)
        }
    }

    mutating func advanceToNextPlayer(afterPlayerID playerID: PlayerID) {
        guard let nextID: PlayerID = nextPlayerID(after: playerID) else { return }
        state = .waitingForPlayer(id: nextID, phase: .beforeRoll)
    }

    // MARK: - Build Actor Identification

    /// Returns the player who is currently allowed to perform a paid build/buy action
    /// (either the active player in `.main`, or the head of the special-build queue).
    /// Throws if the current state doesn't allow paid builds.
    func currentBuildActorID() throws -> PlayerID {
        switch state {
        case .waitingForPlayer(let id, let phase):
            if case .main = phase { return id }
            throw PioneersModelError.notInMainPhase
        case .specialBuildPhase(_, let pending):
            guard let id: PlayerID = pending.first else {
                throw PioneersModelError.notInSpecialBuildPhase
            }
            return id
        case .setup, .gameComplete:
            throw PioneersModelError.notInMainPhase
        }
    }
}
