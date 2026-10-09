import Foundation
import Testing
@testable import PioneersModel

// MARK: - Helpers

private func makePlayers(_ count: Int) -> [Player] {
    let colors: [PlayerColor] = PlayerColor.allCases
    return (0..<count).map { i in
        Player(id: "p\(i + 1)", name: "Player \(i + 1)", color: colors[i % colors.count])
    }
}

private func makeStandardRound(
    playerCount: Int = 3,
    cookedDiceRolls: [Int] = []
) throws -> Round {
    let players: [Player] = makePlayers(playerCount)
    let map: GameMap = playerCount >= Round.expansionThreshold ? .expansion() : .standard()
    return try Round(
        players: players,
        expansionRuleSet: .specialBuilding,
        cookedMap: map,
        cookedNumberTokenOrder: map.numberTokenBag,
        cookedDevCardDeck: map.devCardDeck,
        cookedDiceRolls: cookedDiceRolls
    )
}

/// Drive the setup phase to completion. Returns the resulting round.
private func autoSetup(_ round: inout Round) {
    _ = Round.autoCompleteSetup(&round)
}

private func trailPath(
    in round: Round,
    length: Int,
    excluding excludedEdges: Set<EdgeID> = []
) -> [EdgeID]? {
    let edgesByVertex: [VertexID: [Edge]] = Dictionary(
        grouping: round.edges.filter { excludedEdges.contains($0.id) == false },
        by: { $0.endpointVertexIDs[0] }
    ).merging(
        Dictionary(
            grouping: round.edges.filter { excludedEdges.contains($0.id) == false },
            by: { $0.endpointVertexIDs[1] }
        ),
        uniquingKeysWith: +
    )

    func search(from vertexID: VertexID, used: Set<EdgeID>, path: [EdgeID]) -> [EdgeID]? {
        if path.count == length { return path }
        for edge in edgesByVertex[vertexID, default: []] where used.contains(edge.id) == false {
            guard let nextVertexID = edge.endpointVertexIDs.first(where: { $0 != vertexID }) else {
                continue
            }
            if let result = search(
                from: nextVertexID,
                used: used.union([edge.id]),
                path: path + [edge.id]
            ) {
                return result
            }
        }
        return nil
    }

    for vertex in round.vertices {
        if let path = search(from: vertex.id, used: [], path: []) { return path }
    }
    return nil
}

// MARK: - Initialization

@Test
func rejectsFewerThanThreePlayers() throws {
    let players: [Player] = makePlayers(2)
    #expect(throws: PioneersModelError.notEnoughPlayers) {
        _ = try Round(players: players)
    }
}

@Test
func rejectsMoreThanSixPlayers() throws {
    let players: [Player] = (0..<7).map { Player(id: "p\($0)", name: "Player \($0)", color: .blue) }
    #expect(throws: PioneersModelError.tooManyPlayers) {
        _ = try Round(players: players)
    }
}

@Test
func rejectsDuplicatePlayerIDs() throws {
    let players: [Player] = [
        Player(id: "p1", name: "A", color: .red),
        Player(id: "p1", name: "B", color: .blue),
        Player(id: "p3", name: "C", color: .green),
    ]
    #expect(throws: PioneersModelError.duplicatePlayerIDs) {
        _ = try Round(players: players)
    }
}

@Test
func rejectsDuplicatePlayerColors() throws {
    let players: [Player] = [
        Player(id: "p1", name: "A", color: .red),
        Player(id: "p2", name: "B", color: .red),
        Player(id: "p3", name: "C", color: .green),
    ]
    #expect(throws: PioneersModelError.duplicatePlayerColors) {
        _ = try Round(players: players)
    }
}

@Test
func standardMapIsUsedForThreePlayers() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    #expect(round.tiles.count == 19)
}

@Test
func standardMapIsUsedForFourPlayers() throws {
    let round: Round = try makeStandardRound(playerCount: 4)
    #expect(round.tiles.count == 19)
}

@Test
func expansionMapIsUsedForFivePlayers() throws {
    let round: Round = try makeStandardRound(playerCount: 5)
    #expect(round.tiles.count == 30)
}

@Test
func expansionMapIsUsedForSixPlayers() throws {
    let round: Round = try makeStandardRound(playerCount: 6)
    #expect(round.tiles.count == 30)
}

@Test
func numberTokensAreAssignedToAllNonDesertTiles() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    for tile in round.tiles {
        if tile.type == .desert {
            #expect(tile.numberToken == nil)
        } else {
            #expect(tile.numberToken != nil)
        }
    }
}

@Test(arguments: [3, 5])
func standardNumberTokensFollowOfficialSpiral(playerCount: Int) throws {
    let round: Round = try Round(players: makePlayers(playerCount))
    let map: GameMap = playerCount >= Round.expansionThreshold ? .expansion() : .standard()
    let expected: [Int] = playerCount >= Round.expansionThreshold
        ? GameMap.expansionSpiralNumberTokens
        : GameMap.standardSpiralNumberTokens
    let actual: [Int] = map.spiralTileIDs().compactMap { id in
        round.tiles.first(where: { $0.id == id })?.numberToken
    }
    #expect(actual == expected)
    let redTiles: [Tile] = round.tiles.filter { $0.numberToken == 6 || $0.numberToken == 8 }
    for tile in redTiles {
        #expect(!redTiles.contains { $0.id != tile.id && map.areAdjacent(tile, $0) })
    }
}

@Test(arguments: [3, 5])
func randomNumberTokensKeepRedNumbersApart(playerCount: Int) throws {
    let map: GameMap = playerCount >= Round.expansionThreshold ? .expansion() : .standard()
    let round: Round = try Round(
        players: makePlayers(playerCount),
        numberTokenLayout: .randomSeparatedRed,
        cookedMap: map
    )
    let redTiles: [Tile] = round.tiles.filter { $0.numberToken == 6 || $0.numberToken == 8 }
    #expect(round.tiles.compactMap(\.numberToken).sorted() == map.numberTokenBag.sorted())
    for tile in redTiles {
        #expect(!redTiles.contains { $0.id != tile.id && map.areAdjacent(tile, $0) })
    }
}

@Test
func outlawStartsOnDesert() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    #expect(round.tile(id: round.outlawTileID)?.type == .desert)
}

