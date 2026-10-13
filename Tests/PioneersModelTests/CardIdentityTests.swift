import Foundation
import Testing
@testable import PioneersModel

@Suite struct CardIdentityTests {
    private func assertConservation(_ round: Round) {
        let resourceIDs = round.bankResourceIDs + round.playerHands.flatMap(\.resourceIDs)
        #expect(resourceIDs.count == Set(resourceIDs).count)
        #expect(Set(resourceIDs) == Set(round.resourcesMap.keys))
        let devIDs = round.devCardDeck + round.playerHands.flatMap { $0.heldDevCardIDs + $0.playedDevCardIDs }
        #expect(devIDs.count == Set(devIDs).count)
        #expect(Set(devIDs) == Set(round.devCardsMap.keys))
    }

    private func mainRound() -> Round {
        var round = Round.fake()
        round.state = .waitingForPlayer(id: "p1", phase: .main)
        round.hasRolledDiceThisTurn = true
        return round
    }

    @Test func newRoundsCreatePhysicalResourceBanksAndUniqueDevCards() {
        for count in [3, 4, 5, 6] {
            let round = Round.fake(players: Round.defaultFakePlayers(count: count))
            let expected = count >= 5 ? 24 : 19
            #expect(round.bankResourceIDs.count == expected * Resource.allCases.count)
            for resource in Resource.allCases { #expect(round.bankResourceCounts[resource] == expected) }
            #expect(round.playerHands.allSatisfy { $0.resourceIDs.isEmpty && $0.heldDevCardIDs.isEmpty })
            assertConservation(round)
        }
    }

    @Test func setupAndDiceMoveCardsFromBankWithoutCreatingIdentities() throws {
        var round = Round.fake()
        let map = round.resourcesMap
        #expect(Round.autoCompleteSetup(&round))
        #expect(round.playerHands.contains { !$0.resourceIDs.isEmpty })
        round.cookedDiceRolls = [6]
        try round.rollDice()
        #expect(round.resourcesMap == map)
        assertConservation(round)
    }

    @Test func paymentReturnsExactCardsAndFailedPaymentIsAtomic() throws {
        var round = mainRound()
        round.setTestResources([.wood: 2, .brick: 1], at: 0)
        let selected = try round.resourceIDs(for: Round.trailCost, from: round.playerHands[0].resourceIDs)
        try round.spendResources(Round.trailCost, fromPlayerID: "p1")
        #expect(Set(selected).isSubset(of: Set(round.bankResourceIDs)))
        #expect(round.playerHands[0].resources(using: round.resourcesMap) == [.wood: 1])
        let before = round
        #expect(throws: PioneersModelError.insufficientResources) {
            try round.spendResources([.wood: 1, .ore: 1], fromPlayerID: "p1")
        }
        #expect(round == before)
        assertConservation(round)
    }

    @Test func tradeSwapsExactIdentitiesWithoutPassingThroughBank() throws {
        var round = mainRound()
        round.setTestResources([.wood: 2], at: 0)
        round.setTestResources([.ore: 1], at: 1)
        let wood = Set(round.playerHands[0].resourceIDs), ore = Set(round.playerHands[1].resourceIDs)
        let bank = round.bankResourceIDs
        let offer = try round.postTradeOffer(give: [.wood: 2], receive: [.ore: 1])
        try round.acceptTradeOffer(offerID: offer.id, byPlayerID: "p2")
        #expect(Set(round.playerHands[0].resourceIDs) == ore)
        #expect(Set(round.playerHands[1].resourceIDs) == wood)
        #expect(round.bankResourceIDs == bank)
        assertConservation(round)
    }

    @Test func bankTradeReturnsPaymentAndTransfersExistingBankCard() throws {
        var round = mainRound()
        round.setTestResources([.wood: 4], at: 0)
        let payment = Set(round.playerHands[0].resourceIDs)
        let ore = try #require(round.bankResourceIDs.first { round.resourcesMap[$0] == .ore })
        try round.bankTrade(give: .wood, for: .ore)
        #expect(round.playerHands[0].resourceIDs == [ore])
        #expect(payment.isSubset(of: Set(round.bankResourceIDs)))
        assertConservation(round)
    }

    @Test func unavailableBankTradeDoesNotTakePayment() throws {
        var round = mainRound()
        round.setTestResources([.wood: 4], at: 0)
        round.setTestResources([.ore: 19], at: 1)
        let before = round
        #expect(throws: PioneersModelError.insufficientBankResources) { try round.bankTrade(give: .wood, for: .ore) }
        #expect(round == before)
        assertConservation(round)
    }

