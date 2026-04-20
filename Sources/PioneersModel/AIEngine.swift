import Foundation

// MARK: - AI Difficulty

public enum AIDifficulty: String, Equatable, Codable, CaseIterable, Sendable {
    case easy
    case medium
    case hard

    public var displayableName: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
}

// MARK: - AIAction

/// All distinct AI decisions applicable in a Round, across every phase. `AIEngine.chooseAction`
/// selects one; `AIEngine.makeMove` then applies it to the round via the appropriate public API.
public enum AIAction: Equatable, Sendable {
    case placeInitialHomestead(vertexID: VertexID)
    case placeInitialTrail(edgeID: EdgeID)
    case rollDice
    case discardResources(playerID: PlayerID, resources: [Resource: Int])
    case moveOutlaw(tileID: TileID)
    case stealFromPlayer(victimID: PlayerID)
    case buildTrail(edgeID: EdgeID)
    case buildHomestead(vertexID: VertexID)
    case upgradeToTown(vertexID: VertexID)
    case buyDevCard
    case playDevCard(id: DevCardID, resource: Resource?, pickedResources: [Resource]?)
    case bankTrade(give: Resource, want: Resource)
    case portTrade(portID: PortID, give: Resource, want: Resource)
    case acceptTradeOffer(offerID: TradeOfferID)
    case declineTradeOffer
    case resolvePathfinderEarly
    case endTurn
    case specialBuildPass
}

// MARK: - AIEngine

/// A heuristic AI engine. Uses only public game state (tiles, vertices, edges, buildings,
/// trails, the outlaw's location, port ownership, the active open trade offer, and opponents'
/// resource *counts* — never their hand identities or their held dev cards).
public struct AIEngine: Sendable {
    public let difficulty: AIDifficulty

    public init(difficulty: AIDifficulty) {
        self.difficulty = difficulty
    }

    /// Applies a single AI move on `round` for `playerID`. Returns the chosen action (nil if no
    /// action is applicable, e.g. it isn't this player's turn).
    @discardableResult
    public func makeMove(on round: inout Round, playerID: PlayerID) throws -> AIAction? {
        guard let action: AIAction = chooseAction(for: round, playerID: playerID) else {
            return nil
        }
        try apply(action: action, on: &round, playerID: playerID)
        return action
    }

    /// Selects a legal action for `playerID` under the current round state. Returns nil if the
    /// engine has nothing actionable (wrong player's turn, or no legal move in the current phase).
    public func chooseAction(for round: Round, playerID: PlayerID) -> AIAction? {
        switch round.state {
        case .setup(let pending):
            guard let next: Round.SetupPlacement = pending.first, next.playerID == playerID else { return nil }
            switch next.step {
            case .homestead: return chooseInitialHomestead(round: round, playerID: playerID)
            case .trail: return chooseInitialTrail(round: round, playerID: playerID)
            }
        case .waitingForPlayer(let id, let phase):
            if id != playerID { return chooseNonActiveAction(round: round, playerID: playerID) }
            return chooseActiveAction(round: round, playerID: playerID, phase: phase)
        case .specialBuildPhase(_, let pending):
            guard pending.first == playerID else { return nil }
            return chooseSpecialBuildAction(round: round, playerID: playerID)
        case .gameComplete:
            return nil
        }
    }

    // MARK: - Apply

    private func apply(action: AIAction, on round: inout Round, playerID: PlayerID) throws {
        switch action {
        case .placeInitialHomestead(let vid):
            try round.placeInitialHomestead(playerID: playerID, vertexID: vid)
        case .placeInitialTrail(let eid):
            try round.placeInitialTrail(playerID: playerID, edgeID: eid)
        case .rollDice:
            _ = try round.rollDice()
        case .discardResources(let pid, let bundle):
            try round.discardResources(playerID: pid, resources: bundle)
        case .moveOutlaw(let tileID):
            try round.moveOutlaw(toTileID: tileID)
        case .stealFromPlayer(let victim):
            _ = try round.stealFromPlayer(victimID: victim)
        case .buildTrail(let eid):
            try round.buildTrail(edgeID: eid)
        case .buildHomestead(let vid):
            try round.buildHomestead(vertexID: vid)
        case .upgradeToTown(let vid):
            try round.upgradeToTown(vertexID: vid)
        case .buyDevCard:
            try round.buyDevCard()
        case .playDevCard(let id, let r, let picks):
            try round.playDevCard(id: id, resource: r, pickedResources: picks)
        case .bankTrade(let g, let w):
            try round.bankTrade(give: g, for: w)
        case .portTrade(let pid, let g, let w):
            try round.portTrade(portID: pid, give: g, for: w)
        case .acceptTradeOffer(let offerID):
            try round.acceptTradeOffer(offerID: offerID, byPlayerID: playerID)
        case .declineTradeOffer:
            break // no-op; non-active declines simply by not accepting
        case .resolvePathfinderEarly:
            try round.resolvePathfinderEarly()
        case .endTurn:
            try round.endTurn()
        case .specialBuildPass:
            try round.specialBuildPass()
        }
    }