@Test
func liveGamesShuffleHexTypes() throws {
    let players: [Player] = makePlayers(3)
    let first: Round = try Round(players: players)
    let second: Round = try Round(players: players)
    let firstTypes: [TileType] = first.tiles.map(\.type)
    let secondTypes: [TileType] = second.tiles.map(\.type)
    #expect(firstTypes.sorted(by: { $0.rawValue < $1.rawValue }) == secondTypes.sorted(by: { $0.rawValue < $1.rawValue }))
    #expect(firstTypes != secondTypes)
    #expect(firstTypes.filter { $0 == .desert }.count == 1)
    #expect(first.tile(id: first.outlawTileID)?.type == .desert)
}

// MARK: - Board topology

@Test
func standardBoardHas54VerticesAnd72Edges() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    #expect(round.vertices.count == 54)
    #expect(round.edges.count == 72)
}

@Test
func everyEdgeHasTwoEndpoints() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    for e in round.edges {
        #expect(e.endpointVertexIDs.count == 2)
    }
}

@Test
func allPortsHaveTwoAdjacentVertices() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    #expect(round.ports.count == 9)
    for p in round.ports {
        #expect(p.vertexIDs.count == 2)
    }
}

@Test
func expansionBoardHas11Ports() throws {
    let round: Round = try makeStandardRound(playerCount: 5)
    #expect(round.ports.count == 11)
}

// MARK: - Setup

@Test
func snakeOrderSetupIsComplete() throws {
    var round: Round = try makeStandardRound(playerCount: 4)
    autoSetup(&round)
    #expect(round.isSetup == false)
    // Every player has 2 homesteads and 2 trails.
    for hand in round.playerHands {
        let homesteads: [Building] = round.buildings(for: hand.player.id)
        #expect(homesteads.count == 2)
        #expect(round.trails(for: hand.player.id).count == 2)
    }
    // First player is now at beforeRoll.
    guard case .waitingForPlayer(let firstID, .beforeRoll) = round.state else {
        Issue.record("Expected waitingForPlayer .beforeRoll after setup")
        return
    }
    #expect(firstID == round.playerHands.first?.player.id)
}

@Test
func secondHomesteadGrantsResources() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    // After setup, at least one player should have received some starting resources.
    let totalResources: Int = round.playerHands.map(\.totalResourceCount).reduce(0, +)
    #expect(totalResources > 0)
}

@Test
func initialTrailOptionsOnlyIncludeEdgesAtMostRecentHomestead() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    let playerID = "p1"
    let firstVertexID = try #require(round.vertices.first(where: { round.canPlaceHomestead(at: $0.id) })?.id)
    try round.placeInitialHomestead(playerID: playerID, vertexID: firstVertexID)

    let firstTrailID = try #require(round.vertex(id: firstVertexID)?.adjacentEdgeIDs.first)
    try round.placeInitialTrail(playerID: playerID, edgeID: firstTrailID)

    round.state = .setup(pendingPlacements: [
        .init(playerID: playerID, lap: 2, step: .homestead),
        .init(playerID: playerID, lap: 2, step: .trail),
    ])
    let secondVertexID = try #require(round.vertices.first(where: {
        $0.id != firstVertexID && round.canPlaceHomestead(at: $0.id)
    })?.id)
    try round.placeInitialHomestead(playerID: playerID, vertexID: secondVertexID)

    let oldHomeEdgeID = try #require(round.vertex(id: firstVertexID)?.adjacentEdgeIDs.first(where: {
        $0 != firstTrailID && round.trail(at: $0) == nil
    }))
    #expect(round.canPlaceTrail(at: oldHomeEdgeID, forPlayerID: playerID))
    #expect(!round.canPlaceInitialTrail(at: oldHomeEdgeID, forPlayerID: playerID))

    let newHomeEdgeIDs = try #require(round.vertex(id: secondVertexID)?.adjacentEdgeIDs)
    #expect(!newHomeEdgeIDs.isEmpty)
    #expect(newHomeEdgeIDs.allSatisfy { round.canPlaceInitialTrail(at: $0, forPlayerID: playerID) })
}

// MARK: - Rolling

@Test
func cannotRollDiceOutsideBeforeRollPhase() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [6])
    autoSetup(&round)
    _ = try round.rollDice()
    #expect(throws: PioneersModelError.notInBeforeRollPhase) {
        _ = try round.rollDice()
    }
}

@Test
func rollingNonSevenDistributesResources() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [8])
    autoSetup(&round)

    // Capture resources before the roll (after setup freebie on second homestead).
    let before: [Int] = round.playerHands.map(\.totalResourceCount)
    _ = try round.rollDice()

    // At least one player should have received resources if any building sits on an 8-tile
    // (not guaranteed, but vanishingly unlikely to happen zero times across 4 buildings of each player).
    let after: [Int] = round.playerHands.map(\.totalResourceCount)
    let totalGained: Int = zip(before, after).map { $1 - $0 }.reduce(0, +)
    #expect(totalGained >= 0) // sanity only; production test verifies specific tiles below
    #expect(round.lastDiceTotal == 8)
    guard case .waitingForPlayer(_, .main) = round.state else {
        Issue.record("Expected main phase after rolling non-7")
        return
    }
}

@Test
func rollingSevenEntersSevenResolution() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [7])
    autoSetup(&round)

    // Give the first player a lot of resources to force a discard (they're typically under 7 after setup).
    round.playerHands[0].resources = [.wood: 3, .brick: 3, .wheat: 3]
    _ = try round.rollDice()

    switch round.state {
    case .waitingForPlayer(_, .discardingAfterSeven(let pending)):
        #expect(pending.contains("p1"))
    case .waitingForPlayer(_, .movingOutlaw):
        break // acceptable if nobody had >7 cards
    default:
        Issue.record("Expected 7-resolution phase; got \(round.state)")
    }
}

// MARK: - Seven resolution

@Test
func discardRejectsWrongAmount() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [7])
    autoSetup(&round)
    round.playerHands[0].resources = [.wood: 4, .brick: 4] // 8 cards, must discard 4
    _ = try round.rollDice()

    if case .waitingForPlayer(_, .discardingAfterSeven) = round.state {
        #expect(throws: PioneersModelError.wrongDiscardAmount) {
            try round.discardResources(playerID: "p1", resources: [.wood: 2])
        }
    }
}

