import Foundation
import Testing
@testable import PioneersModel

private func expansionRound(count: Int = 5, rules: Round.ExpansionRuleSet = .pairedPlayers) throws -> Round {
    let players = (0..<count).map { Player(id: "p\($0)", name: "Player \($0)", color: PlayerColor.allCases[$0]) }
    var round = try Round(players: players, expansionRuleSet: rules, cookedDiceRolls: Array(repeating: 2, count: 10))
    _ = Round.autoCompleteSetup(&round)
    return round
}

@Test(arguments: [5, 6])
func pairedPlayersFollowPrimaryTurnOrder(count: Int) throws {
    var round = try expansionRound(count: count)
    #expect(round.expansionRuleSet == .pairedPlayers)
    for index in 0..<count {
        #expect(round.state == .waitingForPlayer(id: "p\(index)", phase: .beforeRoll))
        try round.rollDice()
        try round.endTurn()
        #expect(round.state == .waitingForPlayer(id: "p\((index + 3) % count)", phase: .main))
        #expect(round.isPairedPlayerTurn)
        #expect(throws: PioneersModelError.notInBeforeRollPhase) { try round.rollDice() }
        try round.endTurn()
        #expect(round.isPairedPlayerTurn == false)
    }
    #expect(round.state == .waitingForPlayer(id: "p0", phase: .beforeRoll))
}

@Test
func pairedPlayerCanTradeBuyAndPlayButCannotTradeWithPlayers() throws {
    var round = try expansionRound()
    try round.rollDice()
    round.playerHands[3].resources = [.wood: 8, .wheat: 2, .sheep: 2, .ore: 2]
    let held = DevCard(id: 800, kind: .bountifulHarvest)
    let bought = DevCard(id: 801, kind: .roundup)
    round.playerHands[3].heldDevCards = [held]
    round.devCardDeck = [bought]
    try round.endTurn()
    try round.bankTrade(give: .wood, for: .brick)
    #expect(throws: PioneersModelError.notInMainPhase) {
        try round.postTradeOffer(give: [.wood: 1], receive: [.brick: 1])
    }
    try round.buyDevCard()
    #expect(round.currentPlayerID == "p3")
    #expect(throws: PioneersModelError.cannotPlayDevCardPurchasedThisTurn) {
        try round.playDevCard(id: bought.id, resource: .wood)
    }
    try round.playDevCard(id: held.id, pickedResources: [.wood, .brick])
    #expect(round.currentPhase == .main)
    try round.endTurn()
    #expect(round.hasPlayedDevCardThisTurn == false)
    #expect(round.playerHands[3].devCardIDsPurchasedThisTurn.isEmpty)
}

@Test
func originalSpecialBuildingAllowsMultiplePurchases() throws {
    var round = try expansionRound(rules: .specialBuilding)
    try round.rollDice()
    round.playerHands[1].resources = [.wheat: 2, .sheep: 2, .ore: 2]
    try round.endTurn()
    try round.buyDevCard()
    #expect(round.currentPlayerID == "p1")
    try round.buyDevCard()
    #expect(round.currentPlayerID != "p1" || !round.isSpecialBuildPhase)
}

@Test
func savedRoundsPreserveRulesAndPairedTurn() throws {
    var round = try expansionRound()
    try round.rollDice()
    try round.endTurn()
    let data = try JSONEncoder().encode(round)
    #expect(try JSONDecoder().decode(Round.self, from: data) == round)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "selectedExpansionRuleSet")
    object.removeValue(forKey: "pairedTurnOriginatingPlayerID")
    let oldData = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(Round.self, from: oldData).expansionRuleSet == .specialBuilding)
}

@Test
func revisedRulesAreDefaultAndDoNotAffectSmallGames() throws {
    for count in [3, 4] {
        let players = (0..<count).map { Player(id: "p\($0)", name: "Player", color: PlayerColor.allCases[$0]) }
        var round = try Round(players: players, cookedDiceRolls: [2])
        #expect(round.expansionRuleSet == .pairedPlayers)
        _ = Round.autoCompleteSetup(&round)
        try round.rollDice()
        try round.endTurn()
        #expect(round.state == .waitingForPlayer(id: "p1", phase: .beforeRoll))
    }
}

@Test
func secondaryPlayerCanWinAtStartOfPairedTurn() throws {
    var round = try expansionRound()
    try round.rollDice()
    round.playerHands[3].heldDevCards = (900..<910).map { DevCard(id: $0, kind: .landmark) }
    try round.endTurn()
    #expect(round.isComplete)
    if case .gameComplete(let winner) = round.state {
        #expect(winner.id == "p3")
    }
}