    // MARK: - Active player decisions

    private func chooseActiveAction(round: Round, playerID: PlayerID, phase: Round.TurnPhase) -> AIAction? {
        switch phase {
        case .beforeRoll:
            return .rollDice
        case .discardingAfterSeven(let pending):
            // The active player may themselves be a pending discarder; handle it here too.
            if pending.contains(playerID) {
                return chooseDiscard(round: round, playerID: playerID)
            }
            return nil
        case .movingOutlaw:
            return chooseOutlawTarget(round: round, playerID: playerID)
        case .stealingAfterOutlaw(let candidates, _):
            return chooseStealVictim(round: round, candidates: candidates, playerID: playerID)
        case .main:
            return chooseMainAction(round: round, playerID: playerID)
        case .playingPathfinder(let remaining):
            return choosePathfinderTrail(round: round, playerID: playerID, remaining: remaining)
        case .playingBountifulHarvest:
            let picks: [Resource] = bestTwoPicks(round: round, playerID: playerID)
            return .playDevCard(id: -1, resource: nil, pickedResources: picks)
        case .playingRoundup:
            return .playDevCard(id: -1, resource: bestRoundupTarget(round: round), pickedResources: nil)
        }
    }

    private func chooseNonActiveAction(round: Round, playerID: PlayerID) -> AIAction? {
        // Check if we need to discard (7 rolled by someone else).
        if case .waitingForPlayer(_, .discardingAfterSeven(let pending)) = round.state,
           pending.contains(playerID) {
            return chooseDiscard(round: round, playerID: playerID)
        }
        // Check if we can accept an open trade offer.
        if let offer: TradeOffer = round.openTradeOffer,
           offer.eligibleAcceptors.contains(playerID),
           offer.fromPlayerID != playerID {
            return chooseTradeOfferResponse(round: round, offer: offer, playerID: playerID)
        }
        return nil
    }

    private func chooseMainAction(round: Round, playerID: PlayerID) -> AIAction? {
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return .endTurn }

        // 1. Town upgrade (most valuable VP gain).
        if hand.remainingTowns > 0, Round.hand(hand.resources, covers: Round.townCost) {
            let ownHomesteads: [Building] = round.buildings.filter {
                $0.ownerID == playerID && $0.kind == .homestead
            }
            if let target: Building = ownHomesteads.max(by: { a, b in
                vertexValue(round: round, vertexID: a.vertexID) < vertexValue(round: round, vertexID: b.vertexID)
            }) {
                return .upgradeToTown(vertexID: target.vertexID)
            }
        }

        // 2. New homestead on the best available vertex we can reach.
        if hand.remainingHomesteads > 0, Round.hand(hand.resources, covers: Round.homesteadCost) {
            if let target: VertexID = bestReachableHomesteadVertex(round: round, playerID: playerID) {
                return .buildHomestead(vertexID: target)
            }
        }

        // 3. Trail that extends our network toward a promising vertex.
        if hand.remainingTrails > 0, Round.hand(hand.resources, covers: Round.trailCost) {
            if let eid: EdgeID = chooseExpansionTrail(round: round, playerID: playerID) {
                return .buildTrail(edgeID: eid)
            }
        }

        // 4. Dev card buy when we have the resources and there are cards left.
        if round.devCardDeck.isEmpty == false, Round.hand(hand.resources, covers: Round.devCardCost) {
            if difficulty != .easy {
                return .buyDevCard
            }
        }

        // 5. Bank/port trade toward a missing build resource, when we have surplus.
        if let trade: AIAction = chooseBankOrPortTrade(round: round, playerID: playerID) {
            return trade
        }