    @Test func discardReturnsTheDiscardedIDsToBank() throws {
        var round = mainRound()
        round.setTestResources([.wood: 8], at: 0)
        round.state = .waitingForPlayer(id: "p1", phase: .discardingAfterSeven(pendingPlayerIDs: ["p1"]))
        let old = Set(round.playerHands[0].resourceIDs)
        try round.discardResources(playerID: "p1", resources: [.wood: 4])
        let removed = old.subtracting(round.playerHands[0].resourceIDs)
        #expect(removed.count == 4)
        #expect(removed.isSubset(of: Set(round.bankResourceIDs)))
        assertConservation(round)
    }

    @Test func theftIsDeterministicAcrossRoundTripAndHandOrder() throws {
        var round = mainRound()
        round.setTestResources([.wood: 2, .ore: 1], at: 1)
        round.state = .waitingForPlayer(id: "p1", phase: .stealingAfterOutlaw(candidates: ["p2"], reason: .rolledSeven))
        let selected = try #require(round.playerHands[1].resourceIDs.min())
        var other = try JSONDecoder().decode(Round.self, from: JSONEncoder().encode(round))
        other.playerHands[1].resourceIDs.reverse()
        let bank = round.bankResourceIDs
        let stolen = try round.stealFromPlayer(victimID: "p2")
        #expect(try other.stealFromPlayer(victimID: "p2") == stolen)
        #expect(round.playerHands[0].resourceIDs == [selected])
        #expect(other.playerHands[0].resourceIDs == [selected])
        #expect(round.resourcesMap == other.resourcesMap)
        #expect(round.bankResourceIDs == bank)
        assertConservation(round)
        assertConservation(other)
    }

    @Test func movingOutlawAutoStealsSameIDOnBothCopies() throws {
        var round = mainRound()
        let tile = try #require(round.tiles.first { $0.id != round.outlawTileID })
        round.buildings = [Building(kind: .homestead, ownerID: "p2", vertexID: tile.vertexIDs[0])]
        round.setTestResources([.wood: 1, .ore: 1], at: 1)
        round.state = .waitingForPlayer(id: "p1", phase: .movingOutlaw(reason: .rolledSeven))
        var other = try JSONDecoder().decode(Round.self, from: JSONEncoder().encode(round))
        try round.moveOutlaw(toTileID: tile.id)
        try other.moveOutlaw(toTileID: tile.id)
        #expect(round.playerHands == other.playerHands)
        #expect(round.state == other.state)
        assertConservation(round)
    }

    @Test func developmentCardMovesDeckToHandToPlayedWithoutCopyingData() throws {
        var round = mainRound()
        let cardID = try #require(round.devCardDeck.first { round.devCardsMap[$0]?.kind == .ranger })
        round.devCardDeck.removeAll { $0 == cardID }
        round.devCardDeck.insert(cardID, at: 0)
        round.setTestResources(Round.devCardCost, at: 0)
        let map = round.devCardsMap
        try round.buyDevCard()
        #expect(round.playerHands[0].heldDevCardIDs == [cardID])
        #expect(round.playerHands[0].devCardIDsPurchasedThisTurn == [cardID])
        #expect(throws: PioneersModelError.cannotPlayDevCardPurchasedThisTurn) { try round.playDevCard(id: cardID) }
        round.playerHands[0].devCardIDsPurchasedThisTurn = []
        try round.playDevCard(id: cardID)
        #expect(round.playerHands[0].heldDevCardIDs.isEmpty)
        #expect(round.playerHands[0].playedDevCardIDs == [cardID])
        #expect(round.devCardsMap == map)
        assertConservation(round)
    }

    @Test func roundupTransfersOpponentsExactResourceIDs() throws {
        var round = mainRound()
        let card = try #require(round.devCardDeck.first { round.devCardsMap[$0]?.kind == .roundup })
        round.devCardDeck.removeAll { $0 == card }
        round.playerHands[0].heldDevCardIDs = [card]
        round.setTestResources([.wood: 3, .ore: 1], at: 1)
        round.setTestResources([.wood: 2], at: 2)
        let ids = Set(round.playerHands.flatMap(\.resourceIDs).filter { round.resourcesMap[$0] == .wood })
        let bank = round.bankResourceIDs
        try round.playDevCard(id: card, resource: .wood)
        #expect(Set(round.playerHands[0].resourceIDs) == ids)
        #expect(round.bankResourceIDs == bank)
        assertConservation(round)
    }