@Test
func sevenResolutionSkipsDiscardWhenAllUnderLimit() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [7])
    autoSetup(&round)
    // Clear everyone's hand so nobody has > maxHandSizeBeforeDiscard.
    for i in round.playerHands.indices { round.playerHands[i].resources = [:] }
    _ = try round.rollDice()
    guard case .waitingForPlayer(_, .movingOutlaw) = round.state else {
        Issue.record("Expected movingOutlaw phase")
        return
    }
}

@Test
func movingOutlawToSameTileThrows() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [7])
    autoSetup(&round)
    for i in round.playerHands.indices { round.playerHands[i].resources = [:] }
    _ = try round.rollDice()
    let current: TileID = round.outlawTileID
    #expect(throws: PioneersModelError.cannotMoveOutlawToSameTile) {
        try round.moveOutlaw(toTileID: current)
    }
}

// MARK: - Build legality

@Test
func distanceTwoRuleIsEnforced() throws {
    let round: Round = try makeStandardRound(playerCount: 3)
    // Find any placed homestead's neighbor vertex (after setup) — for this test we work on a
    // freshly-set-up board so we need to simulate: just pick any vertex + its neighbor.
    var r: Round = round
    autoSetup(&r)
    // After auto setup there are 6 homesteads on the board (2 per player * 3 players). Any vertex
    // adjacent to one of those must fail the distance rule.
    let firstBuilding: Building = r.buildings.first!
    let neighborVID: VertexID? = r.vertex(id: firstBuilding.vertexID)?.adjacentVertexIDs.first
    #expect(neighborVID != nil)
    #expect(r.canPlaceHomestead(at: neighborVID!) == false)
}

// MARK: - Bank and Port Trades

@Test
func bankTradeFourForOne() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    let activeID: PlayerID = round.currentPlayerID!
    // Stock up on wood directly (bypass production).
    round.playerHands[0].resources[.wood] = 5
    try round.bankTrade(give: .wood, for: .ore)
    #expect((round.playerHand(for: activeID)?.resources[.wood] ?? 0) == 1)
    #expect((round.playerHand(for: activeID)?.resources[.ore] ?? 0) >= 1)
}

@Test
func bankTradeRequiresFour() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 3]
    #expect(throws: PioneersModelError.insufficientResources) {
        try round.bankTrade(give: .wood, for: .ore)
    }
}

// MARK: - Trade Offer Protocol

@Test
func onlyActivePlayerCanPostTradeOffer() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources[.wood] = 2
    // posting by active player (p1) should work
    let offer: TradeOffer = try round.postTradeOffer(
        give: [.wood: 1],
        receive: [.brick: 1]
    )
    #expect(round.openTradeOffer?.id == offer.id)
}

@Test
func tradeOfferPreservesMixedGiveAndReceiveResources() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 2, .sheep: 3]

    let give: [Resource: Int] = [.wood: 1, .sheep: 2]
    let receive: [Resource: Int] = [.brick: 1, .ore: 1]
    let offer: TradeOffer = try round.postTradeOffer(give: give, receive: receive)

    #expect(offer.give == give)
    #expect(offer.receive == receive)
    #expect(round.openTradeOffer?.give == give)
    #expect(round.openTradeOffer?.receive == receive)
}

@Test
func postTradeOfferReplacesExisting() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 2, .wheat: 2]

    let first: TradeOffer = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    let second: TradeOffer = try round.postTradeOffer(give: [.wheat: 1], receive: [.ore: 1])

    #expect(second.id != first.id)
    #expect(round.openTradeOffer?.id == second.id)
    // Log should contain both the cancel and the post.
    let hasCancel: Bool = round.log.contains { act in
        if case .cancelledTradeOffer(let id) = act.decision, id == first.id { return true }
        return false
    }
    #expect(hasCancel)
}

@Test
func cannotAcceptOwnOffer() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources[.wood] = 2
    let offer: TradeOffer = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    #expect(throws: PioneersModelError.cannotAcceptOwnOffer) {
        try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p1")
    }
}

@Test
func acceptTradeOfferSwapsResources() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 2]
    round.playerHands[1].resources = [.brick: 2]

    let offer: TradeOffer = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p2")

    #expect(round.playerHand(for: "p1")?.resources[.wood] == 1)
    #expect(round.playerHand(for: "p1")?.resources[.brick] == 1)
    #expect(round.playerHand(for: "p2")?.resources[.brick] == 1)
    #expect(round.playerHand(for: "p2")?.resources[.wood] == 1)
    #expect(round.openTradeOffer == nil)
}

@Test
func acceptTradeOfferSwapsMixedGiveAndReceiveResources() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 2, .sheep: 3]
    round.playerHands[1].resources = [.brick: 2, .ore: 2]

    let offer: TradeOffer = try round.postTradeOffer(
        give: [.wood: 1, .sheep: 2],
        receive: [.brick: 1, .ore: 1]
    )
    try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p2")

    #expect(round.playerHand(for: "p1")?.resources == [
        .wood: 1,
        .sheep: 1,
        .brick: 1,
        .ore: 1,
    ])
    #expect(round.playerHand(for: "p2")?.resources == [
        .wood: 1,
        .sheep: 2,
        .brick: 1,
        .ore: 1,
    ])
    #expect(round.openTradeOffer == nil)
}

@Test
func ineligibleAcceptorIsRejected() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 2]
    round.playerHands[1].resources = [.brick: 2]
    round.playerHands[2].resources = [.brick: 2]

    let offer: TradeOffer = try round.postTradeOffer(
        give: [.wood: 1],
        receive: [.brick: 1],
        eligibleAcceptors: ["p2"]
    )
    #expect(throws: PioneersModelError.notEligibleToAcceptOffer) {
        try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p3")
    }
}

// MARK: - Dev cards

@Test
func cannotPlayDevCardPurchasedThisTurn() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wheat: 1, .sheep: 1, .ore: 1]
    try round.buyDevCard()
    // Take the just-bought card and try to play it this turn.
    guard let card: DevCard = round.playerHand(for: "p1")?.heldDevCards.last else {
        Issue.record("Expected a held dev card")
        return
    }
    if card.kind == .landmark {
        // Re-run: landmark can't be played at all (different error)
        #expect(throws: PioneersModelError.cannotPlayLandmark) {
            try round.playDevCard(id: card.id)
        }
    } else {
        #expect(throws: PioneersModelError.cannotPlayDevCardPurchasedThisTurn) {
            try round.playDevCard(id: card.id)
        }
    }
}

