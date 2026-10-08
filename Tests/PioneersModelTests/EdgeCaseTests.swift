import Foundation
import Testing
@testable import PioneersModel

private func makePlayers(_ count: Int) -> [Player] {
    let colors: [PlayerColor] = PlayerColor.allCases
    return (0..<count).map { index in
        Player(id: "p\(index + 1)", name: "Player \(index + 1)", color: colors[index % colors.count])
    }
}

private func makeStandardRound(
    playerCount: Int = 3,
    cookedDiceRolls: [Int] = [],
    cookedStealChoices: [Resource] = []
) throws -> Round {
    let players: [Player] = makePlayers(playerCount)
    let map: GameMap = playerCount >= Round.expansionThreshold ? .expansion() : .standard()
    return try Round(
        players: players,
        cookedMap: map,
        cookedNumberTokenOrder: map.numberTokenBag,
        cookedDevCardDeck: map.devCardDeck,
        cookedDiceRolls: cookedDiceRolls,
        cookedStealChoices: cookedStealChoices
    )
}

private func autoSetup(_ round: inout Round) {
    _ = Round.autoCompleteSetup(&round)
}

private struct IsolatedSite {
    let vertexID: VertexID
    let tileID: TileID
    let resource: Resource
    let token: Int
}

private func isolatedProductionSite(in round: Round) -> IsolatedSite? {
    for vertex in round.vertices {
        let producing: [Tile] = vertex.adjacentTileIDs.compactMap { tileID in
            guard let tile: Tile = round.tile(id: tileID),
                  let token: Int = tile.numberToken,
                  token != 7,
                  tile.type.resource != nil
            else { return nil }
            return tile
        }
        guard producing.count == 1,
              let tile: Tile = producing.first,
              let resource: Resource = tile.type.resource,
              let token: Int = tile.numberToken
        else { continue }
        return IsolatedSite(vertexID: vertex.id, tileID: tile.id, resource: resource, token: token)
    }
    return nil
}

private func clearResources(_ round: inout Round) {
    for index in round.playerHands.indices {
        round.playerHands[index].resources = [:]
    }
}

private func connectedEdgePair(in round: Round) -> (EdgeID, EdgeID, VertexID)? {
    for edge in round.edges {
        for vertexID in edge.endpointVertexIDs {
            guard let vertex: Vertex = round.vertex(id: vertexID) else { continue }
            if let other: EdgeID = vertex.adjacentEdgeIDs.first(where: { $0 != edge.id }) {
                return (edge.id, other, vertexID)
            }
        }
    }
    return nil
}

struct EdgeCaseTests {
@Test
func firstLapHomesteadGrantsNoResources() throws {
    var round: Round = try makeStandardRound()
    let vertexID: VertexID = try #require(round.vertices.first { round.canPlaceHomestead(at: $0.id) }?.id)
    try round.placeInitialHomestead(playerID: "p1", vertexID: vertexID)
    #expect(round.playerHand(for: "p1")?.resources.isEmpty == true)
    #expect(round.buildings.count == 1)
}

@Test
func secondLapHomesteadGrantsOneResourcePerAdjacentTile() throws {
    var round: Round = try makeStandardRound()
    let firstVertexID: VertexID = try #require(round.vertices.first { round.canPlaceHomestead(at: $0.id) }?.id)
    try round.placeInitialHomestead(playerID: "p1", vertexID: firstVertexID)
    let trailID: EdgeID = try #require(round.vertex(id: firstVertexID)?.adjacentEdgeIDs.first)
    try round.placeInitialTrail(playerID: "p1", edgeID: trailID)

    round.state = .setup(pendingPlacements: [
        .init(playerID: "p1", lap: 2, step: .homestead),
        .init(playerID: "p1", lap: 2, step: .trail),
    ])
    let secondVertex: Vertex = try #require(round.vertices.first { vertex in
        vertex.id != firstVertexID
            && round.canPlaceHomestead(at: vertex.id)
            && vertex.adjacentTileIDs.contains { round.tile(id: $0)?.type.resource != nil }
    })
    try round.placeInitialHomestead(playerID: "p1", vertexID: secondVertex.id)

    var expected: [Resource: Int] = [:]
    for tileID in secondVertex.adjacentTileIDs {
        guard let resource: Resource = round.tile(id: tileID)?.type.resource else { continue }
        expected[resource, default: 0] += 1
    }
    #expect(expected.isEmpty == false)
    #expect(round.playerHand(for: "p1")?.resources == expected)
}

@Test
func placingATrailDuringTheHomesteadStepIsRejected() throws {
    var round: Round = try makeStandardRound()
    let edgeID: EdgeID = try #require(round.edges.first?.id)
    let before: Round = round
    #expect(throws: PioneersModelError.notActivePlayer) {
        try round.placeInitialTrail(playerID: "p1", edgeID: edgeID)
    }
    #expect(round == before)
    #expect(round.trails.isEmpty)
}

