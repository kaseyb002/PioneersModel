import Foundation
import Testing
@testable import PioneersModel

extension Round {
    /// Fixtures move real cards between locations; they never duplicate resource identities.
    mutating func setTestResources(_ resources: [Resource: Int], at index: Int) {
        bankResourceIDs.append(contentsOf: playerHands[index].resourceIDs)
        playerHands[index].resourceIDs = []
        let granted = grantResources(resources, toPlayerID: playerHands[index].player.id)
        #expect(granted == resources.filter { $0.value > 0 })
    }

    mutating func setTestResource(_ resource: Resource, count: Int, at index: Int) {
        var resources = playerHands[index].resources(using: resourcesMap)
        resources[resource] = count
        setTestResources(resources, at: index)
    }

    mutating func setTestDevCards(_ cards: [DevCard], at index: Int, played: Bool) {
        let oldIDs = played ? playerHands[index].playedDevCardIDs : playerHands[index].heldDevCardIDs
        devCardDeck.append(contentsOf: oldIDs)
        if played { playerHands[index].playedDevCardIDs = [] }
        else { playerHands[index].heldDevCardIDs = [] }
        appendTestDevCards(at: index, played: played, cards: cards)
    }

    mutating func appendTestDevCard(at index: Int, played: Bool, card: DevCard) {
        appendTestDevCards(at: index, played: played, cards: [card])
    }

    mutating func appendTestDevCards(at index: Int, played: Bool, cards: [DevCard]) {
        for card in cards {
            devCardsMap[card.id] = card
            devCardDeck.removeAll { $0 == card.id }
            for handIndex in playerHands.indices {
                playerHands[handIndex].heldDevCardIDs.removeAll { $0 == card.id }
                playerHands[handIndex].playedDevCardIDs.removeAll { $0 == card.id }
                playerHands[handIndex].devCardIDsPurchasedThisTurn.removeAll { $0 == card.id }
            }
            if played { playerHands[index].playedDevCardIDs.append(card.id) }
            else { playerHands[index].heldDevCardIDs.append(card.id) }
        }
    }
}