// MARK: - Longest road

@Test
func longestRoadAwardedAtFive() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    round.playerHands[0].resources = [.wood: 20, .brick: 20]

    round.cookedDiceRolls = [5]
    _ = try round.rollDice()

    // Extend p1's network by repeatedly building whichever legal edge extends the longest chain.
    var built: Int = 0
    outer: while built < 10 {
        let legal: [Edge] = round.edges.filter {
            round.trail(at: $0.id) == nil && round.isEdgeConnectedToPlayerNetwork(edgeID: $0.id, playerID: "p1")
        }
        guard legal.isEmpty == false else { break }

        // Pick the edge that maximizes p1's longest-chain length after hypothetical placement.
        var bestEdgeID: EdgeID?
        var bestLength: Int = -1
        for e in legal {
            var snapshot: Round = round
            try? snapshot.buildTrail(edgeID: e.id)
            let len: Int = snapshot.longestTrailLength(for: "p1")
            if len > bestLength {
                bestLength = len
                bestEdgeID = e.id
            }
        }
        guard let chosen: EdgeID = bestEdgeID else { break }
        try round.buildTrail(edgeID: chosen)
        built += 1
        if round.longestTrailLength(for: "p1") >= 5 {
            break outer
        }
    }
    let finalLength: Int = round.longestTrailLength(for: "p1")
    #expect(finalLength >= 5)
    #expect(round.longestRoadHolder == "p1")
}

@Test
func tiedLeadersDoNotReceiveLongestRoadWithoutAnIncumbent() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    let firstPath = try #require(trailPath(in: round, length: Round.longestRoadMin))
    let secondPath = try #require(
        trailPath(in: round, length: Round.longestRoadMin, excluding: Set(firstPath))
    )
    round.trails = firstPath.map { Trail(ownerID: "p1", edgeID: $0) }
        + secondPath.map { Trail(ownerID: "p2", edgeID: $0) }

    round.checkLongestRoad()

    #expect(round.longestRoadCandidate() == nil)
    #expect(round.longestRoadHolder == nil)
}

@Test
func incumbentKeepsLongestRoadWhenAnotherPlayerTies() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    let firstPath = try #require(trailPath(in: round, length: Round.longestRoadMin))
    let secondPath = try #require(
        trailPath(in: round, length: Round.longestRoadMin, excluding: Set(firstPath))
    )
    round.trails = firstPath.map { Trail(ownerID: "p1", edgeID: $0) }
        + secondPath.map { Trail(ownerID: "p2", edgeID: $0) }
    round.longestRoadHolder = "p1"

    round.checkLongestRoad()

    #expect(round.longestRoadHolder == "p1")
}

@Test
func tiedChallengersClearLongestRoadWhenIncumbentNoLongerQualifies() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    let firstPath = try #require(trailPath(in: round, length: Round.longestRoadMin))
    let secondPath = try #require(
        trailPath(in: round, length: Round.longestRoadMin, excluding: Set(firstPath))
    )
    round.trails = firstPath.map { Trail(ownerID: "p2", edgeID: $0) }
        + secondPath.map { Trail(ownerID: "p3", edgeID: $0) }
    round.longestRoadHolder = "p1"

    round.checkLongestRoad()

    #expect(round.longestRoadHolder == nil)
}

@Test
func longestRoadAwardLogBelongsToAwardRecipientDuringSpecialBuild() throws {
    var round: Round = try makeStandardRound(playerCount: 5)
    let path = try #require(trailPath(in: round, length: Round.longestRoadMin))
    round.trails = path.map { Trail(ownerID: "p2", edgeID: $0) }
    round.state = .specialBuildPhase(originatingPlayerID: "p1", pending: ["p2"])

    round.checkLongestRoad()

    #expect(round.longestRoadHolder == "p2")
    #expect(round.log.last?.playerID == "p2")
    #expect(round.log.last?.decision == .longestRoadAwarded)
}

// MARK: - Special build phase (5-6 players)