    @Test func harvestCannotConsumeCardWhenRequestedBankSupplyIsMissing() throws {
        var round = mainRound()
        let card = try #require(round.devCardDeck.first { round.devCardsMap[$0]?.kind == .bountifulHarvest })
        round.devCardDeck.removeAll { $0 == card }
        round.playerHands[0].heldDevCardIDs = [card]
        round.setTestResources([.wood: 18], at: 1)
        let before = round
        #expect(throws: PioneersModelError.insufficientBankResources) {
            try round.playDevCard(id: card, pickedResources: [.wood, .wood])
        }
        #expect(round == before)
        try round.playDevCard(id: card, pickedResources: [.wood, .ore])
        #expect(round.playerHands[0].totalResourceCount == 2)
        assertConservation(round)
    }

    @Test func productionShortageWithMultipleRecipientsPaysNeither() throws {
        var round = mainRound()
        let tile = try #require(round.tiles.first { $0.type == .forest })
        round.outlawTileID = try #require(round.tiles.first { $0.type == .desert }).id
        round.buildings = [
            Building(kind: .homestead, ownerID: "p1", vertexID: tile.vertexIDs[0]),
            Building(kind: .homestead, ownerID: "p2", vertexID: tile.vertexIDs[3]),
        ]
        round.setTestResources([.wood: 18], at: 2)
        round.state = .waitingForPlayer(id: "p1", phase: .beforeRoll)
        round.cookedDiceRolls = [try #require(tile.numberToken)]
        try round.rollDice()
        #expect(round.playerHands[0].resources(using: round.resourcesMap)[.wood] == nil)
        #expect(round.playerHands[1].resources(using: round.resourcesMap)[.wood] == nil)
        #expect(round.bankResourceCounts[.wood] == 1)
        assertConservation(round)
    }

    @Test func productionShortageWithSoleRecipientPaysRemainingSupply() throws {
        var round = mainRound()
        let tile = try #require(round.tiles.first { $0.type == .forest })
        round.buildings = [Building(kind: .town, ownerID: "p1", vertexID: tile.vertexIDs[0])]
        round.setTestResources([.wood: 18], at: 2)
        round.state = .waitingForPlayer(id: "p1", phase: .beforeRoll)
        round.cookedDiceRolls = [try #require(tile.numberToken)]
        try round.rollDice()
        #expect(round.playerHands[0].resources(using: round.resourcesMap)[.wood] == 1)
        #expect(round.bankResourceCounts[.wood] == nil)
        assertConservation(round)
    }

    @Test func newWireFormatContainsOnlyIDsInHandsAndRoundTrips() throws {
        let round = Round.fakeInProgress()
        let data = try JSONEncoder().encode(round)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hands = try #require(object["playerHands"] as? [[String: Any]])
        #expect(hands.allSatisfy { $0["resources"] == nil && $0["heldDevCards"] == nil && $0["playedDevCards"] == nil })
        #expect(object["resourcesMap"] != nil && object["devCardsMap"] != nil)
        #expect(try JSONDecoder().decode(Round.self, from: data) == round)
        assertConservation(round)
    }

    @Test func roundsWithoutCardIdentityMapsAreRejected() throws {
        let data = try JSONEncoder().encode(Round.fakeInProgress())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "resourcesMap")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Round.self, from: oldData)
        }
    }

    @Test func harvestCanTakeSoleRemainingBankCard() throws {
        var round = mainRound()
        let card = try #require(round.devCardDeck.first { round.devCardsMap[$0]?.kind == .bountifulHarvest })
        round.devCardDeck.removeAll { $0 == card }
        round.playerHands[0].heldDevCardIDs = [card]
        let retained = try #require(round.bankResourceIDs.first)
        round.playerHands[1].resourceIDs = round.bankResourceIDs.filter { $0 != retained }
        round.bankResourceIDs = [retained]
        try round.playDevCard(id: card, pickedResources: [try #require(round.resourcesMap[retained])])
        #expect(round.playerHands[0].resourceIDs == [retained])
        #expect(round.bankResourceIDs.isEmpty)
        assertConservation(round)
    }

    @Test func unresolvedIDsStillCountAsCards() {
        let hand = PlayerHand(player: .fake(), resourceIDs: ["known", "hidden"], heldDevCardIDs: [1, 2])
        #expect(hand.totalResourceCount == 2)
        #expect(hand.heldDevCardIDs.count == 2)
        #expect(hand.resources(using: ["known": .wood]) == [.wood: 1])
        #expect(hand.heldDevCards(using: [1: DevCard(id: 1, kind: .ranger)]).count == 1)
    }

}