        // 6. Play a held non-ranger dev card if useful (landmark cards are silent; skip).
        if round.hasPlayedDevCardThisTurn == false, difficulty != .easy {
            if let play: AIAction = choosePlayableDevCard(round: round, playerID: playerID) {
                return play
            }
        }

        // Done — end turn.
        return .endTurn
    }

    private func chooseSpecialBuildAction(round: Round, playerID: PlayerID) -> AIAction? {
        // Treat special build like .main, minus trading and dev-card plays. If no build is worthwhile, pass.
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return .specialBuildPass }

        if hand.remainingTowns > 0, Round.hand(hand.resources, covers: Round.townCost) {
            let ownHomesteads: [Building] = round.buildings.filter {
                $0.ownerID == playerID && $0.kind == .homestead
            }
            if let target: Building = ownHomesteads.first {
                return .upgradeToTown(vertexID: target.vertexID)
            }
        }
        if hand.remainingHomesteads > 0, Round.hand(hand.resources, covers: Round.homesteadCost),
           let target: VertexID = bestReachableHomesteadVertex(round: round, playerID: playerID) {
            return .buildHomestead(vertexID: target)
        }
        if hand.remainingTrails > 0, Round.hand(hand.resources, covers: Round.trailCost),
           let eid: EdgeID = chooseExpansionTrail(round: round, playerID: playerID) {
            return .buildTrail(edgeID: eid)
        }
        if round.devCardDeck.isEmpty == false, Round.hand(hand.resources, covers: Round.devCardCost) {
            return .buyDevCard
        }
        return .specialBuildPass
    }

    // MARK: - Setup heuristics

    private func chooseInitialHomestead(round: Round, playerID: PlayerID) -> AIAction? {
        let candidates: [VertexID] = round.vertices.filter { round.canPlaceHomestead(at: $0.id) }.map(\.id)
        guard candidates.isEmpty == false else { return nil }
        let scored: [(VertexID, Double)] = candidates.map { ($0, vertexValue(round: round, vertexID: $0)) }
        if difficulty == .easy {
            // Easy: random among top-third to stay legal but not optimal.
            let sorted: [(VertexID, Double)] = scored.sorted { $0.1 > $1.1 }
            let cut: Int = max(1, sorted.count / 3)
            let slice: ArraySlice<(VertexID, Double)> = sorted.prefix(cut)
            return .placeInitialHomestead(vertexID: slice[slice.indices.randomElement() ?? slice.startIndex].0)
        }
        guard let best: (VertexID, Double) = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        return .placeInitialHomestead(vertexID: best.0)
    }

    private func chooseInitialTrail(round: Round, playerID: PlayerID) -> AIAction? {
        // Walk log backward for last homestead placed; pick any adjacent free edge.
        let vid: VertexID? = round.log.reversed().compactMap { action -> VertexID? in
            guard action.playerID == playerID else { return nil }
            if case .placedInitialHomestead(let v) = action.decision { return v }
            return nil
        }.first
        guard let vid, let v: Vertex = round.vertex(id: vid) else { return nil }
        let free: [EdgeID] = v.adjacentEdgeIDs.filter { round.trail(at: $0) == nil }
        guard let eid: EdgeID = free.first else { return nil }
        return .placeInitialTrail(edgeID: eid)
    }

    // MARK: - Discard / outlaw / steal

    private func chooseDiscard(round: Round, playerID: PlayerID) -> AIAction? {
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return nil }
        let total: Int = hand.totalResourceCount
        let required: Int = total / 2
        guard required > 0 else { return nil }
        // Discard from largest stacks first.
        var remaining: Int = required
        var discard: [Resource: Int] = [:]
        let sorted: [(Resource, Int)] = hand.resources.sorted { $0.value > $1.value }
        for (r, n) in sorted {
            if remaining == 0 { break }
            let take: Int = min(n, remaining)
            discard[r] = take
            remaining -= take
        }
        return .discardResources(playerID: playerID, resources: discard)
    }

    private func chooseOutlawTarget(round: Round, playerID: PlayerID) -> AIAction? {
        // Pick a tile adjacent to the highest-VP opponent (avoid self), weighted by pip count.
        var bestTile: TileID?
        var bestScore: Double = -1
        for tile in round.tiles where tile.id != round.outlawTileID && tile.type != .desert {
            var score: Double = 0
            for vid in tile.vertexIDs {
                guard let b: Building = round.building(at: vid) else { continue }
                if b.ownerID == playerID {
                    score -= 10 // strongly avoid our own buildings
                    continue
                }
                let pip: Double = Double(round.pipCount(forToken: tile.numberToken))
                let vpWeight: Double = Double(round.publicVictoryPoints(for: b.ownerID))
                score += pip * (1.0 + vpWeight * 0.5) * Double(b.kind.resourceYield)
            }
            if score > bestScore {
                bestScore = score
                bestTile = tile.id
            }
        }
        if let tileID: TileID = bestTile {
            return .moveOutlaw(tileID: tileID)
        }
        // Fallback: first non-outlaw tile.
        if let anyID: TileID = round.tiles.first(where: { $0.id != round.outlawTileID })?.id {
            return .moveOutlaw(tileID: anyID)
        }
        return nil
    }

    private func chooseStealVictim(round: Round, candidates: [PlayerID], playerID: PlayerID) -> AIAction? {
        // Prefer the opponent holding the most resource cards.
        let best: PlayerID? = candidates.max { a, b in
            (round.playerHand(for: a)?.totalResourceCount ?? 0) < (round.playerHand(for: b)?.totalResourceCount ?? 0)
        }
        if let best { return .stealFromPlayer(victimID: best) }
        return candidates.first.map { .stealFromPlayer(victimID: $0) }
    }

    // MARK: - Build heuristics

    /// Rough vertex value: sum of expected pips of adjacent non-desert tiles, with a small bonus
    /// for resource diversity. Medium/hard also reward port access.
    private func vertexValue(round: Round, vertexID: VertexID) -> Double {
        guard let v: Vertex = round.vertex(id: vertexID) else { return 0 }
        var pips: Double = 0
        var resources: Set<Resource> = []
        for tileID in v.adjacentTileIDs {
            guard let t: Tile = round.tile(id: tileID) else { continue }
            pips += Double(round.pipCount(forToken: t.numberToken))
            if let r: Resource = t.type.resource { resources.insert(r) }
        }
        var score: Double = pips + Double(resources.count) * 0.5
        if difficulty != .easy, v.portID != nil { score += 1.5 }
        if difficulty == .hard {
            // Blocking: bonus for vertices whose adjacent-vertices host opponents.
            for adj in v.adjacentVertexIDs {
                if let b: Building = round.building(at: adj), b.ownerID != "" { score += 0.3 }
            }
        }
        return score
    }

    private func bestReachableHomesteadVertex(round: Round, playerID: PlayerID) -> VertexID? {
        let reachable: [Vertex] = round.vertices.filter { v in
            guard round.canPlaceHomestead(at: v.id) else { return false }
            for eid in v.adjacentEdgeIDs {
                if let t: Trail = round.trail(at: eid), t.ownerID == playerID { return true }
            }
            return false
        }
        return reachable.max { vertexValue(round: round, vertexID: $0.id) < vertexValue(round: round, vertexID: $1.id) }?.id
    }

    private func chooseExpansionTrail(round: Round, playerID: PlayerID) -> EdgeID? {
        let legal: [Edge] = round.edges.filter {
            round.trail(at: $0.id) == nil && round.isEdgeConnectedToPlayerNetwork(edgeID: $0.id, playerID: playerID)
        }
        guard legal.isEmpty == false else { return nil }
        // Prefer edges whose *other* endpoint opens up a high-value empty vertex.
        let scored: [(Edge, Double)] = legal.map { e in
            var score: Double = 0
            for vid in e.endpointVertexIDs {
                if round.canPlaceHomestead(at: vid) {
                    score += vertexValue(round: round, vertexID: vid)
                }
            }
            return (e, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0.id
    }

    private func choosePathfinderTrail(round: Round, playerID: PlayerID, remaining: Int) -> AIAction {
        if let eid: EdgeID = chooseExpansionTrail(round: round, playerID: playerID) {
            return .buildTrail(edgeID: eid)
        }
        return .resolvePathfinderEarly
    }

    // MARK: - Trade heuristics

    private func chooseBankOrPortTrade(round: Round, playerID: PlayerID) -> AIAction? {
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return nil }
        // Figure out what we're short on for the cheapest next build.
        let wanted: Resource? = firstMissingResource(hand: hand.resources, forCost: Round.homesteadCost)
            ?? firstMissingResource(hand: hand.resources, forCost: Round.trailCost)
            ?? firstMissingResource(hand: hand.resources, forCost: Round.townCost)
            ?? firstMissingResource(hand: hand.resources, forCost: Round.devCardCost)
        guard let want: Resource = wanted else { return nil }

        // Check ports we own.
        let owned: [Port] = round.ports(ownedBy: playerID)
        // 2:1 specific port trade preferred.
        for port in owned {
            if case .specific(let r) = port.kind, (hand.resources[r] ?? 0) >= 2, r != want {
                return .portTrade(portID: port.id, give: r, want: want)
            }
        }
        // 3:1 generic port trade next.
        for port in owned {
            if case .generic = port.kind {
                if let give: Resource = Resource.allCases.first(where: { (hand.resources[$0] ?? 0) >= 3 && $0 != want }) {
                    return .portTrade(portID: port.id, give: give, want: want)
                }
            }
        }
        // 4:1 bank trade last.
        if let give: Resource = Resource.allCases.first(where: { (hand.resources[$0] ?? 0) >= 4 && $0 != want }) {
            return .bankTrade(give: give, want: want)
        }
        return nil
    }

    private func firstMissingResource(hand: [Resource: Int], forCost cost: [Resource: Int]) -> Resource? {
        for (r, n) in cost {
            if (hand[r] ?? 0) < n { return r }
        }
        return nil
    }

    // MARK: - Dev card plays

    private func choosePlayableDevCard(round: Round, playerID: PlayerID) -> AIAction? {
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return nil }
        // Never play a card purchased this turn.
        let cards: [DevCard] = hand.heldDevCards.filter {
            hand.devCardIDsPurchasedThisTurn.contains($0.id) == false && $0.kind != .landmark
        }
        // Prefer Bountiful Harvest or Roundup when they immediately unlock a build; otherwise Ranger.
        if let card: DevCard = cards.first(where: { $0.kind == .bountifulHarvest }) {
            let picks: [Resource] = bestTwoPicks(round: round, playerID: playerID)
            return .playDevCard(id: card.id, resource: nil, pickedResources: picks)
        }
        if let card: DevCard = cards.first(where: { $0.kind == .roundup }) {
            return .playDevCard(id: card.id, resource: bestRoundupTarget(round: round), pickedResources: nil)
        }
        if let card: DevCard = cards.first(where: { $0.kind == .ranger }) {
            return .playDevCard(id: card.id, resource: nil, pickedResources: nil)
        }
        if let card: DevCard = cards.first(where: { $0.kind == .pathfinder }) {
            return .playDevCard(id: card.id, resource: nil, pickedResources: nil)
        }
        return nil
    }

    private func bestTwoPicks(round: Round, playerID: PlayerID) -> [Resource] {
        // Crude: pick the first two resources we're short of for homestead cost.
        var picks: [Resource] = []
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return [.wood, .brick] }
        for (r, n) in Round.homesteadCost {
            if (hand.resources[r] ?? 0) < n { picks.append(r) }
            if picks.count == 2 { break }
        }
        while picks.count < 2 { picks.append(.wheat) }
        return picks
    }

    private func bestRoundupTarget(round: Round) -> Resource {
        // Resource with the largest overall opponent surplus.
        var totals: [Resource: Int] = [:]
        for hand in round.playerHands {
            for (r, n) in hand.resources { totals[r, default: 0] += n }
        }
        return totals.max(by: { $0.value < $1.value })?.key ?? .wheat
    }

    // MARK: - Trade offer response

    private func chooseTradeOfferResponse(round: Round, offer: TradeOffer, playerID: PlayerID) -> AIAction {
        guard let hand: PlayerHand = round.playerHand(for: playerID) else { return .declineTradeOffer }
        // Only accept if we have the resources and the trade nets at least 1 resource we "want".
        guard Round.hand(hand.resources, covers: offer.receive) else { return .declineTradeOffer }
        let wantedResources: Set<Resource> = Set([Round.homesteadCost, Round.trailCost, Round.townCost, Round.devCardCost].flatMap(\.keys))
        let giveResources: Set<Resource> = Set(offer.give.keys)
        if giveResources.intersection(wantedResources).isEmpty { return .declineTradeOffer }
        return .acceptTradeOffer(offerID: offer.id)
    }
}