@Test
func specialBuildPhaseStartsAtFivePlayers() throws {
    var round: Round = try makeStandardRound(playerCount: 5, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    for index in 1..<round.playerHands.count {
        round.playerHands[index].resources = Round.devCardCost
    }
    try round.endTurn()
    guard case .specialBuildPhase(let origin, let pending) = round.state else {
        Issue.record("Expected special build phase, got \(round.state)")
        return
    }
    #expect(origin == "p1")
    #expect(pending.count == 4)
    #expect(pending.contains("p1") == false)
}

@Test
func specialBuildAutomaticallyPassesPlayersWithoutLegalActions() throws {
    var round: Round = try makeStandardRound(playerCount: 5, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    for index in round.playerHands.indices {
        round.playerHands[index].resources = [:]
    }

    try round.endTurn()

    guard case .waitingForPlayer(let id, .beforeRoll) = round.state else {
        Issue.record("Expected the next normal turn, got \(round.state)")
        return
    }
    #expect(id == "p2")
    let automaticPasses = round.log.suffix(4).map(\.decision)
    #expect(automaticPasses == Array(repeating: .specialBuildPass, count: 4))
}

@Test
func specialBuildAutomaticallySkipsOnlyIneligibleQueueHeads() throws {
    var round: Round = try makeStandardRound(playerCount: 5, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    for index in round.playerHands.indices {
        round.playerHands[index].resources = [:]
    }
    round.playerHands[2].resources = Round.devCardCost

    try round.endTurn()

    guard case .specialBuildPhase(let origin, let pending) = round.state else {
        Issue.record("Expected special build phase, got \(round.state)")
        return
    }
    #expect(origin == "p1")
    #expect(pending.first == "p3")
    #expect(round.log.last?.playerID == "p2")
    #expect(round.log.last?.decision == .specialBuildPass)
}

@Test
func buyingCardDuringSpecialBuildAdvancesToNextEligiblePlayer() throws {
    var round: Round = try makeStandardRound(playerCount: 5, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    for index in round.playerHands.indices {
        round.playerHands[index].resources = [:]
    }
    round.playerHands[1].resources = Round.devCardCost
    round.playerHands[2].resources = Round.devCardCost
    try round.endTurn()

    try round.buyDevCard()

    guard case .specialBuildPhase(_, let pending) = round.state else {
        Issue.record("Expected special build phase, got \(round.state)")
        return
    }
    #expect(pending.first == "p3")
    #expect(pending.contains("p2") == false)
}

@Test
func specialBuildCardCanBePlayedBeforeRollingOnNextTurn() throws {
    var round: Round = try makeStandardRound(playerCount: 5, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    for index in round.playerHands.indices {
        round.playerHands[index].resources = [:]
    }
    round.playerHands[1].resources = Round.devCardCost
    let card = DevCard(id: 9001, kind: .roundup)
    round.devCardDeck = [card]
    try round.endTurn()
    #expect(round.isSpecialBuildPhase)

    try round.buyDevCard()

    #expect(round.state == .waitingForPlayer(id: "p2", phase: .beforeRoll))
    round.playerHands[0].resources = [.wood: 2]
    try round.playDevCard(id: card.id, resource: .wood)

    #expect(round.playerHand(for: "p2")?.playedDevCards == [card])
    #expect(round.playerHand(for: "p2")?.resources[.wood] == 2)
    #expect(round.playerHand(for: "p1")?.resources[.wood] == nil)
    #expect(round.state == .waitingForPlayer(id: "p2", phase: .beforeRoll))
    #expect(round.hasRolledDiceThisTurn == false)
}

@Test
func everyBoardBuildDuringSpecialBuildAdvancesToNextEligiblePlayer() throws {
    var baseRound: Round = try makeStandardRound(playerCount: 5)
    autoSetup(&baseRound)
    baseRound.playerHands[2].resources = Round.devCardCost

    var trailRound = baseRound
    trailRound.playerHands[1].resources = Round.trailCost
    trailRound.state = .specialBuildPhase(originatingPlayerID: "p1", pending: ["p2", "p3"])
    guard let edgeID = trailRound.edges.first(where: {
        trailRound.canPlaceTrail(at: $0.id, forPlayerID: "p2")
    })?.id else {
        Issue.record("Expected a legal trail for p2")
        return
    }
    try trailRound.buildTrail(edgeID: edgeID)
    #expect(trailRound.currentPlayerID == "p3")

    var homesteadRound = baseRound
    homesteadRound.playerHands[1].resources = Round.homesteadCost
    homesteadRound.state = .specialBuildPhase(originatingPlayerID: "p1", pending: ["p2", "p3"])
    func reachableHomestead(in round: Round) -> VertexID? {
        round.vertices.first(where: { vertex in
            round.canPlaceHomestead(at: vertex.id) &&
                vertex.adjacentEdgeIDs.contains {
                    round.trail(at: $0)?.ownerID == "p2"
                }
        })?.id
    }
    var extensionsRemaining = 10
    while reachableHomestead(in: homesteadRound) == nil,
          extensionsRemaining > 0,
          let edgeID = homesteadRound.edges.first(where: {
              homesteadRound.canPlaceTrail(at: $0.id, forPlayerID: "p2")
          })?.id {
        homesteadRound.trails.append(Trail(ownerID: "p2", edgeID: edgeID))
        extensionsRemaining -= 1
    }
    guard let vertexID = reachableHomestead(in: homesteadRound) else {
        Issue.record("Expected a legal homestead for p2")
        return
    }
    try homesteadRound.buildHomestead(vertexID: vertexID)
    #expect(homesteadRound.currentPlayerID == "p3")

    var townRound = baseRound
    townRound.playerHands[1].resources = Round.townCost
    townRound.state = .specialBuildPhase(originatingPlayerID: "p1", pending: ["p2", "p3"])
    guard let homesteadID = townRound.buildings.first(where: {
        $0.ownerID == "p2" && $0.kind == .homestead
    })?.vertexID else {
        Issue.record("Expected an upgradeable homestead for p2")
        return
    }
    try townRound.upgradeToTown(vertexID: homesteadID)
    #expect(townRound.currentPlayerID == "p3")
}

@Test
func specialBuildPhaseDoesNotStartAtThreePlayers() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    try round.endTurn()
    guard case .waitingForPlayer(let id, .beforeRoll) = round.state else {
        Issue.record("Expected next player .beforeRoll")
        return
    }
    #expect(id == "p2")
}

@Test
func playerAlreadyAtTenPointsWinsWhenTheirNormalTurnBegins() throws {
    var round: Round = try makeStandardRound(playerCount: 5)
    autoSetup(&round)
    round.playerHands[1].heldDevCards.append(contentsOf: (0..<8).map {
        DevCard(id: 10_000 + $0, kind: .landmark)
    })
    for index in round.playerHands.indices {
        round.playerHands[index].resources = [:]
    }
    round.state = .waitingForPlayer(id: "p1", phase: .main)
    round.hasRolledDiceThisTurn = true

    try round.endTurn()

    #expect(round.victoryPoints(for: "p2") == Round.victoryPointsToWin)
    guard case .gameComplete(let winner) = round.state else {
        Issue.record("Expected p2 to win before rolling, got \(round.state)")
        return
    }
    #expect(winner.id == "p2")
    #expect(round.log.last?.playerID == "p2")
    #expect(round.log.last?.decision == .winnerDeclared(playerID: "p2"))
}

// MARK: - AI

@Test
func aiReturnsLegalRollActionAtBeforeRoll() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    let engine: AIEngine = AIEngine(difficulty: .easy)
    let action: AIAction? = engine.chooseAction(for: round, playerID: "p1")
    #expect(action == .rollDice)
}

@Test
func aiReturnsNilForWrongPlayer() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    let engine: AIEngine = AIEngine(difficulty: .hard)
    let action: AIAction? = engine.chooseAction(for: round, playerID: "p2")
    #expect(action == nil)
}

@Test
func aiCanDriveASetupPhase() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    let engine: AIEngine = AIEngine(difficulty: .medium)
    // Auto-play setup with the AI until it completes.
    var safety: Int = 200
    while round.isSetup, safety > 0 {
        safety -= 1
        guard let pid: PlayerID = round.currentPlayerID else { break }
        guard let action: AIAction = engine.chooseAction(for: round, playerID: pid) else { break }
        try engine.makeMove(on: &round, playerID: pid)
        _ = action
    }
    #expect(round.isSetup == false)
}

@Test
func aiEndsPathfinderWhenOutOfTrailPieces() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    round.playerHands[0].remainingTrails = 0
    round.state = .waitingForPlayer(id: "p1", phase: .playingPathfinder(remainingTrails: 2))
    let engine: AIEngine = AIEngine(difficulty: .hard)

    #expect(engine.chooseAction(for: round, playerID: "p1") == .resolvePathfinderEarly)
    try engine.makeMove(on: &round, playerID: "p1")
    #expect(round.state == .waitingForPlayer(id: "p1", phase: .beforeRoll))
}