@Test
func invalidVertexLeavesTheBoardEmpty() throws {
    var round: Round = try makeStandardRound()
    let before: Round = round
    #expect(throws: PioneersModelError.invalidVertexID) {
        try round.placeInitialHomestead(playerID: "p1", vertexID: -1)
    }
    #expect(round == before)
}

@Test
func homesteadTooCloseToAnotherIsRejected() throws {
    var round: Round = try makeStandardRound()
    let vertexID: VertexID = try #require(round.vertices.first { round.canPlaceHomestead(at: $0.id) }?.id)
    try round.placeInitialHomestead(playerID: "p1", vertexID: vertexID)
    let trailID: EdgeID = try #require(round.vertex(id: vertexID)?.adjacentEdgeIDs.first)
    try round.placeInitialTrail(playerID: "p1", edgeID: trailID)
    let neighborID: VertexID = try #require(round.vertex(id: vertexID)?.adjacentVertexIDs.first)
    let before: Round = round
    #expect(throws: PioneersModelError.vertexTooCloseToBuilding) {
        try round.placeInitialHomestead(playerID: "p2", vertexID: neighborID)
    }
    #expect(round == before)
    #expect(round.buildings.count == 1)
}

@Test
func exactlySevenCardsSkipsDiscard() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [7])
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 7]
    _ = try round.rollDice()
    guard case .waitingForPlayer(_, .movingOutlaw) = round.state else {
        Issue.record("Expected moving the outlaw when every hand has at most 7 cards, got \(round.state)")
        return
    }
    #expect(round.playerHand(for: "p1")?.resources[.wood] == 7)
}

@Test
func nineCardsDiscardHalfRoundedDown() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [7])
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 9]
    _ = try round.rollDice()
    let before: Round = round
    #expect(throws: PioneersModelError.wrongDiscardAmount) {
        try round.discardResources(playerID: "p1", resources: [.wood: 5])
    }
    #expect(round == before)
    try round.discardResources(playerID: "p1", resources: [.wood: 4])
    #expect(round.playerHand(for: "p1")?.resources[.wood] == 5)
}

@Test
func negativeDiscardCountsAreRejected() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [7])
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 8]
    _ = try round.rollDice()
    let before: Round = round
    #expect(throws: PioneersModelError.wrongDiscardAmount) {
        try round.discardResources(playerID: "p1", resources: [.wood: 6, .brick: -2])
    }
    #expect(round == before)
}

@Test
func discardOfAnUnheldResourceLeavesTheHandUnchanged() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [7])
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 8]
    _ = try round.rollDice()
    let before: Round = round
    #expect(throws: PioneersModelError.insufficientResources) {
        try round.discardResources(playerID: "p1", resources: [.wood: 2, .brick: 2])
    }
    #expect(round == before)
}

@Test
func discardOutsideSevenResolutionLeavesTheHandUnchanged() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 4]
    let before: Round = round
    #expect(throws: PioneersModelError.cannotDiscardNow) {
        try round.discardResources(playerID: "p1", resources: [.wood: 2])
    }
    #expect(round == before)
}

@Test
func buildingBeforeTheRollIsRejected() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    round.playerHands[0].resources = Round.trailCost
    let edgeID: EdgeID = try #require(round.edges.first { round.canPlaceTrail(at: $0.id, forPlayerID: "p1") }?.id)
    let before: Round = round
    #expect(throws: PioneersModelError.notInMainPhase) {
        try round.buildTrail(edgeID: edgeID)
    }
    #expect(round == before)
}

@Test
func buildingWithNoResourcesLeavesTheBoardUnchanged() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    clearResources(&round)
    let edgeID: EdgeID = try #require(round.edges.first { round.canPlaceTrail(at: $0.id, forPlayerID: "p1") }?.id)
    let before: Round = round
    #expect(throws: PioneersModelError.insufficientResources) {
        try round.buildTrail(edgeID: edgeID)
    }
    #expect(round == before)
    #expect(round.trail(at: edgeID) == nil)
}

@Test
func disconnectedTrailIsRejected() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[0].resources = Round.trailCost
    let edgeID: EdgeID = try #require(
        round.edges.first { round.canPlaceTrail(at: $0.id, forPlayerID: "p1") == false && round.trail(at: $0.id) == nil }?.id
    )
    let before: Round = round
    #expect(throws: PioneersModelError.trailMustConnectToOwnNetwork) {
        try round.buildTrail(edgeID: edgeID)
    }
    #expect(round == before)
}

