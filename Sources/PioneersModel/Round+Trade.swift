import Foundation

extension Round {
    // MARK: - Player-to-Player Trade Offers

    /// Posts a structured trade offer from the active player. Replaces any open offer in place
    /// (the old one is implicitly cancelled, logged as `cancelledTradeOffer` + `postedTradeOffer`).
    ///
    /// Only the active player in `.main` phase may post offers. `give` and `receive` must have at
    /// least one positive entry each, and the active player must currently hold the `give` resources.
    /// `eligibleAcceptors` defaults to every other player when nil.
    @discardableResult
    public mutating func postTradeOffer(
        give: [Resource: Int],
        receive: [Resource: Int],
        eligibleAcceptors: Set<PlayerID>? = nil,
        postedAt: Date = .now
    ) throws -> TradeOffer {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .main) = state else {
            throw PioneersModelError.notInMainPhase
        }
        let cleanedGive: [Resource: Int] = give.filter { $0.value > 0 }
        let cleanedReceive: [Resource: Int] = receive.filter { $0.value > 0 }
        guard cleanedGive.isEmpty == false, cleanedReceive.isEmpty == false else {
            throw PioneersModelError.invalidTradeOffer
        }
        guard let activeHand: PlayerHand = playerHand(for: activeID) else {
            throw PioneersModelError.playerNotFound
        }
        guard Round.hand(activeHand.resources, covers: cleanedGive) else {
            throw PioneersModelError.insufficientResources
        }

        let acceptors: Set<PlayerID>
        if let supplied: Set<PlayerID> = eligibleAcceptors {
            let opponents: Set<PlayerID> = Set(playerHands.map(\.player.id)).subtracting([activeID])
            acceptors = supplied.intersection(opponents)
            guard acceptors.isEmpty == false else { throw PioneersModelError.invalidTradeOffer }
        } else {
            acceptors = Set(playerHands.map(\.player.id)).subtracting([activeID])
        }

        // If an offer is open, log its cancellation first.
        if let existing: TradeOffer = openTradeOffer {
            logAction(playerID: activeID, decision: .cancelledTradeOffer(id: existing.id))
        }

        let offer = TradeOffer(
            id: nextTradeOfferID,
            fromPlayerID: activeID,
            give: cleanedGive,
            receive: cleanedReceive,
            eligibleAcceptors: acceptors,
            posted: postedAt
        )
        nextTradeOfferID += 1
        openTradeOffer = offer
        logAction(playerID: activeID, decision: .postedTradeOffer(id: offer.id))
        return offer
    }

    /// Cancels the currently-open trade offer. Only the active player may call this.
    public mutating func cancelTradeOffer() throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .main) = state else {
            throw PioneersModelError.notInMainPhase
        }
        guard let offer: TradeOffer = openTradeOffer else {
            throw PioneersModelError.noOpenTradeOffer
        }
        guard offer.fromPlayerID == activeID else {
            throw PioneersModelError.notActivePlayer
        }
        openTradeOffer = nil
        logAction(playerID: activeID, decision: .cancelledTradeOffer(id: offer.id))
    }

    /// An eligible non-active player accepts the open offer. `offerID` must match the current
    /// open offer (prevents accepting a stale offer). Resources swap atomically, the offer clears,
    /// and the turn remains in `.main` for the active player.
    public mutating func acceptTradeOffer(offerID: TradeOfferID, byPlayerID playerID: PlayerID) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard let offer: TradeOffer = openTradeOffer else {
            throw PioneersModelError.noOpenTradeOffer
        }
        guard offer.id == offerID else { throw PioneersModelError.tradeOfferIDMismatch }
        guard offer.fromPlayerID != playerID else { throw PioneersModelError.cannotAcceptOwnOffer }
        guard offer.eligibleAcceptors.contains(playerID) else {
            throw PioneersModelError.notEligibleToAcceptOffer
        }
        guard case .waitingForPlayer = state else {
            throw PioneersModelError.notInMainPhase
        }
        guard let acceptorHand: PlayerHand = playerHand(for: playerID) else {
            throw PioneersModelError.playerNotFound
        }
        guard let proposerHand: PlayerHand = playerHand(for: offer.fromPlayerID) else {
            throw PioneersModelError.playerNotFound
        }
        // Proposer must still have the give resources; acceptor must have the receive resources.
        guard Round.hand(proposerHand.resources, covers: offer.give) else {
            throw PioneersModelError.insufficientResources
        }
        guard Round.hand(acceptorHand.resources, covers: offer.receive) else {
            throw PioneersModelError.insufficientResources
        }

        try spendResources(offer.give, fromPlayerID: offer.fromPlayerID)
        try spendResources(offer.receive, fromPlayerID: playerID)
        grantResources(offer.receive, toPlayerID: offer.fromPlayerID)
        grantResources(offer.give, toPlayerID: playerID)

        openTradeOffer = nil
        logAction(playerID: playerID, decision: .acceptedTradeOffer(id: offer.id, acceptorID: playerID))
    }

    // MARK: - Bank Trade (4:1)

    public mutating func bankTrade(give: Resource, for want: Resource) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .main) = state else {
            throw PioneersModelError.notInMainPhase
        }
        guard give != want else { throw PioneersModelError.invalidBankTrade }
        guard let hand: PlayerHand = playerHand(for: activeID) else {
            throw PioneersModelError.playerNotFound
        }
        guard (hand.resources[give] ?? 0) >= 4 else {
            throw PioneersModelError.insufficientResources
        }
        try spendResources([give: 4], fromPlayerID: activeID)
        grantResources([want: 1], toPlayerID: activeID)
        logAction(
            playerID: activeID,
            decision: .bankTrade(give: [give: 4], receive: [want: 1])
        )
    }

    // MARK: - Port Trade (3:1 or 2:1)

    public mutating func portTrade(portID: PortID, give: Resource, for want: Resource) throws {
        guard isComplete == false else { throw PioneersModelError.gameIsComplete }
        guard case .waitingForPlayer(let activeID, .main) = state else {
            throw PioneersModelError.notInMainPhase
        }
        guard let port: Port = port(id: portID) else { throw PioneersModelError.invalidPortID }
        guard give != want else { throw PioneersModelError.invalidPortTrade }

        // Player must have a building on one of the port's vertices.
        let ownsPort: Bool = port.vertexIDs.contains { vid in
            if let b: Building = building(at: vid) { return b.ownerID == activeID }
            return false
        }
        guard ownsPort else { throw PioneersModelError.portNotOwnedByPlayer }

        switch port.kind {
        case .generic:
            guard let hand: PlayerHand = playerHand(for: activeID) else {
                throw PioneersModelError.playerNotFound
            }
            guard (hand.resources[give] ?? 0) >= 3 else { throw PioneersModelError.insufficientResources }
            try spendResources([give: 3], fromPlayerID: activeID)
            grantResources([want: 1], toPlayerID: activeID)
            logAction(
                playerID: activeID,
                decision: .portTrade(portID: portID, give: [give: 3], receive: [want: 1])
            )
        case .specific(let required):
            guard give == required else { throw PioneersModelError.invalidPortTrade }
            guard let hand: PlayerHand = playerHand(for: activeID) else {
                throw PioneersModelError.playerNotFound
            }
            guard (hand.resources[give] ?? 0) >= 2 else { throw PioneersModelError.insufficientResources }
            try spendResources([give: 2], fromPlayerID: activeID)
            grantResources([want: 1], toPlayerID: activeID)
            logAction(
                playerID: activeID,
                decision: .portTrade(portID: portID, give: [give: 2], receive: [want: 1])
            )
        }
    }
}