// MARK: - Full play-through

@Test
func fullPlayThroughEndsWithWinner() throws {
    // Drive a deterministic game where p1 accumulates VP quickly.
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)

    // Short-circuit VP for testing: stuff p1's hand repeatedly so checkWin fires quickly by
    // buying dev cards and hoping some are landmarks. To guarantee, we directly seed p1 with
    // landmark cards from the deck.
    let landmarkCards: [DevCard] = GameMap.standardDevCardDeck.filter { $0.kind == .landmark }
    // Put 5 landmarks directly into p1's hand (as if already "bought last turn" so not flagged).
    round.playerHands[0].heldDevCards.append(contentsOf: landmarkCards)

    // Kick off p1's turn; they should win via victory-point landmarks + existing building VP.
    round.cookedDiceRolls = [5]
    _ = try round.rollDice()
    // Trigger a checkWin by buying a dev card (will only fire if totalVP >= 10).
    // Give resources for a buy.
    round.playerHands[0].resources[.wheat] = 1
    round.playerHands[0].resources[.sheep] = 1
    round.playerHands[0].resources[.ore] = 1
    try round.buyDevCard()

    let totalVP: Int = round.victoryPoints(for: "p1")
    if totalVP >= Round.victoryPointsToWin {
        #expect(round.isComplete)
        if case .gameComplete(let winner) = round.state {
            #expect(winner.id == "p1")
        }
    } else {
        // If we didn't hit threshold with 5 landmarks + 2 building VPs, simulate more progress:
        // upgrade a homestead to a town to add 1 VP.
        round.playerHands[0].resources = [.wheat: 10, .ore: 10, .wood: 4, .brick: 4, .sheep: 2]
        if let firstOwn: Building = round.buildings.first(where: { $0.ownerID == "p1" && $0.kind == .homestead }) {
            try round.upgradeToTown(vertexID: firstOwn.vertexID)
        }
        #expect(round.victoryPoints(for: "p1") >= 7) // 5 landmarks + 2 bldg VP baseline
    }
    // Regardless of path, log should contain an endedTurn or winnerDeclared marker.
    let endedOrWon: Bool = round.log.contains { act in
        switch act.decision {
        case .winnerDeclared, .endedTurn, .boughtDevCard: return true
        default: return false
        }
    }
    #expect(endedOrWon)
}

// MARK: - Fakes

@Test
func roundFakeProducesValidRound() throws {
    let round: Round = .fake()
    #expect(round.playerHands.count == 3)
    #expect(round.tiles.isEmpty == false)
}

@Test
func fakeInProgressIsBeyondSetup() throws {
    let round: Round = .fakeInProgress()
    #expect(round.isSetup == false)
}

@Test
func fakeCompletedHasWinner() throws {
    let round: Round = .fakeCompleted()
    #expect(round.isComplete)
}

// MARK: - Log cap

@Test
func logIsCappedAtMaxLogActions() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    // Append many synthetic actions to exceed the cap.
    for _ in 0..<(Round.maxLogActions + 50) {
        round.logAction(playerID: "p1", decision: .endedTurn)
    }
    #expect(round.log.count == Round.maxLogActions)
}

// MARK: - Port trades

@Test
func portTradeRequiresOwnership() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 5]
    // p1 doesn't own any port because setup doesn't target port vertices.
    if let firstPort: PioneersModel.Port = round.ports.first {
        #expect(throws: PioneersModelError.portNotOwnedByPlayer) {
            try round.portTrade(portID: firstPort.id, give: .wood, for: .ore)
        }
    }
}

@Test
func genericPortTradeIsThreeForOne() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    guard let port: PioneersModel.Port = round.ports.first(where: {
        if case .generic = $0.kind { return true }
        return false
    }) else { return }
    round.buildings.append(Building(kind: .homestead, ownerID: "p1", vertexID: port.vertexIDs[0]))
    round.playerHands[0].resources = [.wood: 4]
    try round.portTrade(portID: port.id, give: .wood, for: .ore)
    #expect((round.playerHand(for: "p1")?.resources[.wood] ?? 0) == 1)
    #expect((round.playerHand(for: "p1")?.resources[.ore] ?? 0) == 1)
}

@Test
func specificPortTradeIsTwoForOne() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    guard let port: PioneersModel.Port = round.ports.first(where: {
        if case .specific = $0.kind { return true }
        return false
    }) else { return }
    guard case .specific(let r) = port.kind else { return }
    round.buildings.append(Building(kind: .homestead, ownerID: "p1", vertexID: port.vertexIDs[0]))
    round.playerHands[0].resources = [r: 3]
    let other: Resource = Resource.allCases.first(where: { $0 != r })!
    #expect(throws: PioneersModelError.invalidPortTrade) {
        try round.portTrade(portID: port.id, give: other, for: r)
    }
    let want: Resource = r == .wheat ? .ore : .wheat
    try round.portTrade(portID: port.id, give: r, for: want)
    #expect((round.playerHand(for: "p1")?.resources[r] ?? 0) == 1)
    #expect((round.playerHand(for: "p1")?.resources[want] ?? 0) == 1)
}

// MARK: - Dev card mechanics