@Test
func townCollectsTwoResources() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    let site: IsolatedSite = try #require(isolatedProductionSite(in: round))
    round.buildings = [Building(kind: .town, ownerID: "p1", vertexID: site.vertexID)]
    clearResources(&round)
    round.cookedDiceRolls = [site.token]
    _ = try round.rollDice()
    #expect(round.playerHand(for: "p1")?.resources[site.resource] == BuildingKind.town.resourceYield)
    #expect(round.playerHand(for: "p1")?.totalResourceCount == 2)
}

@Test
func outlawBlocksTheTileItOccupies() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    let site: IsolatedSite = try #require(isolatedProductionSite(in: round))
    round.buildings = [Building(kind: .homestead, ownerID: "p1", vertexID: site.vertexID)]
    clearResources(&round)
    round.cookedDiceRolls = [site.token, site.token]
    _ = try round.rollDice()
    #expect(round.playerHand(for: "p1")?.resources[site.resource] == 1)

    clearResources(&round)
    round.outlawTileID = site.tileID
    round.hasRolledDiceThisTurn = false
    round.state = .waitingForPlayer(id: "p1", phase: .beforeRoll)
    _ = try round.rollDice()
    #expect(round.playerHand(for: "p1")?.totalResourceCount == 0)
}

@Test
func twoRangersDoNotAwardLargestArmy() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    round.playerHands[0].playedDevCards = [
        DevCard(id: 1, kind: .ranger),
        DevCard(id: 2, kind: .ranger),
    ]
    round.checkLargestArmy()
    #expect(round.largestArmyHolder == nil)
    #expect(round.publicVictoryPoints(for: "p1") == 2)
}

@Test
func publicVictoryPointsOmitHiddenLandmarks() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    round.longestRoadHolder = "p1"
    round.largestArmyHolder = "p1"
    round.playerHands[0].heldDevCards = [DevCard(id: 1, kind: .landmark)]
    #expect(round.buildings(for: "p1").count == 2)
    #expect(round.publicVictoryPoints(for: "p1") == 6)
    #expect(round.victoryPoints(for: "p1") == 7)
}

@Test
func nineVictoryPointsDoesNotWinAtTurnStart() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    round.playerHands[1].heldDevCards = (0..<7).map { DevCard(id: 200 + $0, kind: .landmark) }
    #expect(round.victoryPoints(for: "p2") == 9)
    round.state = .waitingForPlayer(id: "p1", phase: .main)
    round.hasRolledDiceThisTurn = true
    try round.endTurn()
    #expect(round.isComplete == false)
    #expect(round.state == .waitingForPlayer(id: "p2", phase: .beforeRoll))
}

@Test
func tenVictoryPointsWinsWhenTheTurnBegins() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    round.playerHands[1].heldDevCards = (0..<8).map { DevCard(id: 300 + $0, kind: .landmark) }
    #expect(round.victoryPoints(for: "p2") == Round.victoryPointsToWin)
    round.state = .waitingForPlayer(id: "p1", phase: .main)
    round.hasRolledDiceThisTurn = true
    try round.endTurn()
    guard case .gameComplete(let winner) = round.state else {
        Issue.record("Expected p2 to win at the start of their turn, got \(round.state)")
        return
    }
    #expect(winner.id == "p2")
}

@Test
func opponentAtTenDoesNotWinOnYourBuild() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [4])
    autoSetup(&round)
    _ = try round.rollDice()
    round.playerHands[1].heldDevCards = (0..<8).map { DevCard(id: 400 + $0, kind: .landmark) }
    #expect(round.victoryPoints(for: "p2") == 10)
    round.playerHands[0].resources = Round.trailCost
    let edgeID: EdgeID = try #require(round.edges.first { round.canPlaceTrail(at: $0.id, forPlayerID: "p1") }?.id)
    try round.buildTrail(edgeID: edgeID)
    #expect(round.isComplete == false)
    #expect(round.trail(at: edgeID)?.ownerID == "p1")
}

@Test
func opponentSettlementSplitsTheLongestTrail() throws {
    var round: Round = try makeStandardRound()
    let pair: (EdgeID, EdgeID, VertexID) = try #require(connectedEdgePair(in: round))
    round.trails = [
        Trail(ownerID: "p1", edgeID: pair.0),
        Trail(ownerID: "p1", edgeID: pair.1),
    ]
    #expect(round.longestTrailLength(for: "p1") == 2)
    round.buildings.append(Building(kind: .homestead, ownerID: "p2", vertexID: pair.2))
    #expect(round.longestTrailLength(for: "p1") == 1)
}