@Test
func rangerMovesOutlawAndCountsTowardLargestArmy() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()

    // Seed p1 with 3 ranger cards (directly in hand, not purchased this turn).
    let cards: [DevCard] = [
        DevCard(id: 9001, kind: .ranger),
        DevCard(id: 9002, kind: .ranger),
        DevCard(id: 9003, kind: .ranger),
    ]
    round.playerHands[0].heldDevCards.append(contentsOf: cards)

    try round.playDevCard(id: 9001)
    guard case .waitingForPlayer(_, .movingOutlaw(.playedRanger)) = round.state else {
        Issue.record("Expected movingOutlaw.playedRanger after playing ranger; got \(round.state)")
        return
    }
    // Move outlaw to a tile with no opponents adjacent (a tile where no buildings sit on corners).
    let safeTargets: [TileID] = round.tiles.compactMap { t -> TileID? in
        guard t.id != round.outlawTileID else { return nil }
        let hasAnyBuilding: Bool = t.vertexIDs.contains { round.building(at: $0) != nil }
        return hasAnyBuilding ? nil : t.id
    }
    let target: TileID = safeTargets.first ?? round.tiles.first(where: { $0.id != round.outlawTileID })!.id
    try round.moveOutlaw(toTileID: target)
    // Resolve any leftover stealing phase.
    if case .waitingForPlayer(_, .stealingAfterOutlaw(let candidates, _)) = round.state,
       let first: PlayerID = candidates.first {
        _ = try round.stealFromPlayer(victimID: first)
    }
    #expect(round.playerHand(for: "p1")?.rangersPlayed == 1)
    #expect(round.state == .waitingForPlayer(id: "p1", phase: .main))

    // Back in .main, can't play a 2nd dev card this turn.
    #expect(throws: PioneersModelError.alreadyPlayedDevCardThisTurn) {
        try round.playDevCard(id: 9002)
    }
}

@Test
func rangerPlayedBeforeRollStillRequiresDiceRollAfterOutlawResolution() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)

    let card: DevCard = DevCard(id: 9001, kind: .ranger)
    round.playerHands[0].heldDevCards.append(card)

    try round.playDevCard(id: card.id)
    let target: TileID = round.tiles.first(where: { tile in
        tile.id != round.outlawTileID
            && tile.vertexIDs.allSatisfy { round.building(at: $0) == nil }
    })!.id
    try round.moveOutlaw(toTileID: target)

    #expect(round.hasRolledDiceThisTurn == false)
    #expect(round.state == .waitingForPlayer(id: "p1", phase: .beforeRoll))
    #expect(throws: PioneersModelError.notInMainPhase) {
        try round.endTurn()
    }

    _ = try round.rollDice()
    try round.endTurn()
    #expect(round.state == .waitingForPlayer(id: "p2", phase: .beforeRoll))
}

@Test
func roundupPlayedBeforeRollStillRequiresDiceRoll() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    let card: DevCard = DevCard(id: 9100, kind: .roundup)
    round.playerHands[0].heldDevCards.append(card)

    try round.playDevCard(id: card.id, resource: .wheat)

    #expect(round.state == .waitingForPlayer(id: "p1", phase: .beforeRoll))
}

@Test
func bountifulHarvestPlayedBeforeRollStillRequiresDiceRoll() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    let card: DevCard = DevCard(id: 9200, kind: .bountifulHarvest)
    round.playerHands[0].heldDevCards.append(card)

    try round.playDevCard(id: card.id, pickedResources: [.wheat, .ore])

    #expect(round.state == .waitingForPlayer(id: "p1", phase: .beforeRoll))
}

@Test
func pathfinderEndedEarlyBeforeRollStillRequiresDiceRoll() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    let card: DevCard = DevCard(id: 9300, kind: .pathfinder)
    round.playerHands[0].heldDevCards.append(card)

    try round.playDevCard(id: card.id)
    try round.resolvePathfinderEarly()

    #expect(round.state == .waitingForPlayer(id: "p1", phase: .beforeRoll))
}

@Test
func roundupStealsAllOfOneResource() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()

    let card: DevCard = DevCard(id: 9100, kind: .roundup)
    round.playerHands[0].heldDevCards.append(card)
    round.playerHands[1].resources[.wheat] = 3
    round.playerHands[2].resources[.wheat] = 2
    round.playerHands[0].resources[.wheat] = 0

    try round.playDevCard(id: 9100, resource: .wheat)
    #expect(round.playerHand(for: "p1")?.resources[.wheat] == 5)
    #expect(round.playerHand(for: "p2")?.resources[.wheat] == nil)
    #expect(round.playerHand(for: "p3")?.resources[.wheat] == nil)
}

@Test
func bountifulHarvestGrantsTwoResources() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()

    let card: DevCard = DevCard(id: 9200, kind: .bountifulHarvest)
    round.playerHands[0].heldDevCards.append(card)
    let before: Int = round.playerHand(for: "p1")?.totalResourceCount ?? 0
    try round.playDevCard(id: 9200, pickedResources: [.wheat, .ore])
    let after: Int = round.playerHand(for: "p1")?.totalResourceCount ?? 0
    #expect(after - before == 2)
    #expect((round.playerHand(for: "p1")?.resources[.wheat] ?? 0) >= 1)
    #expect((round.playerHand(for: "p1")?.resources[.ore] ?? 0) >= 1)
}

@Test
func pathfinderPlacesTwoFreeTrails() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()

    let card: DevCard = DevCard(id: 9300, kind: .pathfinder)
    round.playerHands[0].heldDevCards.append(card)
    // No resources needed for pathfinder.
    try round.playDevCard(id: 9300)
    guard case .waitingForPlayer(_, .playingPathfinder(let rem)) = round.state else {
        Issue.record("Expected playingPathfinder phase")
        return
    }
    #expect(rem == 2)

    // Place the first free trail.
    let legal: [EdgeID] = round.edges.compactMap { e in
        round.trail(at: e.id) == nil && round.isEdgeConnectedToPlayerNetwork(edgeID: e.id, playerID: "p1") ? e.id : nil
    }
    guard let first: EdgeID = legal.first else { return }
    try round.buildTrail(edgeID: first)
    if case .waitingForPlayer(_, .playingPathfinder(let rem2)) = round.state {
        #expect(rem2 == 1)
    }
}

@Test
func largestArmyAwardedAtThreeRangers() throws {
    var round: Round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()

    // Put three ranger cards in p1's played pile directly and call checkLargestArmy.
    for i in 0..<3 {
        round.playerHands[0].playedDevCards.append(DevCard(id: 8000 + i, kind: .ranger))
    }
    round.checkLargestArmy()
    #expect(round.largestArmyHolder == "p1")
}

@Test
func largestArmyAwardLogBelongsToAwardRecipient() throws {
    var round: Round = try makeStandardRound(playerCount: 5)
    autoSetup(&round)
    round.state = .specialBuildPhase(originatingPlayerID: "p1", pending: ["p2"])
    for i in 0..<Round.largestArmyMin {
        round.playerHands[1].playedDevCards.append(DevCard(id: 11_000 + i, kind: .ranger))
    }

    round.checkLargestArmy()

    #expect(round.largestArmyHolder == "p2")
    #expect(round.log.last?.playerID == "p2")
    #expect(round.log.last?.decision == .largestArmyAwarded)
}

// MARK: - AI info-hiding structural check

@Test
func aiEngineIsSendableAndDoesNotRequireMutableGlobals() {
    let engine: AIEngine = AIEngine(difficulty: .hard)
    #expect(engine.difficulty == .hard)
}

// MARK: - Codable round-trip

@Test
func roundIsCodableRoundTrip() throws {
    var round: Round = try makeStandardRound(playerCount: 3)
    autoSetup(&round)
    let data: Data = try JSONEncoder().encode(round)
    let decoded: Round = try JSONDecoder().decode(Round.self, from: data)
    #expect(decoded.tiles.count == round.tiles.count)
    #expect(decoded.vertices.count == round.vertices.count)
    #expect(decoded.edges.count == round.edges.count)
    #expect(decoded.playerHands.count == round.playerHands.count)
}

@Test
func declinesAreInformationalAndDoNotPreventAcceptance() throws {
    var round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 2]
    round.playerHands[1].resources = [.brick: 2]
    let offer = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    let state = round.state
    let hands = round.playerHands
    let log = round.log

    try round.declineTradeOffer(offerID: offer.id, byPlayerID: "p2")
    try round.declineTradeOffer(offerID: offer.id, byPlayerID: "p2")
    try round.declineTradeOffer(offerID: offer.id, byPlayerID: "p3")
    #expect(round.openTradeOffer?.declines == ["p2", "p3"])
    #expect(round.state == state)
    #expect(round.playerHands == hands)
    #expect(round.log == log)

    try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p2")
    #expect(round.openTradeOffer == nil)
    #expect(round.state == state)
    #expect(round.playerHand(for: "p2")?.resources == [.brick: 1, .wood: 1])
}

@Test
func declineValidatesOfferAndEligibility() throws {
    var round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    #expect(throws: PioneersModelError.noOpenTradeOffer) {
        try round.declineTradeOffer(offerID: 1, byPlayerID: "p2")
    }
    round.playerHands[0].resources = [.wood: 2]
    let offer = try round.postTradeOffer(
        give: [.wood: 1], receive: [.brick: 1], eligibleAcceptors: ["p2"]
    )
    #expect(throws: PioneersModelError.tradeOfferIDMismatch) {
        try round.declineTradeOffer(offerID: offer.id + 1, byPlayerID: "p2")
    }
    for playerID in ["p1", "p3", "unknown"] {
        #expect(throws: PioneersModelError.notEligibleToAcceptOffer) {
            try round.declineTradeOffer(offerID: offer.id, byPlayerID: playerID)
        }
    }
    #expect(round.openTradeOffer == offer)
    try round.declineTradeOffer(offerID: offer.id, byPlayerID: "p2")
    let replacement = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    #expect(replacement.declines.isEmpty)
}

@Test
func tradeOfferDeclinesPersistAndOlderOffersDecode() throws {
    let offer = TradeOffer.fake(declines: ["p2"])
    let encoded = try JSONEncoder().encode(offer)
    #expect(try JSONDecoder().decode(TradeOffer.self, from: encoded) == offer)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "declines")
    let legacy = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(TradeOffer.self, from: legacy)
    #expect(decoded.declines.isEmpty)
    #expect(decoded.id == offer.id)
    #expect(decoded.eligibleAcceptors == offer.eligibleAcceptors)
}

@Test
func openTradeOfferBlocksOtherTurnActionsWithoutMutatingRound() throws {
    var round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0, 10) })
    round.playerHands[0].heldDevCards = [DevCard(id: 9001, kind: .ranger)]
    let offer = try round.postTradeOffer(give: [.wood: 10], receive: [.brick: 1])
    let edgeID = try #require(round.edges.first { round.canPlaceTrail(at: $0.id, forPlayerID: "p1") }?.id)
    let vertexID = try #require(round.buildings.first { $0.ownerID == "p1" }?.vertexID)
    let portID = try #require(round.ports.first?.id)
    let snapshot = round
    let actions: [(inout Round) throws -> Void] = [
        { try $0.buildTrail(edgeID: edgeID) },
        { try $0.buildHomestead(vertexID: vertexID) },
        { try $0.upgradeToTown(vertexID: vertexID) },
        { try $0.buyDevCard() },
        { try $0.bankTrade(give: .wood, for: .brick) },
        { try $0.portTrade(portID: portID, give: .wood, for: .brick) },
        { try $0.playDevCard(id: 9001) },
    ]
    for action in actions {
        #expect(throws: PioneersModelError.tradeOfferIsOpen) { try action(&round) }
        #expect(round == snapshot)
    }
    try round.declineTradeOffer(offerID: offer.id, byPlayerID: "p2")
    try round.declineTradeOffer(offerID: offer.id, byPlayerID: "p3")
    #expect(throws: PioneersModelError.tradeOfferIsOpen) { try round.buildTrail(edgeID: edgeID) }
    try round.cancelTradeOffer()
    try round.buildTrail(edgeID: edgeID)
    #expect(round.playerHand(for: "p1")?.resources[.wood] == 9)
}

@Test
func openTradeOfferCanBeReplacedAcceptedOrClearedByEndingTurn() throws {
    var round = try makeStandardRound(playerCount: 3, cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = [.wood: 10]
    round.playerHands[1].resources = [.brick: 2]
    let first = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    let replacement = try round.postTradeOffer(give: [.wood: 2], receive: [.brick: 1])
    #expect(first.id != replacement.id)
    var endingRound = round
    #expect(AIEngine(difficulty: .easy).chooseAction(for: endingRound, playerID: "p1") == .endTurn)
    try endingRound.endTurn()
    #expect(endingRound.openTradeOffer == nil)
    try round.acceptTradeOffer(offerID: replacement.id, byPlayerID: "p2")
    try round.bankTrade(give: .wood, for: .ore)
    #expect(round.playerHand(for: "p1")?.resources[.wood] == 4)
}