@Test
func cookedStealTakesTheNamedResource() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [7], cookedStealChoices: [.ore])
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[1].resources = [.ore: 1, .wood: 2]
    let tileID: TileID = try #require(round.tiles.first { tile in
        tile.id != round.outlawTileID
            && tile.vertexIDs.contains { round.building(at: $0)?.ownerID == "p2" }
    }?.id)
    _ = try round.rollDice()
    try round.moveOutlaw(toTileID: tileID)
    #expect(round.playerHand(for: "p1")?.resources[.ore] == 1)
    #expect(round.playerHand(for: "p2")?.resources[.ore] == nil)
    #expect(round.playerHand(for: "p2")?.resources[.wood] == 2)
    #expect(round.state == .waitingForPlayer(id: "p1", phase: .main))
}

@Test
func stealingFromANonCandidateLeavesResourcesUnchanged() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[1].resources = [.ore: 2]
    round.playerHands[2].resources = [.wheat: 2]
    round.state = .waitingForPlayer(
        id: "p1",
        phase: .stealingAfterOutlaw(candidates: ["p2"], reason: .rolledSeven)
    )
    let before: Round = round
    #expect(throws: PioneersModelError.cannotStealFromPlayer) {
        _ = try round.stealFromPlayer(victimID: "p3")
    }
    #expect(round == before)
}

@Test
func movingTheOutlawOutsideThatPhaseIsRejected() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    let before: Round = round
    let otherTileID: TileID = try #require(round.tiles.first { $0.id != round.outlawTileID }?.id)
    #expect(throws: PioneersModelError.mustMoveOutlawFirst) {
        try round.moveOutlaw(toTileID: otherTileID)
    }
    #expect(round == before)
}

@Test
func emptyDevDeckRejectsPurchase() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    round.devCardDeck = []
    round.playerHands[0].resources = Round.devCardCost
    let before: Round = round
    #expect(throws: PioneersModelError.noDevCardsAvailable) {
        try round.buyDevCard()
    }
    #expect(round == before)
}

@Test
func bankTradeForTheSameResourceIsRejected() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 4]
    let before: Round = round
    #expect(throws: PioneersModelError.invalidBankTrade) {
        try round.bankTrade(give: .wood, for: .wood)
    }
    #expect(round == before)
}

@Test
func acceptorWithoutResourcesLeavesTheOfferOpen() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [5])
    autoSetup(&round)
    _ = try round.rollDice()
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 1]
    let offer: TradeOffer = try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    let before: Round = round
    #expect(throws: PioneersModelError.insufficientResources) {
        try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p2")
    }
    #expect(round == before)
    #expect(round.openTradeOffer?.id == offer.id)
}

@Test
func roundupWithoutAResourceKeepsTheCard() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    let card: DevCard = DevCard(id: 9100, kind: .roundup)
    round.playerHands[0].heldDevCards = [card]
    let before: Round = round
    #expect(throws: PioneersModelError.invalidTradeOffer) {
        try round.playDevCard(id: card.id)
    }
    #expect(round == before)
}

@Test
func bountifulHarvestWithOnePickKeepsTheCard() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    let card: DevCard = DevCard(id: 9200, kind: .bountifulHarvest)
    round.playerHands[0].heldDevCards = [card]
    let before: Round = round
    #expect(throws: PioneersModelError.invalidTradeOffer) {
        try round.playDevCard(id: card.id, pickedResources: [.wheat])
    }
    #expect(round == before)
}

@Test
func illegalPathfinderTrailDoesNotSpendAPlacement() throws {
    var round: Round = try makeStandardRound()
    autoSetup(&round)
    let card: DevCard = DevCard(id: 9300, kind: .pathfinder)
    round.playerHands[0].heldDevCards = [card]
    try round.playDevCard(id: card.id)
    let trailCount: Int = round.trails.count
    let edgeID: EdgeID = try #require(
        round.edges.first { round.trail(at: $0.id) == nil && round.canPlaceTrail(at: $0.id, forPlayerID: "p1") == false }?.id
    )
    let before: Round = round
    #expect(throws: PioneersModelError.trailMustConnectToOwnNetwork) {
        try round.buildTrail(edgeID: edgeID)
    }
    #expect(round == before)
    #expect(round.trails.count == trailCount)
    #expect(round.state == .waitingForPlayer(id: "p1", phase: .playingPathfinder(remainingTrails: 2)))
}

@Test
func devCardPlayedWhileDiscardingStaysInHand() throws {
    var round: Round = try makeStandardRound(cookedDiceRolls: [7])
    autoSetup(&round)
    clearResources(&round)
    round.playerHands[0].resources = [.wood: 8]
    let card: DevCard = DevCard(id: 9400, kind: .roundup)
    round.playerHands[0].heldDevCards = [card]
    _ = try round.rollDice()
    let before: Round = round
    #expect(throws: PioneersModelError.notInMainPhase) {
        try round.playDevCard(id: card.id, resource: .wood)
    }
    #expect(round == before)
}
}
